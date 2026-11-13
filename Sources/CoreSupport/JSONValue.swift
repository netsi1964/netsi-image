import Foundation

/// A JSON value that keeps every catalog field, including free-form schema keywords.
/// Numbers are `Decimal` so prices and bounds do not drift through binary floating point.
public enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Decimal)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

// MARK: - Accessors

extension JSONValue {
    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var decimalValue: Decimal? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        guard case .number(let value) = self else { return nil }
        let number = NSDecimalNumber(decimal: value)
        guard number.decimalValue == Decimal(number.int64Value) else { return nil }
        return Int(exactly: number.int64Value)
    }

    public var doubleValue: Double? {
        guard case .number(let value) = self else { return nil }
        return NSDecimalNumber(decimal: value).doubleValue
    }

    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    public subscript(index: Int) -> JSONValue? {
        guard let array = arrayValue, array.indices.contains(index) else { return nil }
        return array[index]
    }

    public func value(at path: [String]) -> JSONValue? {
        var current = self
        for component in path {
            guard let next = current[component] else { return nil }
            current = next
        }
        return current
    }

    /// The declared `type` keyword, if the value is a schema object.
    public var schemaTypeNames: [String] {
        switch self["type"] {
        case .string(let name): return [name]
        case .array(let names): return names.compactMap(\.stringValue)
        default: return []
        }
    }

    /// Human description used in accessibility labels and messages.
    public var kindDescription: String {
        switch self {
        case .null: return "intet"
        case .bool: return "ja/nej"
        case .number: return "tal"
        case .string: return "tekst"
        case .array: return "liste"
        case .object: return "objekt"
        }
    }
}

// MARK: - Parsing and encoding

extension JSONValue {
    public static func parse(_ data: Data) throws -> JSONValue {
        try validateDepth(data, maxDepth: 64)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return JSONValue(any: object)
    }

    /// Rejects absurdly deep JSON before handing it to JSONSerialization and the
    /// recursive `JSONValue(any:)` initializer. Scans raw bytes and ignores
    /// braces inside strings, so an escaped quote cannot hide a level.
    private static func validateDepth(_ data: Data, maxDepth: Int) throws {
        var depth = 0
        var inString = false
        var escaped = false
        for byte in data {
            if inString {
                if escaped {
                    escaped = false
                } else if byte == 0x5C { // backslash
                    escaped = true
                } else if byte == 0x22 { // quote
                    inString = false
                }
                continue
            }
            switch byte {
            case 0x22: // quote
                inString = true
            case 0x7B, 0x5B: // { or [
                depth += 1
                if depth > maxDepth { throw JSONValueError.tooDeep }
            case 0x7D, 0x5D: // } or ]
                depth -= 1
            default:
                break
            }
        }
    }

    public static func parse(_ string: String) throws -> JSONValue {
        guard let data = string.data(using: .utf8) else {
            throw JSONValueError.encodingFailed
        }
        return try parse(data)
    }

    public init(any: Any) {
        switch any {
        case is NSNull:
            self = .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(Decimal(string: number.stringValue) ?? Decimal(number.doubleValue))
            }
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(array.map(JSONValue.init(any:)))
        case let dictionary as [String: Any]:
            self = .object(dictionary.mapValues(JSONValue.init(any:)))
        default:
            self = .null
        }
    }

    public func encoded(pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : []
        return try encoder.encode(self)
    }

    public func encodedString(pretty: Bool = false) throws -> String {
        String(decoding: try encoded(pretty: pretty), as: UTF8.self)
    }
}

public enum JSONValueError: Error, Equatable {
    case encodingFailed
    case tooDeep
}

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Int64.self) {
            self = .number(Decimal(value))
        } else if let value = try? container.decode(Decimal.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        }
    }
}

// MARK: - Convenience literals

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .number(Decimal(value))
    }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        var object: [String: JSONValue] = [:]
        for (key, value) in elements {
            object[key] = value
        }
        self = .object(object)
    }
}
