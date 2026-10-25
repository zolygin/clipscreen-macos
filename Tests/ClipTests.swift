import Foundation
import AppKit

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct ClipTests {
    static var passed = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw TestFailure(description: message) }
    }

    static func test(_ name: String, _ body: () throws -> Void) throws {
        try body()
        passed += 1
        print("PASS \(name)")
    }

    static func capture(_ text: String) -> ClipCapture {
        ClipCapture(payload: ClipPayload(parts: [ClipPart(representations: [
            ClipRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))
        ])]), kind: .text, title: text, detail: "", searchText: text, source: "Tests", thumbnail: nil)
    }

    static func withRepository(_ body: (HistoryRepository, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("clip-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(HistoryRepository(directory: directory), directory)
    }

    static func withPasteboard(_ body: (NSPasteboard) throws -> Void) throws {
        // Never read or change the user's general pasteboard in tests.
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents()
        try body(board)
    }

    static func main() {
        do { try run() }
        catch { print("FAIL \(error)"); exit(1) }
    }

    static func run() throws {
        setbuf(stdout, nil)
        try test("Keeps exactly the newest 100 entries and prunes old payloads") {
            try withRepository { repo, directory in
                for index in 0..<105 { try repo.add(capture("Entry \(index)")) }
                try expect(repo.entries.count == 100, "Incorrect retention count")
                try expect(repo.entries.first?.title == "Entry 104", "Wrong newest entry")
                try expect(repo.entries.last?.title == "Entry 5", "Wrong oldest entry")
                let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                try expect(files.filter { $0.hasSuffix(".clip") }.count == 100, "Evicted payloads remain")
            }
        }
        try test("Duplicates move to front without consuming another slot") {
            try withRepository { repo, _ in
                try repo.add(capture("first"))
                let id = repo.entries[0].id
                try repo.add(capture("second"))
                let date = Date(timeIntervalSince1970: 1000)
                try repo.add(capture("first"), at: date)
                try expect(repo.entries.count == 2, "Duplicate added")
                try expect(repo.entries[0].id == id && repo.entries[0].copiedAt == date, "Duplicate not promoted")
            }
        }
        try test("Unicode, whitespace and rich data survive restart byte for byte") {
            try withRepository { repo, directory in
                let sample = capture("Привет 👩🏽‍💻\n\t  \n日本語")
                try repo.add(sample)
                let reloaded = try HistoryRepository(directory: directory)
                let payload = try reloaded.payload(for: reloaded.entries[0])
                try expect(payload == sample.payload, "Content changed on disk")
            }
        }
        try test("Remove and clear persist and clean payloads and thumbnails") {
            try withRepository { repo, directory in
                let base = capture("with thumbnail")
                let sample = ClipCapture(payload: base.payload, kind: .image, title: base.title, detail: "",
                                         searchText: "", source: "Tests", thumbnail: Data([1, 2, 3]))
                try repo.add(sample)
                let thumb = repo.thumbnailURL(repo.entries[0].id)
                try expect(FileManager.default.fileExists(atPath: thumb.path), "Thumbnail missing")
                try repo.remove(repo.entries[0].id)
                try expect(!FileManager.default.fileExists(atPath: thumb.path), "Thumbnail not deleted")
                try repo.add(capture("new"))
                try repo.clear()
                let reloaded = try HistoryRepository(directory: directory)
                try expect(reloaded.entries.isEmpty, "Clear not persisted")
                let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                try expect(files == ["index.json"], "Payloads remain after clear")
            }
        }
        try test("Corrupt index is preserved instead of silently overwritten") {
            try withRepository { _, directory in
                let index = directory.appendingPathComponent("index.json")
                let bytes = Data("broken index".utf8)
                try bytes.write(to: index)
                do {
                    _ = try HistoryRepository(directory: directory)
                    throw TestFailure(description: "Corruption was ignored")
                } catch HistoryError.damaged { }
                let result = try Data(contentsOf: index)
                try expect(result == bytes, "Original index overwritten")
            }
        }
        try test("Corrupt individual payload does not prevent loading healthy records") {
            try withRepository { repo, directory in
                try repo.add(capture("bad"))
                let broken = directory.appendingPathComponent("\(repo.entries[0].id).clip")
                try repo.add(capture("healthy"))
                try Data("bad".utf8).write(to: broken)
                let reloaded = try HistoryRepository(directory: directory)
                try expect(reloaded.entries.map(\.title) == ["healthy"], "Healthy history lost")
            }
        }
        try test("Uncommitted payloads are cleaned on restart") {
            try withRepository { _, directory in
                let orphan = directory.appendingPathComponent("\(UUID()).clip")
                try Data([1]).write(to: orphan)
                _ = try HistoryRepository(directory: directory)
                try expect(!FileManager.default.fileExists(atPath: orphan.path), "Orphan remains")
            }
        }
        try test("Failed index commit leaves previous history intact") {
            try withRepository { repo, directory in
                try repo.add(capture("committed"))
                let index = directory.appendingPathComponent("index.json")
                let saved = directory.appendingPathComponent("index.backup")
                try FileManager.default.moveItem(at: index, to: saved)
                try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
                do {
                    try repo.add(capture("uncommitted"))
                    throw TestFailure(description: "Write unexpectedly succeeded")
                } catch is TestFailure { throw TestFailure(description: "Write unexpectedly succeeded") }
                catch { }
                try expect(repo.entries.map(\.title) == ["committed"], "In-memory state advanced before commit")
                try FileManager.default.removeItem(at: index)
                try FileManager.default.moveItem(at: saved, to: index)
                let reloaded = try HistoryRepository(directory: directory)
                try expect(reloaded.entries.map(\.title) == ["committed"], "Disk state changed before commit")
            }
        }
        try test("History directory and files are private to the current user") {
            try withRepository { repo, directory in
                try repo.add(capture("private"))
                let folder = try FileManager.default.attributesOfItem(atPath: directory.path)
                let index = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("index.json").path)
                try expect((folder[.posixPermissions] as? NSNumber)?.intValue == 0o700, "Folder permissions")
                try expect((index[.posixPermissions] as? NSNumber)?.intValue == 0o600, "File permissions")
            }
        }
        try test("Fingerprint is independent of representation ordering") {
            let a = ClipRepresentation(type: "public.utf8-plain-text", data: Data("hello".utf8))
            let b = ClipRepresentation(type: "public.rtf", data: Data("{\\rtf1 hello}".utf8))
            let first = ClipPayload(parts: [.init(representations: [a, b])])
            let second = ClipPayload(parts: [.init(representations: [b, a])])
            try expect(first.fingerprint == second.fingerprint, "Representation order affects identity")
            let twoItems = ClipPayload(parts: [.init(representations: [a]), .init(representations: [b])])
            try expect(first.fingerprint != twoItems.fingerprint, "Item boundaries ignored")
        }
        try test("Oversized content is rejected without evicting anything") {
            try withRepository { repo, _ in
                try repo.add(capture("kept"))
                let payload = ClipPayload(parts: [.init(representations: [.init(type: "public.png",
                    data: Data(repeating: 0, count: HistoryRepository.maxPayloadBytes + 1))])])
                let sample = ClipCapture(payload: payload, kind: .image, title: "large", detail: "",
                                         searchText: "", source: "Tests", thumbnail: nil)
                do { try repo.add(sample); throw TestFailure(description: "Oversized capture accepted") }
                catch HistoryError.tooLarge { }
                try expect(repo.entries.map(\.title) == ["kept"], "Prior record lost")
            }
        }
        try test("Named pasteboard round-trips plain text and RTF") {
            try withPasteboard { board in
                let item = NSPasteboardItem()
                item.setString("Привет\nмир", forType: .string)
                let rtf = Data("{\\rtf1 formatted}".utf8)
                item.setData(rtf, forType: .rtf)
                try expect(board.writeObjects([item]), "Named pasteboard write failed; pasteboard server may be unavailable")
                guard let snapshot = try PasteboardCodec.capture(from: board, source: "Tests") else {
                    throw TestFailure(description: "Named pasteboard capture returned nil")
                }
                try expect(snapshot.kind == .text, "Text kind incorrect")
                try expect(PasteboardCodec.restore(snapshot.payload, to: board), "Restore failed")
                try expect(board.string(forType: .string) == "Привет\nмир", "Text changed")
                try expect(board.data(forType: .rtf) == rtf, "Rich formatting changed")
            }
        }
        try test("PNG capture creates a thumbnail and restores original bytes") {
            try withPasteboard { board in
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 16, bitsPerPixel: 32)!
                let png = bitmap.representation(using: .png, properties: [:])!
                board.setData(png, forType: .png)
                let snapshot = try PasteboardCodec.capture(from: board, source: "Tests")!
                try expect(snapshot.kind == .image && snapshot.detail == "4 × 3", "Image metadata incorrect")
                try expect(snapshot.thumbnail != nil, "Missing image thumbnail")
                try expect(PasteboardCodec.restore(snapshot.payload, to: board), "Image restore failed")
                try expect(board.data(forType: .png) == png, "Image data changed")
            }
        }
        try test("Concealed and transient pasteboard transactions are skipped") {
            try withPasteboard { board in
                for marker in PasteboardCodec.ignoredTypes {
                    board.clearContents()
                    let ordinary = NSPasteboardItem()
                    ordinary.setString("public", forType: .string)
                    let secret = NSPasteboardItem()
                    secret.setString("secret", forType: .string)
                    secret.setData(Data(), forType: .init(marker))
                    board.writeObjects([ordinary, secret])
                    let snapshot = try PasteboardCodec.capture(from: board, source: "Tests")
                    try expect(snapshot == nil, "Sensitive transaction captured: \(marker)")
                }
            }
        }
        try test("Multiple file references are preserved as separate items") {
            try withPasteboard { board in
                let urls = ["file:///tmp/one.png", "file:///tmp/two.png"]
                board.writeObjects(urls.map { value -> NSPasteboardItem in
                    let item = NSPasteboardItem()
                    item.setString(value, forType: .fileURL)
                    return item
                })
                let snapshot = try PasteboardCodec.capture(from: board, source: "Tests")!
                try expect(snapshot.kind == .files && snapshot.payload.parts.count == 2, "File group split")
                PasteboardCodec.restore(snapshot.payload, to: board)
                try expect(board.pasteboardItems?.compactMap { $0.string(forType: .fileURL) } == urls, "Files changed")
            }
        }
        try test("Unsupported item in a group cannot cause a partial capture") {
            try withPasteboard { board in
                let text = NSPasteboardItem()
                text.setString("supported", forType: .string)
                let unknown = NSPasteboardItem()
                unknown.setData(Data([1]), forType: .init("local.clip.unknown"))
                board.writeObjects([text, unknown])
                let snapshot = try PasteboardCodec.capture(from: board, source: "Tests")
                try expect(snapshot == nil, "Partially captured a group")
            }
        }
        try test("Monitor captures changes once, ignores own writes and respects pause") {
            try withPasteboard { board in
                let monitor = ClipboardMonitor(board: board)
                var count = 0
                monitor.onCapture = { _ in count += 1 }
                // A real copy takes ownership first; setting data alone does not bump changeCount.
                board.clearContents()
                board.setString("one", forType: .string)
                monitor.poll()
                monitor.poll()
                try expect(count == 1, "Expected one capture, got \(count)")
                board.clearContents()
                board.setString("own write", forType: .string)
                monitor.ignoreCurrentChange()
                monitor.poll()
                try expect(count == 1, "Own write recaptured")
                monitor.paused = true
                board.clearContents()
                board.setString("paused", forType: .string)
                monitor.poll()
                monitor.paused = false
                monitor.poll()
                try expect(count == 1, "Paused content captured on resume")
                board.clearContents()
                board.setString("resumed", forType: .string)
                monitor.poll()
                try expect(count == 2, "Monitoring did not resume")
            }
        }
        try test("Legacy image labels are English without changing saved clipboard data") {
            let image = ClipEntry(id: UUID(), copiedAt: Date(), kind: .image, title: "Изображение",
                                  detail: "1440 × 960", searchText: "Изображение", source: "Preview",
                                  fingerprint: "fixture", byteCount: 100)
            try expect(image.displayTitle == "Image" && image.displayImageDetail == "1440 × 960", "Legacy image label")
            try expect(image.title == "Изображение", "Stored content was rewritten")
            let text = ClipEntry(id: UUID(), copiedAt: Date(), kind: .text, title: "Изображение",
                                 detail: "11 символов", searchText: "Изображение", source: "Notes",
                                 fingerprint: "fixture", byteCount: 100)
            try expect(text.displayTitle == "Изображение", "User text was translated")
        }
        try test("System errors cannot leak non-English localized descriptions into the UI") {
            let error = NSError(domain: NSCocoaErrorDomain, code: 513,
                                userInfo: [NSLocalizedDescriptionKey: "Нет доступа"])
            let message = HistoryError.message(for: error)
            try expect(message.contains("513") && message.contains("History storage"), "Missing recovery information")
            try expect(!message.contains("Нет доступа"), "System-language text leaked")
        }
        try test("New generic clipboard labels are English") {
            try withPasteboard { board in
                board.setString(" \n\t", forType: .string)
                let item = try PasteboardCodec.capture(from: board, source: "Tests")
                try expect(item?.title == "Whitespace and line breaks", "Generic whitespace label")
                try expect(item?.detail == "3 characters", "Character count label")
            }
        }
        print("\n\(passed) tests passed. No access to the system clipboard; no full app build.")
    }
}
