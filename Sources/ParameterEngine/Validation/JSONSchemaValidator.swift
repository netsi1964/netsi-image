import CatalogCore
import CoreSupport
import Foundation

public enum EffectiveSchema {
    /// Endpoint `capability` bounds win over the general OpenAPI schema.
    public static func schema(for spec: ParameterSpec) -> JSONValue {
        guard let capability = spec.capability?.objectValue else { return spec.schema }
        var object = spec.schema.objectValue ?? [:]
        switch capability["type"]?.stringValue {
        case "range":
            if let minimum = capability["min"] { object["minimum"] = minimum }
            if let maximum = capability["max"] { object["maximum"] = maximum }
        case "enum":
            if let values = capability["values"] { object["enum"] = values }
        default:
            break
        }
        return .object(object)
    }
}

public struct JSONSchemaValidator: Sendable {
    public let definitions: [String: JSONValue]

    public init(definitions: [String: JSONValue] = [:]) {
        self.definitions = definitions
    }

    public func validate(_ value: JSONValue, schema: JSONValue, path: PathKey) -> [Issue] {
        validate(value, schema: schema, path: path, depth: 0)
    }

    public func resolve(ref: String) -> JSONValue? {
        let components = ref.split(separator: "/").map(String.init)
        guard ref.hasPrefix("#/"), components.count >= 2, components[0] == "#", components[1] == "$defs" else {
            DebugLog.shared.log("Ikke-lokal $ref ignoreret: \(ref)")
            return nil
        }
        let name = components.dropFirst(2).joined(separator: "/")
        guard let definition = definitions[name] else {
            DebugLog.shared.log("Uopløselig $ref: \(ref)")
            return nil
        }
        return definition
    }

