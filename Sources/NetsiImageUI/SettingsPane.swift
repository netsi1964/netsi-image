import SwiftUI

public struct SettingsPane: View {
    @Bindable var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Indstillinger").font(.title3.bold())

            GroupBox("OpenRouter-nøgle") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(model.keyState.hasKey
                             ? "Nøgle gemt (••••\(model.keyState.maskedSuffix ?? ""))"
                             : "Ingen nøgle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if model.keyState.hasKey {
                            Button("Slet nøgle", role: .destructive) { model.deleteKey() }
                        }
                    }
                    HStack {
                        SecureField("sk-or-…", text: $model.keyInput)
                        Button("Gem nøgle") { Task { await model.saveKey() } }
                            .disabled(model.keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    HStack(spacing: 8) {
                        Button("Test nøgle") { Task { await model.testKey() } }
                            .disabled(!model.keyState.hasKey)
                            .font(.caption)
                        Button("Opdater forbrug") { Task { await model.refreshKeyUsage() } }
                            .disabled(!model.keyState.hasKey)
                            .font(.caption)
                    }

                    if let usage = model.keyState.usageUSD {
                        HStack(spacing: 6) {
                            Text("Brugt: \(StudioMoney.string(usage))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let limit = model.keyState.limitUSD {
                                Text("· Grænse: \(StudioMoney.string(limit))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let remaining = model.keyState.remainingUSD {
                                Text("· Tilbage: \(StudioMoney.string(remaining))")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                    }

                    if let message = model.keyState.message {
                        Text(message).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(6)
            }

            GroupBox("Bibliotek") {
                HStack {
                    Text(model.libraryRootPath.isEmpty ? "Ikke valgt" : model.libraryRootPath)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Vælg mappe…") { model.chooseLibraryRoot() }
                }
                .padding(6)
            }

            GroupBox("Generering") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Brug streaming, hvor endpointet understøtter det", isOn: Binding(
                        get: { model.settings.streamingEnabled },
                        set: { model.settings.streamingEnabled = $0; model.saveSettings() }
                    ))
                    Toggle("Skjul inaktive felter", isOn: Binding(
                        get: { model.settings.hideInactive },
                        set: { model.settings.hideInactive = $0; model.saveSettings() }
                    ))
                    Toggle("Vis usikre felter", isOn: Binding(
                        get: { model.settings.showUncertain },
                        set: { model.settings.showUncertain = $0; model.saveSettings() }
                    ))
                }
                .padding(6)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Luk") { model.showSettings = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 460)
    }
}
