import AppKit
import CatalogCore
import Foundation
import GenerationKit
import LibraryKit
import ParameterEngine
import SwiftUI

// MARK: - Tabs

enum StudioTab: String, CaseIterable, Identifiable {
    case canvas
    case library
    case batch
    case history
    case models

    var id: String { rawValue }

    var title: String {
        switch self {
        case .canvas: return "Canvas"
        case .library: return "Bibliotek"
        case .batch: return "Batch Queue"
        case .history: return "History"
        case .models: return "Models"
        }
    }

    var symbol: String {
        switch self {
        case .canvas: return "paintbrush.pointed"
        case .library: return "square.grid.2x2"
        case .batch: return "square.stack.3d.up"
        case .history: return "clock.arrow.circlepath"
        case .models: return "brain"
        }
    }
}

// MARK: - Shell

/// The three-pane studio layout: top bar, model sidebar, canvas, inspector.
struct StudioShell: View {
    @Bindable var model: AppModel
    @State private var tab: StudioTab = .canvas
    @State private var showSidebar = true
    @State private var showInspector = true

    var body: some View {
        VStack(spacing: 0) {
            StudioTopBar(model: model, tab: $tab, showSidebar: $showSidebar, showInspector: $showInspector)

            HStack(spacing: 0) {
                if showSidebar {
                    StudioSidebar(model: model)
                        .frame(width: 264)
                }
                Rectangle().fill(StudioTheme.border).frame(width: 1)
                content
                if showInspector {
                    Rectangle().fill(StudioTheme.border).frame(width: 1)
                    StudioInspector(model: model)
                        .frame(width: 320)
                }
            }
        }
        .background(StudioTheme.canvas)
        .frame(minWidth: 1_180, minHeight: 720)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .canvas:
            StudioCanvas(model: model)
        case .library:
            StudioLibrary(model: model, title: "Bibliotek")
        case .batch:
            StudioBatchQueue(model: model)
        case .history:
            StudioLibrary(model: model, title: "Historik")
        case .models:
            StudioModels(model: model)
        }
    }
}

// MARK: - Top bar

struct StudioTopBar: View {
    @Bindable var model: AppModel
    @Binding var tab: StudioTab
    @Binding var showSidebar: Bool
    @Binding var showInspector: Bool

    var body: some View {
        HStack(spacing: 0) {
            brand
            Spacer(minLength: 12)
            nav
            Spacer(minLength: 12)
            actions
        }
        .frame(height: 48)
        .background(StudioTheme.surfaceLow.opacity(0.96))
        .overlay(alignment: .bottom) {
            Rectangle().fill(StudioTheme.border).frame(height: 1)
        }
    }

