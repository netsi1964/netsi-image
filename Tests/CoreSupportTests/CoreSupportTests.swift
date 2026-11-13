import Foundation
import Testing

@testable import CoreSupport

@Suite("JSONValue")
struct JSONValueTests {
    @Test("Round-trips every JSON shape through Codable and JSONSerialization")
    func roundTrip() throws {
        let source = """
        {"name":"Netsi","count":3,"ratio":0.5,"flag":true,"nothing":null,
         "list":[1,"two",false],"nested":{"a":{"b":[]}}}
        """
        let parsed = try JSONValue.parse(source)
        let encoded = try parsed.encoded()
        let reparsed = try JSONValue.parse(encoded)
        #expect(parsed == reparsed)
        #expect(reparsed["count"]?.intValue == 3)
        #expect(reparsed["flag"]?.boolValue == true)
        #expect(reparsed["nothing"]?.isNull == true)
        #expect(reparsed.value(at: ["nested", "a", "b"])?.arrayValue?.isEmpty == true)
    }

    @Test("Preserves decimal prices without binary drift")
    func decimals() throws {
        let parsed = try JSONValue.parse(#"{"cost_usd":0.0000023}"#)
        #expect(parsed["cost_usd"]?.decimalValue == Decimal(string: "0.0000023"))
    }

    @Test("Distinguishes booleans from numbers when parsing")
    func booleanNotNumber() throws {
        let parsed = try JSONValue.parse(#"{"a":1,"b":true}"#)
        #expect(parsed["a"] == .number(1))
        #expect(parsed["b"] == .bool(true))
    }

    @Test("Encodes pretty output with sorted keys")
    func prettySorted() throws {
        let parsed = try JSONValue.parse(#"{"b":1,"a":2}"#)
        let text = try parsed.encodedString(pretty: true)
        let firstKeyIndex = try #require(text.range(of: "\"a\""))
        let secondKeyIndex = try #require(text.range(of: "\"b\""))
        #expect(firstKeyIndex.lowerBound < secondKeyIndex.lowerBound)
    }
}

@Suite("PathKey")
struct PathKeyTests {
    @Test("Keeps a provider slug with a slash as one component")
    func slashSegment() {
        let path = PathKey(["provider", "options", "google-ai-studio/global", "cachedContent"])
        #expect(path.components.count == 4)
        #expect(path.components[2] == "google-ai-studio/global")
        #expect(path.parent == PathKey(["provider", "options", "google-ai-studio/global"]))
    }

    @Test("Structural equality, not display equality")
    func structuralEquality() {
        #expect(PathKey(["a.b"]) != PathKey(["a", "b"]))
        #expect(PathKey(display: "a.b") == PathKey(["a", "b"]))
    }

    @Test("Sorts deterministically")
    func ordering() {
        let paths = [PathKey(["b"]), PathKey(["a", "z"]), PathKey(["a", "b"])]
        #expect(paths.sorted() == [PathKey(["a", "b"]), PathKey(["a", "z"]), PathKey(["b"])])
    }
}

@Suite("Confinement and atomic writes")
struct FileSystemTests {
    @Test("Rejects absolute, parent-relative and escaping paths")
    func rejectsEscapes() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: PathConfinementError.self) {
            try PathConfinement.resolve(relative: "/etc/passwd", under: root)
        }
        #expect(throws: PathConfinementError.self) {
            try PathConfinement.resolve(relative: "../escape.png", under: root)
        }
        #expect(throws: PathConfinementError.self) {
            try PathConfinement.resolve(relative: "a/../../b.png", under: root)
        }
        let ok = try PathConfinement.resolve(relative: "Library/2026/11/11/x.png", under: root)
        #expect(ok.pathComponents.contains("Library"))
    }

    @Test("Atomic writer replaces a file without leaving a temp file")
    func atomicReplace() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("image.png")

        try AtomicFileWriter().write(Data("first".utf8), to: target)
        try AtomicFileWriter().write(Data("second".utf8), to: target)

        #expect(try String(contentsOf: target, encoding: .utf8) == "second")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(leftovers == ["image.png"])
    }

    @Test("A failing writer leaves the previous file untouched")
    func failingWriteKeepsOld() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("image.png")
        try AtomicFileWriter().write(Data("first".utf8), to: target)

        let writer = FailingFileWriter(failOn: 1)
        #expect(throws: (any Error).self) {
            try writer.write(Data("second".utf8), to: target)
        }
        #expect(try String(contentsOf: target, encoding: .utf8) == "first")
    }
}

