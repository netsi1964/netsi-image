import CatalogCore
import CoreSupport
import Foundation
import GenerationKit

public struct LibraryItem: Sendable, Equatable, Codable, Identifiable {
    public var sha256: String
    public var filePath: String
    public var sidecarPath: String
    public var createdAt: String
    public var modelId: String?
    public var promptText: String?
    public var costUSD: Decimal?
    public var width: Int?
    public var height: Int?
    public var favorite: Bool
    public var missing: Bool

    public var id: String { sha256 }

    /// A library item is only safe to hand to the system preview when its
    /// file extension is one of the supported raster formats. SVG is never
    /// openable, even if an old sidecar still points at one.
    public var isOpenable: Bool {
        let ext = (filePath as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "webp", "gif"].contains(ext)
    }

    public init(
        sha256: String,
        filePath: String,
        sidecarPath: String,
        createdAt: String,
        modelId: String? = nil,
        promptText: String? = nil,
        costUSD: Decimal? = nil,
        width: Int? = nil,
        height: Int? = nil,
        favorite: Bool = false,
        missing: Bool = false
    ) {
        self.sha256 = sha256
        self.filePath = filePath
        self.sidecarPath = sidecarPath
        self.createdAt = createdAt
        self.modelId = modelId
        self.promptText = promptText
        self.costUSD = costUSD
        self.width = width
        self.height = height
        self.favorite = favorite
        self.missing = missing
    }

    public init(sidecar: Sidecar, filePath: String, sidecarPath: String) {
        self.sha256 = sidecar["result"]?["sha256"]?.stringValue ?? ""
        self.filePath = filePath
        self.sidecarPath = sidecarPath
        self.createdAt = sidecar.createdAt ?? ""
        self.modelId = sidecar.modelId
        self.promptText = sidecar.promptText
        self.costUSD = sidecar.costUSD
        self.width = sidecar.width
        self.height = sidecar.height
        self.favorite = sidecar["favorite"]?.boolValue ?? false
        self.missing = false
    }
}

public protocol LibraryIndex: Sendable {
    func upsert(_ item: LibraryItem) throws
    func all() -> [LibraryItem]
    func remove(sha256: String) throws
    func rebuild(from items: [LibraryItem]) throws
}

/// A derived JSON index. The sidecars are authoritative: delete this file and rebuild.
public final class JSONIndex: LibraryIndex, @unchecked Sendable {
    private let url: URL
    private let writer: any FileWriting
    private let lock = NSLock()
    private var items: [String: LibraryItem] = [:]

    public init(url: URL, writer: any FileWriting = AtomicFileWriter()) throws {
        self.url = url
        self.writer = writer
        if let data = try? Data(contentsOf: url),
           let value = try? JSONValue.parse(data),
           let array = value["items"]?.arrayValue {
            for entry in array {
                if let item = try? entry.decoded(as: LibraryItem.self), !item.sha256.isEmpty {
                    items[item.sha256] = item
                }
            }
        }
    }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return items.count
    }

    public func upsert(_ item: LibraryItem) throws {
        lock.lock()
        items[item.sha256] = item
        let snapshot = items.values.sorted { $0.createdAt > $1.createdAt }
        lock.unlock()
        try persist(snapshot)
    }

    public func all() -> [LibraryItem] {
        lock.lock(); defer { lock.unlock() }
        return items.values.sorted { $0.createdAt > $1.createdAt }
    }

    public func remove(sha256: String) throws {
        lock.lock()
        items.removeValue(forKey: sha256)
        let snapshot = items.values.sorted { $0.createdAt > $1.createdAt }
        lock.unlock()
        try persist(snapshot)
    }

    public func rebuild(from newItems: [LibraryItem]) throws {
        lock.lock()
        items = Dictionary(uniqueKeysWithValues: newItems.map { ($0.sha256, $0) })
        let snapshot = newItems
        lock.unlock()
        try persist(snapshot)
    }

    private func persist(_ snapshot: [LibraryItem]) throws {
        let encoded = try snapshot.map { item -> JSONValue in
            try JSONValue.parse(item.encodedData())
        }
        let root = JSONValue.object([
            "formatVersion": .number(1),
            "items": .array(encoded),
        ])
        try writer.write(try root.encoded(pretty: true), to: url)
    }
}

