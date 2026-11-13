import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ImageInfo: Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var hasAlpha: Bool
    public var mediaType: String?
    public var byteCount: Int

    public init(width: Int, height: Int, hasAlpha: Bool, mediaType: String?, byteCount: Int) {
        self.width = width
        self.height = height
        self.hasAlpha = hasAlpha
        self.mediaType = mediaType
        self.byteCount = byteCount
    }
}

public enum ImageProbeError: Error, Equatable, Sendable {
    case unreadable(String)
}

public protocol ImageProbing: Sendable {
    func probe(url: URL) throws -> ImageInfo
}

public struct ImageIOProbe: ImageProbing {
    public init() {}

    public func probe(url: URL) throws -> ImageInfo {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            throw ImageProbeError.unreadable(url.lastPathComponent)
        }

        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        var mediaType: String?
        if let typeIdentifier = CGImageSourceGetType(source) {
            mediaType = UTType(typeIdentifier as String)?.preferredMIMEType
        }
        let hasAlpha = Self.readAlpha(source: source, mediaType: mediaType)
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let byteCount = (attributes?[.size] as? NSNumber)?.intValue ?? 0

        return ImageInfo(
            width: width,
            height: height,
            hasAlpha: hasAlpha,
            mediaType: mediaType,
            byteCount: byteCount
        )
    }

    private static func readAlpha(source: CGImageSource, mediaType: String?) -> Bool {
        if mediaType == "image/jpeg" { return false }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            return true
        }
    }

    /// Probes in-memory bytes, used for freshly decoded generation results.
    public static func probe(data: Data) -> ImageInfo? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        var mediaType: String?
        if let typeIdentifier = CGImageSourceGetType(source) {
            mediaType = UTType(typeIdentifier as String)?.preferredMIMEType
        }
        return ImageInfo(
            width: width,
            height: height,
            hasAlpha: readAlpha(source: source, mediaType: mediaType),
            mediaType: mediaType,
            byteCount: data.count
        )
    }
}

/// Inlines a local image as a base64 data URL. Providers such as xAI accept
/// `data:` and `http(s)://` URLs, but never a local `file://` URL.
public enum ImageDataURL {
    public static func make(for url: URL) -> String? {
        guard url.isFileURL else { return url.absoluteString }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let mediaType = (try? ImageIOProbe().probe(url: url))?.mediaType
            ?? UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        return "data:\(mediaType);base64,\(data.base64EncodedString())"
    }
}
