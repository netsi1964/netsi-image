import CatalogCore
import CoreSupport
import Foundation

public struct RunState: Sendable, Equatable {
    public var canRun: Bool
    public var blockingCount: Int
    public var warningCount: Int
    public var firstIssue: Issue?
    public var summary: String

    public init(
        canRun: Bool,
        blockingCount: Int,
        warningCount: Int,
        firstIssue: Issue?,
        summary: String
    ) {
        self.canRun = canRun
        self.blockingCount = blockingCount
        self.warningCount = warningCount
        self.firstIssue = firstIssue
        self.summary = summary
    }
}

public struct ValidationEngine: Sendable {
    public let definitions: [String: JSONValue]
    private let probe: any ImageProbing

    public init(definitions: [String: JSONValue] = [:], probe: any ImageProbing = ImageIOProbe()) {
        self.definitions = definitions
        self.probe = probe
    }

    /// One pass in a fixed order: required, schema, value constraints, content constraints.
    public func validate(
        draft: ParameterDraft,
        endpoint: Endpoint,
        references: [URL] = []
    ) -> [Issue] {
        let validator = JSONSchemaValidator(definitions: definitions)
        var issues: [Issue] = []

        for spec in endpoint.parameters {
            // `model` is structural: the builder always sets it from the endpoint.
            if spec.path == PathKey(["model"]) { continue }
            let condition = ConditionEvaluator.evaluate(spec.activeWhen, draft: draft)
            let isActive: Bool
            switch condition {
            case .inactive: isActive = false
            case .active, .unknownOperator: isActive = true
            }

            let value = draft[spec.path]
            if spec.required && isActive && !value.isSet {
                issues.append(Issue(
                    path: spec.path,
                    severity: .blocking,
                    message: "“\(spec.label)” er påkrævet.",
                    expected: "værdi"
                ))
                continue
            }

            guard let json = value.json, isActive else { continue }

            issues += validator.validate(json, schema: EffectiveSchema.schema(for: spec), path: spec.path)
            issues += ValueConstraintEvaluator.issues(for: spec, draft: draft)
            issues += FieldConstraintEvaluator.evaluate(
                spec: spec,
                value: json,
                references: references,
                probe: probe
            )
        }

        let known = Set(endpoint.parameters.map(\.path))
        for path in draft.setPaths where !known.contains(path) {
            issues.append(Issue(
                path: path,
                severity: .warning,
                message: "Feltet findes ikke på \(endpoint.modelId) og sendes ikke."
            ))
        }

        return issues
    }

    public func runState(
        draft: ParameterDraft,
        endpoint: Endpoint,
        references: [URL] = []
    ) -> RunState {
        let issues = validate(draft: draft, endpoint: endpoint, references: references)
        let blocking = issues.filter { $0.severity == .blocking }
        let warnings = issues.filter { $0.severity == .warning }
        let summary: String
        if blocking.isEmpty {
            summary = warnings.isEmpty ? "Klar" : "Klar · \(warnings.count) advarsel\(warnings.count == 1 ? "" : "er")"
        } else {
            summary = "\(blocking.count) felt\(blocking.count == 1 ? "" : "er") mangler opmærksomhed"
        }
        return RunState(
            canRun: blocking.isEmpty,
            blockingCount: blocking.count,
            warningCount: warnings.count,
            firstIssue: blocking.first ?? warnings.first,
            summary: summary
        )
    }
}
