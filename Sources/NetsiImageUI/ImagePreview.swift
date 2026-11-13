import AppKit
import Foundation
import GenerationKit
import RequestKit
import SwiftUI

/// A full-size image the viewer can show. It is either a freshly generated
/// result (in memory) or a library file (on disk).
public struct PreviewImage: Identifiable {
    public let id = UUID()
    public let title: String
    public let image: NSImage
    public let url: URL?
    public let data: Data?
    public let modelId: String?
    public let prompt: String?
    public let cost: Decimal?
    public let createdAt: String?
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let mediaType: String?
    public let fileSize: Int?

    public init(
        title: String,
        image: NSImage,
        url: URL? = nil,
        data: Data? = nil,
        modelId: String? = nil,
        prompt: String? = nil,
        cost: Decimal? = nil,
        createdAt: String? = nil,
        pixelWidth: Int,
        pixelHeight: Int,
        mediaType: String? = nil,
        fileSize: Int? = nil
    ) {
        self.title = title
        self.image = image
        self.url = url
        self.data = data
        self.modelId = modelId
        self.prompt = prompt
        self.cost = cost
        self.createdAt = createdAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.mediaType = mediaType
        self.fileSize = fileSize
    }
}

/// Full-size viewer. "Tilpas" fits the image to the window, "1:1" shows it at
/// its natural size, and the slider zooms in between. The image can be opened
/// in the system Preview app or revealed in Finder.
struct ImagePreviewSheet: View {
    let model: AppModel
    let preview: PreviewImage

    @State private var zoom: CGFloat = 1
    @State private var fitToWindow = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(preview.title).font(.headline).lineLimit(1)
                Spacer()
                Button("Åbn i Preview") { model.openInPreview(preview) }
                Button("Vis i Finder") { model.showInFinder(preview) }
                Button("Luk") { model.dismissPreview() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)

            Divider()

            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: preview.image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: displaySize(in: geo.size).width, height: displaySize(in: geo.size).height)
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }

            Divider()

            HStack(spacing: 12) {
                Button("Tilpas") { fitToWindow = true; zoom = 1 }
                Button("1:1") { fitToWindow = false; zoom = 1 }
                Slider(value: $zoom, in: 0.1...8, step: 0.1) { Text("Zoom") } onEditingChanged: { _ in fitToWindow = false }
                Text("\(Int(zoom * 100)) %").font(.caption).monospacedDigit()
                Spacer()
                Text("\(preview.pixelWidth) × \(preview.pixelHeight) px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let modelId = preview.modelId {
                    Text(modelId).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
        .frame(minWidth: 640, minHeight: 520)
    }

    private func displaySize(in container: CGSize) -> CGSize {
        let natural = preview.image.size
        guard natural.width > 0, natural.height > 0 else { return container }
        if fitToWindow {
            let scale = min(container.width / natural.width, container.height / natural.height, 1)
            return CGSize(width: max(1, natural.width * scale), height: max(1, natural.height * scale))
        }
        return CGSize(width: max(1, natural.width * zoom), height: max(1, natural.height * zoom))
    }
}

/// Shows the error message, the raw provider body, the request id and the
/// request body. The "Se detaljer" button in the alert and the result pane
/// opens this sheet.
struct ErrorDetailSheet: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Fejl").font(.title3.bold())
                Spacer()
                Button("Luk") { model.clearError() }
                    .keyboardShortcut(.cancelAction)
            }

            if let error = model.errorDetail {
                Text(error.message).font(.body)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Type").font(.caption).foregroundStyle(.secondary)
                        Text(error.kind.rawValue).font(.caption)
                    }
                    if let requestId = error.requestId {
                        GridRow {
                            Text("Request ID").font(.caption).foregroundStyle(.secondary)
                            Text(requestId).font(.caption).textSelection(.enabled)
                        }
                    }
                    if let retry = error.retryAfterSeconds {
                        GridRow {
                            Text("Prøv igen om").font(.caption).foregroundStyle(.secondary)
                            Text("\(retry) s").font(.caption)
                        }
                    }
                }

                if let detail = error.detail, !detail.isEmpty {
                    Text("Detaljer").font(.headline)
                    ScrollView([.horizontal, .vertical]) {
                        Text(detail)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                }

                if let job = model.lastJob {
                    DisclosureGroup("Request") {
                        ScrollView([.horizontal, .vertical]) {
                            Text((try? JSONPreview.render(job.requestBody)) ?? "{}")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 160)
                    }
                }

                HStack {
                    Button("Kopiér") { model.copyErrorDetails() }
                    if error.isRetryable {
                        Button("Prøv igen") { model.retryLastError() }
                    }
                    Spacer()
                }
            } else {
                Text("Der er ingen fejldetaljer at vise.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 620, height: 480)
    }
}
