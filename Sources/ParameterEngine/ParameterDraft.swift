import CatalogCore
import CoreSupport
import Foundation

/// Three states per field: not set by the user, set to a value, or reset back to not set.
/// An unset field is never sent — the catalog's own rule for optional parameters.
public enum ParameterValue: Sendable, Hashable {
    case unset
    case value(JSONValue)

    public var json: JSONValue? {
        if case .value(let value) = self { return value }
        return nil
    }

    public var isSet: Bool { json != nil }
}

public struct ParameterDraft: Sendable, Equatable {
    private var values: [PathKey: JSONValue]

    public init(_ values: [PathKey: JSONValue] = [:]) {
        self.values = values
    }

    public subscript(path: PathKey) -> ParameterValue {
        get {
            if let value = values[path] { return .value(value) }
            return .unset
        }
        set {
            switch newValue {
            case .unset: values.removeValue(forKey: path)
            case .value(let value): values[path] = value
            }
        }
    }

    public func isSet(_ path: PathKey) -> Bool { values[path] != nil }

    public mutating func set(_ value: JSONValue, at path: PathKey) {
        values[path] = value
    }

    public mutating func reset(_ path: PathKey) {
        values.removeValue(forKey: path)
    }

    public var setPaths: [PathKey] { values.keys.sorted() }

    public var isEmpty: Bool { values.isEmpty }

    public var count: Int { values.count }

    public mutating func replaceAll(with replacement: [PathKey: JSONValue]) {
        values = replacement
    }

    public func dictionary() -> [PathKey: JSONValue] { values }

    /// Display form used in sidecars (`provider.options.openai.complexity`).
    public func displayDictionary() -> [String: JSONValue] {
        values.reduce(into: [:]) { partial, entry in
            partial[entry.key.description] = entry.value
        }
    }

    /// Only set parameters that are currently active for this endpoint.
    public func appliedParameters(for endpoint: Endpoint) -> [PathKey: JSONValue] {
        var result: [PathKey: JSONValue] = [:]
        for spec in endpoint.parameters where values[spec.path] != nil {
            if case .inactive = ConditionEvaluator.evaluate(spec.activeWhen, draft: self) { continue }
            if case .unknownOperator = ConditionEvaluator.evaluate(spec.activeWhen, draft: self) {
                DebugLog.shared.log("Ukendt activeWhen-operator på \(spec.path.description); feltet behandles som aktivt.")
            }
            result[spec.path] = values[spec.path]
        }
        return result
    }
}

// MARK: - Type compatibility

public enum TypeCompatibility {
    /// The nullable-stripped type names of a schema, e.g. `["integer","null"]` → `["integer"]`.
    public static func typeNames(of schema: JSONValue) -> [String] {
        schema.schemaTypeNames.filter { $0 != "null" }
    }

    public static func isNullable(_ schema: JSONValue) -> Bool {
        let names = schema.schemaTypeNames
        return names.contains("null") || names.isEmpty
    }

    public static func compatible(_ oldSchema: JSONValue, _ newSchema: JSONValue) -> Bool {
        let oldTypes = typeNames(of: oldSchema)
        let newTypes = typeNames(of: newSchema)
        guard let oldPrimary = oldTypes.first, let newPrimary = newTypes.first else { return true }
        if oldPrimary == newPrimary { return true }
        let numeric: Set<String> = ["number", "integer"]
        if numeric.contains(oldPrimary) && numeric.contains(newPrimary) { return true }
        return false
    }

    public static func description(_ schema: JSONValue) -> String {
        let types = typeNames(of: schema)
        return types.isEmpty ? "ukendt" : types.joined(separator: " eller ")
    }
}

// MARK: - Endpoint switch

public struct EndpointSwitchPlan: Sendable, Equatable {
    public struct Drop: Sendable, Equatable {
        public var path: PathKey
        public var value: JSONValue
        public var reason: String
    }

    public var kept: [PathKey: JSONValue]
    public var dropped: [Drop]

    public init(kept: [PathKey: JSONValue], dropped: [Drop]) {
        self.kept = kept
        self.dropped = dropped
    }

    public static func plan(draft: ParameterDraft, from oldEndpoint: Endpoint, to newEndpoint: Endpoint) -> EndpointSwitchPlan {
        var kept: [PathKey: JSONValue] = [:]
        var dropped: [Drop] = []

        for (path, value) in draft.dictionary().sorted(by: { $0.key < $1.key }) {
            guard let newSpec = newEndpoint.parameter(for: path) else {
                dropped.append(Drop(path: path, value: value, reason: "findes ikke på \(newEndpoint.modelId)"))
                continue
            }
            guard let oldSpec = oldEndpoint.parameter(for: path) else {
                kept[path] = value
                continue
            }
            if TypeCompatibility.compatible(oldSpec.schema, newSpec.schema) {
                kept[path] = value
            } else {
                dropped.append(Drop(
                    path: path,
                    value: value,
                    reason: "typen ændrer sig fra \(TypeCompatibility.description(oldSpec.schema)) til \(TypeCompatibility.description(newSpec.schema))"
                ))
            }
        }

        return EndpointSwitchPlan(kept: kept, dropped: dropped)
    }

    /// Applies the switch. Without confirmation the draft is unchanged.
    public func applied(to draft: ParameterDraft, confirming: Bool) -> ParameterDraft {
        guard confirming else { return draft }
        var result = draft
        result.replaceAll(with: kept)
        return result
    }
}
