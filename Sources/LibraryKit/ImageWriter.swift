import CatalogCore
import CoreSupport
import CryptoKit
import Foundation
import GenerationKit

public struct LibraryPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    public var libraryDirectory: URL { root.appendingPathComponent("Library", isDirectory: true) }
    public var indexURL: URL { root.appendingPathComponent("library-index.json") }
    public var thumbnailsDirectory: URL { root.appendingPathComponent("Thumbnails", isDirectory: true) }

    public func dayDirectory(for date: Date, calendar: Calendar = .current, timeZone: TimeZone = .current) -> URL {
        let components = calendar.dateComponents(in: timeZone, from: date)
        let year = String(format: "%04d", components.year ?? 0)
        let month = String(format: "%02d", components.month ?? 0)
        let day = String(format: "%02d", components.day ?? 0)
        return libraryDirectory
            .appendingPathComponent(year, isDirectory: true)
            .appendingPathComponent(month, isDirectory: true)
            .appendingPathComponent(day, isDirectory: true)
    }

    public static func modelSlug(_ modelId: String) -> String {
        let slug = modelId
            .lowercased()
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "@", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        return slug.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }
    }

    public static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d%02d%02d-%02d%02d%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        )
    }

    public static func fileExtension(for mediaType: String) -> String {
        switch mediaType.lowercased() {
        case "image/png": return "png"
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/webp": return "webp"
        case "image/gif": return "gif"
        default: return "bin"
        }
    }
}

/// A sidecar keeps every field, including unknown ones from a newer version of the app.
public struct Sidecar: Sendable, Equatable {
    public var fields: [String: JSONValue]

    public init(fields: [String: JSONValue] = [:]) {
        self.fields = fields
    }

    public init(data: Data) throws {
        let parsed = try JSONValue.parse(data)
        guard let object = parsed.objectValue else {
            throw SidecarError.notAnObject
        }
        self.fields = object
    }

    public subscript(key: String) -> JSONValue? {
        get { fields[key] }
        set { fields[key] = newValue }
    }

    public var formatVersion: Int { fields["formatVersion"]?.intValue ?? 1 }
    public var jobId: String? { fields["jobId"]?.stringValue }
    public var createdAt: String? { fields["createdAt"]?.stringValue }
    public var modelId: String? { fields["model"]?["id"]?.stringValue }
    public var promptText: String? { fields["prompt"]?["raw"]?.stringValue }
    public var costUSD: Decimal? { fields["usage"]?["costUSD"]?.decimalValue }
    public var width: Int? { fields["result"]?["width"]?.intValue }
    public var height: Int? { fields["result"]?["height"]?.intValue }
    public var filePath: String? { fields["result"]?["file"]?.stringValue }
    public var parameters: [String: JSONValue] { fields["parameters"]?.objectValue ?? [:] }

    public func encoded() throws -> Data {
        try JSONValue.object(fields).encoded(pretty: true)
    }

    public static func make(
        job: GenerationJob,
        result: GenerationResult,
        endpoint: Endpoint,
        fileName: String,
        sha256: String,
        parameters: [String: JSONValue],
        prompt: String,
        appVersion: String,
        catalogVersion: String,
        date: Date
    ) -> Sidecar {
        var fields: [String: JSONValue] = [:]
        fields["formatVersion"] = .number(1)
        fields["jobId"] = .string(job.id.uuidString)
        fields["createdAt"] = .string(ISO8601DateFormatter().string(from: date))
        fields["app"] = .object([
            "name": .string("Netsi Image"),
            "version": .string(appVersion),
        ])
        fields["catalog"] = .object([
            "schemaVersion": .string(catalogVersion),
        ])
        fields["model"] = .object([
            "id": .string(endpoint.modelId),
            "endpointId": .string(endpoint.id),
            "provider": .string(endpoint.providerSlug),
            "surface": .string("images"),
        ])
        fields["prompt"] = .object([
            "raw": .string(prompt),
            "composed": .string(prompt),
        ])
        fields["parameters"] = .object(parameters)
        fields["request"] = .object([
            "surface": .string("images"),
            "body": job.requestBody,
        ])
        var resultFields: [String: JSONValue] = [
            "file": .string(fileName),
            "sha256": .string(sha256),
            "bytes": .number(Decimal(result.data.count)),
            "mediaType": .string(result.mediaType),
        ]
        if let width = result.width { resultFields["width"] = .number(Decimal(width)) }
        if let height = result.height { resultFields["height"] = .number(Decimal(height)) }
        if let seed = result.seed { resultFields["seed"] = .number(Decimal(seed)) }
        fields["result"] = .object(resultFields)
        if let cost = job.costUSD {
            fields["usage"] = .object(["costUSD": .number(cost)])
        }
        return Sidecar(fields: fields)
    }
}