    private var brand: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(StudioTheme.primaryGradient)
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                )

            Text("Netsi Image")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StudioTheme.onSurface)

            Text("v\(AppTitle.version)")
                .font(StudioFont.monoSmall)
                .foregroundStyle(StudioTheme.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(StudioTheme.surfaceHigh, in: RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(StudioTheme.borderSubtle, lineWidth: 1)
                )
        }
        .padding(.leading, 82)
    }

    private var nav: some View {
        HStack(spacing: 2) {
            ForEach(StudioTab.allCases) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { tab = item }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 12, weight: .medium))
                        Text(item.title)
                            .font(StudioFont.label)
                    }
                    .foregroundStyle(tab == item ? StudioTheme.primaryFixed : StudioTheme.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        tab == item ? StudioTheme.primary.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(
                                tab == item ? StudioTheme.primary.opacity(0.35) : .clear,
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            StudioIconButton(systemName: "slider.horizontal.3", help: "Vis eller skjul parametre") {
                withAnimation(.easeOut(duration: 0.18)) { showInspector.toggle() }
            }

            StudioIconButton(systemName: "sidebar.leading", help: "Skift sidebar") {
                withAnimation(.easeOut(duration: 0.18)) { showSidebar.toggle() }
            }

            StudioIconButton(systemName: "sidebar.trailing", help: "Skift inspektør") {
                withAnimation(.easeOut(duration: 0.18)) { showInspector.toggle() }
            }

            StudioIconButton(systemName: "gearshape", help: "Indstillinger") {
                model.showSettings = true
            }

            if let usage = model.keyState.usageUSD {
                HStack(spacing: 4) {
                    Image(systemName: "creditcard")
                        .font(.system(size: 10, weight: .medium))
                    Text(StudioMoney.string(usage))
                        .font(StudioFont.monoSmall)
                }
                .foregroundStyle(StudioTheme.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(StudioTheme.surfaceLow, in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(StudioTheme.border, lineWidth: 1)
                )
                .help(spendHelp(usage))
            }

            Rectangle().fill(StudioTheme.border).frame(width: 1, height: 16)

            Button {
                model.showPreview = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "curlybraces").font(.system(size: 11, weight: .medium))
                    Text("JSON").font(StudioFont.labelSmall)
                }
                .foregroundStyle(StudioTheme.onSurfaceVariant)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(StudioTheme.surfaceLow, in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(StudioTheme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("j", modifiers: [.command, .shift])
            .help("JSON ⌘⇧J")

            Button {
                Task { await model.generate() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill").font(.system(size: 11, weight: .semibold))
                    Text("Generér").font(.system(size: 12, weight: .semibold))
                    Text("⌘R").font(StudioFont.monoSmall).opacity(0.75)
                }
            }
            .buttonStyle(StudioPrimaryButtonStyle())
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!model.canGenerate)
            .opacity(model.canGenerate ? 1 : 0.5)
            .help("Generér ⌘R")

            avatar
        }
        .padding(.trailing, 10)
    }

    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(StudioTheme.surfaceHigh)
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(StudioTheme.border, lineWidth: 1))

            Text("NI")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(StudioTheme.primary)

            Circle()
                .fill(StudioTheme.success)
                .frame(width: 7, height: 7)
                .overlay(Circle().stroke(StudioTheme.background, lineWidth: 1))
        }
        .help("Netsi Image")
    }

    private func spendHelp(_ usage: Decimal) -> String {
        var text = "Brugt på OpenRouter: \(StudioMoney.string(usage))"
        if let remaining = model.keyState.remainingUSD {
            text += " · Tilbage: \(StudioMoney.string(remaining))"
        }
        if let limit = model.keyState.limitUSD {
            text += " · Grænse: \(StudioMoney.string(limit))"
        }
        return text
    }
}

// MARK: - Sidebar

