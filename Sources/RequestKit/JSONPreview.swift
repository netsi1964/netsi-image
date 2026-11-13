import CatalogCore
import CoreSupport
import Foundation
import ParameterEngine

public enum JSONPreview {
    public static func render(_ body: JSONValue, pretty: Bool = true) throws -> String {
        try body.encodedString(pretty: pretty)
    }

    /// Rebuilds a body from only the given paths, for the "changed fields only" view.
    public static func filtered(_ body: JSONValue, keeping paths: [PathKey]) -> JSONValue {
        var result: [String: JSONValue] = [:]
        for path in paths {
            guard let value = body.value(at: path.components) else { continue }
            ImagesRequestBuilder.setValue(value, at: path, in: &result)
        }
        return .object(result)
    }
}

public enum Redaction {
    /// Replaces inline base64 payloads in the preview only; the client payload keeps the bytes.
    public static func redact(_ body: JSONValue, fileNames: [String: String] = [:]) -> JSONValue {
        switch body {
        case .string(let text) where text.hasPrefix("data:") && text.count > 128:
            let name = fileNames.first { $0.value == text }?.key ?? "billede"
            let megabytes = Double(text.count) / 1_048_576
            return .string("<fil: \(name), \(String(format: "%.1f", megabytes)) MB>")
        case .array(let items):
            return .array(items.map { redact($0, fileNames: fileNames) })
        case .object(let object):
            return .object(object.mapValues { redact($0, fileNames: fileNames) })
        default:
            return body
        }
    }

}

public struct SSEEvent: Sendable, Equatable {
    public var event: String?
    public var data: String
    public var id: String?

    public init(event: String? = nil, data: String, id: String? = nil) {
        self.event = event
        self.data = data
        self.id = id
    }
}

/// Incremental SSE parser. Feed arbitrary byte chunks; event boundaries may fall anywhere.
public struct SSEParser: Sendable {
    private var buffer = Data()
    private var finished = false

    public init() {}

    public var isDone: Bool { finished }

    public mutating func feed(_ data: Data) -> [SSEEvent] {
        buffer.append(data)
        var events: [SSEEvent] = []
        while let range = nextEventRange() {
            let raw = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0..<range.upperBound)
            if let event = parse(raw) {
                events.append(event)
            }
        }
        return events
    }

    /// Flushes a trailing event without a terminating blank line.
    public mutating func flush() -> [SSEEvent] {
        guard !buffer.isEmpty else { return [] }
        let raw = buffer
        buffer.removeAll()
        return parse(raw).map { [$0] } ?? []
    }

    private mutating func nextEventRange() -> Range<Int>? {
        let lf = Data([0x0A, 0x0A])
        let crlf = Data([0x0D, 0x0A, 0x0D, 0x0A])
        let cr = Data([0x0D, 0x0D])
        var best: Range<Int>?
        for separator in [lf, crlf, cr] {
            if let found = buffer.range(of: separator), best == nil || found.lowerBound < best!.lowerBound {
                best = found
            }
        }
        return best
    }

    private mutating func parse(_ data: Data) -> SSEEvent? {
        let text = String(decoding: data, as: UTF8.self)
        var eventName: String?
        var identifier: String?
        var dataLines: [String] = []

        for line in text.components(separatedBy: .newlines) {
            if line.isEmpty || line.hasPrefix(":") { continue }
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let field = String(parts.first ?? "")
            var value = parts.count > 1 ? String(parts[1]) : ""
            if value.hasPrefix(" ") { value.removeFirst() }
            switch field {
            case "event": eventName = value
            case "data": dataLines.append(value)
            case "id": identifier = value
            default: break
            }
        }

        guard !dataLines.isEmpty else { return nil }
        let combined = dataLines.joined(separator: "\n")
        if combined == "[DONE]" {
            finished = true
        }
        return SSEEvent(event: eventName, data: combined, id: identifier)
    }
}
