import CatalogCore
import CoreSupport
import Foundation
import ParameterEngine

public enum RequestError: Error, Equatable, Sendable, CustomStringConvertible {
    case unsupportedSurface(SurfaceKind)
    case blockingIssues([Issue])
    case emptyEndpoint(String)

    public var description: String {
        switch self {
        case .unsupportedSurface(let surface):
            return "Fladen \(surface.rawValue) understøttes ikke i denne version."
        case .blockingIssues(let issues):
            return issues.map(\.message).joined(separator: " ")
        case .emptyEndpoint(let id):
            return "Endpointet \(id) har ingen parametre."
        }
    }
}

public struct RequestBuildResult: Sendable, Equatable {
    public var body: JSONValue
    public var warnings: [Issue]
    public var notSent: [PathKey]

    public init(body: JSONValue, warnings: [Issue] = [], notSent: [PathKey] = []) {
        self.body = body
        self.warnings = warnings
        self.notSent = notSent
    }
}

public enum ProviderRoutingPlanner {
    public static func isProviderOptionPath(_ path: PathKey) -> Bool {
        path.components.count >= 2 && path.components[0] == "provider" && path.components[1] == "options"
    }

    /// Merges the endpoint's pin without overwriting a value the user set explicitly.
    public static func mergePin(_ pin: ProviderPin, into body: inout [String: JSONValue], draft: ParameterDraft) {
        var provider = body["provider"]?.objectValue ?? [:]
        if !draft.isSet(PathKey(["provider", "only"])) {
            provider["only"] = .array(pin.only.map(JSONValue.string))
        }
        if !draft.isSet(PathKey(["provider", "allow_fallbacks"])) {
            provider["allow_fallbacks"] = .bool(pin.allowFallbacks)
        }
        body["provider"] = .object(provider)
    }
}

public struct ImagesRequestBuilder: Sendable {
    public let definitions: [String: JSONValue]
    private let probe: any ImageProbing

    public init(definitions: [String: JSONValue] = [:], probe: any ImageProbing = ImageIOProbe()) {
        self.definitions = definitions
        self.probe = probe
    }

    /// Builds the exact body for `POST /api/v1/images`. Never returns a partial body:
    /// blocking validation issues throw instead.
    public func build(
        surface: SurfaceKind = .images,
        endpoint: Endpoint,
        draft: ParameterDraft,
        explicitProvider: Bool = true,
        streamEnabled: Bool = false,
        references: [URL] = []
    ) throws -> RequestBuildResult {
        guard surface == .images else {
            throw RequestError.unsupportedSurface(surface)
        }
        guard !endpoint.parameters.isEmpty else {
            throw RequestError.emptyEndpoint(endpoint.id)
        }

        // `model` is always set by the builder, so validation must see it as satisfied.
        var effectiveDraft = draft
        if endpoint.parameters.contains(where: { $0.path == PathKey(["model"]) }) {
            effectiveDraft.set(.string(endpoint.modelId), at: PathKey(["model"]))
        }

        let engine = ValidationEngine(definitions: definitions, probe: probe)
        let issues = engine.validate(draft: effectiveDraft, endpoint: endpoint, references: references)
        let blocking = issues.filter { $0.severity == .blocking }
        guard blocking.isEmpty else {
            throw RequestError.blockingIssues(blocking)
        }

        var body: [String: JSONValue] = [:]
        var warnings = issues.filter { $0.severity == .warning }

        for (path, value) in effectiveDraft.appliedParameters(for: endpoint).sorted(by: { $0.key < $1.key }) {
            if !explicitProvider && ProviderRoutingPlanner.isProviderOptionPath(path) {
                warnings.append(Issue(
                    path: path,
                    severity: .warning,
                    message: "Provider-options sendes kun, når en bestemt provider er valgt. Feltet udelades ved automatisk routing."
                ))
                continue
            }
            Self.setValue(value, at: path, in: &body)
        }

        body["model"] = .string(endpoint.scopeModelId)

        if explicitProvider {
            let pin = endpoint.providerPin ?? ProviderPin(only: [endpoint.providerSlug], allowFallbacks: false)
            ProviderRoutingPlanner.mergePin(pin, into: &body, draft: draft)
        }

        if streamEnabled && endpoint.supportsStreaming && !draft.isSet(PathKey(["stream"])) {
            body["stream"] = .bool(true)
        }

        let knownPaths = Set(endpoint.parameters.map(\.path))
        let notSent = draft.setPaths.filter { path in
            guard knownPaths.contains(path) else { return true }
            if case .inactive = ConditionEvaluator.evaluate(endpoint.parameter(for: path)?.activeWhen, draft: draft) {
                return true
            }
            return false
        }

        return RequestBuildResult(body: .object(body), warnings: warnings, notSent: notSent)
    }

    /// Sets one key per path component, creating intermediate objects.
    public static func setValue(_ value: JSONValue, at path: PathKey, in object: inout [String: JSONValue]) {
        let components = path.components
        guard let head = components.first else { return }
        if components.count == 1 {
            object[head] = value
            return
        }
        var child = object[head]?.objectValue ?? [:]
        setValue(value, at: PathKey(Array(components.dropFirst())), in: &child)
        object[head] = .object(child)
    }

    public static func value(at path: PathKey, in object: JSONValue) -> JSONValue? {
        object.value(at: path.components)
    }
}

extension Endpoint {
    public var scopeModelId: String {
        modelId
    }
}
