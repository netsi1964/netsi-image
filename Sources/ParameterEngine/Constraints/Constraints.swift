import CatalogCore
import CoreSupport
import Foundation

public struct FixSuggestion: Sendable, Hashable {
    public var label: String
    public var path: PathKey
    public var value: JSONValue

    public init(label: String, path: PathKey, value: JSONValue) {
        self.label = label
        self.path = path
        self.value = value
    }
}

public struct Issue: Sendable, Hashable, Identifiable {
    public enum Severity: String, Sendable, Hashable {
        case blocking
        case warning
    }

    public var path: PathKey?
    public var severity: Severity
    public var message: String
    public var expected: String?
    public var actual: String?
    public var fixSuggestion: FixSuggestion?

    public var id: String {
        "\(path?.description ?? "-")|\(severity.rawValue)|\(message)"
    }

    public init(
        path: PathKey?,
        severity: Severity,
        message: String,
        expected: String? = nil,
        actual: String? = nil,
        fixSuggestion: FixSuggestion? = nil
    ) {
        self.path = path
        self.severity = severity
        self.message = message
        self.expected = expected
        self.actual = actual
        self.fixSuggestion = fixSuggestion
    }
}

// MARK: - Value constraints (option level)

public struct OptionAvailability: Sendable, Equatable {
    public var value: JSONValue
    public var isEnabled: Bool
    public var reason: String?

    public init(value: JSONValue, isEnabled: Bool, reason: String? = nil) {
        self.value = value
        self.isEnabled = isEnabled
        self.reason = reason
    }
}

public enum ValueConstraintEvaluator {
    public static func optionValues(for spec: ParameterSpec) -> [JSONValue] {
        if let values = spec.schema["enum"]?.arrayValue { return values }
        if spec.capability?["type"]?.stringValue == "enum" {
            return spec.capability?["values"]?.arrayValue ?? []
        }
        return []
    }

    public static func availability(for spec: ParameterSpec, draft: ParameterDraft) -> [OptionAvailability] {
        optionValues(for: spec).map { option in
            for constraint in spec.valueConstraints {
                guard constraint["value"] == option, let requires = constraint["requires"] else { continue }
                if let reason = unsatisfied(requires, draft: draft) {
                    return OptionAvailability(value: option, isEnabled: false, reason: reason)
                }
            }
            return OptionAvailability(value: option, isEnabled: true)
        }
    }

    public static func issues(for spec: ParameterSpec, draft: ParameterDraft) -> [Issue] {
        guard let selected = draft[spec.path].json else { return [] }
        guard optionValues(for: spec).contains(selected) else { return [] }

        for constraint in spec.valueConstraints {
            guard constraint["value"] == selected, let requires = constraint["requires"] else { continue }
            guard let reason = unsatisfied(requires, draft: draft) else { continue }
            let requiresPath = PathKey(requires["path"]?.arrayValue?.compactMap(\.stringValue) ?? [])
            let allowed = requires["in"]?.arrayValue ?? []
            let fix = allowed.first.map { value in
                FixSuggestion(
                    label: "Sæt \(requiresPath.description) til \(display(value))",
                    path: requiresPath,
                    value: value
                )
            }
            return [Issue(
                path: spec.path,
                severity: .blocking,
                message: "“\(display(selected))” kræver, at \(reason).",
                expected: requires["in"]?.arrayValue?.map(display).joined(separator: " eller "),
                actual: display(selected),
                fixSuggestion: fix
            )]
        }
        return []
    }

    private static func unsatisfied(_ requires: JSONValue, draft: ParameterDraft) -> String? {
        guard let components = requires["path"]?.arrayValue?.compactMap(\.stringValue), !components.isEmpty else {
            return nil
        }
        let path = PathKey(components)
        guard let current = draft[path].json else {
            return "\(path.description) er sat"
        }
        if let allowed = requires["in"]?.arrayValue {
            if allowed.contains(current) { return nil }
            let list = allowed.map(display).joined(separator: " eller ")
            return "\(path.description) = \(list)"
        }
        if let equals = requires["equals"] {
            if current == equals { return nil }
            return "\(path.description) = \(display(equals))"
        }
        return nil
    }