struct StudioSidebar: View {
    @Bindable var model: AppModel
    @State private var expandedFamilies: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            search
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.families) { family in
                        familyRow(family)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            footer
        }
        .background(StudioTheme.surfaceLow)
        .onAppear { expandActive() }
        .onChange(of: model.selectedModelId) { _, _ in expandActive() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Modeller")
                    .font(StudioFont.headlineSmall)
                    .foregroundStyle(StudioTheme.onSurface)
                Text("\(model.summary?.modelCount ?? 0) modeller · \(model.summary?.providerRouteCount ?? 0) providers")
                    .font(StudioFont.bodySmall)
                    .foregroundStyle(StudioTheme.secondary)
            }
            Spacer()
            Button {
                Task { await model.refreshCatalog() }
            } label: {
                Text(model.isRefreshing ? "Opdaterer…" : "Opdater")
                    .font(StudioFont.labelSmall)
                    .foregroundStyle(StudioTheme.primaryFixed)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(StudioTheme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(StudioTheme.primary.opacity(0.25), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshing)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var search: some View {
        StudioSearchField(
            placeholder: "Søg modeller...",
            text: Binding(
                get: { model.filter.text },
                set: { model.filter.text = $0 }
            ),
            shortcut: "⌘K"
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func familyRow(_ family: ModelFamily) -> some View {
        let isActive = family.rows.contains(where: { $0.id == model.selectedModelId })
        let expanded = expandedFamilies.contains(family.id)

        return VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if expanded {
                        expandedFamilies.remove(family.id)
                    } else {
                        expandedFamilies.insert(family.id)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(StudioTheme.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))

                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(isActive ? StudioTheme.primary : StudioTheme.secondary)

                    Text(family.displayName)
                        .font(StudioFont.label)
                        .foregroundStyle(isActive ? StudioTheme.onSurface : StudioTheme.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    StudioPill(text: "\(family.rows.count)")

                    if let price = family.cheapestPerToken {
                        Text(price)
                            .font(StudioFont.monoSmall)
                            .foregroundStyle(StudioTheme.secondary.opacity(0.8))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(
                    isActive ? StudioTheme.surface.opacity(0.5) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 2) {
                    ForEach(family.rows) { row in
                        modelRow(row)
                    }
                }
                .padding(.leading, 14)
            }
        }
    }

    private func modelRow(_ row: ModelRow) -> some View {
        let selected = row.id == model.selectedModelId

        return Button {
            model.chooseModel(row.id)
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(selected ? StudioTheme.onSurface : StudioTheme.secondary)
                        .lineLimit(1)
                    Text(row.surfaces.map(\.title).joined(separator: " · "))
                        .font(.system(size: 9))
                        .foregroundStyle(StudioTheme.secondary.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let price = row.pricePerToken {
                    Text(price)
                        .font(StudioFont.monoSmall)
                        .foregroundStyle(StudioTheme.secondary.opacity(0.8))
                }
                if selected {
                    Circle()
                        .fill(StudioTheme.flame)
                        .frame(width: 5, height: 5)
                        .shadow(color: StudioTheme.flame, radius: 3)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                selected ? StudioTheme.surfaceHigh : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(selected ? StudioTheme.primary.opacity(0.35) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Prompt")
                        .font(StudioFont.labelSmall)
                        .foregroundStyle(StudioTheme.onSurfaceVariant)
                    Spacer()
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11))
                        .foregroundStyle(StudioTheme.secondary)
                }
                Text(model.prompt.isEmpty ? "Ingen prompt endnu" : model.prompt)
                    .font(StudioFont.bodySmall)
                    .italic()
                    .foregroundStyle(StudioTheme.secondary)
                    .lineLimit(3)
            }
            .padding(8)
            .background(StudioTheme.surfaceLowest, in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(StudioTheme.border, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    StudioStatusDot(color: model.keyState.hasKey ? StudioTheme.success : StudioTheme.error)
                    Text("OpenRouter")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(StudioTheme.secondary)
                    Spacer()
                    Text(model.keyState.hasKey ? "Nøgle OK" : "Ingen nøgle")
                        .font(StudioFont.monoSmall)
                        .foregroundStyle(model.keyState.hasKey ? StudioTheme.success : StudioTheme.error)
                }

                if let usage = model.keyState.usageUSD {
                    HStack(spacing: 4) {
                        Text("Brugt")
                            .font(.system(size: 10))
                            .foregroundStyle(StudioTheme.secondary)
                        Spacer()
                        Text(StudioMoney.string(usage))
                            .font(StudioFont.monoSmall)
                            .foregroundStyle(StudioTheme.onSurface)
                    }
                }

                if let remaining = model.keyState.remainingUSD {
                    HStack(spacing: 4) {
                        Text("Tilbage")
                            .font(.system(size: 10))
                            .foregroundStyle(StudioTheme.secondary)
                        Spacer()
                        Text(StudioMoney.string(remaining))
                            .font(StudioFont.monoSmall)
                            .foregroundStyle(StudioTheme.success)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(StudioTheme.borderSubtle, lineWidth: 1)
            )

            Button {
                model.showSettings = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape").font(.system(size: 12))
                    Text("Indstillinger...").font(StudioFont.label)
                    Spacer()
                }
                .foregroundStyle(StudioTheme.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .overlay(alignment: .top) {
            Rectangle().fill(StudioTheme.border).frame(height: 1)
        }
    }

    private func expandActive() {
        guard let id = model.selectedModelId,
              let family = model.families.first(where: { $0.rows.contains(where: { $0.id == id }) })
        else { return }
        expandedFamilies.insert(family.id)
    }
}

// MARK: - Canvas

struct StudioCanvas: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PromptBar(model: model)

            ScrollView {
                VStack(spacing: 12) {
                    HeroPreview(model: model)
                    LibrarySection(model: model)
                }
                .padding(12)
            }
            .scrollIndicators(.hidden)

            CanvasStatusBar(model: model)
        }
        .background(StudioTheme.canvas)
    }
}

struct PromptBar: View {
    @Bindable var model: AppModel

    private let modifiers = ["Gyldent lys", "8K Cinema", "Cinematisk", "Fotorealistisk"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(StudioTheme.flame)
                    .padding(.top, 2)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $model.prompt)
                        .font(StudioFont.body)
                        .scrollContentBackground(.hidden)
                        .background(.clear)
                        .frame(minHeight: 56)

                    if model.prompt.isEmpty {
                        Text("Beskriv dit drømmebillede med lyssætning, stil, komposition...")
                            .font(StudioFont.body)
                            .foregroundStyle(StudioTheme.secondary.opacity(0.5))
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
            }

            HStack(spacing: 6) {
                ForEach(modifiers, id: \.self) { modifier in
                    StudioChip(text: "+ \(modifier)") {
                        append(modifier)
                    }
                }

                Spacer(minLength: 4)

                Text("\(model.prompt.count) / 1000")
                    .font(StudioFont.monoSmall)
                    .foregroundStyle(StudioTheme.secondary)

                Button {
                    Task { await model.generate() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").font(.system(size: 11, weight: .semibold))
                        Text("Generér").font(.system(size: 12, weight: .semibold))
                        Text("⌘R").font(StudioFont.monoSmall).opacity(0.75)
                    }
                }
                .buttonStyle(StudioPrimaryButtonStyle())
                .disabled(!model.canGenerate)
                .opacity(model.canGenerate ? 1 : 0.5)
            }
        }
        .padding(12)
        .background(StudioTheme.surfaceLow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
        .padding(12)
    }

    private func append(_ modifier: String) {
        if model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.prompt = modifier
        } else {
            model.prompt += ", \(modifier)"
        }
    }
}

struct HeroPreview: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            stage
            if !model.libraryItems.isEmpty { rail }
            caption
        }
        .background(StudioTheme.surfaceLow)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private var stage: some View {
        ZStack {
            StudioTheme.surfaceLowest

            if let image = model.heroImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 420)
            } else if let error = model.lastJob?.error {
                errorState(error)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .overlay(alignment: .top) { hud }
    }

    private var hud: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                StudioStatusDot(color: StudioTheme.success)
                Text(model.heroTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(StudioTheme.onSurface)
                if let size = model.heroPixelSize {
                    Text("·").foregroundStyle(StudioTheme.secondary)
                    Text("\(size.0) × \(size.1) px")
                        .font(StudioFont.monoSmall)
                        .foregroundStyle(StudioTheme.secondary)
                }
                if let steps = stepsValue {
                    Text("·").foregroundStyle(StudioTheme.secondary)
                    Text("Step \(steps)")
                        .font(StudioFont.monoSmall)
                        .foregroundStyle(StudioTheme.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(StudioTheme.canvas.opacity(0.8), in: Capsule())
            .overlay(Capsule().stroke(StudioTheme.border, lineWidth: 1))

            Spacer()

            HStack(spacing: 2) {
                StudioIconButton(systemName: "plus.magnifyingglass", help: "Vis i fuld størrelse") {
                    model.previewHero()
                }
                StudioIconButton(systemName: "rectangle.on.rectangle", help: "Åbn i Preview") {
                    if let preview = model.heroPreviewImage { model.openInPreview(preview) }
                }
                StudioIconButton(systemName: "arrow.down.to.line", help: "Vis i Finder") {
                    model.heroInFinder()
                }
            }
            .padding(3)
            .background(StudioTheme.canvas.opacity(0.8), in: Capsule())
            .overlay(Capsule().stroke(StudioTheme.border, lineWidth: 1))
        }
        .padding(12)
    }

    /// The sampling steps of the current draft, when the model exposes the field.
    private var stepsValue: Int? {
        guard let field = model.plan.allFields.first(where: { $0.spec.key == "steps" }) else { return nil }
        return model.draft[field.spec.path].json?.intValue
    }

    /// A rail of the newest generations, so the canvas carries the library with it.
    private var rail: some View {
        HStack(spacing: 6) {
            ForEach(model.libraryItems.prefix(7)) { item in
                Button {
                    model.previewLibraryItem(item)
                } label: {
                    Group {
                        if let image = thumbnail(for: item) {
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFill()
                        } else {
                            Rectangle().fill(StudioTheme.surface)
                        }
                    }
                    .frame(width: 54, height: 34)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(StudioTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help(item.promptText ?? item.filePath)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(StudioTheme.surfaceLowest.opacity(0.55))
        .overlay(alignment: .top) {
            Rectangle().fill(StudioTheme.border).frame(height: 1)
        }
    }

    private func thumbnail(for item: LibraryKit.LibraryItem) -> NSImage? {
        guard !model.libraryRootPath.isEmpty else { return nil }
        let url = URL(fileURLWithPath: model.libraryRootPath).appendingPathComponent(item.filePath)
        return NSImage(contentsOf: url)
    }

    private var caption: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("AKTIV VISNING")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.flame)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(StudioTheme.flame.opacity(0.18), in: Capsule())
                    .overlay(Capsule().stroke(StudioTheme.flame.opacity(0.4), lineWidth: 1))

                Text(model.heroTitle)
                    .font(StudioFont.headlineSmall)
                    .foregroundStyle(StudioTheme.onSurface)
                    .lineLimit(1)

                Text("Prompt: \(model.prompt)")
                    .font(StudioFont.bodySmall)
                    .foregroundStyle(StudioTheme.secondary.opacity(0.8))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button {
                    model.previewHero()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .medium))
                        Text("Vis").font(StudioFont.labelSmall)
                    }
                }
                .buttonStyle(StudioSecondaryButtonStyle(compact: true))
                .disabled(model.heroImage == nil)

                Button {
                    model.heroInFinder()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder").font(.system(size: 10, weight: .medium))
                        Text("Finder").font(StudioFont.labelSmall)
                    }
                }
                .buttonStyle(StudioSecondaryButtonStyle(compact: true))
                .disabled(model.heroImage == nil)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(StudioTheme.border).frame(height: 1)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(StudioTheme.secondary.opacity(0.35))
            Text("Intet billede endnu")
                .font(StudioFont.headline)
                .foregroundStyle(StudioTheme.secondary)
            Text("Vælg en model, justér parametre og tryk ⌘R")
                .font(StudioFont.bodySmall)
                .foregroundStyle(StudioTheme.secondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 340)
        .background(StudioTheme.surfaceLowest)
    }

    private func errorState(_ error: JobError) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(StudioTheme.error)
            Text(error.message)
                .font(StudioFont.headline)
                .foregroundStyle(StudioTheme.onSurface)
                .multilineTextAlignment(.center)
            Button("Se detaljer") { model.showErrorDetails = true }
                .buttonStyle(StudioSecondaryButtonStyle(compact: true))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 340)
        .background(StudioTheme.surfaceLowest)
    }
}

