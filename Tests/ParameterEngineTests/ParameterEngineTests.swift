import AppKit
import CatalogCore
import CoreSupport
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import ParameterEngine

private func catalogStore() throws -> CatalogStore {
    try CatalogStore.bundled()
}

private func sunburstEndpoint() async throws -> Endpoint {
    let store = try catalogStore()
    let model = try #require(await store.model(id: "openai/gpt-image-2.6-sunburst"))
    return try #require(EndpointResolver.resolve(model).endpoint)
}

private func spec(_ endpoint: Endpoint, _ key: String) throws -> ParameterSpec {
    try #require(endpoint.parameters.first { $0.key == key })
}

private func writeImage(width: Int, height: Int, alpha: Bool, type: UTType) throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("image.\(type.preferredFilenameExtension ?? "png")")

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let alphaInfo: CGImageAlphaInfo = alpha ? .premultipliedLast : .noneSkipLast
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: alphaInfo.rawValue
    ))
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: alpha ? 0.5 : 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())

    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return url
}

@Suite("Field plan parity")
struct FieldPlanParityTests {
    @Test("Every images endpoint renders exactly the parameters the catalog declares")
    func parityAcrossImageEndpoints() async throws {
        let store = try catalogStore()
        let models = await store.allModels()
        var endpointsChecked = 0
        var fieldsChecked = 0

        for model in models {
            for endpoint in model.imageEndpoints {
                let plan = FieldPlan.make(
                    endpoint: endpoint,
                    draft: ParameterDraft(),
                    settings: FieldPlanSettings(showUncertain: true, hideInactive: false)
                )
                #expect(plan.allFields.count == endpoint.parameters.count, "\(endpoint.id)")
                #expect(!plan.allFields.isEmpty, "\(endpoint.id) har ingen felter")
                endpointsChecked += 1
                fieldsChecked += plan.allFields.count
            }
        }

        #expect(endpointsChecked == 69)
        #expect(fieldsChecked == 1_154)
    }

    @Test("Control-kind totals across all 1.907 entries equal the catalog numbers")
    func controlTotals() async throws {
        let store = try catalogStore()
        var totals: [String: Int] = [:]
        for model in await store.allModels() {
            for surface in model.surfaces.values {
                for endpoint in surface.endpoints {
                    for parameter in endpoint.parameters {
                        totals[parameter.control.rawValue, default: 0] += 1
                    }
                }
            }
        }

        #expect(totals["select"] == 357)
        #expect(totals["text"] == 283)
        #expect(totals["json-editor"] == 410)
        #expect(totals["number"] == 232)
        #expect(totals["multi-select"] == 190)
        #expect(totals["checkbox"] == 142)
        #expect(totals["repeater"] == 78)
        #expect(totals["ordered-multi-select"] == 69)
        #expect(totals["textarea"] == 69)
        #expect(totals["image-list"] == 68)
        #expect(totals["size-input"] == 6)
        #expect(totals["image-input"] == 2)
        #expect(totals["constant"] == 1)
        #expect(totals.values.reduce(0, +) == 1_907)
    }

    @Test("An unknown control falls back to the JSON editor")
    func unknownControl() {
        let mapping = ControlMapping.widget(for: .unknown("brand-new"))
        #expect(mapping.kind == .jsonEditor)
        #expect(mapping.isUnknown)
    }

    @Test("Sections, badges and search-driven expansion")
    func sectionsAndSearch() async throws {
        let endpoint = try await sunburstEndpoint()
        let plan = FieldPlan.make(endpoint: endpoint, draft: ParameterDraft())

        #expect(plan.sections.first?.id == "model")
        #expect(plan.sections.contains { $0.id == "routing" })
        #expect(plan.sections.contains { $0.id == "provider_options" })

        let providerOption = try #require(plan.allFields.first { $0.spec.group == "provider_options" })
        #expect(providerOption.sectionID == "provider_options")

        let hits = plan.matchingPaths("complexity")
        #expect(!hits.isEmpty)

        let label = FieldPlan.accessibilityLabel(for: try spec(endpoint, "prompt"), value: .unset)
        #expect(label.contains("Prompt"))
        #expect(label.contains("ikke sat"))
    }