public enum SidecarError: Error, Equatable, Sendable {
    case notAnObject
}

public struct WrittenImage: Sendable, Equatable {
    public var imageURL: URL
    public var sidecarURL: URL
    public var relativeImagePath: String
    public var relativeSidecarPath: String
    public var sha256: String

    public init(imageURL: URL, sidecarURL: URL, relativeImagePath: String, relativeSidecarPath: String, sha256: String) {
        self.imageURL = imageURL
        self.sidecarURL = sidecarURL
        self.relativeImagePath = relativeImagePath
        self.relativeSidecarPath = relativeSidecarPath
        self.sha256 = sha256
    }
}

public struct ImageWriter: Sendable {
    private let paths: LibraryPaths
    private let writer: any FileWriting

    public init(paths: LibraryPaths, writer: any FileWriting = AtomicFileWriter()) {
        self.paths = paths
        self.writer = writer
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public func write(
        data: Data,
        result: GenerationResult,
        job: GenerationJob,
        endpoint: Endpoint,
        parameters: [String: JSONValue],
        prompt: String,
        appVersion: String = "1.0.0",
        catalogVersion: String,
        date: Date
    ) throws -> WrittenImage {
        let directory = paths.dayDirectory(for: date)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try PathConfinement.ensureContained(directory, root: paths.root)

        let base = "\(LibraryPaths.timestamp(date))-\(LibraryPaths.modelSlug(job.modelId))-\(job.id.uuidString.prefix(6))"
        let ext = LibraryPaths.fileExtension(for: result.mediaType)

        var suffix = 0
        var imageURL = directory.appendingPathComponent("\(base).\(ext)")
        while FileManager.default.fileExists(atPath: imageURL.path) {
            suffix += 1
            imageURL = directory.appendingPathComponent("\(base)-\(suffix).\(ext)")
        }
        let sidecarURL = imageURL.deletingPathExtension().appendingPathExtension("json")

        let hash = Self.sha256(data)
        var sidecar = Sidecar.make(
            job: job,
            result: result,
            endpoint: endpoint,
            fileName: imageURL.lastPathComponent,
            sha256: hash,
            parameters: parameters,
            prompt: prompt,
            appVersion: appVersion,
            catalogVersion: catalogVersion,
            date: date
        )

        // The JSON travels inside the image, so the picture stays self-describing.
        let encodedSidecar = try sidecar.encoded()
        let imageBytes = ImageMetadata.embed(encodedSidecar, in: data, mediaType: result.mediaType) ?? data
        let finalHash = Self.sha256(imageBytes)
        if imageBytes != data {
            var fields = sidecar.fields
            if var resultFields = fields["result"]?.objectValue {
                resultFields["sha256"] = .string(finalHash)
                resultFields["bytes"] = .number(Decimal(imageBytes.count))
                fields["result"] = .object(resultFields)
            }
            sidecar = Sidecar(fields: fields)
        }

        try writer.write(imageBytes, to: imageURL)
        try writer.write(try sidecar.encoded(), to: sidecarURL)

        let relativeImage = imageURL.path.replacingOccurrences(of: paths.root.path + "/", with: "")
        let relativeSidecar = sidecarURL.path.replacingOccurrences(of: paths.root.path + "/", with: "")
        return WrittenImage(
            imageURL: imageURL,
            sidecarURL: sidecarURL,
            relativeImagePath: relativeImage,
            relativeSidecarPath: relativeSidecar,
            sha256: finalHash
        )
    }
}
