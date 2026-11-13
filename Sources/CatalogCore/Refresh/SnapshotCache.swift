import CoreSupport
import Foundation

/// Caches the last refreshed snapshot next to the app's application-support data,
/// with a per-source manifest so a partial refresh is visible.
public struct SnapshotCache: Sendable {
    public let directory: URL
    private let writer: any FileWriting

    public init(directory: URL? = nil, writer: any FileWriting = AtomicFileWriter()) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = base.appendingPathComponent("dk.netsi.image/catalog", isDirectory: true)
        }
        self.writer = writer
    }

    public var snapshotURL: URL { directory.appendingPathComponent("catalog.json") }
    public var manifestURL: URL { directory.appendingPathComponent("manifest.json") }

    public func load() throws -> Data? {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else { return nil }
        return try Data(contentsOf: snapshotURL)
    }

    public func loadManifest() -> [String: String] {
        guard let data = try? Data(contentsOf: manifestURL),
              let value = try? JSONValue.parse(data),
              let object = value.objectValue
        else { return [:] }
        return object.compactMapValues(\.stringValue)
    }

    public func save(_ data: Data, manifest: [String: String]) throws {
        try writer.write(data, to: snapshotURL)
        let manifestJSON = JSONValue.object(manifest.mapValues(JSONValue.string))
        try writer.write(try manifestJSON.encoded(pretty: true), to: manifestURL)
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: snapshotURL.path) {
            try FileManager.default.removeItem(at: snapshotURL)
        }
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            try FileManager.default.removeItem(at: manifestURL)
        }
    }
}