    @Test("Uncertain fields are hidden unless enabled")
    func uncertainHidden() async throws {
        let store = try catalogStore()
        let model = try #require(await store.model(id: "openai/gpt-image-2.6-sunburst"))
        let endpoint = try #require(EndpointResolver.resolve(model).endpoint)

        let hidden = FieldPlan.make(endpoint: endpoint, draft: ParameterDraft(), settings: FieldPlanSettings(showUncertain: false))
        let all = FieldPlan.make(endpoint: endpoint, draft: ParameterDraft(), settings: FieldPlanSettings(showUncertain: true))
        #expect(hidden.allFields.count <= all.allFields.count)
        #expect(hidden.hiddenUncertainCount == all.allFields.count - hidden.allFields.count)
    }
}

@Suite("Draft and endpoint switching")
struct DraftTests {
    @Test("Tri-state: unset, set, reset")
    func triState() async throws {
        let endpoint = try await sunburstEndpoint()
        var draft = ParameterDraft()
        let path = PathKey(["quality"])

        #expect(draft[path] == .unset)
        #expect(draft.appliedParameters(for: endpoint).isEmpty)

        draft.set(.string("high"), at: path)
        #expect(draft.isSet(path))
        #expect(draft.appliedParameters(for: endpoint)[path] == .string("high"))

        draft.reset(path)
        #expect(draft[path] == .unset)
        #expect(draft.appliedParameters(for: endpoint)[path] == nil)
    }

    @Test("Switching endpoints keeps compatible paths and explains dropped ones")
    func switchPlan() async throws {
        let store = try catalogStore()
        let sunburst = try await sunburstEndpoint()
        let minimaxModel = try #require(await store.model(id: "minimax/minimax-h3-image"))
        let minimax = try #require(EndpointResolver.resolve(minimaxModel).endpoint)

        var draft = ParameterDraft()
        draft.set(.string("high"), at: PathKey(["quality"]))
        draft.set(.string("3:2"), at: PathKey(["aspect_ratio"]))

        let plan = EndpointSwitchPlan.plan(draft: draft, from: sunburst, to: minimax)
        #expect(plan.kept[PathKey(["aspect_ratio"])] == .string("3:2"))
        #expect(plan.dropped.contains { $0.path == PathKey(["quality"]) })

        let unchanged = plan.applied(to: draft, confirming: false)
        #expect(unchanged.isSet(PathKey(["quality"])))

        let applied = plan.applied(to: draft, confirming: true)
        #expect(!applied.isSet(PathKey(["quality"])))
        #expect(applied.isSet(PathKey(["aspect_ratio"])))
    }
}

@Suite("Schema validation")
struct SchemaValidationTests {
    @Test("Keyword coverage: one passing and one failing value each")
    func keywords() throws {
        let validator = JSONSchemaValidator()

        func issues(_ value: JSONValue, _ schema: JSONValue) -> [ParameterEngine.Issue] {
            validator.validate(value, schema: schema, path: PathKey(["x"]))
        }

        #expect(issues(.string("a"), .object(["type": .string("string")])).isEmpty)
        #expect(!issues(.number(1), .object(["type": .string("string")])).isEmpty)

        #expect(issues(.string("a"), .object(["enum": .array([.string("a")])])).isEmpty)
        #expect(!issues(.string("b"), .object(["enum": .array([.string("a")])])).isEmpty)

        #expect(issues(.number(3), .object(["minimum": .number(1), "maximum": .number(5)])).isEmpty)
        #expect(!issues(.number(9), .object(["maximum": .number(5)])).isEmpty)

        #expect(issues(.string("abc"), .object(["minLength": .number(1), "maxLength": .number(5)])).isEmpty)
        #expect(!issues(.string("abcdef"), .object(["maxLength": .number(5)])).isEmpty)

        #expect(issues(.array([.number(1)]), .object(["maxItems": .number(2)])).isEmpty)
        #expect(!issues(.array([.number(1), .number(2), .number(3)]), .object(["maxItems": .number(2)])).isEmpty)
    }

    @Test("Nullable types accept null and optional fields stay optional")
    func nullable() {
        let validator = JSONSchemaValidator()
        let schema = JSONValue.object(["type": .array([.string("integer"), .string("null")])])
        #expect(validator.validate(.null, schema: schema, path: PathKey(["x"])).isEmpty)
        #expect(validator.validate(.number(3), schema: schema, path: PathKey(["x"])).isEmpty)
        #expect(!validator.validate(.string("3"), schema: schema, path: PathKey(["x"])).isEmpty)
    }

