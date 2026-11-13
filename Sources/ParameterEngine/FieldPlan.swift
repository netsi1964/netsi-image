import CatalogCore
import CoreSupport
import Foundation

public struct FieldPlanSettings: Sendable, Equatable {
    public var showUncertain: Bool
    public var hideInactive: Bool
    public var requiredFirst: Bool

    public init(showUncertain: Bool = true, hideInactive: Bool = true, requiredFirst: Bool = true) {
        self.showUncertain = showUncertain
        self.hideInactive = hideInactive
        self.requiredFirst = requiredFirst
    }
}

public struct PlannedField: Sendable, Equatable, Identifiable {
    public var spec: ParameterSpec
    public var widget: ControlKind
    public var isUnknownControl: Bool
    public var isActive: Bool
    public var isSet: Bool
    public var sectionID: String
    public var accessibilityLabel: String

    public var id: PathKey { spec.path }
}

public struct PlannedSection: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var fields: [PlannedField]
    public var changedCount: Int
    public var inactiveCount: Int

    public var subtitle: String {
        var parts = ["\(fields.count) felter"]
        if changedCount > 0 { parts.append("\(changedCount) ændret") }
        if inactiveCount > 0 { parts.append("\(inactiveCount) inaktiv") }
        return parts.joined(separator: " · ")
    }
}

public enum ControlMapping {
    /// One table feeds both the widget factory and the parity tests.
    public static func widget(for kind: ControlKind) -> (kind: ControlKind, isUnknown: Bool) {
        switch kind {
        case .unknown: return (.jsonEditor, true)
        default: return (kind, false)
        }
    }
}

public struct FieldPlan: Sendable, Equatable {
    public var endpointId: String
    public var sections: [PlannedSection]
    public var hiddenUncertainCount: Int
    public var hiddenInactiveCount: Int

    public init(
        endpointId: String,
        sections: [PlannedSection],
        hiddenUncertainCount: Int,
        hiddenInactiveCount: Int
    ) {
        self.endpointId = endpointId
        self.sections = sections
        self.hiddenUncertainCount = hiddenUncertainCount
        self.hiddenInactiveCount = hiddenInactiveCount
    }

    public var allFields: [PlannedField] { sections.flatMap(\.fields) }

    public func field(_ path: PathKey) -> PlannedField? {
        allFields.first { $0.spec.path == path }
    }

    public static func make(
        endpoint: Endpoint,
        draft: ParameterDraft,
        settings: FieldPlanSettings = FieldPlanSettings()
    ) -> FieldPlan {
        var hiddenUncertain = 0
        var hiddenInactive = 0
        var buckets: [String: [PlannedField]] = [:]
        var inactiveBySection: [String: Int] = [:]

        for spec in endpoint.parameters {
            if !settings.showUncertain && spec.bucket == .uncertain {
                hiddenUncertain += 1
                continue
            }

            let sectionID = section(for: spec)
            let outcome = ConditionEvaluator.evaluate(spec.activeWhen, draft: draft)
            let isActive: Bool
            switch outcome {
            case .active, .unknownOperator:
                isActive = true
            case .inactive:
                isActive = false
            }

            if !isActive {
                hiddenInactive += 1
                inactiveBySection[sectionID, default: 0] += 1
                if settings.hideInactive { continue }
            }

            let mapping = ControlMapping.widget(for: spec.control)
            let field = PlannedField(
                spec: spec,
                widget: mapping.kind,
                isUnknownControl: mapping.isUnknown,
                isActive: isActive,
                isSet: draft.isSet(spec.path),
                sectionID: sectionID,
                accessibilityLabel: accessibilityLabel(for: spec, value: draft[spec.path])
            )
            buckets[sectionID, default: []].append(field)
        }

        let order = ["model", "routing", "provider_options"]
        let sections = order.compactMap { id -> PlannedSection? in
            guard let fields = buckets[id], !fields.isEmpty || (inactiveBySection[id] ?? 0) > 0 else { return nil }
            let sorted = settings.requiredFirst
                ? fields.filter(\.spec.required) + fields.filter { !$0.spec.required }
                : fields
            return PlannedSection(
                id: id,
                title: title(for: id),
                fields: sorted,
                changedCount: fields.filter(\.isSet).count,
                inactiveCount: inactiveBySection[id] ?? 0
            )
        }

        return FieldPlan(
            endpointId: endpoint.id,
            sections: sections,
            hiddenUncertainCount: hiddenUncertain,
            hiddenInactiveCount: hiddenInactive
        )
    }

    public static func section(for spec: ParameterSpec) -> String {
        switch spec.group {
        case "routing": return "routing"
        case "provider_options": return "provider_options"
        default: return "model"
        }
    }

    public static func title(for sectionID: String) -> String {
        switch sectionID {
        case "routing": return "Routing"
        case "provider_options": return "Provider-options"
        default: return "Modelparametre"
        }
    }

    /// Matches key, label and path. Returns the matching paths so the UI can expand their sections.
    public func matchingPaths(_ query: String) -> [PathKey] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return allFields.map(\.spec.path) }
        return allFields.filter { field in
            field.spec.key.lowercased().contains(needle)
                || field.spec.label.lowercased().contains(needle)
                || field.spec.path.description.lowercased().contains(needle)
        }.map(\.spec.path)
    }

    public static func accessibilityLabel(for spec: ParameterSpec, value: ParameterValue) -> String {
        let typeTitle: String
        switch spec.control {
        case .checkbox: typeTitle = "ja/nej"
        case .number, .sizeInput: typeTitle = "tal"
        case .select, .multiSelect, .orderedMultiSelect: typeTitle = "valgmulighed"
        case .imageList, .imageInput: typeTitle = "billede"
        case .repeater: typeTitle = "liste af rækker"
        case .jsonEditor: typeTitle = "JSON"
        default: typeTitle = "tekst"
        }

        let valueTitle: String
        switch value {
        case .unset:
            valueTitle = "ikke sat"
        case .value(let json):
            switch json {
            case .string(let text): valueTitle = text
            case .number(let number): valueTitle = "\(number)"
            case .bool(let flag): valueTitle = flag ? "ja" : "nej"
            case .null: valueTitle = "tom"
            case .array(let items): valueTitle = "\(items.count) elementer"
            case .object: valueTitle = "objekt"
            }
        }

        return "\(spec.label), \(typeTitle), \(valueTitle)"
    }
}