struct LibrarySection: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Bibliotek")
                    .font(StudioFont.headlineSmall)
                    .foregroundStyle(StudioTheme.onSurface)
                StudioPill(text: "\(model.libraryItems.count) generationer")

                Spacer()

                StudioSearchField(
                    placeholder: "Søg i bibliotek...",
                    text: Binding(
                        get: { model.libraryQuery },
                        set: {
                            model.libraryQuery = $0
                            Task { await model.searchLibrary() }
                        }
                    )
                )
                .frame(width: 220)

                Button {
                    Task { await model.rebuildLibrary() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
                        Text("Genopbyg indeks").font(StudioFont.labelSmall)
                    }
                }
                .buttonStyle(StudioSecondaryButtonStyle(compact: true))
            }

            LibraryGrid(model: model)
        }
        .padding(12)
        .background(StudioTheme.surfaceLow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }
}

struct LibraryGrid: View {
    let model: AppModel
    var columns: [GridItem] = [GridItem(.adaptive(minimum: 130), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(model.libraryItems) { item in
                LibraryTile(item: item, model: model)
            }
        }
    }
}

struct LibraryTile: View {
    let item: LibraryKit.LibraryItem
    let model: AppModel
    @State private var hovering = false

    var body: some View {
        Button {
            model.previewLibraryItem(item)
        } label: {
            ZStack(alignment: .bottomLeading) {
                if let image = loadImage() {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: 160, height: 160)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(StudioTheme.surface)
                        .frame(width: 160, height: 160)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundStyle(StudioTheme.secondary)
                        )
                }

                if hovering {
                    LinearGradient(
                        colors: [.black.opacity(0.85), .clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .frame(height: 70)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.promptText ?? "Uden prompt")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(item.modelId ?? "—")
                            .font(StudioFont.monoSmall)
                            .foregroundStyle(StudioTheme.primaryFixed)
                            .lineLimit(1)
                    }
                    .padding(6)
                }
            }
            .frame(width: 160, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        hovering ? StudioTheme.primary.opacity(0.5) : StudioTheme.border,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Vis i fuld størrelse") { model.previewLibraryItem(item) }
            Button("Åbn i Preview") {
                if let preview = model.makePreviewImage(item) {
                    model.openInPreview(preview)
                }
            }
            Button("Vis i Finder") {
                if let preview = model.makePreviewImage(item) {
                    model.showInFinder(preview)
                }
            }
        }
    }

    private func loadImage() -> NSImage? {
        guard !model.libraryRootPath.isEmpty else { return nil }
        let url = URL(fileURLWithPath: model.libraryRootPath).appendingPathComponent(item.filePath)
        return NSImage(contentsOf: url)
    }
}

