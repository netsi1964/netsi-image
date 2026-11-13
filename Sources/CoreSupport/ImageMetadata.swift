import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Embeds a JSON document inside the image file itself, so the metadata travels
/// with the picture and is not lost when the sidecar is copied away.
public enum ImageMetadata {
    /// The keyword used in the image's text metadata.
    public static let keyword = "NetsiImage"

    /// Returns the image with the JSON embedded, or `nil` when the format is
    /// unsupported or the image cannot be written. The caller keeps the
    /// original bytes in that case.
    public static func embed(_ json: Data, in image: Data, mediaType: String) -> Data? {
        guard let text = String(data: json, encoding: .utf8) else { return nil }
        switch mediaType.lowercased() {
        case "image/png":
            return embedPNG(text, in: image)
        case "image/jpeg", "image/jpg":
            return embedJPEG(text, in: image)
        default:
            return nil
        }
    }

    /// Reads the embedded JSON back, if the image has one.
    public static func json(from image: Data, mediaType: String) -> String? {
        switch mediaType.lowercased() {
        case "image/png":
            return readPNG(image)
        case "image/jpeg", "image/jpg":
            return readJPEG(image)
        default:
            return nil
        }
    }

    // MARK: - PNG

    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    private static func embedPNG(_ text: String, in image: Data) -> Data? {
        let bytes = [UInt8](image)
        guard bytes.count > 8, Array(bytes[0..<8]) == pngSignature else { return nil }

        var offset = 8
        var chunks: [Data] = []
        while offset + 12 <= bytes.count {
            let length = Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16
                | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            let type = String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii) ?? ""
            let end = offset + 12 + length
            guard end <= bytes.count else { return nil }
            chunks.append(Data(bytes[offset..<end]))
            offset = end
            if type == "IEND" { break }
        }

        guard !chunks.isEmpty else { return nil }
        var payload = Data(keyword.utf8)
        payload.append(0) // keyword terminator
        payload.append(0) // compression flag
        payload.append(0) // compression method
        payload.append(0) // language tag terminator
        payload.append(0) // translated keyword terminator
        payload.append(contentsOf: text.utf8)

        let chunk = pngChunk(type: "iTXt", payload: payload)

        var output = Data(pngSignature)
        for (index, existing) in chunks.enumerated() {
            if index == 1 {
                // Insert after IHDR, before the first IDAT or other chunk.
                output.append(chunk)
            }
            output.append(existing)
        }
        return output
    }

    private static func pngChunk(type: String, payload: Data) -> Data {
        var chunk = Data()
        let length = UInt32(payload.count).bigEndian
        chunk.append(contentsOf: withUnsafeBytes(of: length) { Array($0) })
        let typeBytes = Data(type.utf8)
        chunk.append(typeBytes)
        chunk.append(payload)
        var crc = CRC32()
        crc.update(typeBytes)
        crc.update(payload)
        let checksum = UInt32(crc.value).bigEndian
        chunk.append(contentsOf: withUnsafeBytes(of: checksum) { Array($0) })
        return chunk
    }

    private static func readPNG(_ image: Data) -> String? {
        let bytes = [UInt8](image)
        guard bytes.count > 8, Array(bytes[0..<8]) == pngSignature else { return nil }
        var offset = 8
        while offset + 12 <= bytes.count {
            let length = Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16
                | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            let type = String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii) ?? ""
            let end = offset + 12 + length
            guard end <= bytes.count else { return nil }
            if type == "iTXt" || type == "tEXt" {
                let payload = Data(bytes[(offset + 8)..<(offset + 8 + length)])
                if let text = textFromPNGChunk(payload, type: type) {
                    return text
                }
            }
            if type == "IEND" { return nil }
            offset = end
        }
        return nil
    }

    private static func textFromPNGChunk(_ payload: Data, type: String) -> String? {
        let bytes = [UInt8](payload)
        guard let terminator = bytes.firstIndex(of: 0) else { return nil }
        let key = String(bytes: bytes[0..<terminator], encoding: .ascii)
        guard key == keyword else { return nil }

        if type == "tEXt" {
            let text = bytes[(terminator + 1)...]
            return String(bytes: text, encoding: .isoLatin1)
        }

        // iTXt: compression flag, method, language tag, translated keyword, then text.
        var cursor = terminator + 1
        guard bytes.count >= cursor + 2 else { return nil }
        let compression = bytes[cursor]
        cursor += 2
        guard let language = bytes[cursor...].firstIndex(of: 0) else { return nil }
        cursor = language + 1
        guard let translated = bytes[cursor...].firstIndex(of: 0) else { return nil }
        cursor = translated + 1
        guard compression == 0 else { return nil }
        return String(bytes: bytes[cursor...], encoding: .utf8)
    }

    // MARK: - JPEG

    private static func embedJPEG(_ text: String, in image: Data) -> Data? {
        let bytes = [UInt8](image)
        guard bytes.count > 2, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        let payload = Data("\(keyword):\(text)".utf8)
        guard payload.count + 2 <= 65_535 else { return nil }
        var segment = Data([0xFF, 0xFE])
        let length = UInt16(payload.count + 2).bigEndian
        segment.append(contentsOf: withUnsafeBytes(of: length) { Array($0) })
        segment.append(payload)

        var output = Data(bytes[0..<2])
        output.append(segment)
        output.append(contentsOf: bytes[2...])
        return output
    }

    private static func readJPEG(_ image: Data) -> String? {
        let bytes = [UInt8](image)
        guard bytes.count > 2, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        var offset = 2
        while offset + 4 <= bytes.count {
            guard bytes[offset] == 0xFF else { return nil }
            let marker = bytes[offset + 1]
            if marker == 0xD8 || marker == 0x01 || (0xD0...0xD7).contains(marker) {
                offset += 2
                continue
            }
            if marker == 0xD9 { return nil }
            let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            guard length >= 2, offset + 2 + length <= bytes.count else { return nil }
            if marker == 0xFE {
                let payload = Data(bytes[(offset + 4)..<(offset + 2 + length)])
                if let text = String(data: payload, encoding: .utf8),
                   text.hasPrefix("\(keyword):") {
                    return String(text.dropFirst(keyword.count + 1))
                }
            }
            offset += 2 + length
        }
        return nil
    }
}

/// CRC-32 (IEEE 802.3) as required by PNG.
private struct CRC32 {
    private var table: [UInt32] = CRC32.makeTable()
    private var crc: UInt32 = 0xFFFF_FFFF

    var value: UInt32 { crc ^ 0xFFFF_FFFF }

    mutating func update(_ data: Data) {
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
    }

    private static func makeTable() -> [UInt32] {
        var table: [UInt32] = []
        table.reserveCapacity(256)
        for index in 0..<256 {
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) != 0 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
            }
            table.append(value)
        }
        return table
    }
}
