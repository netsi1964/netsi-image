import AppKit
import CatalogCore
import CoreSupport
import Foundation
import GenerationKit
import LibraryKit
import Observation
import ParameterEngine
import RequestKit
import SettingsKit
import SwiftUI

@MainActor
@Observable
public final class AppModel {
    // Catalog
    public private(set) var rows: [ModelRow] = []
    public var filter = ModelFilter()
    public private(set) var summary: CatalogSummary?
    public var selectedModelId: String?

    // Configuration
    public var endpoint: Endpoint?
    public var endpointChoices: [Endpoint] = []
    public var draft = ParameterDraft()
    public var prompt: String = "Et fyrtårn ved den jyske vestkyst" {
        didSet {
            syncPromptToDraft()
            recompute()
        }
    }
    public var settings: AppSettings
    public var keyState: KeyState = KeyState(hasKey: false, readOnly: true)
    public var keyInput: String = ""

    // Derived
    public private(set) var plan: FieldPlan = FieldPlan(endpointId: "", sections: [], hiddenUncertainCount: 0, hiddenInactiveCount: 0)
    public private(set) var runState = RunState(canRun: false, blockingCount: 0, warningCount: 0, firstIssue: nil, summary: "Indlæser…")
    public private(set) var issues: [Issue] = []
    public private(set) var previewText = ""
    public private(set) var notSent: [PathKey] = []
    public var focusedPath: PathKey?
    public private(set) var pendingSwitch: EndpointSwitchPlan?

    // Results and library
    public private(set) var lastJob: GenerationJob?
    public private(set) var libraryItems: [LibraryKit.LibraryItem] = []
    public var libraryQuery: String = ""
    public private(set) var isGenerating = false
    public private(set) var isRefreshing = false
    public private(set) var pendingRefreshData: Data?
    public private(set) var pendingRefreshManifest: [String: String]?
    public private(set) var refreshQuestion: String?
    public private(set) var routingWarnings: [String] = []
    public var showPreview = false
    public var showSettings = false
    public var errorMessage: String?
    public var errorDetail: JobError?
    public var showErrorDetails = false
    public var previewImage: PreviewImage?
    public private(set) var loadError: String?
    public private(set) var libraryRootPath: String = ""

    private var store: CatalogStore?
    private var library: LibraryService?
    private let keychain = KeychainStore()
    private let settingsStore = SettingsStore()
    private let coordinator: GenerationCoordinator
    private let builder = ImagesRequestBuilder()
    private var catalogVersion = "1.0.0"

    public init() {
        settings = settingsStore.load()
        coordinator = GenerationCoordinator(client: OpenRouterClient())
    }

    // MARK: - Loading

    public func load() async {
        do {
            let cache = SnapshotCache()
            let bundled = try CatalogStore.bundledData()
            let bundledVersion = (try? JSONValue.parse(bundled))?["schemaVersion"]?.stringValue
            var data = bundled
            if let cached = try? cache.load(),
               let cachedVersion = (try? JSONValue.parse(cached))?["schemaVersion"]?.stringValue,
               cachedVersion == bundledVersion {
                data = cached
            }
            let store: CatalogStore
            do {
                store = try CatalogStore(data: data)
            } catch {
                store = try CatalogStore(data: bundled)
            }
            self.store = store
            summary = await store.summary()
            catalogVersion = await store.schemaVersion()
            let models = await store.allModels()
            rows = models.map(ModelRow.init(model:))
            refreshKeyState()

            let preferred = settings.defaultModelId.flatMap { id in rows.first { $0.id == id } }
            let firstGeneratable = rows.first { $0.availability == .generatable }
            await loadDefinitions()
            await selectModel(id: preferred?.id ?? firstGeneratable?.id ?? rows.first?.id ?? "")
            await prepareLibrary()
            await refreshKeyUsage()
        } catch {
            loadError = "Kataloget kunne ikke indlæses: \(error)"
        }
    }

