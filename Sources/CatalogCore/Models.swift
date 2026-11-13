import CoreSupport
import Foundation

public enum SurfaceKind: Sendable, Hashable, Codable, CustomStringConvertible {
    case images
    case chatCompletions
    case responses
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "images": self = .images
        case "chatCompletions": self = .chatCompletions
        case "responses": self = .responses
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .images: return "images"
        case .chatCompletions: return "chatCompletions"
        case .responses: return "responses"
        case .unknown(let value): return value
        }
    }

    public var description: String { rawValue }

    public var title: String {
        switch self {
        case .images: return "Images"
        case .chatCompletions: return "Chat Completions"
        case .responses: return "Responses"
        case .unknown(let value): return value
        }
    }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum ControlKind: Sendable, Hashable, Codable, CustomStringConvertible {
    case select
    case text
    case number
    case textarea
    case checkbox
    case multiSelect
    case orderedMultiSelect
    case repeater
    case imageList
    case imageInput
    case sizeInput
    case jsonEditor
    case constant
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "select": self = .select
        case "text": self = .text
        case "number": self = .number
        case "textarea": self = .textarea
        case "checkbox": self = .checkbox
        case "multi-select": self = .multiSelect
        case "ordered-multi-select": self = .orderedMultiSelect
        case "repeater": self = .repeater
        case "image-list": self = .imageList
        case "image-input": self = .imageInput
        case "size-input": self = .sizeInput
        case "json-editor": self = .jsonEditor
        case "constant": self = .constant
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .select: return "select"
        case .text: return "text"
        case .number: return "number"
        case .textarea: return "textarea"
        case .checkbox: return "checkbox"
        case .multiSelect: return "multi-select"
        case .orderedMultiSelect: return "ordered-multi-select"
        case .repeater: return "repeater"
        case .imageList: return "image-list"
        case .imageInput: return "image-input"
        case .sizeInput: return "size-input"
        case .jsonEditor: return "json-editor"
        case .constant: return "constant"
        case .unknown(let value): return value
        }
    }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum EvidenceKind: Sendable, Hashable, Codable, CustomStringConvertible {
    case endpointCatalog
    case generalEndpointCatalog
    case openapi
    case upstreamSchema
    case crossSurfaceHint
    case surfaceUnverified
    case historicalDocumentation
    case openrouterDocumentation
    case inferredType
    case allowlistOnly
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "endpoint_catalog": self = .endpointCatalog
        case "general_endpoint_catalog": self = .generalEndpointCatalog
        case "openapi": self = .openapi
        case "upstream_schema": self = .upstreamSchema
        case "cross_surface_hint": self = .crossSurfaceHint
        case "surface_unverified": self = .surfaceUnverified
        case "historical_documentation": self = .historicalDocumentation
        case "openrouter_documentation": self = .openrouterDocumentation
        case "inferred_type": self = .inferredType
        case "allowlist_only": self = .allowlistOnly
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .endpointCatalog: return "endpoint_catalog"
        case .generalEndpointCatalog: return "general_endpoint_catalog"
        case .openapi: return "openapi"
        case .upstreamSchema: return "upstream_schema"
        case .crossSurfaceHint: return "cross_surface_hint"
        case .surfaceUnverified: return "surface_unverified"
        case .historicalDocumentation: return "historical_documentation"
        case .openrouterDocumentation: return "openrouter_documentation"
        case .inferredType: return "inferred_type"
        case .allowlistOnly: return "allowlist_only"
        case .unknown(let value): return value
        }
    }

    public var description: String { rawValue }

    public var bucket: EvidenceBucket {
        switch self {
        case .endpointCatalog, .generalEndpointCatalog: return .verified
        case .openapi: return .schema
        case .openrouterDocumentation, .historicalDocumentation: return .documentation
        case .upstreamSchema, .crossSurfaceHint: return .provider
        case .surfaceUnverified, .allowlistOnly, .inferredType, .unknown: return .uncertain
        }
    }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum EvidenceBucket: String, Sendable, Hashable, CaseIterable {
    case verified
    case schema
    case documentation
    case provider
    case uncertain

    public var badge: String {
        switch self {
        case .verified: return "●"
        case .schema: return "○"
        case .documentation: return "◐"
        case .provider: return "◑"
        case .uncertain: return "◇"
        }
    }

    public var title: String {
        switch self {
        case .verified: return "Verificeret"
        case .schema: return "Skema"
        case .documentation: return "Dok."
        case .provider: return "Provider"
        case .uncertain: return "Usikker"
        }
    }
}

public struct ParameterScope: Sendable, Hashable, Codable {
    public var modelId: String
    public var modelVersion: String?
    public var providerSlug: String?
    public var providerTag: String?