public enum LibrarySearch {
    /// Prompt-word search over prompt text and file name, case- and diacritic-insensitive.
    public static func search(_ query: String, in items: [LibraryItem]) -> [LibraryItem] {
        let tokens = query
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else { return items }

        return items.filter { item in
            let haystack = [
                item.promptText ?? "",
                item.filePath,
                item.modelId ?? "",
            ].joined(separator: " ")
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }
}

public struct IndexRebuilder: Sendable {
    public init() {}

    /// Walks every sidecar under `Library/` and rebuilds index entries.
    public func rebuild(root: URL) throws -> [LibraryItem] {
        let paths = LibraryPaths(root: root)
        guard FileManager.default.fileExists(atPath: paths.libraryDirectory.path) else { return [] }

        var result: [LibraryItem] = []
        let enumerator = FileManager.default.enumerator(
            at: paths.libraryDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension.lowercased() == "json" else { continue }
            guard let data = try? Data(contentsOf: url),
                  let sidecar = try? Sidecar(data: data)
            else { continue }

            let imageURL = url.deletingPathExtension().appendingPathExtension(imageExtension(for: sidecar))
            let relativeSidecar = url.path.replacingOccurrences(of: paths.root.path + "/", with: "")
            let relativeImage = imageURL.path.replacingOccurrences(of: paths.root.path + "/", with: "")
            var item = LibraryItem(sidecar: sidecar, filePath: relativeImage, sidecarPath: relativeSidecar)
            item.missing = !FileManager.default.fileExists(atPath: imageURL.path)
            if item.sha256.isEmpty {
                item.sha256 = relativeSidecar
            }
            result.append(item)
        }

        return result.sorted { $0.createdAt > $1.createdAt }
    }

    private func imageExtension(for sidecar: Sidecar) -> String {
        let mediaType = sidecar["result"]?["mediaType"]?.stringValue ?? "image/png"
        return LibraryPaths.fileExtension(for: mediaType)
    }
}

extension LibraryItem {
    func encodedData() throws -> Data {
        try JSONEncoder().encode(self)
    }
}

extension JSONValue {
    func decoded<T: Decodable>(as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: encoded())
    }
}

/// The service the UI talks to: one place that writes files and updates the index.
public actor LibraryService {
    public let paths: LibraryPaths
    private let writer: ImageWriter
    private let index: JSONIndex
    private let catalogVersion: String

    public init(root: URL, catalogVersion: String = "1.0.0", fileWriter: any FileWriting = AtomicFileWriter()) throws {
        let paths = LibraryPaths(root: root)
        self.paths = paths
        self.writer = ImageWriter(paths: paths, writer: fileWriter)
        self.index = try JSONIndex(url: paths.indexURL, writer: fileWriter)
        self.catalogVersion = catalogVersion
    }

    public func save(
        job: GenerationJob,
        result: GenerationResult,
        endpoint: Endpoint,
        parameters: [String: JSONValue],
        prompt: String,
        date: Date = Date()
    ) throws -> LibraryItem {
        let written = try writer.write(
            data: result.data,
            result: result,
            job: job,
            endpoint: endpoint,
            parameters: parameters,
            prompt: prompt,
            catalogVersion: catalogVersion,
            date: date
        )
        let sidecar = try Sidecar(data: Data(contentsOf: written.sidecarURL))
        var item = LibraryItem(
            sidecar: sidecar,
            filePath: written.relativeImagePath,
            sidecarPath: written.relativeSidecarPath
        )
        item.sha256 = written.sha256
        item.missing = false
        try index.upsert(item)
        return item
    }

    public func items() -> [LibraryItem] { index.all() }

    public func search(_ query: String) -> [LibraryItem] {
        LibrarySearch.search(query, in: index.all())
    }

    public func rebuild() throws -> Int {
        let rebuilt = try IndexRebuilder().rebuild(root: paths.root)
        try index.rebuild(from: rebuilt)
        return rebuilt.count
    }

    public func remove(_ item: LibraryItem) throws {
        let imageURL = paths.root.appendingPathComponent(item.filePath)
        let sidecarURL = paths.root.appendingPathComponent(item.sidecarPath)
        try PathConfinement.ensureContained(imageURL, root: paths.root)
        try PathConfinement.ensureContained(sidecarURL, root: paths.root)
        if FileManager.default.fileExists(atPath: imageURL.path) {
            try FileManager.default.trashItem(at: imageURL, resultingItemURL: nil)
        }
        if FileManager.default.fileExists(atPath: sidecarURL.path) {
            try FileManager.default.trashItem(at: sidecarURL, resultingItemURL: nil)
        }
        try index.remove(sha256: item.sha256)
    }
}
