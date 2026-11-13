import AppKit
import CatalogCore
import CoreSupport
import GenerationKit
import LibraryKit
import ParameterEngine
import SwiftUI
import UniformTypeIdentifiers

public struct AppShell: View {
    @State private var model = AppModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            if let error = model.loadError {
                ContentUnavailableView(
                    "Kataloget kunne ikke indlæses",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .background(StudioTheme.canvas)
                .foregroundStyle(StudioTheme.onSurface)
            } else {
                StudioShell(model: model)
            }
        }
        .frame(minWidth: 1_180, minHeight: 720)
        .background(StudioTheme.canvas)
        .background(WindowConfigurator())
        .task { await model.load() }
        .sheet(isPresented: Bindable(model).showPreview) {
            JSONPreviewSheet(model: model)
        }
        .sheet(isPresented: Bindable(model).showSettings) {
            SettingsPane(model: model)
        }
        .sheet(item: Binding(
            get: { model.endpointChoices.first },
            set: { if $0 == nil { model.endpointChoices = [] } }
        )) { first in
            ProviderChoiceSheet(model: model, endpoints: model.endpointChoices.isEmpty ? [first] : model.endpointChoices)
        }
        .sheet(item: Bindable(model).previewImage) { preview in
            ImagePreviewSheet(model: model, preview: preview)
        }
        .sheet(isPresented: Bindable(model).showErrorDetails) {
            ErrorDetailSheet(model: model)
        }
        .alert(
            "Felter findes ikke på den nye model",
            isPresented: Binding(
                get: { model.pendingSwitch != nil },
                set: { if !$0 { model.cancelSwitch() } }
            )
        ) {
            Button("Behold kun fælles felter") { model.confirmSwitch() }
            Button("Annullér", role: .cancel) { model.cancelSwitch() }
        } message: {
            Text(model.pendingSwitch?.dropped.map { "\($0.path.description): \($0.reason)" }.joined(separator: "\n") ?? "")
        }
        .alert("Fejl", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            if model.errorDetail != nil {
                Button("Se detaljer") { model.showErrorDetails = true }
            }
            Button("OK", role: .cancel) { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .modifier(WindowTitleModifier())
        .navigationTitle(AppTitle.title)
    }
}

private struct ProviderChoiceSheet: View {
    let model: AppModel
    let endpoints: [Endpoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vælg provider").font(.title3.bold())
            ForEach(endpoints, id: \.id) { endpoint in
                Button {
                    model.choose(endpoint: endpoint)
                } label: {
                    HStack {
                        Text(endpoint.providerName)
                        Spacer()
                        Text("\(endpoint.parameters.count) felter").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

struct ValueTextField: View {
    let model: AppModel
    let field: PlannedField
    @Binding var text: String
    let numeric: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField("Standard (sendes ikke)", text: Binding(
                get: { text },
                set: { newValue in
                    text = newValue
                    if newValue.isEmpty {
                        model.reset(field.spec.path)
                    } else if numeric, let number = Decimal(string: newValue.replacingOccurrences(of: ",", with: ".")) {
                        model.set(.number(number), at: field.spec.path)
                    } else if !numeric {
                        model.set(.string(newValue), at: field.spec.path)
                    }
                }
            ))
            .textFieldStyle(.plain)
            .font(StudioFont.bodySmall)
            .studioFieldChrome()

            if !field.spec.suggestedValues.isEmpty {
                Menu {
                    ForEach(Array(field.spec.suggestedValues.enumerated()), id: \.offset) { _, value in
                        Button(ValueConstraintEvaluator.display(value)) {
                            text = ValueConstraintEvaluator.display(value)
                            model.set(value, at: field.spec.path)
                        }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Forslag fra kataloget")
            }
        }
    }
}

struct ParameterRowView: View {
    let model: AppModel
    let field: PlannedField
    @State private var text: String = ""
    @State private var jsonText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(designLabel(for: field.spec.key))
                    .font(StudioFont.labelSmall)
                    .foregroundStyle(StudioTheme.onSurface)
                    .lineLimit(1)

                if field.spec.required {
                    Text("påkrævet")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(StudioTheme.flame)
                }

                Spacer(minLength: 4)

                if field.isSet {
                    Button {
                        model.reset(field.spec.path)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(StudioTheme.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Nulstil til ikke sat")
                }

                evidenceBadge
            }

            designWidget

            if let issue = model.issues.first(where: { $0.path == field.spec.path }) {
                HStack(spacing: 4) {
                    Text(issue.message)
                        .font(StudioFont.monoSmall)
                        .foregroundStyle(issue.severity == .blocking ? StudioTheme.error : StudioTheme.flame)
                    if let fix = issue.fixSuggestion {
                        Button(fix.label) { model.applyFix(fix) }
                            .buttonStyle(.link)
                            .font(StudioFont.monoSmall)
                    }
                }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 2)
        .padding(.vertical, 3)
        .background(
            model.focusedPath == field.spec.path ? StudioTheme.primary.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay(alignment: .leading) {
            if model.focusedPath == field.spec.path {
                Capsule()
                    .fill(StudioTheme.primary)
                    .frame(width: 2)
                    .padding(.vertical, 3)
            }
        }
        .onAppear { text = stringValue }
    }

    @ViewBuilder
    private var designWidget: some View {
        switch field.spec.key {
        case "aspect_ratio":
            AspectRatioChips(model: model, field: field)
        case "steps":
            ParameterSlider(model: model, field: field, title: "Sampling Steps", min: 10, max: 60, step: 1)
        case "guidance":
            ParameterSlider(model: model, field: field, title: "Guidance (CFG Scale)", min: 1, max: 20, step: 0.5)
        case "seed":
            SeedControl(model: model, field: field)
        case "input_references", "reference_images", "image":
            ReferenceDropzone(model: model, field: field)
        case "allow_fallbacks":
            ParameterToggle(model: model, field: field)
        case "ignore", "only":
            ParameterSelect(model: model, field: field)
        case "n":
            ParameterNumber(model: model, field: field)
        case "output_format":
            ParameterSelect(model: model, field: field)
        default:
            widget
        }
    }

    private func designLabel(for key: String) -> String {
        switch key {
        case "aspect_ratio": return "Billedformat (Aspect)"
        case "steps": return "Sampling Steps"
        case "guidance": return "Guidance (CFG Scale)"
        default: return field.spec.label
        }
    }

    private var evidenceBadge: some View {
        HStack(spacing: 3) {
            if field.spec.bucket == .verified {
                StudioStatusDot(color: StudioTheme.success, size: 4)
            }
            Text(field.spec.bucket.title)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(StudioTheme.secondary.opacity(0.8))
        }
        .help(field.spec.note ?? field.spec.source ?? "")
    }

    @ViewBuilder
    private var widget: some View {
        switch field.widget {
        case .select:
            Picker("", selection: Binding(
                get: { model.value(field.spec.path).json?.stringValue ?? "" },
                set: { newValue in
                    if newValue.isEmpty { model.reset(field.spec.path) }
                    else { model.set(.string(newValue), at: field.spec.path) }
                }
            )) {
                Text("Standard (sendes ikke)").tag("")
                ForEach(ValueConstraintEvaluator.optionValues(for: field.spec), id: \.self) { option in
                    Text(ValueConstraintEvaluator.display(option)).tag(option.stringValue ?? ValueConstraintEvaluator.display(option))
                }
            }
            .labelsHidden()

        case .checkbox:
            Toggle("", isOn: Binding(
                get: { model.value(field.spec.path).json?.boolValue ?? false },
                set: { model.set(.bool($0), at: field.spec.path) }
            ))
            .labelsHidden()

        case .number:
            TextField("Standard (sendes ikke)", text: Binding(
                get: { text },
                set: { newValue in
                    text = newValue
                    if newValue.isEmpty {
                        model.reset(field.spec.path)
                    } else if let number = Decimal(string: newValue.replacingOccurrences(of: ",", with: ".")) {
                        model.set(.number(number), at: field.spec.path)
                    }
                }
            ))
            .textFieldStyle(.plain)
            .font(StudioFont.bodySmall)
            .studioFieldChrome()

        case .sizeInput:
            ValueTextField(model: model, field: field, text: $text, numeric: true)

        case .textarea:
            TextEditor(text: Binding(
                get: { text },
                set: { newValue in
                    text = newValue
                    if newValue.isEmpty { model.reset(field.spec.path) }
                    else { model.set(.string(newValue), at: field.spec.path) }
                }
            ))
            .font(StudioFont.bodySmall)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 60)
            .studioFieldChrome()

        case .multiSelect, .orderedMultiSelect:
            Menu {
                ForEach(selectableOptions, id: \.self) { option in
                    Button {
                        toggle(option)
                    } label: {
                        Text((isSelected(option) ? "✓ " : "   ") + ValueConstraintEvaluator.display(option))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedList.isEmpty ? "Ingen valgt" : selectedList.joined(separator: ", "))
                        .font(StudioFont.bodySmall)
                        .foregroundStyle(selectedList.isEmpty ? StudioTheme.secondary.opacity(0.7) : StudioTheme.onSurface)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(StudioTheme.secondary)
                }
                .studioFieldChrome()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

        case .repeater, .jsonEditor, .unknown:
            jsonEditor

        case .imageList, .imageInput:
            ReferenceDropzone(model: model, field: field)

        case .constant:
            Text(model.value(field.spec.path).json?.stringValue ?? "")
                .font(StudioFont.monoSmall)
                .foregroundStyle(StudioTheme.secondary)

        case .text:
            ValueTextField(model: model, field: field, text: $text, numeric: false)
        }
    }

    private var jsonEditor: some View {
        TextEditor(text: Binding(
            get: { jsonText.isEmpty ? (model.value(field.spec.path).json.flatMap { try? $0.encodedString(pretty: true) } ?? "") : jsonText },
            set: { newValue in
                jsonText = newValue
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    model.reset(field.spec.path)
                } else if let value = try? JSONValue.parse(newValue) {
                    model.set(value, at: field.spec.path)
                }
            }
        ))
        .font(.system(size: 10, weight: .regular, design: .monospaced))
        .scrollContentBackground(.hidden)
        .frame(minHeight: 60)
        .studioFieldChrome()
    }

    private var stringValue: String {
        switch model.value(field.spec.path) {
        case .unset: return ""
        case .value(let json):
            switch json {
            case .string(let text): return text
            case .number(let number): return "\(number)"
            default: return (try? json.encodedString()) ?? ""
            }
        }
    }

    private var selectedList: [String] {
        (model.value(field.spec.path).json?.arrayValue ?? []).compactMap { $0.stringValue ?? ValueConstraintEvaluator.display($0) }
    }

    /// Catalog suggestions (207 entries, all on `order`) plus any declared enum options.
    private var selectableOptions: [JSONValue] {
        var options = ValueConstraintEvaluator.optionValues(for: field.spec)
        for suggestion in field.spec.suggestedValues where !options.contains(suggestion) {
            options.append(suggestion)
        }
        return options
    }

    private func isSelected(_ option: JSONValue) -> Bool {
        (model.value(field.spec.path).json?.arrayValue ?? []).contains(option)
    }

    private func toggle(_ option: JSONValue) {
        var array = model.value(field.spec.path).json?.arrayValue ?? []
        if let index = array.firstIndex(of: option) {
            array.remove(at: index)
        } else {
            array.append(option)
        }
        if array.isEmpty { model.reset(field.spec.path) }
        else { model.set(.array(array), at: field.spec.path) }
    }
}

// MARK: - Design parameter controls

private struct AspectRatioChips: View {
    let model: AppModel
    let field: PlannedField

    var body: some View {
        let options = ValueConstraintEvaluator.optionValues(for: field.spec)
        let selected = model.value(field.spec.path).json?.stringValue
        let preferred = ["1:1", "16:9", "4:5", "9:16"]
        let preferredOptions = preferred.compactMap { value in
            options.first { ($0.stringValue ?? ValueConstraintEvaluator.display($0)) == value }
        }
        let shown = preferredOptions.count == 4 ? preferredOptions : Array(options.prefix(4))

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
            ForEach(shown, id: \.self) { option in
                let value = option.stringValue ?? ValueConstraintEvaluator.display(option)
                Button {
                    if selected == value {
                        model.reset(field.spec.path)
                    } else {
                        model.set(.string(value), at: field.spec.path)
                    }
                } label: {
                    VStack(spacing: 4) {
                        AspectGlyph(ratio: value)
                            .frame(width: 24, height: 24)
                        Text(value)
                            .font(.system(size: 10, weight: selected == value ? .semibold : .regular))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        selected == value ? StudioTheme.flame.opacity(0.15) : StudioTheme.surface,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(
                                selected == value ? StudioTheme.flame : StudioTheme.border,
                                lineWidth: 1
                            )
                    )
                    .foregroundStyle(selected == value ? StudioTheme.primary : StudioTheme.secondary)
                }
                .buttonStyle(.plain)
                .help(value)
            }
        }
    }
}

/// A tiny proportional rectangle that previews an aspect ratio such as "16:9".
private struct AspectGlyph: View {
    let ratio: String

    var body: some View {
        GeometryReader { proxy in
            let parts = ratio.split(separator: ":").compactMap { Double($0) }
            let box = proxy.size
            let width = max(parts.first ?? 1, 0.2)
            let height = max(parts.count > 1 ? parts[1] : 1, 0.2)
            let scale = min(box.width / width, box.height / height)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(.foreground, lineWidth: 1)
                .frame(width: width * scale, height: height * scale)
                .position(x: box.width / 2, y: box.height / 2)
        }
    }
}

private struct ParameterSlider: View {
    let model: AppModel
    let field: PlannedField
    let title: String
    let min: Double
    let max: Double
    let step: Double

    var body: some View {
        let value = model.value(field.spec.path).json?.doubleValue ?? ((min + max) / 2)
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(StudioFont.labelSmall)
                    .foregroundStyle(StudioTheme.onSurface)
                Spacer()
                Text(formatted(value))
                    .font(StudioFont.monoSmall)
                    .foregroundStyle(StudioTheme.primary)
            }
            Slider(
                value: Binding(
                    get: { value },
                    set: { model.set(.number(Decimal($0)), at: field.spec.path) }
                ),
                in: min...max,
                step: step
            )
            .tint(StudioTheme.primary)
            HStack {
                Text("Hurtig (\(Int(min)))")
                    .font(StudioFont.monoSmall)
                    .foregroundStyle(StudioTheme.secondary.opacity(0.6))
                Spacer()
                Text("Optimal (\(Int((min + max) / 2)))")
                    .font(StudioFont.monoSmall)
                    .foregroundStyle(StudioTheme.secondary.opacity(0.6))
                Spacer()
                Text("Maks (\(Int(max)))")
                    .font(StudioFont.monoSmall)
                    .foregroundStyle(StudioTheme.secondary.opacity(0.6))
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

private struct SeedControl: View {
    let model: AppModel
    let field: PlannedField
    @State private var text = ""

    var body: some View {
        HStack(spacing: 4) {
            TextField("Tilfældig", text: $text)
                .textFieldStyle(.plain)
                .font(StudioFont.mono)
                .studioFieldChrome()
                .onChange(of: text) { _, newValue in
                    if newValue.isEmpty {
                        model.reset(field.spec.path)
                    } else if let number = Int(newValue) {
                        model.set(.number(Decimal(number)), at: field.spec.path)
                    }
                }
            Button {
                model.reset(field.spec.path)
                text = ""
            } label: {
                Image(systemName: "lock.open").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(StudioSecondaryButtonStyle(compact: true))
            .help("Nulstil seed")
            Button {
                let seed = Int.random(in: 0...Int.max)
                text = String(seed)
                model.set(.number(Decimal(seed)), at: field.spec.path)
            } label: {
                Image(systemName: "casino").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(StudioSecondaryButtonStyle(compact: true))
            .help("Tilfældigt seed")
        }
        .onAppear { text = stringValue }
    }

    private var stringValue: String {
        if let number = model.value(field.spec.path).json?.intValue { return String(number) }
        return ""
    }
}

private struct ReferenceDropzone: View {
    let model: AppModel
    let field: PlannedField
    @State private var showImporter = false

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: "add.photo")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(StudioTheme.secondary)
                HStack(spacing: 3) {
                    Text("Træk billeder hertil eller")
                        .font(StudioFont.labelSmall)
                        .foregroundStyle(StudioTheme.secondary)
                    Text("Vælg...")
                        .font(StudioFont.labelSmall)
                        .foregroundStyle(StudioTheme.primary)
                        .underline()
                }
                .lineLimit(1)
            }
            if count > 0 {
                HStack(spacing: 6) {
                    Text("\(count) billede(r) valgt")
                        .font(StudioFont.monoSmall)
                        .foregroundStyle(StudioTheme.success)
                    Button("Fjern") { model.reset(field.spec.path) }
                        .buttonStyle(.plain)
                        .font(StudioFont.monoSmall)
                        .foregroundStyle(StudioTheme.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            StudioTheme.surfaceLowest.opacity(0.5),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(StudioTheme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .contentShape(Rectangle())
        .onTapGesture { showImporter = true }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: field.widget == .imageList
        ) { result in
            if case .success(let urls) = result {
                attach(urls)
            }
        }
    }

    private var count: Int {
        if let array = model.value(field.spec.path).json?.arrayValue { return array.count }
        return model.value(field.spec.path).isSet ? 1 : 0
    }

    private func attach(_ urls: [URL]) {
        let parts: [JSONValue] = urls.compactMap { url in
            guard let dataURL = ImageDataURL.make(for: url) else { return nil }
            return .object([
                "type": .string("image_url"),
                "image_url": .object(["url": .string(dataURL)]),
            ])
        }
        guard !parts.isEmpty else { return }
        if field.widget == .imageList {
            model.set(.array(parts), at: field.spec.path)
        } else if let first = parts.first {
            model.set(first, at: field.spec.path)
        }
    }
}

private struct ParameterToggle: View {
    let model: AppModel
    let field: PlannedField

    var body: some View {
        Toggle("", isOn: Binding(
            get: { model.value(field.spec.path).json?.boolValue ?? false },
            set: { model.set(.bool($0), at: field.spec.path) }
        ))
        .labelsHidden()
        .toggleStyle(.switch)
        .tint(StudioTheme.primary)
    }
}

private struct ParameterSelect: View {
    let model: AppModel
    let field: PlannedField

    private var options: [JSONValue] { ValueConstraintEvaluator.optionValues(for: field.spec) }
    private var current: String { model.value(field.spec.path).json?.stringValue ?? "" }

    var body: some View {
        Menu {
            Button("Ingen valgt") { model.reset(field.spec.path) }
            if !options.isEmpty { Divider() }
            ForEach(options, id: \.self) { option in
                Button(ValueConstraintEvaluator.display(option)) {
                    model.set(option, at: field.spec.path)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(current.isEmpty ? "Ingen valgt" : ValueConstraintEvaluator.display(.string(current)))
                    .font(StudioFont.bodySmall)
                    .foregroundStyle(current.isEmpty ? StudioTheme.secondary.opacity(0.7) : StudioTheme.onSurface)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(StudioTheme.secondary)
            }
            .contentShape(Rectangle())
            .studioFieldChrome()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }
}

private struct ParameterNumber: View {
    let model: AppModel
    let field: PlannedField
    @State private var text = ""

    var body: some View {
        TextField("Standard", text: $text)
            .textFieldStyle(.plain)
            .font(StudioFont.mono)
            .studioFieldChrome()
            .onChange(of: text) { _, newValue in
                if newValue.isEmpty {
                    model.reset(field.spec.path)
                } else if let number = Decimal(string: newValue.replacingOccurrences(of: ",", with: ".")) {
                    model.set(.number(number), at: field.spec.path)
                }
            }
            .onAppear { text = stringValue }
    }

    private var stringValue: String {
        if let number = model.value(field.spec.path).json?.intValue { return String(number) }
        return ""
    }
}

// MARK: - Sheets

private struct JSONPreviewSheet: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Request-body").font(.headline)
                Spacer()
                Button("Kopiér") { model.copyPreview() }
                Button("Luk") { model.showPreview = false }
            }
            ScrollView([.horizontal, .vertical]) {
                Text(model.previewText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !model.notSent.isEmpty {
                Divider()
                Text("Sendes ikke (\(model.notSent.count))")
                    .font(.caption.bold())
                Text(model.notSent.map(\.description).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(width: 720, height: 520)
    }
}
