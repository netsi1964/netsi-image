import CoreSupport
import Foundation

public enum RefreshError: Error, Equatable, Sendable, CustomStringConvertible {
    case http(status: Int, url: String)
    case malformed(url: String, reason: String)
    case schemaMismatch(found: String, expected: String)
    case missingSource(String)

    public var description: String {
        switch self {
        case .http(let status, let url): return "HTTP \(status) fra \(url)"
        case .malformed(let url, let reason): return "Ugyldigt svar fra \(url): \(reason)"
        case .schemaMismatch(let found, let expected):
            return "Katalogets schemaVersion er \(found), men appen kræver \(expected)."
        case .missingSource(let name): return "Katalogets kilde \(name) mangler."
        }
    }
}

public enum SchemaVersionGuard {
    public static func validate(candidate: JSONValue, expected: String) throws {
        let found = candidate["schemaVersion"]?.stringValue ?? ""
        guard found == expected else {
            throw RefreshError.schemaMismatch(found: found, expected: expected)
        }
    }
}

public enum RefreshMapper {
    /// Accepts either a bare JSON array or `{ "data": [...] }`.
    public static func array(from payload: JSONValue, url: String) throws -> [JSONValue] {
        if let array = payload.arrayValue { return array }
        if let array = payload["data"]?.arrayValue { return array }
        throw RefreshError.malformed(url: url, reason: "forventede en liste eller et data-felt")
    }

    public static func modelId(_ modelJSON: JSONValue) -> String? {
        modelJSON["id"]?.stringValue ?? modelJSON["model"]?.stringValue
    }

