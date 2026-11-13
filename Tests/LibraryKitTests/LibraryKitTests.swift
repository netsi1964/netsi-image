import CatalogCore
import CoreSupport
import Foundation
import Testing

@testable import GenerationKit
@testable import LibraryKit

private func makeEndpoint() -> Endpoint {
    Endpoint(
        id: "test/model@test",
        providerName: "Test",
        providerSlug: "test",
        providerTag: "test",
        modelId: "test/model",
        parameters: []
    )
}

private func makeJob() -> GenerationJob {
    GenerationJob(
        modelId: "test/model",
        endpointId: "test/model@test",
        requestBody: .object(["model": .string("test/model"), "prompt": .string("Et fyrtårn")])
    )
}

private func makeResult() -> GenerationResult {
    GenerationResult(index: 0, data: Data("fake-image-bytes".utf8), mediaType: "image/png", width: 4, height: 3)
}

private func tempRoot() throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Suite("Image writer and sidecars")
struct ImageWriterTests {
    @Test("Writes image and sidecar with the measured field set")
    func writesFiles() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = LibraryPaths(root: root)
        let writer = ImageWriter(paths: paths)
        let job = makeJob()
        let result = makeResult()
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let written = try writer.write(
            data: result.data,
            result: result,
            job: job,
            endpoint: makeEndpoint(),
            parameters: ["prompt": .string("Et fyrtårn"), "quality": .string("high")],
            prompt: "Et fyrtårn",
            catalogVersion: "1.0.0",
            date: date
        )

        #expect(FileManager.default.fileExists(atPath: written.imageURL.path))
        #expect(FileManager.default.fileExists(atPath: written.sidecarURL.path))
        #expect(written.imageURL.lastPathComponent.contains("test-model"))
        #expect(written.imageURL.lastPathComponent.hasSuffix(".png"))
        #expect(written.relativeImagePath.hasPrefix("Library/"))
        #expect(written.relativeSidecarPath.hasPrefix("Library/"))

        let sidecar = try Sidecar(data: Data(contentsOf: written.sidecarURL))
        #expect(sidecar.formatVersion == 1)
        #expect(sidecar.jobId == job.id.uuidString)
        #expect(sidecar.modelId == "test/model")
        #expect(sidecar.promptText == "Et fyrtårn")
        #expect(sidecar.parameters["quality"] == .string("high"))
        #expect(sidecar["request"]?["body"]?["prompt"] == .string("Et fyrtårn"))
        #expect(sidecar["result"]?["sha256"]?.stringValue == written.sha256)
        #expect(sidecar.width == 4)
        #expect(sidecar.height == 3)
    }

    @Test("Embeds the JSON inside the image file")
    func embedsMetadata() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
        let result = GenerationResult(index: 0, data: png, mediaType: "image/png", width: 1, height: 1)
        let writer = ImageWriter(paths: LibraryPaths(root: root))

        let written = try writer.write(
            data: png,
            result: result,
            job: makeJob(),
            endpoint: makeEndpoint(),
            parameters: [:],
            prompt: "Et fyrtårn",
            catalogVersion: "1",
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let bytes = try Data(contentsOf: written.imageURL)
        let embedded = try #require(ImageMetadata.json(from: bytes, mediaType: "image/png"))
        #expect(embedded.contains("Et fyrtårn"))
        #expect(embedded.contains("Netsi Image"))
        #expect(bytes.count > png.count)
    }

    @Test("Embeds the JSON inside a JPEG file")
    func embedsMetadataJPEG() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let jpeg = try #require(Data(base64Encoded: "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q=="))
        let result = GenerationResult(index: 0, data: jpeg, mediaType: "image/jpeg", width: 1, height: 1)
        let writer = ImageWriter(paths: LibraryPaths(root: root))

        let written = try writer.write(
            data: jpeg,
            result: result,
            job: makeJob(),
            endpoint: makeEndpoint(),
            parameters: [:],
            prompt: "Et fyrtårn",
            catalogVersion: "1",
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let bytes = try Data(contentsOf: written.imageURL)
        let embedded = try #require(ImageMetadata.json(from: bytes, mediaType: "image/jpeg"))
        #expect(embedded.contains("Et fyrtårn"))
        #expect(embedded.contains("Netsi Image"))
        #expect(bytes.count > jpeg.count)
    }

    @Test("Collisions get a suffix instead of overwriting")
    func collision() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = ImageWriter(paths: LibraryPaths(root: root))
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let job = makeJob()

        let first = try writer.write(data: Data("a".utf8), result: makeResult(), job: job, endpoint: makeEndpoint(), parameters: [:], prompt: "p", catalogVersion: "1", date: date)
        let second = try writer.write(data: Data("b".utf8), result: makeResult(), job: job, endpoint: makeEndpoint(), parameters: [:], prompt: "p", catalogVersion: "1", date: date)

        #expect(first.imageURL != second.imageURL)
        #expect(second.imageURL.lastPathComponent.contains("-1."))
        #expect(try Data(contentsOf: first.imageURL) == Data("a".utf8))
    }

    @Test("Unknown sidecar fields survive a rewrite")
    func preservesUnknownFields() throws {
        var sidecar = Sidecar(fields: ["formatVersion": .number(1), "futureField": .string("bevar mig")])
        sidecar["jobId"] = .string("abc")
        let data = try sidecar.encoded()
        let reparsed = try Sidecar(data: data)
        #expect(reparsed["futureField"] == .string("bevar mig"))
        #expect(reparsed.jobId == "abc")
    }
}