struct CanvasStatusBar: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            StudioStatusDot(color: model.canGenerate ? StudioTheme.success : StudioTheme.error)
            Text(model.canGenerate ? "Klar til generering" : "Mangler oplysninger")
                .font(.system(size: 11))
                .foregroundStyle(model.canGenerate ? StudioTheme.success : StudioTheme.error)

            Text("·").foregroundStyle(StudioTheme.secondary)
            Text("Valgt: ")
                .font(.system(size: 11))
                .foregroundStyle(StudioTheme.secondary)
            Text(model.selectedRow?.name ?? model.endpoint?.modelId ?? "—")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(StudioTheme.onSurface)

            Spacer()

            if model.isGenerating {
                ProgressView().controlSize(.small)
                Text("Genererer…")
                    .font(.system(size: 11))
                    .foregroundStyle(StudioTheme.generating)
            }

            Text("⌘R Generér")
                .font(StudioFont.monoSmall)
                .foregroundStyle(StudioTheme.secondary.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(StudioTheme.surfaceLowest)
        .overlay(alignment: .top) {
            Rectangle().fill(StudioTheme.border).frame(height: 1)
        }
    }
}

// MARK: - Library & models tabs

struct StudioLibrary: View {
    let model: AppModel
    var title: String = "Bibliotek"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(StudioFont.headlineLarge)
                    .foregroundStyle(StudioTheme.onSurface)
                StudioPill(text: "\(model.libraryItems.count) generationer")