    public init(
        modelId: String,
        modelVersion: String? = nil,
        providerSlug: String? = nil,
        providerTag: String? = nil
    ) {
        self.modelId = modelId
        self.modelVersion = modelVersion
        self.providerSlug = providerSlug
        self.providerTag = providerTag
    }
}

public struct PriceRule: Sendable, Hashable, Codable {
    public var billable: String
    public var unit: String
    public var costUSD: Decimal

    public init(billable: String, unit: String, costUSD: Decimal) {
        self.billable = billable
        self.unit = unit
        self.costUSD = costUSD
    }
}

public struct ProviderPin: Sendable, Hashable, Codable {
    public var only: [String]
    public var allowFallbacks: Bool

    public init(only: [String], allowFallbacks: Bool) {
        self.only = only
        self.allowFallbacks = allowFallbacks
    }
}

public struct ParameterSpec: Sendable, Hashable, Codable, Identifiable {
    public var key: String
    public var label: String
    public var path: PathKey
    public var scope: ParameterScope
    public var schema: JSONValue
    public var control: ControlKind
    public var required: Bool
    public var evidence: EvidenceKind
    public var source: String?
    public var capability: JSONValue?
    public var activeWhen: JSONValue?
    public var valueConstraints: [JSONValue]
    public var constraints: JSONValue?
    public var suggestedValues: [JSONValue]
    public var group: String?
    public var note: String?
    public var allowedBy: String?

    public var id: PathKey { path }
    public var bucket: EvidenceBucket { evidence.bucket }

    public init(
        key: String,
        label: String,
        path: PathKey,
        scope: ParameterScope,
        schema: JSONValue,
        control: ControlKind,
        required: Bool,
        evidence: EvidenceKind,
        source: String? = nil,
        capability: JSONValue? = nil,
        activeWhen: JSONValue? = nil,
        valueConstraints: [JSONValue] = [],
        constraints: JSONValue? = nil,
        suggestedValues: [JSONValue] = [],
        group: String? = nil,
        note: String? = nil,
        allowedBy: String? = nil
    ) {
        self.key = key
        self.label = label
        self.path = path
        self.scope = scope
        self.schema = schema
        self.control = control
        self.required = required
        self.evidence = evidence
        self.source = source
        self.capability = capability
        self.activeWhen = activeWhen
        self.valueConstraints = valueConstraints
        self.constraints = constraints
        self.suggestedValues = suggestedValues
        self.group = group
        self.note = note
        self.allowedBy = allowedBy
    }

    init(json: JSONValue, fallbackScope: ParameterScope) {
        key = json["key"]?.stringValue ?? ""
        label = json["label"]?.stringValue ?? key
        path = PathKey(json["path"]?.arrayValue?.compactMap(\.stringValue) ?? [key])
        if let scopeJSON = json["scope"] {
            scope = ParameterScope(
                modelId: scopeJSON["modelId"]?.stringValue ?? fallbackScope.modelId,
                modelVersion: scopeJSON["modelVersion"]?.stringValue,
                providerSlug: scopeJSON["providerSlug"]?.stringValue,
                providerTag: scopeJSON["providerTag"]?.stringValue
            )
        } else {
            scope = fallbackScope
        }
        schema = json["schema"] ?? .object([:])
        control = ControlKind(rawValue: json["control"]?.stringValue ?? "")
        required = json["required"]?.boolValue ?? false
        evidence = EvidenceKind(rawValue: json["evidence"]?.stringValue ?? "")
        source = json["source"]?.stringValue
        capability = json["capability"]
        activeWhen = json["activeWhen"]
        valueConstraints = json["valueConstraints"]?.arrayValue ?? []
        constraints = json["constraints"]
        suggestedValues = json["suggestedValues"]?.arrayValue ?? []
        group = json["group"]?.stringValue
        note = json["note"]?.stringValue
        allowedBy = json["allowedBy"]?.stringValue
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(label, forKey: .label)
        try container.encode(path.components, forKey: .path)
        try container.encode(scope, forKey: .scope)
        try container.encode(schema, forKey: .schema)
        try container.encode(control.rawValue, forKey: .control)
        try container.encode(required, forKey: .required)
        try container.encode(evidence.rawValue, forKey: .evidence)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(capability, forKey: .capability)
        try container.encodeIfPresent(activeWhen, forKey: .activeWhen)
        if !valueConstraints.isEmpty { try container.encode(valueConstraints, forKey: .valueConstraints) }
        try container.encodeIfPresent(constraints, forKey: .constraints)
        if !suggestedValues.isEmpty { try container.encode(suggestedValues, forKey: .suggestedValues) }
        try container.encodeIfPresent(group, forKey: .group)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(allowedBy, forKey: .allowedBy)
    }

