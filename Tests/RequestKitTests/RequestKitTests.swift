import CatalogCore
import CoreSupport
import Foundation
import Testing

@testable import ParameterEngine
@testable import RequestKit

private func store() throws -> CatalogStore { try CatalogStore.bundled() }

private func endpoint(modelId: String) async throws -> Endpoint {
    let model = try #require(await store().model(id: modelId))
    return try #require(EndpointResolver.resolve(model).endpoint)
}

private func draft(from body: JSONValue, endpoint: Endpoint) -> ParameterDraft {
    var draft = ParameterDraft()
    for spec in endpoint.parameters {
        if let value = body.value(at: spec.path.components) {
            draft.set(value, at: spec.path)
        }
    }
    return draft
}

@Suite("Request builder")
struct RequestBuilderTests {
    @Test("Reproduces requestExamples[0] exactly")
    func exampleOne() async throws {
        let store = try store()
        let catalog = await store.catalog()
        let example = try #require(catalog.requestExamples.first { $0.body["model"]?.stringValue == "openai/gpt-image-2.6-sunburst" })
        let endpoint = try await endpoint(modelId: "openai/gpt-image-2.6-sunburst")
        let builder = ImagesRequestBuilder(definitions: await store.definitions())

        let built = try builder.build(
            endpoint: endpoint,
            draft: draft(from: example.body, endpoint: endpoint),
            explicitProvider: true
        )
        #expect(built.body == example.body)
    }

    @Test("Reproduces requestExamples[1] exactly")
    func exampleTwo() async throws {
        let store = try store()
        let catalog = await store.catalog()
        let example = try #require(catalog.requestExamples.first { $0.body["model"]?.stringValue == "google/gemini-3.1-flash-image" })
        let model = try #require(await store.model(id: "google/gemini-3.1-flash-image"))
        let endpoint = try #require(model.imageEndpoints.first { $0.providerPin?.only == ["google-vertex/global"] })
        let builder = ImagesRequestBuilder(definitions: await store.definitions())

        let built = try builder.build(
            endpoint: endpoint,
            draft: draft(from: example.body, endpoint: endpoint),
            explicitProvider: true
        )
        #expect(built.body == example.body)
    }

    @Test("Nests provider options under provider.options.<slug>")
    func nesting() async throws {
        let model = try #require(await store().model(id: "sourceful/riverflow-v2.6-pro"))
        let endpoint = try #require(model.imageEndpoints.first)
        let fonts = try #require(endpoint.parameters.first { $0.path.components.contains("font_inputs") })

        var draft = ParameterDraft()
        draft.set(.string("Et banner"), at: PathKey(["prompt"]))
        let fontValue = JSONValue.array([
            .object(["font_url": .string("https://example.com/font.woff2"), "text": .string("Hej")]),
        ])
        draft.set(fontValue, at: fonts.path)

        let built = try ImagesRequestBuilder().build(endpoint: endpoint, draft: draft, explicitProvider: true)
        #expect(built.body.value(at: fonts.path.components) == fontValue)
        #expect(built.body["provider"]?["options"]?["sourceful"]?["font_inputs"] == fontValue)
    }

    @Test("Streaming is only requested where the endpoint supports it")
    func streaming() async throws {
        let store = try store()
        let models = await store.allModels()
        let streamingEndpoint = try #require(models.flatMap(\.imageEndpoints).first { $0.supportsStreaming })
        let nonStreaming = try #require(models.flatMap(\.imageEndpoints).first { !$0.supportsStreaming })

        var draft = ParameterDraft()
        draft.set(.string("Et billede"), at: PathKey(["prompt"]))

        let streamed = try ImagesRequestBuilder().build(
            endpoint: streamingEndpoint,
            draft: draft,
            explicitProvider: true,
            streamEnabled: true
        )
        #expect(streamed.body["stream"] == .bool(true))

        let plain = try ImagesRequestBuilder().build(
            endpoint: nonStreaming,
            draft: draft,
            explicitProvider: true,
            streamEnabled: true
        )
        #expect(plain.body["stream"] == nil)
    }

    @Test("Blocking validation refuses to produce a body")
    func blockingIssues() async throws {
        let endpoint = try await endpoint(modelId: "openai/gpt-image-2.6-sunburst")
        do {
            _ = try ImagesRequestBuilder().build(endpoint: endpoint, draft: ParameterDraft())
            Issue.record("Expected blockingIssues")
        } catch let error as RequestError {
            if case .blockingIssues(let issues) = error {
                #expect(issues.contains { $0.path == PathKey(["prompt"]) })
            } else {
                Issue.record("Wrong error: \(error)")
            }
        }
    }

    @Test("Auto routing drops provider options with a warning")
    func autoRouting() async throws {
        let model = try #require(await store().model(id: "openai/gpt-image-2.6-sunburst"))
        let endpoint = try #require(EndpointResolver.resolve(model).endpoint)
        var draft = ParameterDraft()
        draft.set(.string("Et fyrtårn"), at: PathKey(["prompt"]))
        let complexity = try #require(endpoint.parameters.first { $0.path.components.last == "complexity" })
        draft.set(.string("high"), at: complexity.path)

        let built = try ImagesRequestBuilder().build(endpoint: endpoint, draft: draft, explicitProvider: false)
        #expect(built.body["provider"]?["options"] == nil)
        #expect(built.warnings.contains { $0.message.contains("Provider-options") })
    }
    @Test("A non-images surface is refused explicitly")
    func unsupportedSurface() async throws {
        let endpoint = try await endpoint(modelId: "openai/gpt-image-2.6-sunburst")
        var draft = ParameterDraft()
        draft.set(.string("Et fyrtårn"), at: PathKey(["prompt"]))

        do {
            _ = try ImagesRequestBuilder().build(surface: .chatCompletions, endpoint: endpoint, draft: draft)
            Issue.record("Expected unsupportedSurface")
        } catch let error as RequestError {
            #expect(error == .unsupportedSurface(.chatCompletions))
        }
    }

