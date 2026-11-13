import CoreSupport
import CryptoKit
import Foundation
import Testing

@testable import CatalogCore

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

@Suite("Catalog bootstrap")
struct CatalogBootstrapTests {
    @Test("The bundled catalog is byte-identical to the repository file")
    func bundledCopyMatchesRepository() throws {
        let rootData = try Data(contentsOf: repoRoot.appendingPathComponent("openrouter-image-ui-catalog.json"))
        let bundled = try CatalogStore.bundledData()
        #expect(sha256(rootData) == sha256(bundled))
    }

    @Test("Decodes the measured catalog totals")
    func totals() async throws {
        let store = try CatalogStore.bundled()
        let summary = await store.summary()

        #expect(summary.schemaVersion == "1.0.0")
        #expect(summary.modelCount == 68)
        #expect(summary.endpointCounts["images"] == 69)
        #expect(summary.endpointCounts["chatCompletions"] == 26)
        #expect(summary.endpointCounts["responses"] == 26)
        #expect(summary.endpointCount == 121)
        #expect(summary.parameterCounts["images"] == 1_154)
        #expect(summary.parameterCount == 1_907)
        #expect(summary.providerRouteCount == 17)
        #expect(summary.modelsWithImagesSurface == 65)
        #expect(summary.modelsWithoutImageEndpoint == ["meta/muse-image"])
    }

    @Test("Summary access decodes no parameters; one model decodes only that model")
    func lazyDecoding() async throws {
        let store = try CatalogStore(data: try CatalogStore.bundledData())
        await store.resetCounters()

        _ = await store.summary()
        let afterSummary = await store.decodeCounters()
        #expect(afterSummary.models == 0)
        #expect(afterSummary.parameters == 0)

        let model = await store.model(id: "openai/gpt-image-2.6-sunburst")
        let expected = model?.surfaces.values.reduce(0) { $0 + $1.endpoints.reduce(0) { $0 + $1.parameters.count } } ?? 0
        let afterModel = await store.decodeCounters()
        #expect(afterModel.models == 1)
        #expect(afterModel.parameters == expected)
        #expect(expected > 0)

        _ = await store.model(id: "openai/gpt-image-2.6-sunburst")
        let afterCacheHit = await store.decodeCounters()
        #expect(afterCacheHit.models == 1)
    }

    @Test("A provider slug with a slash stays one path component")
    func slashSegments() async throws {
        let store = try CatalogStore.bundled()
        var slashPaths = 0
        for model in await store.allModels() {
            for surface in model.surfaces.values {
                for endpoint in surface.endpoints {
                    for spec in endpoint.parameters where spec.path.components.contains(where: { $0.contains("/") }) {
                        slashPaths += 1
                    }
                }
            }
        }
        #expect(slashPaths == 16)

        let model = await store.model(id: "openai/gpt-image-2.6-sunburst")
        let spec = model?.surfaces["images"]?.endpoints.first?.parameters.first {
            $0.path.components.contains("google-ai-studio/global")
        }
        if let spec {
            #expect(spec.path.components.count == 4)
        }
    }

    @Test("The whole catalog round-trips through JSON without losing a value")
    func fullRoundTrip() throws {
        let root = try JSONValue.parse(try CatalogStore.bundledData())
        let encoded = try root.encoded()
        let reparsed = try JSONValue.parse(encoded)
        #expect(root == reparsed)
        #expect(reparsed["models"]?.arrayValue?.count == 68)
        #expect(reparsed["$defs"]?.objectValue?.count == root["$defs"]?.objectValue?.count)
    }

    @Test("Unknown keys and unknown control kinds decode without throwing")
    func tolerance() async throws {
        let json = """
        {"schemaVersion":"1.0.0","generatedAt":"now","future":{"x":1},
         "models":[{"id":"a/b","name":"A","publisher":"a","surfaces":{"images":{"endpoints":[
           {"id":"a/b@p","providerSlug":"p","parameters":[
             {"key":"weird","label":"Weird","path":["weird"],"schema":{"type":"string"},
              "control":"brand-new-control","required":false,"evidence":"brand_new_evidence",
              "unknownField":42}]}]}}}]}
        """
        let store = try CatalogStore(data: Data(json.utf8))
        let model = await store.model(id: "a/b")
        let spec = model?.surfaces["images"]?.endpoints.first?.parameters.first
        #expect(spec?.control == .unknown("brand-new-control"))
        #expect(spec?.evidence == .unknown("brand_new_evidence"))
        #expect(spec?.bucket == .uncertain)
    }
}

@Suite("Model families")
struct ModelFamilyTests {
    private func row(_ name: String, publisher: String) -> ModelRow {
        ModelRow(model: CatalogModel(id: "x", name: name, publisher: publisher))
    }