    private func prepareLibrary() async {
        let root: URL
        if let path = settings.libraryRootPath {
            root = URL(fileURLWithPath: path)
        } else {
            root = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Pictures/Netsi Image", isDirectory: true)
            settings.libraryRootPath = root.path
            settingsStore.save(settings)
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let service = try LibraryService(root: root, catalogVersion: catalogVersion)
            library = service
            libraryRootPath = root.path
            libraryItems = await service.items()
        } catch {
            errorMessage = "Biblioteket kunne ikke åbnes: \(error)"
            errorDetail = JobError(kind: .unknown, message: "Biblioteket kunne ikke åbnes.", detail: "\(error)")
        }
    }

    public func chooseLibraryRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Vælg bibliotek"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.libraryRootPath = url.path
        settingsStore.save(settings)
        Task { await prepareLibrary() }
    }

    // MARK: - Model selection

    public var filteredRows: [ModelRow] { filter.apply(rows) }

    /// Filtered rows grouped into product lines, one row per model version.
    public var families: [ModelFamily] { ModelFamily.families(filteredRows) }

    /// The model row behind the current selection, for display names.
    public var selectedRow: ModelRow? {
        if let id = selectedModelId, let row = rows.first(where: { $0.id == id }) { return row }
        if let id = endpoint?.modelId { return rows.first(where: { $0.id == id }) }
        return nil
    }

    /// A display name for a model id, or the id itself when the catalog has no row.
    public func displayName(forModel modelId: String?) -> String {
        guard let modelId else { return "—" }
        return rows.first(where: { $0.id == modelId })?.name ?? modelId
    }

    public func chooseModel(_ id: String) {
        Task { await selectModel(id: id) }
    }

    public func selectModel(id: String) async {
        selectedModelId = id
        guard let store, let model = await store.model(id: id) else { return }
        switch EndpointResolver.resolve(model) {
        case .resolved(let endpoint):
            applyEndpoint(endpoint)
        case .chooseProvider(let endpoints):
            endpointChoices = endpoints
        case .noImageEndpoint:
            errorMessage = "\(model.name) har ingen offentlig billed-endpoint."
        case .chatOnly:
            errorMessage = "\(model.name) understøtter kun chat/responses i dette katalog."
        }
    }

    public func choose(endpoint: Endpoint) {
        endpointChoices = []
        applyEndpoint(endpoint)
    }

    private func applyEndpoint(_ newEndpoint: Endpoint) {
        if let previous = endpoint, previous.id != newEndpoint.id {
            let switchPlan = EndpointSwitchPlan.plan(draft: draft, from: previous, to: newEndpoint)
            if switchPlan.dropped.isEmpty {
                draft = switchPlan.applied(to: draft, confirming: true)
                commit(newEndpoint)
            } else {
                pendingSwitch = switchPlan
                commit(newEndpoint)
            }
        } else {
            commit(newEndpoint)
        }
    }

    public func confirmSwitch() {
        if let pendingSwitch {
            draft = pendingSwitch.applied(to: draft, confirming: true)
        }
        pendingSwitch = nil
        recompute()
    }

    public func cancelSwitch() {
        pendingSwitch = nil
        recompute()
    }

    private func commit(_ endpoint: Endpoint) {
        self.endpoint = endpoint
        settings.defaultModelId = endpoint.modelId
        settingsStore.save(settings)
        syncPromptToDraft()
        recompute()
    }

    // MARK: - Draft editing

    public func value(_ path: PathKey) -> ParameterValue { draft[path] }

    public func set(_ value: JSONValue, at path: PathKey) {
        draft.set(value, at: path)
        recompute()
    }

    public func reset(_ path: PathKey) {
        draft.reset(path)
        recompute()
    }

    public func applyFix(_ fix: FixSuggestion) {
        draft.set(fix.value, at: fix.path)
        recompute()
    }

    public func recompute() {
        guard let endpoint else { return }
        let engine = ValidationEngine(definitions: definitions())
        issues = engine.validate(draft: draft, endpoint: endpoint)
        runState = engine.runState(draft: draft, endpoint: endpoint)
        plan = FieldPlan.make(
            endpoint: endpoint,
            draft: draft,
            settings: FieldPlanSettings(
                showUncertain: settings.showUncertain,
                hideInactive: settings.hideInactive,
                requiredFirst: true
            )
        )
        refreshPreview()
    }

    /// Keeps the prompt in the request draft, so the prompt the user types in
    /// the canvas is the prompt the provider receives. The prompt field is
    /// optional in some catalogs, so it is only set when the endpoint has one.
    private func syncPromptToDraft() {
        guard let endpoint,
              let path = endpoint.parameters.first(where: { $0.key == "prompt" })?.path
        else { return }
        draft.set(.string(prompt), at: path)
    }

    /// Refreshes the snapshot from OpenRouter, keeps the old one on any failure, and
    /// updates the picker without a restart (AC-012). A catalog that shrinks by more than
    /// 10 % is held back until the user confirms.
    public func refreshCatalog(force: Bool = false) async {
        guard store != nil else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let bundled = try CatalogStore.bundledData()
            let client = CatalogRefreshClient(transport: URLSessionTransport(maxResponseBytes: 16 * 1024 * 1024))
            let result = try await client.refresh(bundledData: bundled)

            let currentCount = rows.count
            if !force, currentCount > 0, result.summary.modelCount < Int(Double(currentCount) * 0.9) {
                pendingRefreshData = result.data
                pendingRefreshManifest = result.manifest
                refreshQuestion = "Kataloget faldt fra \(currentCount) til \(result.summary.modelCount) modeller. Bekræft for at bruge det."
                return
            }

            try await apply(refresh: result)
        } catch {
            errorMessage = "Kataloget kunne ikke opdateres: \(error)"
            errorDetail = JobError(kind: .unknown, message: "Kataloget kunne ikke opdateres.", detail: "\(error)")
        }
    }

    public func confirmRefresh() async {
        guard let data = pendingRefreshData else { return }
        let manifest = pendingRefreshManifest
        pendingRefreshData = nil
        pendingRefreshManifest = nil
        refreshQuestion = nil
        do {
            try await store?.replace(data: data)
            if let manifest { try? SnapshotCache().save(data, manifest: manifest) }
            await reloadRows()
        } catch {
            errorMessage = "Kataloget kunne ikke opdateres: \(error)"
        }
    }

    public func dismissRefresh() {
        pendingRefreshData = nil
        pendingRefreshManifest = nil
        refreshQuestion = nil
    }

    private func apply(refresh result: CatalogRefreshResult) async throws {
        try await store?.replace(data: result.data)
        try? SnapshotCache().save(result.data, manifest: result.manifest)
        await reloadRows()
    }

    private func reloadRows() async {
        guard let store else { return }
        summary = await store.summary()
        catalogVersion = await store.schemaVersion()
        definitionsCache = await store.definitions()
        rows = await store.allModels().map(ModelRow.init(model:))
        if let id = selectedModelId {
            await selectModel(id: id)
        }
    }

    public func testKey() async {
        guard let key = try? keychain.readKey() else {
            keyState = KeyState(hasKey: false, readOnly: true, message: "Ingen nøgle at teste.")
            return
        }
        do {
            let result = try await OpenRouterClient().testKey(apiKey: key)
            apply(result, key: key)
            if !result.ok {
                errorMessage = result.message
                errorDetail = JobError(kind: .unauthorized, message: result.message)
            }
        } catch {
            errorMessage = "Nøglen kunne ikke testes: \(error)"
        }
    }

    /// Fetches the key's spend and credit limit from OpenRouter. Called on
    /// launch and from Indstillinger, where the numbers are informational.
    public func refreshKeyUsage() async {
        guard let key = try? keychain.readKey(), !key.isEmpty else { return }
        do {
            let result = try await OpenRouterClient().testKey(apiKey: key)
            guard result.ok else { return }
            apply(result, key: key)
        } catch {
            // Informational only: keep the last known spend on failure.
        }
    }

    private func apply(_ result: KeyTestResult, key: String) {
        keyState = KeyState(
            hasKey: result.ok,
            maskedSuffix: result.ok ? String(key.suffix(4)) : nil,
            message: result.message,
            usageUSD: result.usageUSD,
            limitUSD: result.limitUSD,
            remainingUSD: result.remainingUSD
        )
    }

    private func refreshPreview() {
        guard let endpoint else { previewText = ""; return }
        do {
            let built = try builder.build(
                endpoint: endpoint,
                draft: draft,
                explicitProvider: true,
                streamEnabled: settings.streamingEnabled
            )
            previewText = try JSONPreview.render(Redaction.redact(built.body))
            notSent = built.notSent
        } catch {
            previewText = "{}"
            notSent = draft.setPaths
        }
    }

    private var definitionsCache: [String: JSONValue] = [:]

    private func definitions() -> [String: JSONValue] {
        definitionsCache
    }

    public func loadDefinitions() async {
        if let store {
            definitionsCache = await store.definitions()
        }
    }

    // MARK: - Keys

    public func refreshKeyState() {
        do {
            keyState = KeyState.resolve(key: try keychain.readKey())
        } catch let error as KeychainError {
            keyState = KeyState.resolve(error: error)
        } catch {
            keyState = KeyState(hasKey: false, readOnly: true, message: "\(error)")
        }
    }

    public func saveKey() async {
        do {
            try keychain.saveKey(keyInput)
            keyInput = ""
            refreshKeyState()
        } catch let error as KeychainError {
            errorMessage = error.description
            errorDetail = nil
        } catch {
            errorMessage = "\(error)"
            errorDetail = nil
        }
    }

    public func deleteKey() {
        do {
            try keychain.deleteKey()
            refreshKeyState()
        } catch let error as KeychainError {
            errorMessage = error.description
            errorDetail = nil
        } catch {
            errorMessage = "\(error)"
            errorDetail = nil
        }
    }

    public func saveSettings() {
        settingsStore.save(settings)
        recompute()
    }

    // MARK: - Generation

    public var canGenerate: Bool {
        runState.canRun && keyState.hasKey && endpoint != nil && !isGenerating
    }

    public func generate() async {
        guard let endpoint else { return }
        guard let key = try? keychain.readKey() else {
            errorMessage = "Tilføj en OpenRouter-nøgle i Indstillinger."
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        do {
            let built = try builder.build(
                endpoint: endpoint,
                draft: draft,
                explicitProvider: true,
                streamEnabled: settings.streamingEnabled
            )
            routingWarnings = built.warnings.map(\.message)
            let useStream = settings.streamingEnabled && endpoint.supportsStreaming
            var job = GenerationJob(modelId: endpoint.modelId, endpointId: endpoint.id, requestBody: built.body)
            var finished = await coordinator.submit(job: job, apiKey: key, stream: useStream)

            // A provider may accept the streaming request but never send a completed
            // image. Fall back to a plain request so the user still gets a picture.
            if useStream, finished.error?.kind == .decoding, finished.results.isEmpty {
                job = GenerationJob(modelId: endpoint.modelId, endpointId: endpoint.id, requestBody: built.body)
                finished = await coordinator.submit(job: job, apiKey: key, stream: false)
            }

            lastJob = finished
            if let error = finished.error {
                errorMessage = error.message
                errorDetail = error
                return
            }
            if let library {
                for result in finished.results {
                    _ = try await library.save(
                        job: finished,
                        result: result,
                        endpoint: endpoint,
                        parameters: draft.displayDictionary(),
                        prompt: prompt
                    )
                }
                libraryItems = await library.items()
            }
        } catch {
            errorMessage = "\(error)"
            errorDetail = JobError(kind: .unknown, message: "\(error)", detail: nil)
        }
    }

    public func searchLibrary() async {
        guard let library else { return }
        libraryItems = libraryQuery.isEmpty
            ? await library.items()
            : await library.search(libraryQuery)
    }

    public func rebuildLibrary() async {
        guard let library else { return }
        do {
            _ = try await library.rebuild()
            libraryItems = await library.items()
        } catch {
            errorMessage = "Indekset kunne ikke genopbygges: \(error)"
            errorDetail = JobError(kind: .unknown, message: "Indekset kunne ikke genopbygges.", detail: "\(error)")
        }
    }

    public func copyPreview() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(previewText, forType: .string)
    }

    public func resetDraft() {
        draft = ParameterDraft()
        recompute()
    }

    // MARK: - Full-size preview and error details

    public var lastError: JobError? { lastJob?.error }

    public var hasError: Bool { lastJob?.error != nil }

    /// Opens a freshly generated result in the full-size viewer.
    public func previewResult(_ result: GenerationResult, job: GenerationJob) {
        guard let image = NSImage(data: result.data) else {
            errorMessage = "Billedet kunne ikke vises."
            errorDetail = nil
            return
        }
        let info = ImageIOProbe.probe(data: result.data)
        previewImage = PreviewImage(
            title: "\(job.modelId) · \(result.index + 1)",
            image: image,
            data: result.data,
            modelId: job.modelId,
            prompt: prompt,
            cost: job.costUSD,
            createdAt: ISO8601DateFormatter().string(from: job.createdAt),
            pixelWidth: info?.width ?? result.width ?? Int(image.size.width),
            pixelHeight: info?.height ?? result.height ?? Int(image.size.height),
            mediaType: result.mediaType,
            fileSize: result.data.count
        )
    }

    // MARK: - Hero preview

    /// The image the canvas shows first: the last generation, or the newest
    /// library item when nothing has been generated in this session.
    public var heroImage: NSImage? {
        if let result = lastJob?.results.first, let image = NSImage(data: result.data) {
            return image
        }
        guard !libraryRootPath.isEmpty, let first = libraryItems.first else { return nil }
        let url = URL(fileURLWithPath: libraryRootPath).appendingPathComponent(first.filePath)
        return NSImage(contentsOf: url)
    }

    /// A full preview for the hero image, without opening it.
    public var heroPreviewImage: PreviewImage? {
        if let job = lastJob, let result = job.results.first, let image = NSImage(data: result.data) {
            let info = ImageIOProbe.probe(data: result.data)
            return PreviewImage(
                title: "\(job.modelId) · \(result.index + 1)",
                image: image,
                data: result.data,
                modelId: job.modelId,
                prompt: prompt,
                cost: job.costUSD,
                createdAt: ISO8601DateFormatter().string(from: job.createdAt),
                pixelWidth: info?.width ?? result.width ?? Int(image.size.width),
                pixelHeight: info?.height ?? result.height ?? Int(image.size.height),
                mediaType: result.mediaType,
                fileSize: result.data.count
            )
        }
        if let first = libraryItems.first { return makePreviewImage(first) }
        return nil
    }

    public var heroTitle: String {
        if let job = lastJob { return displayName(forModel: job.modelId) }
        if let first = libraryItems.first {
            return first.modelId.map(displayName(forModel:)) ?? "Bibliotek"
        }
        return "Intet billede endnu"
    }

    public var heroPixelSize: (Int, Int)? {
        if let job = lastJob, let result = job.results.first {
            let info = ImageIOProbe.probe(data: result.data)
            let width = info?.width ?? result.width ?? 0
            let height = info?.height ?? result.height ?? 0
            return width > 0 && height > 0 ? (width, height) : nil
        }
        if let first = libraryItems.first {
            let width = first.width ?? 0
            let height = first.height ?? 0
            return width > 0 && height > 0 ? (width, height) : nil
        }
        return nil
    }

    public func previewHero() {
        if let heroPreviewImage { previewImage = heroPreviewImage }
    }

    public func heroInFinder() {
        if let heroPreviewImage { showInFinder(heroPreviewImage) }
    }

    /// Builds a preview for a library item without opening it.
    public func makePreviewImage(_ item: LibraryKit.LibraryItem) -> PreviewImage? {
        guard !libraryRootPath.isEmpty else { return nil }
        let url = URL(fileURLWithPath: libraryRootPath).appendingPathComponent(item.filePath)
        guard let image = NSImage(contentsOf: url) else { return nil }
        return PreviewImage(
            title: item.promptText ?? item.filePath,
            image: image,
            url: url,
            modelId: item.modelId,
            prompt: item.promptText,
            cost: item.costUSD,
            createdAt: item.createdAt,
            pixelWidth: item.width ?? Int(image.size.width),
            pixelHeight: item.height ?? Int(image.size.height),
            mediaType: nil
        )
    }

    /// Opens a library item in the full-size viewer.
    public func previewLibraryItem(_ item: LibraryKit.LibraryItem) {
        guard let preview = makePreviewImage(item) else {
            errorMessage = "Billedet kunne ikke åbnes: \(item.filePath)"
            errorDetail = nil
            return
        }
        previewImage = preview
    }

    public func dismissPreview() {
        previewImage = nil
    }

    /// Hands the image to the system Preview app. A generated result is written
    /// to a temporary file first; a library item is opened in place. Only
    /// raster formats are ever opened; SVG and unknown extensions are refused.
    private static let openableImageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "gif"]

    public func openInPreview(_ preview: PreviewImage) {
        if let url = preview.url {
            guard Self.openableImageExtensions.contains(url.pathExtension.lowercased()) else {
                errorMessage = "Filen kan ikke åbnes, fordi den ikke er et understøttet billedformat."
                errorDetail = nil
                return
            }
            NSWorkspace.shared.open(url)
            return
        }
        guard let data = preview.data else { return }
        let ext = preview.mediaType.map { LibraryPaths.fileExtension(for: $0) } ?? "png"
        guard Self.openableImageExtensions.contains(ext.lowercased()) else {
            errorMessage = "Billedet kan ikke åbnes, fordi formatet ikke er understøttet."
            errorDetail = nil
            return
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("netsi-image-\(preview.id.uuidString).\(ext)")
        do {
            try data.write(to: temp, options: .atomic)
            NSWorkspace.shared.open(temp)
        } catch {
            errorMessage = "Billedet kunne ikke åbnes: \(error)"
            errorDetail = JobError(kind: .unknown, message: "Billedet kunne ikke åbnes.", detail: "\(error)")
        }
    }

    public func showInFinder(_ preview: PreviewImage) {
        if let url = preview.url {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        guard let data = preview.data else { return }
        let ext = preview.mediaType.map { LibraryPaths.fileExtension(for: $0) } ?? "png"
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("netsi-image-\(preview.id.uuidString).\(ext)")
        do {
            try data.write(to: temp, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([temp])
        } catch {
            errorMessage = "Billedet kunne ikke vises: \(error)"
            errorDetail = JobError(kind: .unknown, message: "Billedet kunne ikke vises.", detail: "\(error)")
        }
    }

    public func copyErrorDetails() {
        guard let error = errorDetail else { return }
        var lines: [String] = ["Fejl: \(error.message)"]
        if let detail = error.detail, !detail.isEmpty {
            lines.append("Detaljer:\n\(detail)")
        }
        if let requestId = error.requestId {
            lines.append("Request ID: \(requestId)")
        }
        if let retry = error.retryAfterSeconds {
            lines.append("Prøv igen om: \(retry) s")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n\n"), forType: .string)
    }

    public func clearError() {
        errorMessage = nil
        errorDetail = nil
        showErrorDetails = false
    }

    public func retryLastError() {
        clearError()
        Task { await generate() }
    }
}