    @Test("Catalog suggestions are offered and never restrict the value")
    func suggestions() async throws {
        let store = try store()
        let model = try #require(await store.model(id: "x-ai/grok-imagine-image-2.0"))
        let endpoint = try #require(EndpointResolver.resolve(model).endpoint)
        let order = try #require(endpoint.parameters.first { $0.key == "order" })
        #expect(order.suggestedValues == [.string("xai")])

        var draft = ParameterDraft()
        draft.set(.string("Et billede"), at: PathKey(["prompt"]))
        draft.set(.array([.string("xai"), .string("en-anden-provider")]), at: order.path)

        let built = try ImagesRequestBuilder(definitions: await store.definitions())
            .build(endpoint: endpoint, draft: draft)
        #expect(built.body.value(at: order.path.components) == .array([.string("xai"), .string("en-anden-provider")]))
    }

    @Test("The body never carries keys outside the endpoint's parameters")
    func keySet() async throws {
        let store = try store()
        let builder = ImagesRequestBuilder(definitions: await store.definitions())
        var checked = 0

        for model in await store.allModels() {
            for endpoint in model.imageEndpoints {
                var draft = ParameterDraft()
                draft.set(.string("Et billede"), at: PathKey(["prompt"]))
                guard let built = try? builder.build(endpoint: endpoint, draft: draft, explicitProvider: true) else {
                    continue
                }
                let allowed = Set(endpoint.parameters.map(\.path.components[0])).union(["model", "stream"])
                for key in (built.body.objectValue ?? [:]).keys {
                    #expect(allowed.contains(key), "\(endpoint.id) har nøglen \(key)")
                }
                #expect(built.body["model"]?.stringValue == endpoint.modelId)
                checked += 1
            }
        }
        #expect(checked >= 60)
    }
}

@Suite("SSE parser")
struct SSEParserTests {
    @Test("Splits events across arbitrary chunk boundaries")
    func fragmented() {
        let text = "event: image_generation.partial_image\ndata: {\"b64_json\":\"abc\"}\n\nevent: done\ndata: [DONE]\n\n"
        var parser = SSEParser()
        var events: [SSEEvent] = []
        for byte in Data(text.utf8) {
            events += parser.feed(Data([byte]))
        }
        #expect(events.count == 2)
        #expect(events[0].event == "image_generation.partial_image")
        #expect(events[0].data.contains("abc"))
        #expect(events[1].data == "[DONE]")
        #expect(parser.isDone)
    }

    @Test("Handles CRLF, comments and several events in one chunk")
    func mixed() {
        var parser = SSEParser()
        let chunk = Data(": kommentar\r\nevent: one\r\ndata: a\r\n\r\nevent: two\r\ndata: b\r\n\r\n".utf8)
        let events = parser.feed(chunk)
        #expect(events.map(\.event) == ["one", "two"])
        #expect(events.map(\.data) == ["a", "b"])
    }

    @Test("Joins multiple data lines")
    func multiline() {
        var parser = SSEParser()
        let events = parser.feed(Data("event: e\ndata: line1\ndata: line2\n\n".utf8))
        #expect(events.first?.data == "line1\nline2")
    }
}

@Suite("Preview and redaction")
struct PreviewTests {
    @Test("Redacts inline base64 but keeps the payload")
    func redaction() throws {
        let payload = "data:image/png;base64," + String(repeating: "A", count: 300)
        let body = JSONValue.object(["input_references": .array([.object(["image_url": .object(["url": .string(payload)])])])])
        let redacted = Redaction.redact(body, fileNames: ["a.png": payload])
        let text = try redacted.encodedString()
        #expect(text.contains("<fil: a.png"))
        #expect(body["input_references"]?[0]?["image_url"]?["url"]?.stringValue == payload)
    }

    @Test("Preview render stays under 50 ms")
    func previewPerformance() async throws {
        let endpoint = try await endpoint(modelId: "openai/gpt-image-2.6-sunburst")
        var draft = ParameterDraft()
        draft.set(.string("Et fyrtårn"), at: PathKey(["prompt"]))
        let built = try ImagesRequestBuilder().build(endpoint: endpoint, draft: draft)

        let clock = ContinuousClock()
        var text = ""
        let elapsed = clock.measure {
            text = (try? JSONPreview.render(Redaction.redact(built.body))) ?? ""
        }
        print("Preview rendered in \(elapsed) (\(text.count) tegn)")
        #expect(text.contains("prompt"))
        #expect(elapsed < .milliseconds(50))
    }

    @Test("Filtered preview keeps only the given paths")
    func filtered() {
        let body = JSONValue.object([
            "model": .string("m"),
            "prompt": .string("p"),
            "quality": .string("high"),
        ])
        let filtered = JSONPreview.filtered(body, keeping: [PathKey(["prompt"])])
        #expect(filtered == .object(["prompt": .string("p")]))
    }
}