                Spacer()

                StudioSearchField(
                    placeholder: "Søg i bibliotek...",
                    text: Binding(
                        get: { model.libraryQuery },
                        set: {
                            model.libraryQuery = $0
                            Task { await model.searchLibrary() }
                        }
                    )
                )
                .frame(width: 260)

                Button {
                    Task { await model.rebuildLibrary() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
                        Text("Genopbyg indeks").font(StudioFont.labelSmall)
                    }
                }
                .buttonStyle(StudioSecondaryButtonStyle(compact: true))
            }
            .padding(12)
            .overlay(alignment: .bottom) {
                Rectangle().fill(StudioTheme.border).frame(height: 1)
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(model.libraryItems) { item in
                        LibraryTile(item: item, model: model)
                    }
                }
                .padding(12)
            }
            .scrollIndicators(.hidden)
        }
        .background(StudioTheme.canvas)
    }
}

struct StudioModels: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(model.filteredRows) { row in
                    modelCard(row)
                }
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
        .background(StudioTheme.canvas)
    }

    private func modelCard(_ row: ModelRow) -> some View {
        let selected = row.id == model.selectedModelId

        return Button {
            model.chooseModel(row.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(row.name)
                        .font(StudioFont.label)
                        .foregroundStyle(StudioTheme.onSurface)
                        .lineLimit(1)
                    Spacer()
                    if selected {
                        StudioStatusDot(color: StudioTheme.flame)
                    }
                }
                Text(row.publisher)
                    .font(StudioFont.bodySmall)
                    .foregroundStyle(StudioTheme.secondary)
                HStack(spacing: 6) {
                    Text(row.surfaces.map(\.title).joined(separator: " · "))
                        .font(StudioFont.monoSmall)
                        .foregroundStyle(StudioTheme.secondary.opacity(0.7))
                    Spacer()
                    if let price = row.pricePerToken {
                        Text(price)
                            .font(StudioFont.monoSmall)
                            .foregroundStyle(StudioTheme.secondary)
                    }
                }
                if row.availability != .generatable {
                    Text(row.availability.title)
                        .font(StudioFont.monoSmall)
                        .foregroundStyle(StudioTheme.flame)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StudioTheme.surfaceLow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? StudioTheme.primary.opacity(0.5) : StudioTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Batch queue

struct StudioBatchQueue: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Batch Queue")
                    .font(StudioFont.headlineLarge)
                    .foregroundStyle(StudioTheme.onSurface)
                StudioPill(text: "\(queueCount) job")
                Spacer()
                if model.isGenerating {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small)
                        Text("Kører…")
                            .font(StudioFont.labelSmall)
                            .foregroundStyle(StudioTheme.generating)
                    }
                }
            }
            .padding(16)
            .overlay(alignment: .bottom) {
                Rectangle().fill(StudioTheme.border).frame(height: 1)
            }

            if let job = model.lastJob {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        jobRow(job)
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(StudioTheme.secondary.opacity(0.35))
                    Text("Ingen job i køen")
                        .font(StudioFont.headline)
                        .foregroundStyle(StudioTheme.secondary)
                    Text("Generér et billede, så vises jobbet her.")
                        .font(StudioFont.bodySmall)
                        .foregroundStyle(StudioTheme.secondary.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(StudioTheme.canvas)
    }

    private var queueCount: Int {
        model.lastJob == nil ? 0 : 1
    }

    private func jobRow(_ job: GenerationJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    StudioStatusDot(color: job.error == nil ? StudioTheme.success : StudioTheme.error)
                    Text(job.modelId)
                        .font(StudioFont.label)
                        .foregroundStyle(StudioTheme.onSurface)
                }
                Spacer()
                if let cost = job.costUSD {
                    Text("$" + String(describing: cost))
                        .font(StudioFont.monoSmall)
                        .foregroundStyle(StudioTheme.secondary)
                }
                if let latency = job.latencyMilliseconds {
                    Text("\(latency) ms")
                        .font(StudioFont.monoSmall)
                        .foregroundStyle(StudioTheme.secondary)
                }
            }

            Text(job.requestBody["prompt"]?.stringValue ?? "—")
                .font(StudioFont.bodySmall)
                .foregroundStyle(StudioTheme.secondary)
                .lineLimit(2)

            HStack(spacing: 6) {
                StudioPill(text: "\(job.results.count) resultat")
                StudioPill(text: job.endpointId)
                if let error = job.error {
                    StudioPill(text: error.kind.rawValue, color: StudioTheme.error)
                }
            }
        }
        .padding(12)
        .background(StudioTheme.surfaceLow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }
}