    @Test("ContentPartImage resolves through $defs")
    func contentPartImage() async throws {
        let store = try catalogStore()
        let definitions = await store.definitions()
        let validator = JSONSchemaValidator(definitions: definitions)

        let valid = JSONValue.object([
            "type": .string("image_url"),
            "image_url": .object(["url": .string("https://example.com/a.png")]),
        ])
        let invalidType = JSONValue.object([
            "type": .string("text"),
            "image_url": .object(["url": .string("https://example.com/a.png")]),
        ])
        let missingURL = JSONValue.object(["type": .string("image_url")])
        let schema = JSONValue.object(["$ref": .string("#/$defs/ContentPartImage")])

        #expect(validator.validate(valid, schema: schema, path: PathKey(["ref"])).isEmpty)
        #expect(!validator.validate(invalidType, schema: schema, path: PathKey(["ref"])).isEmpty)
        #expect(!validator.validate(missingURL, schema: schema, path: PathKey(["ref"])).isEmpty)
    }

    @Test("Endpoint capability bounds win over the schema")
    func capabilityBounds() async throws {
        let store = try catalogStore()
        let model = try #require(await store.model(id: "openai/gpt-image-2.6-sunburst"))
        let endpoint = try #require(EndpointResolver.resolve(model).endpoint)
        let n = try spec(endpoint, "n")

        let schema = EffectiveSchema.schema(for: n)
        let validator = JSONSchemaValidator()
        #expect(validator.validate(.number(1), schema: schema, path: n.path).isEmpty)
        #expect(!validator.validate(.number(99), schema: schema, path: n.path).isEmpty)
    }
}

@Suite("Conditions and constraints")
struct ConditionTests {
    @Test("frame_count is inactive unless output_format is gif")
    func frameCount() async throws {
        let endpoint = try await sunburstEndpoint()
        let frameCount = try spec(endpoint, "frame_count")

        #expect(ConditionEvaluator.evaluate(frameCount.activeWhen, draft: ParameterDraft()) == .inactive)

        var draft = ParameterDraft()
        draft.set(.string("gif"), at: PathKey(["output_format"]))
        #expect(ConditionEvaluator.evaluate(frameCount.activeWhen, draft: draft) == .active)

        var jpegDraft = ParameterDraft()
        jpegDraft.set(.string("jpeg"), at: PathKey(["output_format"]))
        #expect(ConditionEvaluator.evaluate(frameCount.activeWhen, draft: jpegDraft) == .inactive)
    }

    @Test("An unknown operator keeps the field active and is reported")
    func unknownOperator() {
        let condition = JSONValue.object([
            "path": .array([.string("a")]),
            "greaterThan": .number(3),
        ])
        if case .unknownOperator(let name) = ConditionEvaluator.evaluate(condition, draft: ParameterDraft()) {
            #expect(name == "greaterThan")
        } else {
            Issue.record("Expected unknownOperator")
        }
    }

    @Test("Transparent background requires png or webp, with a one-click fix")
    func valueConstraints() async throws {
        let endpoint = try await sunburstEndpoint()
        let background = try spec(endpoint, "background")

        var draft = ParameterDraft()
        draft.set(.string("transparent"), at: background.path)
        draft.set(.string("jpeg"), at: PathKey(["output_format"]))

        let issues = ValueConstraintEvaluator.issues(for: background, draft: draft)
        #expect(issues.count == 1)
        #expect(issues.first?.severity == .blocking)
        #expect(issues.first?.message.contains("png") == true)
        #expect(issues.first?.fixSuggestion?.value == .string("png"))

        let options = ValueConstraintEvaluator.availability(for: background, draft: draft)
        #expect(options.first { $0.value == .string("transparent") }?.isEnabled == false)

        draft.set(.string("png"), at: PathKey(["output_format"]))
        #expect(ValueConstraintEvaluator.issues(for: background, draft: draft).isEmpty)
    }

    @Test("All 13 value constraints mark their governed option unavailable")
    func allValueConstraints() async throws {
        let store = try catalogStore()
        var governed = 0
        var governedAndOffered = 0
        for model in await store.allModels() {
            for surface in model.surfaces.values {
                for endpoint in surface.endpoints {
                    for parameter in endpoint.parameters where !parameter.valueConstraints.isEmpty {
                        for constraint in parameter.valueConstraints {
                            guard let value = constraint["value"] else { continue }
                            governed += 1
                            var draft = ParameterDraft()
                            draft.set(value, at: parameter.path)
                            let issues = ValueConstraintEvaluator.issues(for: parameter, draft: draft)
                            if ValueConstraintEvaluator.optionValues(for: parameter).contains(value) {
                                governedAndOffered += 1
                                #expect(issues.count == 1, "\(endpoint.id) \(parameter.path)")
                            } else {
                                #expect(issues.isEmpty, "værdien er ikke en valgmulighed på \(endpoint.id)")
                            }
                        }
                    }
                }
            }
        }
        #expect(governed == 13)
        // Two endpoints only offer "auto"/"opaque", so "transparent" is not a selectable option there.
        #expect(governedAndOffered == 11)
    }
}

