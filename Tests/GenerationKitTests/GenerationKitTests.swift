import CatalogCore
import CoreSupport
import Foundation
import Testing

@testable import GenerationKit

private let tinyPNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
private let tinyJPEG = "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q=="
private let tinyWebP = "UklGRhIAAABXRUJQVlA4TAYAAAAvAAAAAAfQ//73v/+BiOh/AAA="
private let tinyGIF = "R0lGODdhAQABAJEAAAAAAP8AAP///wAAACH5BAkAAAMALAAAAAABAAEAAAICTAEAOw=="

private func imageBody(_ base64: String, mediaType: String) -> Data {
    Data("{\"data\":[{\"b64_json\":\"\(base64)\",\"media_type\":\"\(mediaType)\"}]}".utf8)
}

final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

final class BodyCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Data?
    func set(_ data: Data?) { lock.lock(); value = data; lock.unlock() }
    var data: Data? { lock.lock(); defer { lock.unlock() }; return value }
}

struct StubTransport: HTTPTransport {
    var statusCode: Int = 200
    var body: Data = Data()
    var headers: [String: String] = [:]
    var delay: Duration = .zero
    var counter = CallCounter()
    var bodyCapture = BodyCapture()
    var chunks: [Data] = []

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        counter.increment()
        bodyCapture.set(request.body)
        if delay > .zero { try await Task.sleep(for: delay) }
        return HTTPResponse(statusCode: statusCode, headers: headers, body: body)
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPStream {
        counter.increment()
        bodyCapture.set(request.body)
        let chunks = chunks
        return HTTPStream(
            statusCode: statusCode,
            headers: headers,
            chunks: AsyncThrowingStream { continuation in
                for chunk in chunks { continuation.yield(chunk) }
                continuation.finish()
            }
        )
    }
}

private func successBody(cost: String? = "0.04") -> Data {
    let usage = cost.map { ",\"usage\":{\"cost\":\($0)}" } ?? ""
    let json = "{\"data\":[{\"b64_json\":\"\(tinyPNG)\",\"media_type\":\"image/png\"}]\(usage)}"
    return Data(json.utf8)
}

@Suite("OpenRouter client")
struct OpenRouterClientTests {
    @Test("Decodes images, media type, dimensions and cost")
    func decodeSuccess() async throws {
        let client = OpenRouterClient(transport: StubTransport(body: successBody()))
        let response = try await client.generate(body: .object(["model": .string("m")]), apiKey: "key")
        #expect(response.results.count == 1)
        #expect(response.results[0].mediaType == "image/png")
        #expect(response.results[0].width == 1)
        #expect(response.costUSD == Decimal(string: "0.04"))
    }

    @Test("An absent cost is unknown, never zero")
    func unknownCost() async throws {
        let client = OpenRouterClient(transport: StubTransport(body: successBody(cost: nil)))
        let response = try await client.generate(body: .object([:]), apiKey: "key")
        #expect(response.costUSD == nil)
    }

    @Test("A plain request drops the stream flag")
    func plainRequestDropsStream() async throws {
        let transport = StubTransport(body: successBody())
        let client = OpenRouterClient(transport: transport)
        _ = try await client.generate(
            body: .object(["stream": .bool(true), "model": .string("m")]),
            apiKey: "key"
        )
        let body = try #require(transport.bodyCapture.data)
        let parsed = try JSONValue.parse(body)
        #expect(parsed["stream"] == nil)
        #expect(parsed["model"]?.stringValue == "m")
    }

    @Test("Maps HTTP errors to actionable Danish states")
    func errorMapping() {
        let unauthorized = JobError.map(statusCode: 401, body: Data(), headers: [:])
        #expect(unauthorized.kind == .unauthorized)
        #expect(unauthorized.message.contains("nøgle"))

        #expect(JobError.map(statusCode: 402, body: Data(), headers: [:]).kind == .credits)

        let limited = JobError.map(statusCode: 429, body: Data(), headers: ["retry-after": "7"])
        #expect(limited.kind == .rateLimited)
        #expect(limited.retryAfterSeconds == 7)
        #expect(limited.message.contains("7"))

        let server = JobError.map(statusCode: 503, body: Data(), headers: [:])
        #expect(server.kind == .server)
        #expect(server.isRetryable)

        #expect(JobError.map(statusCode: 400, body: Data(), headers: [:]).kind == .badRequest)
        #expect(!JobError.map(statusCode: 400, body: Data(), headers: [:]).isRetryable)
    }