    public static func display(_ value: JSONValue) -> String {
        switch value {
        case .string(let text): return text
        case .number(let number): return "\(number)"
        case .bool(let flag): return flag ? "ja" : "nej"
        case .null: return "tom"
        case .array(let items): return "[" + items.map(display).joined(separator: ", ") + "]"
        case .object: return "{…}"
        }
    }
}

// MARK: - Field constraints (content level)

public enum FieldConstraintEvaluator {
    public static func evaluate(
        spec: ParameterSpec,
        value: JSONValue,
        references: [URL],
        probe: any ImageProbing = ImageIOProbe()
    ) -> [Issue] {
        guard let constraints = spec.constraints?.objectValue, !constraints.isEmpty else { return [] }
        guard let fileURL = fileURL(from: value) else { return [] }
        guard let info = try? probe.probe(url: fileURL) else {
            return [Issue(
                path: spec.path,
                severity: .warning,
                message: "Billedet kunne ikke læses: \(fileURL.lastPathComponent)"
            )]
        }

        var issues: [Issue] = []

        if let mediaType = constraints["mediaType"]?.stringValue, info.mediaType != mediaType {
            issues.append(Issue(
                path: spec.path,
                severity: .blocking,
                message: "“\(spec.label)” skal være \(mediaType), men filen er \(info.mediaType ?? "ukendt").",
                expected: mediaType,
                actual: info.mediaType
            ))
        }

        if constraints["transparent"]?.boolValue == true, !info.hasAlpha {
            issues.append(Issue(
                path: spec.path,
                severity: .blocking,
                message: "“\(spec.label)” skal have gennemsigtig baggrund (alpha)."
            ))
        }

        if let index = constraints["matchDimensionsOfReference"]?.intValue,
           references.indices.contains(index),
           let reference = try? probe.probe(url: references[index]) {
            if reference.width != info.width || reference.height != info.height {
                issues.append(Issue(
                    path: spec.path,
                    severity: .blocking,
                    message: "“\(spec.label)” skal have samme dimensioner som referencebillede \(index + 1) (\(reference.width) × \(reference.height)), men er \(info.width) × \(info.height)."
                ))
            }
        }

        if let pixelSize = constraints["pixelSize"]?.objectValue, case .string(let text) = value {
            issues += pixelSizeIssues(spec: spec, text: text, pixelSize: pixelSize)
        }

        return issues
    }

    private static func pixelSizeIssues(spec: ParameterSpec, text: String, pixelSize: [String: JSONValue]) -> [Issue] {
        let parts = text.lowercased().split(separator: "x").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return [] }
        var issues: [Issue] = []
        if let step = pixelSize["step"]?.intValue {
            if parts[0] % step != 0 || parts[1] % step != 0 {
                issues.append(Issue(
                    path: spec.path,
                    severity: .blocking,
                    message: "Bredde og højde skal være delelige med \(step).",
                    actual: text
                ))
            }
        }
        if let maxRatio = pixelSize["maxAspectRatio"]?.decimalValue {
            let ratio = Decimal(max(parts[0], parts[1])) / Decimal(min(parts[0], parts[1]))
            if ratio > maxRatio {
                issues.append(Issue(
                    path: spec.path,
                    severity: .blocking,
                    message: "Forholdet mellem siderne må højst være \(maxRatio):1.",
                    actual: "\(ratio):1"
                ))
            }
        }
        return issues
    }

    private static func fileURL(from value: JSONValue) -> URL? {
        switch value {
        case .string(let text):
            if let url = URL(string: text), url.isFileURL { return url }
            return URL(fileURLWithPath: text)
        case .object(let object):
            if let urlString = object["image_url"]?["url"]?.stringValue ?? object["url"]?.stringValue {
                if let url = URL(string: urlString), url.isFileURL { return url }
                if urlString.hasPrefix("/") { return URL(fileURLWithPath: urlString) }
            }
            return nil
        default:
            return nil
        }
    }
}
