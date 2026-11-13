import CatalogCore
import CoreSupport
import Foundation
import ParameterEngine
import RequestKit

public enum JobStatus: String, Sendable, Equatable, Codable {
    case queued
    case running
    case streaming
    case succeeded
    case failed
    case cancelled
}

public struct GenerationResult: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var index: Int
    public var data: Data
    public var mediaType: String
    public var width: Int?
    public var height: Int?
    public var seed: Int?
    public var providerSlug: String?

    public init(
        id: UUID = UUID(),
        index: Int,
        data: Data,
        mediaType: String,
        width: Int? = nil,
        height: Int? = nil,
        seed: Int? = nil,
        providerSlug: String? = nil
    ) {
        self.id = id
        self.index = index
        self.data = data
        self.mediaType = mediaType
        self.width = width
        self.height = height
        self.seed = seed
        self.providerSlug = providerSlug
    }
}

public struct JobError: Error, Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case unauthorized
        case credits
        case rateLimited
        case server
        case badRequest
        case network
        case cancelled
        case decoding
        case unknown
    }

    public var kind: Kind
    public var message: String
    public var detail: String?
    public var retryAfterSeconds: Int?
    public var requestId: String?

    public init(
        kind: Kind,
        message: String,
        detail: String? = nil,
        retryAfterSeconds: Int? = nil,
        requestId: String? = nil
    ) {
        self.kind = kind
        self.message = message
        self.detail = detail
        self.retryAfterSeconds = retryAfterSeconds
        self.requestId = requestId
    }

    public var isRetryable: Bool {
        switch kind {
        case .rateLimited, .server, .network: return true
        default: return false
        }
    }

    public static func map(statusCode: Int, body: Data, headers: [String: String]) -> JobError {
        let detail = String(decoding: body, as: UTF8.self)
        var requestId: String?
        for (key, value) in headers where key.lowercased() == "x-request-id" {
            requestId = value
        }
        switch statusCode {
        case 401, 403:
            return JobError(kind: .unauthorized, message: "Nøglen blev afvist. Kontrollér din OpenRouter-nøgle i Indstillinger.", detail: detail, requestId: requestId)
        case 402:
            return JobError(kind: .credits, message: "Der er ikke kredit nok på OpenRouter-kontoen.", detail: detail, requestId: requestId)
        case 429:
            let retry = headers.first { $0.key.lowercased() == "retry-after" }.flatMap { Int($0.value) }
            return JobError(
                kind: .rateLimited,
                message: retry.map { "For mange forespørgsler. Prøv igen om \($0) s." } ?? "For mange forespørgsler. Prøv igen om lidt.",
                detail: detail,
                retryAfterSeconds: retry,
                requestId: requestId
            )
        case 400..<500:
            return JobError(kind: .badRequest, message: "Provideren afviste forespørgslen. Se detaljerne.", detail: detail, requestId: requestId)
        case 500..<600:
            return JobError(kind: .server, message: "Provideren havde en midlertidig fejl. Prøv igen.", detail: detail, requestId: requestId)
        default:
            return JobError(kind: .unknown, message: "Ukendt svar fra OpenRouter (HTTP \(statusCode)).", detail: detail, requestId: requestId)
        }
    }
}

public struct GenerationJob: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var modelId: String
    public var endpointId: String
    public var status: JobStatus
    public var createdAt: Date
    public var finishedAt: Date?
    public var costUSD: Decimal?
    public var latencyMilliseconds: Int?
    public var error: JobError?
    public var results: [GenerationResult]
    public var requestBody: JSONValue
    public var partialImage: Data?

    public init(
        id: UUID = UUID(),
        modelId: String,
        endpointId: String,
        status: JobStatus = .queued,
        createdAt: Date = Date(),
        requestBody: JSONValue = .object([:])
    ) {
        self.id = id
        self.modelId = modelId
        self.endpointId = endpointId
        self.status = status
        self.createdAt = createdAt
        self.requestBody = requestBody
        self.results = []
    }
}

public struct GenerationResponse: Sendable, Equatable {
    public var results: [GenerationResult]
    public var costUSD: Decimal?
    public var requestId: String?

    public init(results: [GenerationResult], costUSD: Decimal?, requestId: String? = nil) {
        self.results = results
        self.costUSD = costUSD
        self.requestId = requestId
    }
}

public enum GenerationEvent: Sendable {
    case partial(Data)
    case completed(GenerationResponse)
    case failed(JobError)
}