    @Test("Google models group under one Nano Banana family")
    func google() async throws {
        let store = try CatalogStore.bundled()
        let rows = await store.allModels().map(ModelRow.init(model:))
        let google = ModelFamily.families(rows).filter { $0.publisher == "google" }
        #expect(google.count == 1)
        #expect(google.first?.displayName == "Google: Nano Banana")
        #expect(google.first?.rows.count == 7)
    }

    @Test("Family names drop the version and variant suffix")
    func familyNames() {
        #expect(ModelFamily.familyName(for: row("Google: Nano Banana 2.1", publisher: "google")) == "Nano Banana")
        #expect(ModelFamily.familyName(for: row("Google: Nano Banana Pro (Gemini 3 Pro Image)", publisher: "google")) == "Nano Banana")
        #expect(ModelFamily.familyName(for: row("OpenAI: GPT Image 2.6 Sunburst", publisher: "openai")) == "GPT")
        #expect(ModelFamily.familyName(for: row("Sourceful: Riverflow V2.6 Pro", publisher: "sourceful")) == "Riverflow")
        #expect(ModelFamily.familyName(for: row("Krea: Krea 2 Large", publisher: "krea")) == "Krea")
        #expect(ModelFamily.familyName(for: row("Black Forest Labs: FLUX.2 Klein 4B", publisher: "black-forest-labs")) == "FLUX")
    }

    @Test("Every family keeps its own publisher and rows")
    func grouping() async throws {
        let store = try CatalogStore.bundled()
        let rows = await store.allModels().map(ModelRow.init(model:))
        let families = ModelFamily.families(rows)
        #expect(families.reduce(0) { $0 + $1.rows.count } == rows.count)
        #expect(Set(families.map(\.id)).count == families.count)
        #expect(families.allSatisfy { family in family.rows.allSatisfy { $0.publisher == family.publisher } })
    }

    @Test("Per-token price is exposed when the catalog has one")
    func price() async throws {
        let store = try CatalogStore.bundled()
        let rows = await store.allModels().map(ModelRow.init(model:))
        let minimax = try #require(rows.first { $0.id == "minimax/minimax-h3-image-highspeed" })
        #expect(minimax.pricePerToken == "$0.0000076/token")
    }
}

@Suite("Model filters and endpoint resolution")
struct ModelFilterTests {
    @Test("68 rows with the measured availability states")
    func rows() async throws {
        let store = try CatalogStore.bundled()
        let rows = await store.allModels().map(ModelRow.init(model:))
        #expect(rows.count == 68)

        #expect(rows.first { $0.id == "meta/muse-image" }?.availability == .noImageEndpoint)
        #expect(rows.first { $0.id == "openrouter/auto" }?.availability == .chatOnly)
        #expect(rows.first { $0.id == "openai/gpt-image-2.6-sunburst" }?.availability == .generatable)
        #expect(rows.filter { $0.supportsStreaming }.count == 10)
    }

    @Test("Filters compose and survive a snapshot swap")
    func filters() async throws {
        let store = try CatalogStore.bundled()
        let rows = await store.allModels().map(ModelRow.init(model:))

        let openai = ModelFilter(publisher: "openai").apply(rows)
        #expect(!openai.isEmpty)
        #expect(openai.allSatisfy { $0.publisher == "openai" })

        let text = ModelFilter(text: "flux").apply(rows)
        #expect(text.allSatisfy { $0.id.lowercased().contains("flux") || $0.name.lowercased().contains("flux") })

        let combined = ModelFilter(text: "image", publisher: "recraft", generatableOnly: true).apply(rows)
        #expect(combined.allSatisfy { $0.publisher == "recraft" && $0.availability == .generatable })

        var filter = ModelFilter(publisher: "recraft")
        let before = filter.apply(rows).count
        try await store.replace(data: try CatalogStore.bundledData())
        let after = filter.apply(await store.allModels().map(ModelRow.init(model:))).count
        #expect(before == after)
    }

    @Test("Sunburst resolves to its openai endpoint with 24 parameters")
    func resolver() async throws {
        let store = try CatalogStore.bundled()
        let model = try #require(await store.model(id: "openai/gpt-image-2.6-sunburst"))
        let resolution = EndpointResolver.resolve(model)
        let endpoint = try #require(resolution.endpoint)
        #expect(endpoint.id == "openai/gpt-image-2.6-sunburst@openai")
        #expect(endpoint.parameters.count == 24)
        #expect(endpoint.providerPin?.only == ["openai"])
    }
}