@Suite("Index, rebuild and search")
struct LibraryIndexTests {
    @Test("Deleting the index and rebuilding restores every item")
    func rebuild() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LibraryPaths(root: root)
        let writer = ImageWriter(paths: paths)
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        for index in 0..<25 {
            let result = GenerationResult(index: index, data: Data("bytes-\(index)".utf8), mediaType: "image/png", width: 8, height: 8)
            _ = try writer.write(
                data: result.data,
                result: result,
                job: makeJob(),
                endpoint: makeEndpoint(),
                parameters: [:],
                prompt: "Prompt \(index)",
                catalogVersion: "1",
                date: date.addingTimeInterval(Double(index))
            )
        }

        let index = try JSONIndex(url: paths.indexURL)
        let rebuilt = try IndexRebuilder().rebuild(root: root)
        try index.rebuild(from: rebuilt)
        #expect(index.all().count == 25)

        try FileManager.default.removeItem(at: paths.indexURL)
        let empty = try JSONIndex(url: paths.indexURL)
        #expect(empty.all().isEmpty)

        try empty.rebuild(from: try IndexRebuilder().rebuild(root: root))
        #expect(empty.all().count == 25)
        #expect(empty.all().allSatisfy { !$0.sha256.isEmpty })
    }

    @Test("A moved image is reported missing")
    func missingImage() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LibraryPaths(root: root)
        let writer = ImageWriter(paths: paths)
        let written = try writer.write(data: Data("x".utf8), result: makeResult(), job: makeJob(), endpoint: makeEndpoint(), parameters: [:], prompt: "p", catalogVersion: "1", date: Date())

        try FileManager.default.removeItem(at: written.imageURL)
        let items = try IndexRebuilder().rebuild(root: root)
        #expect(items.count == 1)
        #expect(items[0].missing)
    }

    @Test("Search matches prompt words and ignores case")
    func search() {
        let items = [
            LibraryItem(sha256: "1", filePath: "a.png", sidecarPath: "a.json", createdAt: "2026-01-01", promptText: "Et fyrtårn ved Vestkysten"),
            LibraryItem(sha256: "2", filePath: "b.png", sidecarPath: "b.json", createdAt: "2026-01-02", promptText: "En skovsø om morgenen"),
        ]
        #expect(LibrarySearch.search("fyrtårn", in: items).count == 1)
        #expect(LibrarySearch.search("VESTKYSTEN", in: items).count == 1)
        #expect(LibrarySearch.search("skovsø morgen", in: items).count == 1)
        #expect(LibrarySearch.search("", in: items).count == 2)
    }

    @Test("10.000 items search under 300 ms")
    func searchPerformance() {
        let items = (0..<10_000).map { index in
            LibraryItem(
                sha256: String(index),
                filePath: "Library/2026/11/11/billede-\(index).png",
                sidecarPath: "Library/2026/11/11/billede-\(index).json",
                createdAt: "2026-11-11",
                promptText: "Prompt nummer \(index) med et fyrtårn"
            )
        }
        let clock = ContinuousClock()
        var result: [LibraryItem] = []
        let elapsed = clock.measure {
            result = LibrarySearch.search("fyrtårn 42", in: items)
        }
        print("Searched 10.000 items in \(elapsed)")
        #expect(!result.isEmpty)
        #expect(elapsed < .milliseconds(300))
    }
}

@Suite("Safe file extensions")
struct LibraryFileExtensionTests {
    @Test("Maps supported formats and rejects SVG")
    func fileExtensionMapping() {
        #expect(LibraryPaths.fileExtension(for: "image/png") == "png")
        #expect(LibraryPaths.fileExtension(for: "image/jpeg") == "jpg")
        #expect(LibraryPaths.fileExtension(for: "image/jpg") == "jpg")
        #expect(LibraryPaths.fileExtension(for: "image/webp") == "webp")
        #expect(LibraryPaths.fileExtension(for: "image/gif") == "gif")
        #expect(LibraryPaths.fileExtension(for: "image/svg+xml") == "bin")
        #expect(LibraryPaths.fileExtension(for: "application/octet-stream") == "bin")
    }

    @Test("An existing SVG sidecar does not crash and is not openable")
    func svgSidecarIsNotOpenable() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LibraryPaths(root: root)
        let day = paths.libraryDirectory.appendingPathComponent("2026/01/01", isDirectory: true)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)

        var sidecar = Sidecar(fields: ["formatVersion": .number(1)])
        sidecar["result"] = .object([
            "mediaType": .string("image/svg+xml"),
            "sha256": .string("abc"),
            "file": .string("billede.svg"),
        ])
        sidecar["createdAt"] = .string("2026-01-01T00:00:00Z")
        try sidecar.encoded().write(to: day.appendingPathComponent("billede.json"))
        try Data("<svg onload=\"alert(1)\"></svg>".utf8).write(to: day.appendingPathComponent("billede.svg"))

        let items = try IndexRebuilder().rebuild(root: root)
        #expect(items.count == 1)
        #expect(items[0].isOpenable == false)
        #expect(items[0].filePath.hasSuffix(".bin"))
    }

    @Test("A library item pointing at .svg is not openable")
    func itemWithSVGIsNotOpenable() {
        let item = LibraryItem(
            sha256: "x",
            filePath: "Library/2026/01/01/billede.svg",
            sidecarPath: "Library/2026/01/01/billede.json",
            createdAt: "2026-01-01"
        )
        #expect(item.isOpenable == false)
    }
}