    /// Merges remote model/endpoint payloads into the bundled catalog shape.
    /// Remote data wins where it is present; bundled parameters survive when a remote
    /// endpoint omits them, so a thin upstream response never erases the form.
    public static func merge(
        bundled root: JSONValue,
        modelsPayload: JSONValue,
        endpointsByModel: [String: JSONValue],
        generatedAt: String
    ) throws -> JSONValue {
        var rootObject = root.objectValue ?? [:]
        let bundledModels = root["models"]?.arrayValue ?? []
        let remoteModels = try array(from: modelsPayload, url: "models")
        let remoteById = Dictionary(
            remoteModels.compactMap { item -> (String, JSONValue)? in
                guard let id = modelId(item) else { return nil }
                return (id, item)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var mergedModels: [JSONValue] = []
        var seen: Set<String> = []

        for bundled in bundledModels {
            guard let id = bundled["id"]?.stringValue else { continue }
            var model = bundled.objectValue ?? [:]
            if let remote = remoteById[id] {
                if let name = remote["name"]?.stringValue { model["name"] = .string(name) }
                if let created = remote["created"]?.stringValue { model["catalogDate"] = .string(created) }
                if let modalities = remote["input_modalities"] { model["inputModalities"] = modalities }
            }
            if let endpointsPayload = endpointsByModel[id] {
                model["surfaces"] = mergeSurfaces(
                    bundled: bundled["surfaces"] ?? .object([:]),
                    endpointsPayload: endpointsPayload,
                    modelId: id
                )
            }
            mergedModels.append(.object(model))
            seen.insert(id)
        }

        for (id, remote) in remoteById.sorted(by: { $0.key < $1.key }) where !seen.contains(id) {
            guard let endpointsPayload = endpointsByModel[id] else { continue }
            var model: [String: JSONValue] = [
                "id": .string(id),
                "name": remote["name"] ?? .string(id),
                "publisher": .string(String(id.split(separator: "/").first ?? "")),
                "inputModalities": remote["input_modalities"] ?? .array([.string("text")]),
                "outputModalities": .array([.string("image")]),
                "catalogDate": remote["created"] ?? .string(generatedAt),
            ]
            model["surfaces"] = mergeSurfaces(
                bundled: .object([:]),
                endpointsPayload: endpointsPayload,
                modelId: id
            )
            mergedModels.append(.object(model))
        }

        rootObject["models"] = .array(mergedModels)
        rootObject["generatedAt"] = .string(generatedAt)
        return .object(rootObject)
    }

    private static func mergeSurfaces(
        bundled: JSONValue,
        endpointsPayload: JSONValue,
        modelId: String
    ) -> JSONValue {
        var surfaces = bundled.objectValue ?? [:]
        let remoteEndpoints: [JSONValue]
        do {
            remoteEndpoints = try array(from: endpointsPayload, url: "endpoints")
        } catch {
            return .object(surfaces)
        }

        var surface = surfaces["images"]?.objectValue ?? [
            "status": .string("verified"),
            "endpoints": .array([]),
        ]
        var bundledById: [String: JSONValue] = [:]
        for endpoint in surface["endpoints"]?.arrayValue ?? [] {
            if let id = endpoint["id"]?.stringValue { bundledById[id] = endpoint }
        }

        var mergedEndpoints: [JSONValue] = []
        for remote in remoteEndpoints {
            let providerSlug = remoteProviderSlug(remote)
            guard !providerSlug.isEmpty else { continue }
            let id = remote["id"]?.stringValue ?? "\(modelId)@\(providerSlug)"
            var endpoint = bundledById[id]?.objectValue ?? [:]
            endpoint["id"] = .string(id)
            endpoint["providerSlug"] = .string(providerSlug)
            endpoint["providerTag"] = remote["providerTag"] ?? remote["provider_tag"] ?? .string(providerSlug)
            endpoint["providerName"] = remote["providerName"] ?? remote["provider_name"] ?? .string(providerSlug)
            if let streaming = remote["supportsStreaming"] ?? remote["supports_streaming"] {
                endpoint["supportsStreaming"] = streaming
            }
            if let pricing = remote["pricing"] {
                endpoint["pricing"] = normalizePricing(pricing)
            }
            if let parameters = remote["parameters"]?.arrayValue, !parameters.isEmpty {
                endpoint["parameters"] = .array(parameters.map { normalizeParameter($0, modelId: modelId, providerSlug: providerSlug) })
            }
            if endpoint["parameters"]?.arrayValue == nil {
                endpoint["parameters"] = .array([])
            }
            mergedEndpoints.append(.object(endpoint))
        }

        surface["endpoints"] = .array(mergedEndpoints)
        surfaces["images"] = .object(surface)
        return .object(surfaces)
    }

    private static func remoteProviderSlug(_ endpoint: JSONValue) -> String {
        if let slug = endpoint["providerSlug"]?.stringValue { return slug }
        if let slug = endpoint["provider_slug"]?.stringValue { return slug }
        if let provider = endpoint["provider"]?.stringValue { return provider }
        if let provider = endpoint["provider"]?["slug"]?.stringValue { return provider }
        return ""
    }

    private static func normalizePricing(_ pricing: JSONValue) -> JSONValue {
        if let array = pricing.arrayValue {
            return .array(array.compactMap { rule -> JSONValue? in
                guard let billable = rule["billable"]?.stringValue,
                      let unit = rule["unit"]?.stringValue,
                      let cost = rule["cost_usd"]?.decimalValue
                else { return nil }
                return .object([
                    "billable": .string(billable),
                    "unit": .string(unit),
                    "cost_usd": .number(cost),
                ])
            })
        }
        return .array([])
    }

    private static func normalizeParameter(_ parameter: JSONValue, modelId: String, providerSlug: String) -> JSONValue {
        var object = parameter.objectValue ?? [:]
        let key = object["key"]?.stringValue ?? ""
        if object["label"] == nil { object["label"] = .string(key) }
        if object["path"] == nil { object["path"] = .array([.string(key)]) }
        if object["schema"] == nil { object["schema"] = .object(["type": .string("string")]) }
        if object["control"] == nil { object["control"] = .string("text") }
        if object["required"] == nil { object["required"] = .bool(false) }
        if object["evidence"] == nil { object["evidence"] = .string("openapi") }
        if object["scope"] == nil {
            object["scope"] = .object([
                "modelId": .string(modelId),
                "providerSlug": .string(providerSlug),
                "providerTag": .string(providerSlug),
            ])
        }
        return .object(object)
    }
}

public struct CatalogRefreshResult: Sendable {
    public var data: Data
    public var summary: CatalogSummary
    public var manifest: [String: String]

    public init(data: Data, summary: CatalogSummary, manifest: [String: String]) {
        self.data = data
        self.summary = summary
        self.manifest = manifest
    }
}

public struct CatalogRefreshClient: Sendable {
    private let transport: any HTTPTransport
    private let log: DebugLog
    private let clock: any Clock

    public init(
        transport: any HTTPTransport,
        log: DebugLog = .shared,
        clock: any Clock = SystemClock()
    ) {
        self.transport = transport
        self.log = log
        self.clock = clock
    }

    public func refresh(bundledData: Data) async throws -> CatalogRefreshResult {
        let root = try JSONValue.parse(bundledData)
        let expectedVersion = root["schemaVersion"]?.stringValue ?? ""
        let sources = (root["sources"]?.objectValue ?? [:]).compactMapValues(\.stringValue)

        guard let modelsURLString = sources["imageModels"], let modelsURL = URL(string: modelsURLString) else {
            throw RefreshError.missingSource("imageModels")
        }
        guard let endpointTemplate = sources["imageEndpoints"] else {
            throw RefreshError.missingSource("imageEndpoints")
        }

        let modelsResponse = try await fetch(modelsURL)
        let modelsPayload = try JSONValue.parse(modelsResponse.body)
        let remoteModels = try RefreshMapper.array(from: modelsPayload, url: modelsURL.absoluteString)
        let ids = remoteModels.compactMap(RefreshMapper.modelId)

        var endpointsByModel: [String: JSONValue] = [:]
        var manifest: [String: String] = [modelsURL.absoluteString: "ok"]

        for id in ids {
            guard let url = endpointURL(template: endpointTemplate, modelId: id) else { continue }
            do {
                let response = try await fetch(url)
                endpointsByModel[id] = try JSONValue.parse(response.body)
                manifest[url.absoluteString] = "ok"
            } catch {
                log.log("Refresh: kunne ikke hente \(url.absoluteString): \(error)")
                throw error
            }
        }

        let merged = try RefreshMapper.merge(
            bundled: root,
            modelsPayload: modelsPayload,
            endpointsByModel: endpointsByModel,
            generatedAt: ISO8601DateFormatter().string(from: clock.now)
        )
        try SchemaVersionGuard.validate(candidate: merged, expected: expectedVersion)

        let data = try merged.encoded(pretty: true)
        let summary = CatalogStore.summarize(merged)
        return CatalogRefreshResult(data: data, summary: summary, manifest: manifest)
    }

    private func fetch(_ url: URL) async throws -> HTTPResponse {
        let response: HTTPResponse
        do {
            response = try await transport.send(HTTPRequest(url: url, headers: ["Accept": "application/json"]))
        } catch {
            log.log("Refresh: netværksfejl for \(url.absoluteString)")
            throw RefreshError.http(status: 0, url: url.absoluteString)
        }
        guard (200..<300).contains(response.statusCode) else {
            log.log("Refresh: HTTP \(response.statusCode) for \(url.absoluteString)")
            throw RefreshError.http(status: response.statusCode, url: url.absoluteString)
        }
        return response
    }

    func endpointURL(template: String, modelId: String) -> URL? {
        let parts = modelId.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return nil }
        guard let author = Self.encodedPathComponent(parts[0]),
              let slug = Self.encodedPathComponent(parts[1]),
              let templateURL = URL(string: template),
              templateURL.scheme == "https",
              let host = templateURL.host
        else { return nil }

        let replaced = template
            .replacingOccurrences(of: "{author}", with: author)
            .replacingOccurrences(of: "{slug}", with: slug)
        guard let url = URL(string: replaced),
              url.scheme == templateURL.scheme,
              url.host == host
        else { return nil }
        return url
    }

    /// Validates a path segment and percent-encodes anything outside the
    /// allowed path characters. Rejects dot segments, traversal, query and
    /// fragment delimiters, percent escapes and whitespace/control characters.
    private static func encodedPathComponent(_ component: String) -> String? {
        guard !component.isEmpty, component != ".", component != ".." else { return nil }
        let forbidden = CharacterSet(charactersIn: "/?#%")
            .union(.whitespacesAndNewlines)
            .union(.controlCharacters)
        guard component.rangeOfCharacter(from: forbidden) == nil else { return nil }

        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        allowed.subtract(.whitespacesAndNewlines)
        allowed.subtract(.controlCharacters)
        return component.addingPercentEncoding(withAllowedCharacters: allowed)
    }
}
