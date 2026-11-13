import Foundation

public struct HTTPRequest: Sendable, Equatable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data?

    public init(
        url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable, Equatable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    public var bodyString: String {
        String(decoding: body, as: UTF8.self)
    }
}

/// A streaming response. `chunks` yields whatever the transport received, split arbitrarily;
/// the SSE parser tolerates event boundaries inside a chunk.
public struct HTTPStream: Sendable {
    public var statusCode: Int
    public var headers: [String: String]
    public var chunks: AsyncThrowingStream<Data, any Error>

    public init(
        statusCode: Int,
        headers: [String: String] = [:],
        chunks: AsyncThrowingStream<Data, any Error>
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.chunks = chunks
    }
}

public enum HTTPError: Error, Equatable, Sendable {
    case invalidResponse
    case transport(String)
    case cancelled
    case responseTooLarge
}

public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
    func stream(_ request: HTTPRequest) async throws -> HTTPStream
}

/// The real transport. No third-party dependency, no automatic retries.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    public let maxResponseBytes: Int

    public init(session: URLSession = .shared, maxResponseBytes: Int = 64 * 1024 * 1024) {
        self.session = session
        self.maxResponseBytes = maxResponseBytes
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: 120)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        do {
            let (bytes, response) = try await session.bytes(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw HTTPError.invalidResponse
            }
            if let contentLength = http.value(forHTTPHeaderField: "Content-Length"),
               let length = Int(contentLength), length > maxResponseBytes {
                throw HTTPError.responseTooLarge
            }
            var data = Data()
            data.reserveCapacity(min(maxResponseBytes, 1 << 20))
            for try await byte in bytes {
                if data.count >= maxResponseBytes { throw HTTPError.responseTooLarge }
                data.append(byte)
            }
            return HTTPResponse(
                statusCode: http.statusCode,
                headers: http.allHeaderFields.reduce(into: [:]) { partial, entry in
                    if let key = entry.key as? String {
                        partial[key] = String(describing: entry.value)
                    }
                },
                body: data
            )
        } catch is CancellationError {
            throw HTTPError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw HTTPError.cancelled
        } catch let error as HTTPError {
            throw error
        } catch {
            throw HTTPError.transport(error.localizedDescription)
        }
    }

    public func stream(_ request: HTTPRequest) async throws -> HTTPStream {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: 300)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.invalidResponse
        }
        if let contentLength = http.value(forHTTPHeaderField: "Content-Length"),
           let length = Int(contentLength), length > maxResponseBytes {
            throw HTTPError.responseTooLarge
        }

        let limit = maxResponseBytes
        let stream = AsyncThrowingStream<Data, any Error> { continuation in
            let task = Task {
                var buffer = Data()
                buffer.reserveCapacity(4096)
                var total = 0
                do {
                    for try await byte in bytes {
                        total += 1
                        if total > limit { throw HTTPError.responseTooLarge }
                        buffer.append(byte)
                        if buffer.count >= 2048 {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }

        return HTTPStream(
            statusCode: http.statusCode,
            headers: http.allHeaderFields.reduce(into: [:]) { partial, entry in
                if let key = entry.key as? String {
                    partial[key] = String(describing: entry.value)
                }
            },
            chunks: stream
        )
    }
}