@Suite("Field constraints")
struct FieldConstraintTests {
    @Test("Mask must be PNG, transparent and match the reference dimensions")
    func mask() async throws {
        let endpoint = try await sunburstEndpoint()
        let markup = try spec(endpoint, "markup")

        let reference = try writeImage(width: 64, height: 64, alpha: true, type: .png)
        let goodMask = try writeImage(width: 64, height: 64, alpha: true, type: .png)
        let opaqueMask = try writeImage(width: 64, height: 64, alpha: false, type: .png)
        let jpegMask = try writeImage(width: 64, height: 64, alpha: false, type: .jpeg)
        let smallMask = try writeImage(width: 32, height: 32, alpha: true, type: .png)

        func value(_ url: URL) -> JSONValue {
            .object([
                "type": .string("image_url"),
                "image_url": .object(["url": .string(url.absoluteString)]),
            ])
        }

        #expect(FieldConstraintEvaluator.evaluate(spec: markup, value: value(goodMask), references: [reference]).isEmpty)

        let jpegIssues = FieldConstraintEvaluator.evaluate(spec: markup, value: value(jpegMask), references: [reference])
        #expect(jpegIssues.contains { $0.message.contains("image/png") })

        let alphaIssues = FieldConstraintEvaluator.evaluate(spec: markup, value: value(opaqueMask), references: [reference])
        #expect(alphaIssues.contains { $0.message.contains("gennemsigtig") })

        let dimensionIssues = FieldConstraintEvaluator.evaluate(spec: markup, value: value(smallMask), references: [reference])
        #expect(dimensionIssues.contains { $0.message.contains("dimensioner") })
    }
}

@Suite("Validation engine")
struct ValidationEngineTests {
    @Test("Required, warning and run state")
    func runState() async throws {
        let endpoint = try await sunburstEndpoint()
        let engine = ValidationEngine()

        let empty = engine.runState(draft: ParameterDraft(), endpoint: endpoint)
        #expect(!empty.canRun)
        #expect(empty.blockingCount >= 1)
        #expect(empty.summary.contains("mangler opmærksomhed"))

        var draft = ParameterDraft()
        draft.set(.string("Et fyrtårn"), at: PathKey(["prompt"]))
        let ready = engine.runState(draft: draft, endpoint: endpoint)
        #expect(ready.canRun)

        draft.set(.string("x"), at: PathKey(["not_a_field"]))
        let warned = engine.runState(draft: draft, endpoint: endpoint)
        #expect(warned.canRun)
        #expect(warned.warningCount == 1)
    }

    @Test("Validating 200 fields stays under 20 ms")
    func performance() throws {
        let scope = ParameterScope(modelId: "synthetic/model")
        let parameters = (0..<200).map { index in
            ParameterSpec(
                key: "field\(index)",
                label: "Felt \(index)",
                path: PathKey(["field\(index)"]),
                scope: scope,
                schema: .object(["type": .string("string"), "maxLength": .number(20)]),
                control: .text,
                required: false,
                evidence: .openapi
            )
        }
        let endpoint = Endpoint(
            id: "synthetic/model@synthetic",
            providerName: "Synthetic",
            providerSlug: "synthetic",
            providerTag: "synthetic",
            modelId: "synthetic/model",
            parameters: parameters
        )
        var draft = ParameterDraft()
        for index in 0..<200 {
            draft.set(.string("værdi\(index)"), at: PathKey(["field\(index)"]))
        }

        let engine = ValidationEngine()
        let clock = ContinuousClock()
        var issues: [ParameterEngine.Issue] = []
        let elapsed = clock.measure {
            issues = engine.validate(draft: draft, endpoint: endpoint)
        }
        print("Validated 200 fields in \(elapsed)")
        #expect(issues.isEmpty)
        #expect(elapsed < .milliseconds(20))
    }
}
