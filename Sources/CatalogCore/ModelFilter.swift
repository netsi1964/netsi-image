import Foundation

public enum Availability: String, Sendable, Equatable, Codable {
    case generatable
    case noImageEndpoint
    case chatOnly

    public var title: String {
        switch self {
        case .generatable: return "Kan generere billeder"
        case .noImageEndpoint: return "Ingen offentlig billed-endpoint"
        case .chatOnly: return "Kun chat/responses"
        }
    }
}

public struct ModelRow: Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var publisher: String
    public var surfaces: [SurfaceKind]
    public var providers: [String]
    public var supportsStreaming: Bool
    public var availability: Availability
    /// Cheapest per-token price in the catalog, or `nil` when the endpoint has no price data.
    public var pricePerToken: String?

    public init(model: CatalogModel) {
        id = model.id
        name = model.name
        publisher = model.publisher
        surfaces = model.surfaceKinds
        providers = model.providerSlugs
        supportsStreaming = model.imageEndpoints.contains(where: \.supportsStreaming)
        pricePerToken = Self.pricePerToken(for: model)
        if let images = model.surface(.images) {
            if images.endpoints.isEmpty {
                availability = .noImageEndpoint
            } else {
                availability = .generatable
            }
        } else {
            availability = .chatOnly
        }
    }

    /// The cheapest per-token price, preferring the output image rate.
    public static func pricePerToken(for model: CatalogModel) -> String? {
        let rules = model.imageEndpoints.flatMap(\.pricing)
        guard let rule = rules.first(where: { $0.unit == "token" && $0.billable == "output_image" })
            ?? rules.first(where: { $0.unit == "token" })
        else { return nil }
        let number = NSDecimalNumber(decimal: rule.costUSD)
        return "$\(number.stringValue)/token"
    }
}

/// A product line: several model versions grouped under one publisher, e.g.
/// "Google: Nano Banana" with "Nano Banana 2.1" and "Nano Banana Pro" underneath.
public struct ModelFamily: Sendable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var publisher: String
    public var publisherDisplayName: String
    public var rows: [ModelRow]

    public init(id: String, title: String, publisher: String, publisherDisplayName: String, rows: [ModelRow]) {
        self.id = id
        self.title = title
        self.publisher = publisher
        self.publisherDisplayName = publisherDisplayName
        self.rows = rows
    }

    /// Display title, e.g. "Google: Nano Banana".
    public var displayName: String { "\(publisherDisplayName): \(title)" }

    /// Lowest price per token among the family's endpoints, if the catalog has any.
    public var cheapestPerToken: String? {
        rows.compactMap(\.pricePerToken).min()
    }

    /// Groups filtered rows into product lines, preserving catalog order.
    public static func families(_ rows: [ModelRow]) -> [ModelFamily] {
        var order: [String] = []
        var grouped: [String: [ModelRow]] = [:]
        for row in rows {
            let key = "\(row.publisher)|\(familyName(for: row))"
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(row)
        }
        return order.compactMap { key in
            guard let rows = grouped[key], let first = rows.first else { return nil }
            return ModelFamily(
                id: key,
                title: familyName(for: first),
                publisher: first.publisher,
                publisherDisplayName: publisherDisplayName(for: first),
                rows: rows
            )
        }
    }

    /// "Google" from the catalog's "Google: …" name prefix, falling back to the slug.
    public static func publisherDisplayName(for row: ModelRow) -> String {
        if let colon = row.name.firstIndex(of: ":") {
            let prefix = row.name[..<colon].trimmingCharacters(in: .whitespaces)
            if !prefix.isEmpty { return prefix }
        }
        return row.publisher.capitalized
    }

    /// The product name without the version suffix, e.g. "Nano Banana 2.1" → "Nano Banana".
    public static func familyName(for row: ModelRow) -> String {
        var name = row.name
        if let colon = name.firstIndex(of: ":") {
            name = String(name[name.index(after: colon)...])
        }
        if let paren = name.firstIndex(of: "(") { name = String(name[..<paren]) }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)

        var words = name.split(separator: " ").map(String.init)
        while words.count > 1, let last = words.last, isVersionOrDescriptor(last) {
            words.removeLast()
        }
        // A single word may still carry a version suffix, e.g. "FLUX.2" or "GPT-5.4".
        if words.count == 1, let only = words.first {
            if let dot = only.firstIndex(of: "."), dot > only.startIndex {
                words = [String(only[..<dot])]
            } else if let dash = only.firstIndex(of: "-"), dash > only.startIndex {
                words = [String(only[..<dash])]
            }
        }
        return words.isEmpty ? name : words.joined(separator: " ")
    }

    /// A trailing token that carries a version number or a variant descriptor.
    private static func isVersionOrDescriptor(_ token: String) -> Bool {
        if token.rangeOfCharacter(from: .decimalDigits) != nil { return true }
        return descriptors.contains(token.lowercased())
    }

    private static let descriptors: Set<String> = [
        "pro", "lite", "flash", "turbo", "highspeed", "medium", "large", "max",
        "flex", "utility", "styles", "vector", "edit", "preview", "beta",
        "sunburst", "flare", "klein", "mini", "image", "router", "code",
        "imagine", "4b", "h3", "k3",
    ]
}

public struct ModelFilter: Sendable, Equatable {
    public var text: String
    public var publisher: String?
    public var surface: SurfaceKind?
    public var provider: String?
    public var generatableOnly: Bool

    public init(
        text: String = "",
        publisher: String? = nil,
        surface: SurfaceKind? = nil,
        provider: String? = nil,
        generatableOnly: Bool = false
    ) {
        self.text = text
        self.publisher = publisher
        self.surface = surface
        self.provider = provider
        self.generatableOnly = generatableOnly
    }

    public func matches(_ row: ModelRow) -> Bool {
        if generatableOnly && row.availability != .generatable { return false }
        if let publisher, row.publisher != publisher { return false }
        if let surface, !row.surfaces.contains(surface) { return false }
        if let provider, !row.providers.contains(provider) { return false }
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return row.id.lowercased().contains(needle)
            || row.name.lowercased().contains(needle)
            || row.publisher.lowercased().contains(needle)
    }

    public func apply(_ rows: [ModelRow]) -> [ModelRow] {
        rows.filter(matches)
    }
}

public enum EndpointResolution: Sendable, Equatable {
    case resolved(Endpoint)
    case chooseProvider([Endpoint])
    case noImageEndpoint
    case chatOnly

    public var endpoint: Endpoint? {
        if case .resolved(let endpoint) = self { return endpoint }
        return nil
    }
}

public enum EndpointResolver {
    /// Returns exactly one images endpoint, or an explicit provider choice when several exist.
    public static func resolve(_ model: CatalogModel) -> EndpointResolution {
        guard let images = model.surface(.images) else { return .chatOnly }
        switch images.endpoints.count {
        case 0: return .noImageEndpoint
        case 1: return .resolved(images.endpoints[0])
        default: return .chooseProvider(images.endpoints)
        }
    }
}
