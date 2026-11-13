import CatalogCore
import CoreSupport
import Foundation

public enum ConditionOutcome: Sendable, Equatable {
    case active
    case inactive
    case unknownOperator(String)
}

public enum ConditionEvaluator {
    /// `activeWhen` has three measured shapes: `equals`, `in` (values list) and `minItems`.
    /// An unknown operator keeps the field active and is reported once to the debug log.
    public static func evaluate(_ condition: JSONValue?, draft: ParameterDraft) -> ConditionOutcome {
        guard let condition, let object = condition.objectValue, !object.isEmpty else {
            return .active
        }
        guard let pathComponents = object["path"]?.arrayValue?.compactMap(\.stringValue),
              !pathComponents.isEmpty
        else {
            return .unknownOperator("path")
        }

        let known: Set<String> = ["path", "equals", "in", "minItems"]
        if let unknown = Set(object.keys).subtracting(known).sorted().first {
            return .unknownOperator(unknown)
        }

        let path = PathKey(pathComponents)
        let current = draft[path].json

        if let equals = object["equals"] {
            guard let current else { return .inactive }
            return current == equals ? .active : .inactive
        }
        if let allowed = object["in"]?.arrayValue {
            guard let current else { return .inactive }
            return allowed.contains(current) ? .active : .inactive
        }
        if let minimum = object["minItems"]?.intValue {
            guard case .array(let items)? = current else { return .inactive }
            return items.count >= minimum ? .active : .inactive
        }
        return .active
    }
}
