import SwiftUI

/// Orca-inspired dark developer palette: deep navy-black canvas, low-chroma
/// panels, signal green/blue accents, red reserved for destructive actions.
enum Theme {
    static let background   = Color(hex: 0x0A0C10)
    static let surface      = Color(hex: 0x11141B)
    static let surfaceHover = Color(hex: 0x181C25)
    static let surfaceHigh  = Color(hex: 0x1D222D)
    static let border       = Color(hex: 0x252B38)

    static let textPrimary   = Color(hex: 0xE8ECF4)
    static let textSecondary = Color(hex: 0x8B93A7)
    static let textFaint     = Color(hex: 0x5A6172)

    static let accent  = Color(hex: 0x5AA9FF)   // interactive blue
    static let green   = Color(hex: 0x3FDCA4)   // alive / success
    static let amber   = Color(hex: 0xF5B95C)   // warning / protected
    static let red     = Color(hex: 0xFF5C6C)   // destructive
    static let purple  = Color(hex: 0xA78BFA)   // dev-port chip

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Shared small views

/// Colored status dot (connection state, liveness).
struct StatusDot: View {
    var color: Color
    var size: CGFloat = 7
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.6), radius: 3)
    }
}

/// Small rounded chip, used for dev-port labels and badges.
struct Chip: View {
    var text: String
    var color: Color
    var body: some View {
        Text(text)
            .font(Theme.mono(10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
    }
}

/// Monospaced value with a copy-to-clipboard button (F3.2, F3.3).
struct CopyableValue: View {
    var label: String
    var value: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(Theme.ui(10, weight: .semibold))
                    .foregroundStyle(Theme.textFaint)
                    .textCase(.uppercase)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(nanoseconds: 1_200_000_000); copied = false }
                } label: {
                    Label(copied ? "복사됨" : "복사", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(Theme.ui(10))
                        .foregroundStyle(copied ? Theme.green : Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            Text(value)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
        }
    }
}

/// Flat dark button used across panels.
struct PorterButtonStyle: ButtonStyle {
    var tint: Color = Theme.textPrimary
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(12, weight: .medium))
            .foregroundStyle(prominent ? Color.black : tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                prominent ? tint : (configuration.isPressed ? Theme.surfaceHigh : Theme.surfaceHover),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(prominent ? .clear : Theme.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
