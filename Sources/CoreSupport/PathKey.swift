import Foundation

/// A request path is a list of object keys. A provider slug that contains a slash
/// (`google-ai-studio/global`) stays exactly one component.
public struct PathKey: Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
    public let components: [String]

    public init(_ components: [String]) {
        self.components = components
    }

    /// Display-only convenience. Never parse user input back into a path with this:
    /// a key may itself contain a dot.
    public init(display: String) {
        self.components = display.split(separator: ".").map(String.init)
    }

    public var description: String {
        components.joined(separator: ".")
    }

    public var pointer: String {
        "/" + components.map { $0.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1") }
            .joined(separator: "/")
    }

    public var isEmpty: Bool { components.isEmpty }

    public var parent: PathKey? {
        guard components.count > 1 else { return nil }
        return PathKey(Array(components.dropLast()))
    }

    public var lastComponent: String? { components.last }

    public func appending(_ component: String) -> PathKey {
        PathKey(components + [component])
    }

    public static func < (lhs: PathKey, rhs: PathKey) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.components = try container.decode([String].self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(components)
    }
}