@Suite("Catalog refresh")
struct CatalogRefreshTests {
    @Test("A schema version mismatch is rejected and named")
    func schemaGuard() {
        let candidate = JSONValue.object(["schemaVersion": .string("2.0.0")])
        #expect(throws: RefreshError.self) {
            try SchemaVersionGuard.validate(candidate: candidate, expected: "1.0.0")
        }
    }

    @Test("An HTTP error is surfaced with the failing URL")
    func httpError() async throws {
        struct FailingTransport: HTTPTransport {
            func send(_ request: HTTPRequest) async throws -> HTTPResponse {
                HTTPResponse(statusCode: 500)
            }
            func stream(_ request: HTTPRequest) async throws -> HTTPStream {
                throw HTTPError.transport("unused")
            }
        }

        let client = CatalogRefreshClient(transport: FailingTransport())
        do {
            _ = try await client.refresh(bundledData: try CatalogStore.bundledData())
            Issue.record("Expected a refresh error")
        } catch let error as RefreshError {
            #expect(error.description.contains("openrouter.ai"))
        }
    }

    @Test("A successful refresh adds a model and updates generatedAt")
    func successfulRefresh() async throws {
        struct RefreshTransport: HTTPTransport {
            func send(_ request: HTTPRequest) async throws -> HTTPResponse {
                if request.url.absoluteString.contains("/endpoints") {
                    let body = #"{"data":[{"id":"acme/new-model@acme","provider":"acme","pricing":[],"parameters":[{"key":"prompt","label":"Prompt","path":["prompt"],"schema":{"type":"string"},"control":"textarea","required":true,"evidence":"openapi"}]}]}"#
                    return HTTPResponse(statusCode: 200, body: Data(body.utf8))
                }
                let body = #"{"data":[{"id":"acme/new-model","name":"Acme New"}]}"#
                return HTTPResponse(statusCode: 200, body: Data(body.utf8))
            }
            func stream(_ request: HTTPRequest) async throws -> HTTPStream {
                HTTPStream(statusCode: 500, chunks: AsyncThrowingStream { $0.finish() })
            }
        }

        let bundled = try CatalogStore.bundledData()
        let before = try CatalogStore(data: bundled)
        let beforeSummary = await before.summary()

        let result = try await CatalogRefreshClient(transport: RefreshTransport())
            .refresh(bundledData: bundled)

        #expect(result.summary.modelCount == beforeSummary.modelCount + 1)
        #expect(result.summary.generatedAt != beforeSummary.generatedAt)
        #expect(result.manifest.count == 2)

        let refreshed = try CatalogStore(data: result.data)
        #expect(await refreshed.model(id: "acme/new-model") != nil)
        #expect((await before.summary()).generatedAt == beforeSummary.generatedAt)
    }

    @Test("Snapshot cache round-trips and clears")
    func snapshotCache() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = SnapshotCache(directory: root)
        #expect(try cache.load() == nil)
        try cache.save(Data("{}".utf8), manifest: ["https://example.com": "ok"])
        #expect(try cache.load() == Data("{}".utf8))
        #expect(cache.loadManifest()["https://example.com"] == "ok")
        try cache.clear()
        #expect(try cache.load() == nil)
    }
}

@Suite("Endpoint URL validation")
struct EndpointURLTests {
    private struct NoopTransport: HTTPTransport {
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            HTTPResponse(statusCode: 200)
        }
        func stream(_ request: HTTPRequest) async throws -> HTTPStream {
            HTTPStream(statusCode: 200, chunks: AsyncThrowingStream { $0.finish() })
        }
    }

    private let template = "https://openrouter.ai/api/v1/images/{author}/{slug}/endpoints"
    private let client = CatalogRefreshClient(transport: NoopTransport())

    @Test("Valid IDs produce a URL on the template host")
    func validIDs() {
        for id in ["openai/gpt-image-2", "x/y:free"] {
            let url = client.endpointURL(template: template, modelId: id)
            #expect(url != nil)
            #expect(url?.host == "openrouter.ai")
            #expect(url?.scheme == "https")
        }
    }

    @Test("Traversal and injection are rejected")
    func invalidIDs() {
        for id in ["a/../b", "a/b?x=1", "a/b#c", "../x", "a/%2e%2e", "a b/c", "a/b c", "a/b\tc", "a/b\nc"] {
            #expect(client.endpointURL(template: template, modelId: id) == nil, "\(id) should be rejected")
        }
    }

    @Test("A non-HTTPS template is rejected")
    func nonHTTPSTemplate() {
        let http = "http://openrouter.ai/api/v1/images/{author}/{slug}"
        #expect(client.endpointURL(template: http, modelId: "openai/gpt-image-2") == nil)
    }
}
