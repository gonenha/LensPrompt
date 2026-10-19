import Foundation

public struct TakeShareBatch: Identifiable, Sendable {
    public let id: UUID
    public let directory: URL
    public let urls: [URL]
}

/// File work stays off the UI actor. Originals remain intact until explicit take deletion.
public actor TakeExportStore {
    public init() {}
    public func prepare(takes: [Take], libraryRoot: URL, exportRoot: URL) throws -> TakeShareBatch {
        guard !takes.isEmpty else { throw LibraryError.missingTake }
        let id = UUID(), directory = exportRoot.appendingPathComponent(UUID().uuidString)
        var urls: [URL] = []
        do {
            for take in takes {
                try Task.checkCancellation()
                let source = libraryRoot.appendingPathComponent("Takes").appendingPathComponent(take.fileName)
                guard FileManager.default.fileExists(atPath: source.path) else { throw LibraryError.missingTake }
                let folder = directory.appendingPathComponent(take.id.uuidString)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = folder.appendingPathComponent(take.exportFileName)
                // Hard links avoid duplicating large video files when the filesystem permits it.
                do { try FileManager.default.linkItem(at: source, to: destination) }
                catch { try FileManager.default.copyItem(at: source, to: destination) }
                urls.append(destination)
            }
            return TakeShareBatch(id: id, directory: directory, urls: urls)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
    public func release(_ batch: TakeShareBatch) { try? FileManager.default.removeItem(at: batch.directory) }
}