public struct KeyTestResult: Sendable, Equatable {
    public var ok: Bool
    public var message: String
    /// Total spend on the key, from `/api/v1/key`.
    public var usageUSD: Decimal?
    /// The key's credit limit, when one is set.
    public var limitUSD: Decimal?
    /// What is left of the limit, when one is set.
    public var remainingUSD: Decimal?
    public var isFreeTier: Bool?

    public init(
        ok: Bool,
        message: String,
        usageUSD: Decimal? = nil,
        limitUSD: Decimal? = nil,
        remainingUSD: Decimal? = nil,
        isFreeTier: Bool? = nil
    ) {
        self.ok = ok
        self.message = message
        self.usageUSD = usageUSD
        self.limitUSD = limitUSD
        self.remainingUSD = remainingUSD
        self.isFreeTier = isFreeTier
    }
}

public struct OpenRouterClient: Sendable {
    public struct Configuration: Sendable {
        public var baseURL: URL
        public var referer: String
        public var title: String
        public var maxResponseBytes: Int

        public init(
            baseURL: URL = URL(string: "https://openrouter.ai")!,
            referer: String = "https://netsi.dk",
            title: String = "Netsi Image",
            maxResponseBytes: Int = 64 * 1024 * 1024
        ) {
            self.baseURL = baseURL
            self.referer = referer
            self.title = title
            self.maxResponseBytes = maxResponseBytes
        }
    }

    private let transport: any HTTPTransport
    private let configuration: Configuration

    public init(transport: any HTTPTransport = URLSessionTransport(), configuration: Configuration = Configuration()) {
        self.transport = transport
        self.configuration = configuration
    }

    /// One cheap authorised request that proves the key works and returns the
    /// key's spend and limit from `GET /api/v1/key`.
    public func testKey(apiKey: String) async throws -> KeyTestResult {
        let url = configuration.baseURL.appendingPathComponent("api/v1/key")
        let response = try await transport.send(HTTPRequest(
            url: url,
            headers: ["Authorization": "Bearer \(apiKey)", "Accept": "application/json"]
        ))
        guard (200..<300).contains(response.statusCode) else {
            let error = JobError.map(statusCode: response.statusCode, body: response.body, headers: response.headers)
            return KeyTestResult(ok: false, message: error.message)
        }

        let json = (try? JSONValue.parse(response.body)) ?? .object([:])
        let data = json["data"] ?? json
        let usage = data["usage"]?.decimalValue ?? json["usage"]?.decimalValue
        let limit = data["limit"]?.decimalValue ?? json["limit"]?.decimalValue
        let remaining = data["limit_remaining"]?.decimalValue ?? json["limit_remaining"]?.decimalValue
        let freeTier = data["is_free_tier"]?.boolValue ?? json["is_free_tier"]?.boolValue

        var message = "Nøglen virker."
        if let usage {
            message += " Brugt: \(Self.money(usage))."
        }
        if let remaining {
            message += " Tilbage: \(Self.money(remaining))."
        }

        return KeyTestResult(
            ok: true,
            message: message,
            usageUSD: usage,
            limitUSD: limit,
            remainingUSD: remaining,
            isFreeTier: freeTier
        )
    }

    /// "$2.78" — two decimals, POSIX separators so it matches OpenRouter.
    public static func money(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let number = NSDecimalNumber(decimal: value)
        return "$" + (formatter.string(from: number) ?? number.stringValue)
    }

