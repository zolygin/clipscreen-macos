import Foundation
import CryptoKit

struct ClipRepresentation: Codable, Equatable {
    let type: String
    let data: Data
}

struct ClipPart: Codable, Equatable {
    let representations: [ClipRepresentation]
}

struct ClipPayload: Codable, Equatable {
    let parts: [ClipPart]

    var byteCount: Int {
        parts.reduce(0) { $0 + $1.representations.reduce(0) { $0 + $1.data.count } }
    }

    // Length-prefix fields so different item/type boundaries cannot collide.
    var fingerprint: String {
        var hash = SHA256()
        func append(_ data: Data) {
            var count = UInt64(data.count).bigEndian
            withUnsafeBytes(of: &count) { hash.update(data: Data($0)) }
            hash.update(data: data)
        }
        for part in parts {
            append(Data("item".utf8))
            for rep in part.representations.sorted(by: { $0.type < $1.type }) {
                append(Data(rep.type.utf8))
                append(rep.data)
            }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum ClipKind: String, Codable { case text, image, files }

struct ClipEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var copiedAt: Date
    let kind: ClipKind
    let title: String
    let detail: String
    let searchText: String
    var source: String
    let fingerprint: String
    let byteCount: Int

    // Existing records keep their original bytes and metadata. Generic image
    // labels are presented in English even for records from the first version.
    var displayTitle: String { kind == .image ? "Image" : title }
    var displayImageDetail: String? {
        detail.range(of: #"^\d+ × \d+$"#, options: .regularExpression) != nil ? detail : nil
    }
}

struct ClipCapture {
    let payload: ClipPayload
    let kind: ClipKind
    let title: String
    let detail: String
    let searchText: String
    let source: String
    let thumbnail: Data?
}

enum HistoryError: LocalizedError {
    case tooLarge, unsupported, damaged

    var errorDescription: String? {
        switch self {
        case .tooLarge: return "This item exceeds 50 MB and was not saved."
        case .unsupported: return "This clipboard format is not supported yet."
        case .damaged: return "History could not be read. Your original files have been preserved."
        }
    }

    static func message(for error: Error) -> String {
        if let error = error as? HistoryError { return error.errorDescription! }
        return "History storage is unavailable. Check disk space and folder permissions. (Error \((error as NSError).code))"
    }
}

/// Access only from the storage queue. The index is the commit point:
/// write payload first, atomically replace index, then delete evicted data.
final class HistoryRepository {
    static let limit = 100
    static let maxPayloadBytes = 50 * 1024 * 1024
    let directory: URL
    private(set) var entries: [ClipEntry] = []
    private let fm = FileManager.default

    init(directory: URL) throws {
        self.directory = directory
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let index = directory.appendingPathComponent("index.json")
        if fm.fileExists(atPath: index.path) {
            do { entries = try JSONDecoder().decode([ClipEntry].self, from: Data(contentsOf: index)) }
            catch { throw HistoryError.damaged }
        }
        // A damaged/missing individual payload must not break the whole history.
        let valid = entries.filter { entry in
            guard let payload = try? payload(for: entry) else { return false }
            return payload.fingerprint == entry.fingerprint
        }
        if valid != entries || valid.count > Self.limit {
            try commit(Array(valid.prefix(Self.limit)))
        }
        try cleanOrphans()
    }

    func add(_ capture: ClipCapture, at date: Date = Date()) throws {
        guard capture.payload.byteCount <= Self.maxPayloadBytes else { throw HistoryError.tooLarge }
        guard !capture.payload.parts.isEmpty,
              capture.payload.parts.allSatisfy({ !$0.representations.isEmpty }) else {
            throw HistoryError.unsupported
        }
        let fingerprint = capture.payload.fingerprint
        if var existing = entries.first(where: { $0.fingerprint == fingerprint }) {
            existing.copiedAt = date
            existing.source = capture.source
            try commit([existing] + entries.filter { $0.id != existing.id })
            return
        }
        let entry = ClipEntry(id: UUID(), copiedAt: date, kind: capture.kind,
                              title: capture.title, detail: capture.detail,
                              searchText: capture.searchText, source: capture.source,
                              fingerprint: fingerprint, byteCount: capture.payload.byteCount)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try write(encoder.encode(capture.payload), to: payloadURL(entry.id))
        if let thumbnail = capture.thumbnail { try write(thumbnail, to: thumbnailURL(entry.id)) }
        try commit(Array(([entry] + entries).prefix(Self.limit)))
        try cleanOrphans()
    }

    func payload(for entry: ClipEntry) throws -> ClipPayload {
        try PropertyListDecoder().decode(ClipPayload.self, from: Data(contentsOf: payloadURL(entry.id)))
    }

    func remove(_ id: UUID) throws {
        try commit(entries.filter { $0.id != id })
        try cleanOrphans()
    }

    func clear() throws {
        try commit([])
        try cleanOrphans()
    }

    func thumbnailURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id).png") }
    private func payloadURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id).clip") }

    private func commit(_ next: [ClipEntry]) throws {
        try write(JSONEncoder().encode(next), to: directory.appendingPathComponent("index.json"))
        entries = next
    }

    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func cleanOrphans() throws {
        let keep = Set(entries.flatMap { ["\($0.id).clip", "\($0.id).png"] })
        for url in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where ["clip", "png"].contains(url.pathExtension) && !keep.contains(url.lastPathComponent) {
            try fm.removeItem(at: url)
        }
    }
}
