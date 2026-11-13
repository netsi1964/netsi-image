import AppKit
import SwiftUI

// MARK: - Palette

extension Color {
    /// A colour from a 0xRRGGBB literal, matching the design tokens.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// "Sequoia Dark Studio" — the dark-first palette from the design document.
enum StudioTheme {
    static let canvas = Color(hex: 0x0B0F17)
    static let background = Color(hex: 0x0C1322)
    static let surfaceLowest = Color(hex: 0x070E1D)
    static let surfaceLow = Color(hex: 0x141B2B)
    static let surface = Color(hex: 0x191F2F)
    static let surfaceHigh = Color(hex: 0x232A3A)
    static let surfaceHighest = Color(hex: 0x2E3545)

    static let onSurface = Color(hex: 0xDCE2F7)
    static let onSurfaceVariant = Color(hex: 0xE2BFB2)
    static let secondary = Color(hex: 0xCCC5BC)

    static let primary = Color(hex: 0xF66018)
    static let primaryFixed = Color(hex: 0xFFB599)
    static let flame = Color(hex: 0xF97316)
    static let generating = Color(hex: 0x38BDF8)
    static let success = Color(hex: 0x10B981)
    static let error = Color(hex: 0xFFB4AB)

    static let border = Color.white.opacity(0.08)
    static let borderSubtle = Color.white.opacity(0.04)
    static let glass = Color(hex: 0x171F2E).opacity(0.72)
    static let accentGlow = Color(hex: 0xEA580C).opacity(0.35)

    static let primaryGradient = LinearGradient(
        colors: [primary, flame],
        startPoint: .leading,
        endPoint: .trailing
    )
}

/// Typography from the design document, mapped onto the system font (Inter is
/// not bundled; SF Pro is the closest native equivalent).
enum StudioFont {    static let display = Font.system(size: 32, weight: .bold)
    static let headlineLarge = Font.system(size: 22, weight: .semibold)
    static let headline = Font.system(size: 16, weight: .semibold)
    static let headlineSmall = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular)
    static let bodySmall = Font.system(size: 12, weight: .regular)
    static let label = Font.system(size: 12, weight: .medium)
    static let labelSmall = Font.system(size: 11, weight: .medium)
    static let mono = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let monoSmall = Font.system(size: 10, weight: .medium, design: .monospaced)
}

/// Money formatting shared by the spend readouts. POSIX separators so the
/// number matches what OpenRouter shows.
enum StudioMoney {
    static func string(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let number = NSDecimalNumber(decimal: value)
        return "$" + (formatter.string(from: number) ?? number.stringValue)
    }
}

// MARK: - Window chrome

/// Turns the SwiftUI window into a full-size content window with a transparent
/// title bar, so the app can draw its own top bar and keep the traffic lights.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = NSColor(red: 0x0B / 255, green: 0x0F / 255, blue: 0x17 / 255, alpha: 1)
            window.isMovableByWindowBackground = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Components

/// A rounded panel with a hairline border, matching the design's glass cards.
struct StudioPanel<Content: View>: View {
    var radius: CGFloat = 12
    var fill: Color = StudioTheme.surfaceLow
    var stroke: Color = StudioTheme.border
    var padding: CGFloat = 12
    let content: Content

    init(
        radius: CGFloat = 12,
        fill: Color = StudioTheme.surfaceLow,
        stroke: Color = StudioTheme.border,
        padding: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.radius = radius
        self.fill = fill
        self.stroke = stroke
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
    }
}

/// The primary "Generate" button: warm gradient, white text, orange glow.
struct StudioPrimaryButtonStyle: ButtonStyle {
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11 : 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 9 : 14)
            .padding(.vertical, compact ? 4 : 7)
            .background(
                StudioTheme.primaryGradient,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: StudioTheme.primary.opacity(0.35), radius: 6, y: 2)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Frosted secondary button with a hairline border.
struct StudioSecondaryButtonStyle: ButtonStyle {
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11 : 12, weight: .medium))
            .foregroundStyle(StudioTheme.onSurface)
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, compact ? 4 : 6)
            .background(
                configuration.isPressed ? Color.white.opacity(0.12) : Color.white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: 1)
            )
    }
}

/// Frameless 28×28 icon hit area, brightening on hover.
struct StudioIconButton: View {
    let systemName: String
    var help: String = ""
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(hovering ? StudioTheme.onSurface : StudioTheme.secondary)
                .frame(width: 28, height: 28)
                .background(
                    hovering ? StudioTheme.surface : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Compact pill for prompt modifiers, style tokens and segmented controls.
struct StudioChip: View {
    let text: String
    var isActive: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            Text(text)
                .font(StudioFont.labelSmall)
                .foregroundStyle(isActive ? StudioTheme.primaryFixed : StudioTheme.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    isActive ? StudioTheme.primary.opacity(0.15) : StudioTheme.surface,
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(
                        isActive ? StudioTheme.primary.opacity(0.5) : StudioTheme.border,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

/// Small glowing status dot.
struct StudioStatusDot: View {
    var color: Color = StudioTheme.success
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.6), radius: 3)
    }
}

/// Search field with a leading icon and an optional shortcut badge.
struct StudioSearchField: View {
    let placeholder: String
    @Binding var text: String
    var shortcut: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(StudioTheme.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(StudioFont.bodySmall)
                .foregroundStyle(StudioTheme.onSurface)

            if let shortcut {
                Text(shortcut)
                    .font(StudioFont.monoSmall)
                    .foregroundStyle(StudioTheme.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(StudioTheme.borderSubtle, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(StudioTheme.surfaceLowest, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }
}

/// Collapsible section header with a disclosure triangle.
struct StudioSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var isExpanded: Bool = true
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(StudioTheme.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))

                Text(title)
                    .font(StudioFont.headlineSmall)
                    .foregroundStyle(StudioTheme.onSurface)

                Spacer()

                if let subtitle {
                    Text(subtitle)
                        .font(StudioFont.monoSmall)
                        .foregroundStyle(StudioTheme.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Dark control chrome for text inputs, dropdowns and other inspector fields.
struct StudioFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                StudioTheme.surfaceLowest,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: 1)
            )
    }
}

extension View {
    /// Wraps a control in the inspector's dark field chrome.
    func studioFieldChrome() -> some View { modifier(StudioFieldChrome()) }
}

/// Small rounded count badge.
struct StudioPill: View {
    let text: String
    var color: Color = StudioTheme.secondary

    var body: some View {
        Text(text)
            .font(StudioFont.monoSmall)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(StudioTheme.surface, in: Capsule())
            .overlay(Capsule().stroke(StudioTheme.borderSubtle, lineWidth: 1))
    }
}
