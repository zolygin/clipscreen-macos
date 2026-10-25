import AppKit

/// Disk writes are serialized off the main thread. UI updates are always on main.
final class HistoryModel {
    private let queue = DispatchQueue(label: "local.clip.history", qos: .userInitiated)
    private var repository: HistoryRepository?
    private(set) var entries: [ClipEntry] = []
    private(set) var error: String?
    private(set) var isLoading = true
    var onChange: (() -> Void)?
    let directory: URL
    private let images = NSCache<NSUUID, NSImage>()

    init(directory: URL) {
        self.directory = directory
        images.countLimit = 100
        queue.async {
            do {
                self.repository = try HistoryRepository(directory: directory)
                self.publish()
            } catch { self.report(error) }
        }
    }

    func add(_ capture: ClipCapture) { mutate { try $0.add(capture) } }
    func remove(_ id: UUID) { mutate { try $0.remove(id) } }
    func clear() { mutate { try $0.clear() }; images.removeAllObjects() }

    func load(_ entry: ClipEntry, completion: @escaping (Result<ClipPayload, Error>) -> Void) {
        queue.async {
            let result = Result { () throws -> ClipPayload in
                guard let repository = self.repository else { throw HistoryError.damaged }
                return try repository.payload(for: entry)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func thumbnail(_ entry: ClipEntry) -> NSImage? {
        if let image = images.object(forKey: entry.id as NSUUID) { return image }
        guard let image = NSImage(contentsOf: directory.appendingPathComponent("\(entry.id).png")) else { return nil }
        images.setObject(image, forKey: entry.id as NSUUID)
        return image
    }

    func flush() { queue.sync {} }

    private func mutate(_ work: @escaping (HistoryRepository) throws -> Void) {
        queue.async {
            do {
                guard let repository = self.repository else { throw HistoryError.damaged }
                try work(repository)
                self.publish()
            } catch {
                // Cleanup can fail after an index commit. Always reflect the committed index.
                self.publish()
                self.report(error)
            }
        }
    }

    private func publish() {
        let entries = repository?.entries ?? []
        DispatchQueue.main.async {
            self.entries = entries
            self.isLoading = false
            self.error = nil
            self.onChange?()
        }
    }

    private func report(_ error: Error) {
        DispatchQueue.main.async {
            self.isLoading = false
            self.error = HistoryError.message(for: error)
            self.onChange?()
        }
    }
}
