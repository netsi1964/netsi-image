import Foundation

/// Sniffs the media type of an image from its magic bytes and confirms that
/// ImageIO can actually decode it. Only the formats the library accepts are
/// reported; anything else — including SVG — returns `nil`.
public enum ImageFormatSniffer {
    public static let supportedMediaTypes: Set<String> = [
        "image/png", "image/jpeg", "image/webp", "image/gif",
    ]

    public static func mediaType(for data: Data) -> String? {
        guard let sniffed = sniffMagicBytes(data) else { return nil }
        guard supportedMediaTypes.contains(sniffed) else { return nil }
        // Confirm the bytes really are a decodable image of that format.
        guard ImageIOProbe.probe(data: data) != nil else { return nil }
        return sniffed
    }

    private static func sniffMagicBytes(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(16))

        if bytes.count >= 8,
           bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47,
           bytes[4] == 0x0D, bytes[5] == 0x0A, bytes[6] == 0x1A, bytes[7] == 0x0A {
            return "image/png"
        }
        if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
            return "image/jpeg"
        }
        if bytes.count >= 6 {
            let gif = String(bytes: bytes[0..<6], encoding: .ascii)
            if gif == "GIF87a" || gif == "GIF89a" {
                return "image/gif"
            }
        }
        if bytes.count >= 12,
           bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46,
           bytes[8] == 0x57, bytes[9] == 0x45, bytes[10] == 0x42, bytes[11] == 0x50 {
            return "image/webp"
        }
        return nil
    }
}
