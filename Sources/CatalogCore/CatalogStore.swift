import CoreSupport
import Foundation

public struct CatalogSummary: Sendable, Equatable, Codable {
    public var schemaVersion: String
    public var generatedAt: String
    public var baseURL: String?
    public var language: String?
    public var modelCount: Int
    public var endpointCounts: [String: Int]
    public var parameterCounts: [String: Int]
    public var providerRouteCount: Int
    public var modelsWithImagesSurface: Int
    public var modelsWithoutImageEndpoint: [String]

    public var endpointCount: Int { endpointCounts.values.reduce(0, +) }
    public var parameterCount: Int { parameterCounts.values.reduce(0, +) }
}

public enum CatalogError: Error, Equatable, Sendable, CustomStringConvertible {
    case malformedCatalog(String)
    case schemaMismatch(found: String, expected: String)
    case missingBundledCatalog

    public var description: String {
        switch self {
        case .malformedCatalog(let reason): return "Kataloget kunne ikke læses: \(reason)"
        case .schemaMismatch(let found, let expected):
            return "Katalogets schemaVersion er \(found), men appen kræver \(expected)."
        case .missingBundledCatalog: return "Det medfølgende modelkatalog blev ikke fundet."
        }
    }
}

/// Lazily decoded catalog. Loading parses the JSON tree once and decodes typed models on demand,
/// so opening the app never converts 1.907 parameter entries.
public actor CatalogStore {
    private var root: JSONValue
    private var summaryValue: CatalogSummary
    private var modelIndex: [String: JSONValue]
    private var cache: [String: CatalogModel] = [:]
    private var parameterDecodes = 0
    private var modelDecodes = 0

    public init(data: Data) throws {
        let root = try JSONValue.parse(data)
        guard let schemaVersion = root["schemaVersion"]?.stringValue, !schemaVersion.isEmpty else {
            throw CatalogError.malformedCatalog("schemaVersion mangler")
        }
        guard root["models"]?.arrayValue != nil else {
            throw CatalogError.malformedCatalog("models mangler")
        }
        self.root = root
        self.summaryValue = Self.summarize(root)
        var index: [String: JSONValue] = [:]
        for model in root["models"]?.arrayValue ?? [] {
            if let id = model["id"]?.stringValue {
                index[id] = model
            }
        }
        self.modelIndex = index
    }

    public static func bundledData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "openrouter-image-ui-catalog", withExtension: "json") else {
            throw CatalogError.missingBundledCatalog
        }
        return try Data(contentsOf: url)
    }

    public static func bundled() throws -> CatalogStore {
        try CatalogStore(data: try bundledData())
    }

    // MARK: - Summary

    public func summary() -> CatalogSummary { summaryValue }

    public func schemaVersion() -> String { root["schemaVersion"]?.stringValue ?? "" }

    public func generatedAt() -> String { root["generatedAt"]?.stringValue ?? "" }

    public func sources() -> [String: String] {
        (root["sources"]?.objectValue ?? [:]).compactMapValues(\.stringValue)
    }

    public func rawJSON() -> JSONValue { root }

    public func definitions() -> [String: JSONValue] {
        root["$defs"]?.objectValue ?? [:]
    }

    /// Instrumentation for the lazy-decode criterion.
    public func decodeCounters() -> (models: Int, parameters: Int) {
        (modelDecodes, parameterDecodes)
    }

    public func resetCounters() {
        modelDecodes = 0
        parameterDecodes = 0
    }

    // MARK: - Models

    public func modelIds() -> [String] {
        modelIndex.keys.sorted()
    }

    public func model(id: String) -> CatalogModel? {
        if let cached = cache[id] { return cached }
        guard let json = modelIndex[id] else { return nil }
        let model = CatalogModel(json: json)
        cache[id] = model
        modelDecodes += 1
        parameterDecodes += model.surfaces.values.reduce(0) { $0 + $1.endpoints.reduce(0) { $0 + $1.parameters.count } }
        return model
    }

    public func allModels() -> [CatalogModel] {
        modelIds().compactMap { model(id: $0) }
    }

    public func models(withSurface surface: SurfaceKind) -> [CatalogModel] {
        allModels().filter { $0.surface(surface) != nil }
    }

    public func catalog() -> Catalog {
        Catalog(json: root)
    }

    // MARK: - Replacement

    /// Swaps the snapshot atomically. Any failure leaves the previous snapshot untouched.
    public func replace(data: Data) throws {
        let candidate = try JSONValue.parse(data)
        let found = candidate["schemaVersion"]?.stringValue ?? ""
        guard found == schemaVersion() else {
            throw CatalogError.schemaMismatch(found: found, expected: schemaVersion())
        }
        guard candidate["models"]?.arrayValue != nil else {
            throw CatalogError.malformedCatalog("models mangler")
        }
        var index: [String: JSONValue] = [:]
        for model in candidate["models"]?.arrayValue ?? [] {
            if let id = model["id"]?.stringValue {
                index[id] = model
            }
        }
        root = candidate
        summaryValue = Self.summarize(candidate)
        modelIndex = index
        cache.removeAll()
        modelDecodes = 0
        parameterDecodes = 0
    }

    // MARK: - Summary computation (no typed decoding)

    static func summarize(_ root: JSONValue) -> CatalogSummary {
        let models = root["models"]?.arrayValue ?? []
        var endpointCounts: [String: Int] = [:]
        var parameterCounts: [String: Int] = [:]
        var providers: Set<String> = []
        var withImages = 0
        var withoutImageEndpoint: [String] = []

        for model in models {
            let surfaces = model["surfaces"]?.objectValue ?? [:]
            if surfaces["images"] != nil { withImages += 1 }
            for (surfaceName, surface) in surfaces {
                let endpoints = surface["endpoints"]?.arrayValue ?? []
                endpointCounts[surfaceName, default: 0] += endpoints.count
                if surfaceName == "images" && endpoints.isEmpty, let id = model["id"]?.stringValue {
                    withoutImageEndpoint.append(id)
                }
                for endpoint in endpoints {
                    parameterCounts[surfaceName, default: 0] += endpoint["parameters"]?.arrayValue?.count ?? 0
                    if let provider = endpoint["providerSlug"]?.stringValue {
                        providers.insert(provider)
                    }
                }
            }
        }

        return CatalogSummary(
            schemaVersion: root["schemaVersion"]?.stringValue ?? "",
            generatedAt: root["generatedAt"]?.stringValue ?? "",
            baseURL: root["baseUrl"]?.stringValue,
            language: root["language"]?.stringValue,
            modelCount: models.count,
            endpointCounts: endpointCounts,
            parameterCounts: parameterCounts,
            providerRouteCount: providers.count,
            modelsWithImagesSurface: withImages,
            modelsWithoutImageEndpoint: withoutImageEndpoint.sorted()
        )
    }
}