    public func generate(body: JSONValue, apiKey: String) async throws -> GenerationResponse {        let request = try makeRequest(body: body, apiKey: apiKey, stream: false)
        let response = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw JobError.map(statusCode: response.statusCode, body: response.body, headers: response.headers)
        }
        return try Self.decode(response: response, maxBytes: configuration.maxResponseBytes)
    }

    public func stream(body: JSONValue, apiKey: String) async throws -> AsyncThrowingStream<GenerationEvent, any Error> {
        let request = try makeRequest(body: body, apiKey: apiKey, stream: true)
        let stream = try await transport.stream(request)
        let maxBytes = configuration.maxResponseBytes

        guard (200..<300).contains(stream.statusCode) else {
            var collected = Data()
            for try await chunk in stream.chunks { collected.append(chunk) }
            throw JobError.map(statusCode: stream.statusCode, body: collected, headers: stream.headers)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                var parser = SSEParser()
                var lastCost: Decimal?
                var requestId: String? = stream.headers.first { $0.key.lowercased() == "x-request-id" }?.value
                do {
                    for try await chunk in stream.chunks {
                        for event in parser.feed(chunk) {
                            switch event.event {
                            case "image_generation.partial_image":
                                if let payload = try? JSONValue.parse(event.data),
                                   let base64 = payload["b64_json"]?.stringValue {
                                    if base64.utf8.count > Self.maxBase64Length(maxBytes) {
                                        continuation.yield(.failed(JobError(kind: .decoding, message: "Billedet er for stort.")))
                                        continuation.finish()
                                        return
                                    }
                                    if let data = Data(base64Encoded: base64) {
                                        continuation.yield(.partial(data))
                                    }
                                }
                            case "image_generation.completed":
                                if let payload = try? JSONValue.parse(event.data) {
                                    lastCost = payload["usage"]?["cost"]?.decimalValue
                                    requestId = payload["id"]?.stringValue ?? requestId
                                    if let base64 = payload["b64_json"]?.stringValue {
                                        do {
                                            let result = try Self.result(index: 0, base64: base64, maxBytes: maxBytes)
                                            continuation.yield(.completed(GenerationResponse(results: [result], costUSD: lastCost, requestId: requestId)))
                                        } catch let error as JobError {
                                            continuation.yield(.failed(error))
                                            continuation.finish()
                                            return
                                        }
                                    }
                                }
                            case "error":
                                let error = Self.streamError(from: event.data, requestId: requestId)
                                continuation.yield(.failed(error))
                                continuation.finish()
                                return
                            default:
                                if event.data == "[DONE]" {
                                    continuation.finish()
                                    return
                                }
                            }
                        }
                        if parser.isDone { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(JobError(kind: .network, message: "Forbindelsen blev afbrudt.", detail: error.localizedDescription, requestId: requestId)))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeRequest(body: JSONValue, apiKey: String, stream: Bool) throws -> HTTPRequest {
        var payload = body
        if var object = payload.objectValue {
            // A plain request must never carry `stream: true`, or the provider
            // answers with SSE and the JSON decoder rejects it.
            if stream {
                object["stream"] = .bool(true)
            } else {
                object.removeValue(forKey: "stream")
            }
            payload = .object(object)
        }
        let url = configuration.baseURL.appendingPathComponent("api/v1/images")
        return HTTPRequest(
            url: url,
            method: "POST",
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json",
                "Accept": stream ? "text/event-stream" : "application/json",
                "HTTP-Referer": configuration.referer,
                "X-Title": configuration.title,
            ],
            body: try payload.encoded()
        )
    }

    public static func decode(response: HTTPResponse, maxBytes: Int = 64 * 1024 * 1024) throws -> GenerationResponse {
        let payload: JSONValue
        do {
            payload = try JSONValue.parse(response.body)
        } catch {
            throw JobError(kind: .decoding, message: "Svaret kunne ikke læses som JSON.")
        }
        let items = payload["data"]?.arrayValue ?? []
        var results: [GenerationResult] = []
        for (index, item) in items.enumerated() {
            guard let base64 = item["b64_json"]?.stringValue else { continue }
            results.append(try result(index: index, base64: base64, maxBytes: maxBytes))
        }
        guard !results.isEmpty else {
            throw JobError(kind: .decoding, message: "Svaret indeholdt ingen billeder.")
        }
        return GenerationResponse(
            results: results,
            costUSD: payload["usage"]?["cost"]?.decimalValue,
            requestId: response.headers.first { $0.key.lowercased() == "x-request-id" }?.value
        )
    }

    /// Decodes one base64 payload, enforces the response size limit and
    /// verifies the actual bytes. The server's `media_type` is never trusted.
    private static func result(index: Int, base64: String, maxBytes: Int) throws -> GenerationResult {
        guard base64.utf8.count <= maxBase64Length(maxBytes) else {
            throw JobError(kind: .decoding, message: "Billedet er for stort.")
        }
        guard let data = Data(base64Encoded: base64) else {
            throw JobError(kind: .decoding, message: "Billedet kunne ikke afkodes.")
        }
        guard let sniffed = ImageFormatSniffer.mediaType(for: data) else {
            throw JobError(
                kind: .decoding,
                message: "Billedet er ikke et understøttet format. Kun PNG, JPEG, WebP og GIF er tilladt."
            )
        }
        let info = ImageIOProbe.probe(data: data)
        return GenerationResult(
            index: index,
            data: data,
            mediaType: sniffed,
            width: info?.width,
            height: info?.height
        )
    }

    private static func maxBase64Length(_ maxBytes: Int) -> Int {
        (maxBytes * 4 / 3) + 16
    }

    private static func streamError(from data: String, requestId: String?) -> JobError {
        let payload = try? JSONValue.parse(data)
        let message = payload?["error"]?["message"]?.stringValue
            ?? payload?["message"]?.stringValue
            ?? "Provideren rapporterede en fejl under streaming."
        return JobError(
            kind: .server,
            message: message,
            detail: data,
            requestId: payload?["id"]?.stringValue ?? requestId
        )
    }
}

public actor GenerationCoordinator {
    private let client: OpenRouterClient
    private let clock: any Clock
    private var jobs: [UUID: GenerationJob] = [:]
    private var tasks: [UUID: Task<GenerationJob, Never>] = [:]
    private var cancelled: Set<UUID> = []

    public init(client: OpenRouterClient, clock: any Clock = SystemClock()) {
        self.client = client
        self.clock = clock
    }

    /// Submitting an id that is already active makes no second request.
    public func submit(
        job: GenerationJob,
        apiKey: String,
        stream: Bool,
        onEvent: (@Sendable (GenerationEvent) -> Void)? = nil
    ) async -> GenerationJob {
        if tasks[job.id] != nil {
            return jobs[job.id] ?? job
        }
        if let existing = jobs[job.id], existing.status != .queued {
            return existing
        }

        var current = job
        current.status = .running
        jobs[job.id] = current

        // The work runs in its own task so `cancel` can stop the transport call.
        let task = Task { await self.run(job: job, apiKey: apiKey, stream: stream, onEvent: onEvent) }
        tasks[job.id] = task

        var finished = await task.value
        if cancelled.contains(job.id) {
            finished.status = .cancelled
        }
        tasks[job.id] = nil
        jobs[job.id] = finished
        return finished
    }

    private func run(
        job: GenerationJob,
        apiKey: String,
        stream: Bool,
        onEvent: (@Sendable (GenerationEvent) -> Void)?
    ) async -> GenerationJob {
        var current = job
        current.status = .running
        let started = clock.now

        do {
            if stream {
                current.status = .streaming
                jobs[job.id] = current
                let events = try await client.stream(body: job.requestBody, apiKey: apiKey)
                var lastPartial: Data?
                for try await event in events {
                    if cancelled.contains(job.id) || Task.isCancelled { break }
                    switch event {
                    case .partial(let data):
                        lastPartial = data
                        current.partialImage = data
                        jobs[job.id] = current
                        onEvent?(event)
                    case .completed(let response):
                        current.results = response.results
                        current.costUSD = response.costUSD
                        jobs[job.id] = current
                        onEvent?(event)
                    case .failed(let error):
                        current.error = error
                        current.status = .failed
                        jobs[job.id] = current
                        onEvent?(event)
                        return finished(current, started: started)
                    }
                }
                if current.results.isEmpty {
                    current.status = .failed
                    current.error = JobError(
                        kind: .decoding,
                        message: lastPartial != nil
                            ? "Strømmen sluttede uden et færdigt billede."
                            : "Strømmen sluttede uden billeder.",
                        detail: "Ingen billeder i svaret. Prøv igen, eller slå streaming fra i Indstillinger."
                    )
                } else if cancelled.contains(job.id) || Task.isCancelled {
                    current.status = .cancelled
                } else if current.status != .failed {
                    current.status = .succeeded
                }
            } else {
                let response = try await client.generate(body: job.requestBody, apiKey: apiKey)
                if cancelled.contains(job.id) || Task.isCancelled {
                    current.status = .cancelled
                } else {
                    current.results = response.results
                    current.costUSD = response.costUSD
                    current.status = .succeeded
                }
            }
        } catch let error as JobError {
            current.status = (cancelled.contains(job.id) || Task.isCancelled) ? .cancelled : .failed
            current.error = error
        } catch is CancellationError {
            current.status = .cancelled
        } catch {
            current.status = (cancelled.contains(job.id) || Task.isCancelled) ? .cancelled : .failed
            current.error = JobError(kind: .unknown, message: "Ukendt fejl.", detail: error.localizedDescription)
        }

        return finished(current, started: started)
    }

    private func finished(_ job: GenerationJob, started: Date) -> GenerationJob {
        var job = job
        job.finishedAt = clock.now
        job.latencyMilliseconds = Int(clock.now.timeIntervalSince(started) * 1000)
        jobs[job.id] = job
        return job
    }

    /// Cancels the work task, which cancels the in-flight transport call.
    public func cancel(_ id: UUID) {
        cancelled.insert(id)
        tasks[id]?.cancel()
        if var job = jobs[id] {
            job.status = .cancelled
            jobs[id] = job
        }
    }

    public func job(_ id: UUID) -> GenerationJob? { jobs[id] }
}