    @Test("Cancelling a job leaves it cancelled")
    func cancellation() async throws {
        let transport = StubTransport(body: successBody(), delay: .milliseconds(200))
        let coordinator = GenerationCoordinator(client: OpenRouterClient(transport: transport))
        let job = GenerationJob(modelId: "m", endpointId: "m@p", requestBody: .object([:]))

        let task = Task { await coordinator.submit(job: job, apiKey: "key", stream: false) }
        try await Task.sleep(for: .milliseconds(20))
        await coordinator.cancel(job.id)
        let finished = await task.value
        #expect(finished.status == .cancelled)
    }

    @Test("Cancelling stops an in-flight request promptly")
    func cancelStopsTraffic() async throws {
        let transport = StubTransport(body: successBody(), delay: .seconds(10))
        let coordinator = GenerationCoordinator(client: OpenRouterClient(transport: transport))
        let job = GenerationJob(modelId: "m", endpointId: "m@p", requestBody: .object([:]))

        let started = Date()
        let task = Task { await coordinator.submit(job: job, apiKey: "key", stream: false) }
        try await Task.sleep(for: .milliseconds(50))
        await coordinator.cancel(job.id)
        let finished = await task.value
        let elapsed = Date().timeIntervalSince(started)

        #expect(finished.status == .cancelled)
        #expect(elapsed < 1.0, "afbrydelsen tog \(elapsed) s")
    }

    @Test("Submitting a finished job again makes no second request")
    func idempotency() async throws {
        let transport = StubTransport(body: successBody())
        let coordinator = GenerationCoordinator(client: OpenRouterClient(transport: transport))
        let job = GenerationJob(modelId: "m", endpointId: "m@p", requestBody: .object([:]))

        _ = await coordinator.submit(job: job, apiKey: "key", stream: false)
        _ = await coordinator.submit(job: job, apiKey: "key", stream: false)
        #expect(transport.counter.count == 1)
    }