    enum CodingKeys: String, CodingKey {
        case key, label, path, scope, schema, control, required, evidence, source
        case capability, activeWhen, valueConstraints, constraints, suggestedValues
        case group, note, allowedBy
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        label = try container.decode(String.self, forKey: .label)
        path = PathKey(try container.decode([String].self, forKey: .path))
        scope = try container.decode(ParameterScope.self, forKey: .scope)
        schema = try container.decode(JSONValue.self, forKey: .schema)
        control = ControlKind(rawValue: try container.decode(String.self, forKey: .control))
        required = try container.decode(Bool.self, forKey: .required)
        evidence = EvidenceKind(rawValue: try container.decode(String.self, forKey: .evidence))
        source = try container.decodeIfPresent(String.self, forKey: .source)
        capability = try container.decodeIfPresent(JSONValue.self, forKey: .capability)
        activeWhen = try container.decodeIfPresent(JSONValue.self, forKey: .activeWhen)
        valueConstraints = try container.decodeIfPresent([JSONValue].self, forKey: .valueConstraints) ?? []
        constraints = try container.decodeIfPresent(JSONValue.self, forKey: .constraints)
        suggestedValues = try container.decodeIfPresent([JSONValue].self, forKey: .suggestedValues) ?? []
        group = try container.decodeIfPresent(String.self, forKey: .group)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        allowedBy = try container.decodeIfPresent(String.self, forKey: .allowedBy)
    }
}

public struct Endpoint: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var providerName: String
    public var providerSlug: String
    public var providerTag: String
    public var modelId: String
    public var modelVersion: String?
    public var providerPin: ProviderPin?
    public var supportsStreaming: Bool
    public var pricing: [PriceRule]
    public var parameters: [ParameterSpec]

    public init(
        id: String,
        providerName: String,
        providerSlug: String,
        providerTag: String,
        modelId: String,
        modelVersion: String? = nil,
        providerPin: ProviderPin? = nil,
        supportsStreaming: Bool = false,
        pricing: [PriceRule] = [],
        parameters: [ParameterSpec] = []
    ) {
        self.id = id
        self.providerName = providerName
        self.providerSlug = providerSlug
        self.providerTag = providerTag
        self.modelId = modelId
        self.modelVersion = modelVersion
        self.providerPin = providerPin
        self.supportsStreaming = supportsStreaming
        self.pricing = pricing
        self.parameters = parameters
    }

    public func parameter(for path: PathKey) -> ParameterSpec? {
        parameters.first { $0.path == path }
    }
}

public struct CatalogSurface: Sendable, Hashable, Codable {
    public var status: String?
    public var source: String?
    public var endpoints: [Endpoint]

    public init(status: String? = nil, source: String? = nil, endpoints: [Endpoint] = []) {
        self.status = status
        self.source = source
        self.endpoints = endpoints
    }
}

public struct CatalogModel: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var publisher: String
    public var version: String?
    public var versionSource: String?
    public var kind: String?
    public var inputModalities: [String]
    public var outputModalities: [String]
    public var catalogDate: String?
    public var modelPage: String?
    public var surfaces: [String: CatalogSurface]

    public init(
        id: String,
        name: String,
        publisher: String,
        version: String? = nil,
        versionSource: String? = nil,
        kind: String? = nil,
        inputModalities: [String] = [],
        outputModalities: [String] = [],
        catalogDate: String? = nil,
        modelPage: String? = nil,
        surfaces: [String: CatalogSurface] = [:]
    ) {
        self.id = id
        self.name = name
        self.publisher = publisher
        self.version = version
        self.versionSource = versionSource
        self.kind = kind
        self.inputModalities = inputModalities
        self.outputModalities = outputModalities
        self.catalogDate = catalogDate
        self.modelPage = modelPage
        self.surfaces = surfaces
    }

    public var surfaceKinds: [SurfaceKind] {
        surfaces.keys.map(SurfaceKind.init(rawValue:)).sorted { $0.rawValue < $1.rawValue }
    }

    public func surface(_ kind: SurfaceKind) -> CatalogSurface? {
        surfaces[kind.rawValue]
    }

    public var imageEndpoints: [Endpoint] {
        surface(.images)?.endpoints ?? []
    }

    public var providerSlugs: [String] {
        Array(Set(surfaces.values.flatMap { $0.endpoints.map(\.providerSlug) })).sorted()
    }
}

public struct RequestExample: Sendable, Hashable, Codable {
    public var surface: SurfaceKind
    public var body: JSONValue

    public init(surface: SurfaceKind, body: JSONValue) {
        self.surface = surface
        self.body = body
    }
}