@Suite("ImageDataURL")
struct ImageDataURLTests {
    @Test("A local image file becomes a base64 data URL")
    func localImageBecomesDataURL() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
        try png.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let dataURL = try #require(ImageDataURL.make(for: url))
        #expect(dataURL.hasPrefix("data:image/png;base64,"))
        #expect(dataURL == "data:image/png;base64,\(png.base64EncodedString())")
    }

    @Test("An HTTP URL passes through unchanged")
    func httpURLPassesThrough() {
        let url = URL(string: "https://example.com/a.png")!
        #expect(ImageDataURL.make(for: url) == "https://example.com/a.png")
    }

    @Test("An unreadable local file returns nil")
    func missingFileReturnsNil() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).png")
        #expect(ImageDataURL.make(for: url) == nil)
    }
}

@Suite("JSON depth limit")
struct JSONDepthTests {
    @Test("Depth 64 parses")
    func depth64() throws {
        let json = String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64)
        let value = try JSONValue.parse(json)
        var depth = 0
        var current = value
        while let next = current.arrayValue?.first {
            depth += 1
            current = next
        }
        #expect(depth == 64)
    }

    @Test("Depth 65 is rejected")
    func depth65() {
        let json = String(repeating: "[", count: 65) + "0" + String(repeating: "]", count: 65)
        #expect(throws: JSONValueError.self) {
            try JSONValue.parse(json)
        }
    }

    @Test("Depth 10,000 is rejected without crashing")
    func depth10000() {
        let json = String(repeating: "[", count: 10_000) + "0" + String(repeating: "]", count: 10_000)
        #expect(throws: JSONValueError.self) {
            try JSONValue.parse(json)
        }
    }
}

@Suite("ImageFormatSniffer")
struct ImageFormatSnifferTests {
    private let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    private let jpeg = "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q=="
    private let webp = "UklGRhIAAABXRUJQVlA4TAYAAAAvAAAAAAfQ//73v/+BiOh/AAA="
    private let gif = "R0lGODdhAQABAJEAAAAAAP8AAP///wAAACH5BAkAAAMALAAAAAABAAEAAAICTAEAOw=="

    @Test("Recognises the four supported formats")
    func supportedFormats() {
        #expect(ImageFormatSniffer.mediaType(for: Data(base64Encoded: png)!) == "image/png")
        #expect(ImageFormatSniffer.mediaType(for: Data(base64Encoded: jpeg)!) == "image/jpeg")
        #expect(ImageFormatSniffer.mediaType(for: Data(base64Encoded: webp)!) == "image/webp")
        #expect(ImageFormatSniffer.mediaType(for: Data(base64Encoded: gif)!) == "image/gif")
    }

    @Test("Rejects SVG and unknown bytes")
    func rejectsUnsupported() {
        #expect(ImageFormatSniffer.mediaType(for: Data("<svg onload=\"alert(1)\"></svg>".utf8)) == nil)
        #expect(ImageFormatSniffer.mediaType(for: Data([0x00, 0x01, 0x02, 0x03])) == nil)
        #expect(ImageFormatSniffer.mediaType(for: Data()) == nil)
    }
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var headers: [String: String] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: Self.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("URLSessionTransport limits", .serialized)
struct URLSessionTransportLimitTests {
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test("A response under the limit is accepted")
    func underLimit() async throws {
        StubURLProtocol.body = Data(repeating: 0x41, count: 64)
        StubURLProtocol.statusCode = 200
        StubURLProtocol.headers = ["Content-Length": "64"]
        let transport = URLSessionTransport(session: makeSession(), maxResponseBytes: 128)
        let response = try await transport.send(HTTPRequest(url: URL(string: "https://example.com")!))
        #expect(response.body.count == 64)
    }

    @Test("A response over the limit is rejected by send")
    func overLimitSend() async {
        StubURLProtocol.body = Data(repeating: 0x41, count: 1024)
        StubURLProtocol.statusCode = 200
        StubURLProtocol.headers = ["Content-Length": "1024"]
        let transport = URLSessionTransport(session: makeSession(), maxResponseBytes: 128)
        do {
            _ = try await transport.send(HTTPRequest(url: URL(string: "https://example.com")!))
            Issue.record("Expected responseTooLarge")
        } catch let error as HTTPError {
            #expect(error == .responseTooLarge)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("A response over the limit is rejected by stream")
    func overLimitStream() async {
        StubURLProtocol.body = Data(repeating: 0x41, count: 1024)
        StubURLProtocol.statusCode = 200
        StubURLProtocol.headers = ["Content-Length": "1024"]
        let transport = URLSessionTransport(session: makeSession(), maxResponseBytes: 128)
        do {
            _ = try await transport.stream(HTTPRequest(url: URL(string: "https://example.com")!))
            Issue.record("Expected responseTooLarge")
        } catch let error as HTTPError {
            #expect(error == .responseTooLarge)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