    @Test("Test key reports success, spend and failure without leaking the key")
    func testKey() async throws {
        let okClient = OpenRouterClient(transport: StubTransport(body: Data(#"{"data":{"label":"test","usage":2.78,"limit":10,"limit_remaining":7.22}}"#.utf8)))
        let ok = try await okClient.testKey(apiKey: "sk-or-secret-1234")
        #expect(ok.ok)
        #expect(ok.usageUSD == Decimal(string: "2.78"))
        #expect(ok.limitUSD == Decimal(string: "10"))
        #expect(ok.remainingUSD == Decimal(string: "7.22"))
        #expect(ok.message.contains("$2.78"))
        #expect(!ok.message.contains("secret"))

        let badClient = OpenRouterClient(transport: StubTransport(statusCode: 401, body: Data()))
        let bad = try await badClient.testKey(apiKey: "sk-or-secret-1234")
        #expect(!bad.ok)
        #expect(bad.message.contains("nøgle"))
        #expect(!bad.message.contains("secret"))
    }

    @Test("Streaming yields a partial image and a completed result with cost")
    func streaming() async throws {
        let partial = Data("event: image_generation.partial_image\ndata: {\"b64_json\":\"\(tinyPNG)\"}\n\n".utf8)
        let completed = Data("event: image_generation.completed\ndata: {\"b64_json\":\"\(tinyPNG)\",\"media_type\":\"image/png\",\"usage\":{\"cost\":0.05}}\n\n".utf8)
        let transport = StubTransport(body: Data(), chunks: [partial, completed])

        let coordinator = GenerationCoordinator(client: OpenRouterClient(transport: transport))
        let job = GenerationJob(modelId: "m", endpointId: "m@p", requestBody: .object([:]))
        let finished = await coordinator.submit(job: job, apiKey: "key", stream: true)

        #expect(finished.status == .succeeded)
        #expect(finished.costUSD == Decimal(string: "0.05"))
        #expect(finished.results.count == 1)
        #expect(finished.partialImage != nil)
    }

    @Test("A stream error event carries the provider message")
    func streamError() async throws {
        let errorEvent = Data("event: error\ndata: {\"id\":\"req_1\",\"error\":{\"message\":\"Provideren afviste\"}}\n\n".utf8)
        let transport = StubTransport(body: Data(), chunks: [errorEvent])
        let coordinator = GenerationCoordinator(client: OpenRouterClient(transport: transport))
        let job = GenerationJob(modelId: "m", endpointId: "m@p", requestBody: .object([:]))
        let finished = await coordinator.submit(job: job, apiKey: "key", stream: true)

        #expect(finished.status == .failed)
        #expect(finished.error?.message.contains("afviste") == true)
        #expect(finished.error?.requestId == "req_1")
    }

    @Test("An empty stream fails instead of reporting a silent success")
    func emptyStream() async throws {
        let transport = StubTransport(body: Data(), chunks: [])
        let coordinator = GenerationCoordinator(client: OpenRouterClient(transport: transport))
        let job = GenerationJob(modelId: "m", endpointId: "m@p", requestBody: .object([:]))
        let finished = await coordinator.submit(job: job, apiKey: "key", stream: true)

        #expect(finished.status == .failed)
        #expect(finished.error?.kind == .decoding)
        #expect(finished.results.isEmpty)
    }
}

@Suite("Image format validation")
struct ImageFormatValidationTests {
    private func generate(_ body: Data, maxBytes: Int = 64 * 1024 * 1024) async throws -> GenerationResponse {
        let client = OpenRouterClient(
            transport: StubTransport(body: body),
            configuration: OpenRouterClient.Configuration(maxResponseBytes: maxBytes)
        )
        return try await client.generate(body: .object([:]), apiKey: "key")
    }

    @Test("PNG, JPEG, WebP and GIF bytes are accepted and sniffed")
    func supportedFormats() async throws {
        let cases: [(String, String)] = [
            (tinyPNG, "image/png"),
            (tinyJPEG, "image/jpeg"),
            (tinyWebP, "image/webp"),
            (tinyGIF, "image/gif"),
        ]
        for (base64, expected) in cases {
            let response = try await generate(imageBody(base64, mediaType: expected))
            #expect(response.results.first?.mediaType == expected)
        }
    }

    @Test("PNG bytes win over a server claim of SVG")
    func serverSVGClaimIsIgnored() async throws {
        let response = try await generate(imageBody(tinyPNG, mediaType: "image/svg+xml"))
        #expect(response.results.first?.mediaType == "image/png")
    }

    @Test("SVG bytes are rejected as a decoding error")
    func svgBytesRejected() async {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" onload=\"alert(1)\"></svg>"
        let base64 = Data(svg.utf8).base64EncodedString()
        do {
            _ = try await generate(imageBody(base64, mediaType: "image/png"))
            Issue.record("Expected a decoding error")
        } catch let error as JobError {
            #expect(error.kind == .decoding)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Random and empty bytes are rejected")
    func randomAndEmptyRejected() async {
        let random = Data([0x00, 0x01, 0x02, 0x03, 0x04]).base64EncodedString()
        for base64 in [random, ""] {
            do {
                _ = try await generate(imageBody(base64, mediaType: "image/png"))
                Issue.record("Expected a decoding error for \(base64)")
            } catch let error as JobError {
                #expect(error.kind == .decoding)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test("A base64 image larger than maxResponseBytes is rejected")
    func base64TooLarge() async {
        do {
            _ = try await generate(imageBody(tinyPNG, mediaType: "image/png"), maxBytes: 10)
            Issue.record("Expected a decoding error")
        } catch let error as JobError {
            #expect(error.kind == .decoding)
            #expect(error.message.contains("for stort"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Streaming rejects an SVG payload")
    func streamingRejectsSVG() async throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" onload=\"alert(1)\"></svg>"
        let base64 = Data(svg.utf8).base64EncodedString()
        let completed = Data("event: image_generation.completed\ndata: {\"b64_json\":\"\(base64)\",\"media_type\":\"image/png\"}\n\n".utf8)
        let transport = StubTransport(body: Data(), chunks: [completed])
        let coordinator = GenerationCoordinator(client: OpenRouterClient(transport: transport))
        let job = GenerationJob(modelId: "m", endpointId: "m@p", requestBody: .object([:]))
        let finished = await coordinator.submit(job: job, apiKey: "key", stream: true)

        #expect(finished.status == .failed)
        #expect(finished.error?.kind == .decoding)
    }
}