// MARK: - Inspector

struct StudioInspector: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(visibleSections) { section in
                            sectionView(section)
                        }
                    }
                    .padding(12)
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.focusedPath) { _, newValue in
                    guard let newValue else { return }
                    withAnimation { proxy.scrollTo(newValue, anchor: .center) }
                }
            }

            footer
        }
        .background(StudioTheme.surfaceLow)
        .onAppear {
            if model.plan.allFields.isEmpty { model.recompute() }
            expanded = Set(model.plan.sections.map(\.id))
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Parametre")
                .font(StudioFont.headlineSmall)
                .foregroundStyle(StudioTheme.onSurface)
            StudioPill(text: "\(model.plan.allFields.count) felter")
            Spacer()
            Button("Nulstil") { model.resetDraft() }
                .buttonStyle(.plain)
                .font(StudioFont.labelSmall)
                .foregroundStyle(StudioTheme.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(StudioTheme.border).frame(height: 1)
        }
    }

    private var searchField: some View {
        StudioSearchField(placeholder: "Søg i felter...", text: $search)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    private func sectionView(_ section: PlannedSection) -> some View {
        let isExpanded = expanded.contains(section.id) || !search.isEmpty

        return VStack(alignment: .leading, spacing: 6) {
            StudioSectionHeader(
                title: section.title,
                subtitle: "\(section.fields.count) felter",
                isExpanded: isExpanded
            ) {
                withAnimation(.easeOut(duration: 0.15)) {
                    if expanded.contains(section.id) {
                        expanded.remove(section.id)
                    } else {
                        expanded.insert(section.id)
                    }
                }
            }

            if isExpanded {
                ForEach(section.fields) { field in
                    ParameterRowView(model: model, field: field)
                        .id(field.spec.path)
                }
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(StudioTheme.border)
                .frame(height: 1)
        }
    }

    private var visibleSections: [PlannedSection] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return model.plan.sections }
        let matching = Set(model.plan.matchingPaths(needle))
        return model.plan.sections.compactMap { section in
            var copy = section
            copy.fields = section.fields.filter { matching.contains($0.spec.path) }
            return copy.fields.isEmpty ? nil : copy
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                StudioStatusDot(color: model.runState.canRun ? StudioTheme.success : StudioTheme.error)
                Text(model.runState.canRun ? "Alle parametre gyldige" : "Mangler oplysninger")
                    .font(StudioFont.labelSmall)
                    .foregroundStyle(model.runState.canRun ? StudioTheme.success : StudioTheme.error)
                Spacer()
                if let latency = model.lastJob?.latencyMilliseconds {
                    Text("\(latency) ms")
                        .font(StudioFont.monoSmall)
                        .foregroundStyle(StudioTheme.secondary)
                }
            }

            HStack(spacing: 6) {
                Button {
                    model.showPreview = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "curlybraces").font(.system(size: 11, weight: .medium))
                        Text("JSON").font(StudioFont.labelSmall)
                    }
                }
                .buttonStyle(StudioSecondaryButtonStyle(compact: true))
                .frame(maxWidth: .infinity)

                Button {
                    Task { await model.generate() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill").font(.system(size: 11, weight: .semibold))
                        Text("Generér").font(StudioFont.labelSmall)
                    }
                }
                .buttonStyle(StudioPrimaryButtonStyle())
                .frame(maxWidth: .infinity)
                .disabled(!model.canGenerate)
                .opacity(model.canGenerate ? 1 : 0.5)
            }
        }
        .padding(12)
        .background(StudioTheme.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(StudioTheme.border).frame(height: 1)
        }
    }
}