    private func validate(_ value: JSONValue, schema: JSONValue, path: PathKey, depth: Int) -> [Issue] {
        guard depth < 32 else { return [] }
        guard var object = schema.objectValue else { return [] }
        var issues: [Issue] = []

        if let ref = object["$ref"]?.stringValue, let resolved = resolve(ref: ref) {
            issues += validate(value, schema: resolved, path: path, depth: depth + 1)
            object.removeValue(forKey: "$ref")
        }

        if case .null = value, isNullable(object) {
            return issues
        }

        if let declaredTypes = typeNames(object["type"]) {
            let matching = declaredTypes.contains { matchesType(value, $0) }
            if !matching {
                let expected = declaredTypes.filter { $0 != "null" }.joined(separator: " eller ")
                return issues + [Issue(
                    path: path,
                    severity: .blocking,
                    message: "Forventede \(expected), men fik \(value.kindDescription).",
                    expected: expected,
                    actual: value.kindDescription
                )]
            }
        }

        if let allowed = object["enum"]?.arrayValue, !allowed.contains(value) {
            issues.append(Issue(
                path: path,
                severity: .blocking,
                message: "Værdien skal være en af: \(allowed.map(ValueConstraintEvaluator.display).joined(separator: ", ")).",
                expected: allowed.map(ValueConstraintEvaluator.display).joined(separator: ", "),
                actual: ValueConstraintEvaluator.display(value)
            ))
        }

        if let constant = object["const"], constant != value {
            issues.append(Issue(
                path: path,
                severity: .blocking,
                message: "Værdien skal være \(ValueConstraintEvaluator.display(constant)).",
                expected: ValueConstraintEvaluator.display(constant),
                actual: ValueConstraintEvaluator.display(value)
            ))
        }

        if case .number(let number) = value {
            if let minimum = object["minimum"]?.decimalValue, number < minimum {
                issues.append(Issue(
                    path: path,
                    severity: .blocking,
                    message: "Værdien må mindst være \(minimum).",
                    expected: "≥ \(minimum)",
                    actual: "\(number)"
                ))
            }
            if let maximum = object["maximum"]?.decimalValue, number > maximum {
                issues.append(Issue(
                    path: path,
                    severity: .blocking,
                    message: "Værdien må højst være \(maximum).",
                    expected: "≤ \(maximum)",
                    actual: "\(number)"
                ))
            }
        }

        if case .string(let text) = value {
            if let minimum = object["minLength"]?.intValue, text.count < minimum {
                issues.append(Issue(
                    path: path,
                    severity: .blocking,
                    message: "Teksten skal være mindst \(minimum) tegn.",
                    expected: "≥ \(minimum) tegn",
                    actual: "\(text.count) tegn"
                ))
            }
            if let maximum = object["maxLength"]?.intValue, text.count > maximum {
                issues.append(Issue(
                    path: path,
                    severity: .blocking,
                    message: "Teksten må højst være \(maximum) tegn.",
                    expected: "≤ \(maximum) tegn",
                    actual: "\(text.count) tegn"
                ))
            }
            if let pattern = object["pattern"]?.stringValue, !Self.matches(pattern: pattern, text: text) {
                issues.append(Issue(
                    path: path,
                    severity: .blocking,
                    message: "Teksten matcher ikke mønstret \(pattern).",
                    expected: pattern,
                    actual: text
                ))
            }
        }

        if case .array(let items) = value {
            if let minimum = object["minItems"]?.intValue, items.count < minimum {
                issues.append(Issue(
                    path: path,
                    severity: .blocking,
                    message: "Listen skal have mindst \(minimum) elementer.",
                    expected: "≥ \(minimum)",
                    actual: "\(items.count)"
                ))
            }
            if let maximum = object["maxItems"]?.intValue, items.count > maximum {
                issues.append(Issue(
                    path: path,
                    severity: .blocking,
                    message: "Listen må højst have \(maximum) elementer.",
                    expected: "≤ \(maximum)",
                    actual: "\(items.count)"
                ))
            }
            if let itemSchema = object["items"] {
                for (index, item) in items.enumerated() {
                    issues += validate(item, schema: itemSchema, path: path.appending("\(index)"), depth: depth + 1)
                }
            }
        }

        if case .object(let dictionary) = value {
            let required = object["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
            for key in required where dictionary[key] == nil {
                issues.append(Issue(
                    path: path.appending(key),
                    severity: .blocking,
                    message: "Påkrævet felt mangler.",
                    expected: "felt"
                ))
            }
            if let properties = object["properties"]?.objectValue {
                for (key, propertySchema) in properties {
                    guard let propertyValue = dictionary[key] else { continue }
                    issues += validate(propertyValue, schema: propertySchema, path: path.appending(key), depth: depth + 1)
                }
            }
        }

        if let anyOf = object["anyOf"]?.arrayValue {
            let results = anyOf.map { validate(value, schema: $0, path: path, depth: depth + 1) }
            if results.allSatisfy({ !$0.isEmpty }) {
                issues.append(Issue(
                    path: path,
                    severity: .blocking,
                    message: "Værdien matcher ingen af de tilladte former."
                ))
            }
        }

        if let oneOf = object["oneOf"]?.arrayValue {
            let matching = oneOf.filter { validate(value, schema: $0, path: path, depth: depth + 1).isEmpty }
            if matching.count != 1 {
                issues.append(Issue(
                    path: path,
                    severity: .blocking,
                    message: "Værdien skal matche præcis én tilladt form (matcher \(matching.count))."
                ))
            }
        }

        if let allOf = object["allOf"]?.arrayValue {
            for subSchema in allOf {
                issues += validate(value, schema: subSchema, path: path, depth: depth + 1)
            }
        }

        return issues
    }

    private func isNullable(_ schema: [String: JSONValue]) -> Bool {
        guard let names = typeNames(schema["type"]) else { return false }
        return names.contains("null")
    }

    private func typeNames(_ value: JSONValue?) -> [String]? {
        guard let value else { return nil }
        if let name = value.stringValue { return [name] }
        if let names = value.arrayValue { return names.compactMap(\.stringValue) }
        return nil
    }

    private func matchesType(_ value: JSONValue, _ type: String) -> Bool {
        switch type {
        case "string":
            if case .string = value { return true }
        case "boolean":
            if case .bool = value { return true }
        case "integer":
            if case .number(let number) = value {
                let decimal = NSDecimalNumber(decimal: number)
                if decimal.decimalValue == Decimal(decimal.int64Value) { return true }
            }
        case "number":
            if case .number = value { return true }
        case "array":
            if case .array = value { return true }
        case "object":
            if case .object = value { return true }
        case "null":
            if case .null = value { return true }
        default:
            return true
        }
        return false
    }

    static func matches(pattern: String, text: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            DebugLog.shared.log("Ugyldigt pattern ignoreret: \(pattern)")
            return true
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.firstMatch(in: text, options: [], range: range) != nil
    }
}