public struct Catalog: Sendable, Codable {
    public var schemaVersion: String
    public var generatedAt: String
    public var baseURL: String?
    public var language: String?
    public var coverage: JSONValue?
    public var sources: [String: String]
    public var ui: JSONValue?
    public var apiSurfaces: [String: JSONValue]
    public var requestExamples: [RequestExample]
    public var models: [CatalogModel]
    public var definitions: [String: JSONValue]

    public init(
        schemaVersion: String,
        generatedAt: String,
        baseURL: String? = nil,
        language: String? = nil,
        coverage: JSONValue? = nil,
        sources: [String: String] = [:],
        ui: JSONValue? = nil,
        apiSurfaces: [String: JSONValue] = [:],
        requestExamples: [RequestExample] = [],
        models: [CatalogModel] = [],
        definitions: [String: JSONValue] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.baseURL = baseURL
        self.language = language
        self.coverage = coverage
        self.sources = sources
        self.ui = ui
        self.apiSurfaces = apiSurfaces
        self.requestExamples = requestExamples
        self.models = models
        self.definitions = definitions
    }
}

// MARK: - Decoding

extension Catalog {
    public init(json: JSONValue) {
        schemaVersion = json["schemaVersion"]?.stringValue ?? ""
        generatedAt = json["generatedAt"]?.stringValue ?? ""
        baseURL = json["baseUrl"]?.stringValue
        language = json["language"]?.stringValue
        coverage = json["coverage"]
        sources = (json["sources"]?.objectValue ?? [:]).compactMapValues(\.stringValue)
        ui = json["ui"]
        apiSurfaces = json["apiSurfaces"]?.objectValue ?? [:]
        requestExamples = (json["requestExamples"]?.arrayValue ?? []).map { item in
            RequestExample(
                surface: SurfaceKind(rawValue: item["surface"]?.stringValue ?? ""),
                body: item["body"] ?? .object([:])
            )
        }
        models = (json["models"]?.arrayValue ?? []).map(CatalogModel.init(json:))
        definitions = json["$defs"]?.objectValue ?? [:]
    }
}

extension CatalogModel {
    init(json: JSONValue) {
        let modelId = json["id"]?.stringValue ?? ""
        id = modelId
        name = json["name"]?.stringValue ?? modelId
        publisher = json["publisher"]?.stringValue ?? String(modelId.split(separator: "/").first ?? "")
        version = json["version"]?.stringValue
        versionSource = json["versionSource"]?.stringValue
        kind = json["kind"]?.stringValue
        inputModalities = json["inputModalities"]?.arrayValue?.compactMap(\.stringValue) ?? []
        outputModalities = json["outputModalities"]?.arrayValue?.compactMap(\.stringValue) ?? []
        catalogDate = json["catalogDate"]?.stringValue
        modelPage = json["modelPage"]?.stringValue

        let scope = ParameterScope(modelId: modelId)
        var mapped: [String: CatalogSurface] = [:]
        for (key, value) in json["surfaces"]?.objectValue ?? [:] {
            var surface = CatalogSurface(
                status: value["status"]?.stringValue,
                source: value["source"]?.stringValue
            )
            surface.endpoints = (value["endpoints"]?.arrayValue ?? []).map { endpointJSON in
                Endpoint(json: endpointJSON, modelId: modelId, fallbackScope: scope)
            }
            mapped[key] = surface
        }
        surfaces = mapped
    }
}

extension Endpoint {
    init(json: JSONValue, modelId: String, fallbackScope: ParameterScope) {
        providerSlug = json["providerSlug"]?.stringValue
            ?? json["provider"]?.stringValue
            ?? ""
        id = json["id"]?.stringValue
            ?? "\(modelId)@\(providerSlug)"
        providerName = json["providerName"]?.stringValue ?? providerSlug
        providerTag = json["providerTag"]?.stringValue ?? providerSlug
        self.modelId = modelId
        modelVersion = json["modelVersion"]?.stringValue
        if let pin = json["providerPin"] {
            providerPin = ProviderPin(
                only: pin["only"]?.arrayValue?.compactMap(\.stringValue) ?? [providerSlug],
                allowFallbacks: pin["allow_fallbacks"]?.boolValue ?? false
            )
        }
        supportsStreaming = json["supportsStreaming"]?.boolValue ?? false
        pricing = (json["pricing"]?.arrayValue ?? []).compactMap { item in
            guard let billable = item["billable"]?.stringValue,
                  let unit = item["unit"]?.stringValue,
                  let cost = item["cost_usd"]?.decimalValue
            else { return nil }
            return PriceRule(billable: billable, unit: unit, costUSD: cost)
        }
        var scope = fallbackScope
        scope.providerSlug = providerSlug
        scope.providerTag = providerTag
        let specs = (json["parameters"]?.arrayValue ?? []).map { ParameterSpec(json: $0, fallbackScope: scope) }
        parameters = specs
    }
}
