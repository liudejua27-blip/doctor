import SwiftUI

/// Visual tokens for the internal, Chinese-first prototype shell. These
/// tokens do not carry health, safety, or persistence semantics.
enum BodyCompanionTheme {
    static let canvas = Color(red: 0.958, green: 0.973, blue: 0.988)
    static let surface = Color.white.opacity(0.94)
    static let surfaceTinted = Color(red: 0.912, green: 0.953, blue: 0.976)
    static let ink = Color(red: 0.071, green: 0.145, blue: 0.255)
    static let secondaryInk = Color(red: 0.282, green: 0.373, blue: 0.498)
    static let accent = Color(red: 0.086, green: 0.475, blue: 0.922)
    static let accentSoft = Color(red: 0.808, green: 0.921, blue: 0.992)
    static let mint = Color(red: 0.079, green: 0.635, blue: 0.560)
    static let warm = Color(red: 0.947, green: 0.536, blue: 0.248)
    static let line = Color(red: 0.826, green: 0.871, blue: 0.918)
    static let shadow = Color(red: 0.102, green: 0.224, blue: 0.390).opacity(0.09)

    static let cornerRadius: CGFloat = 24
    static let compactCornerRadius: CGFloat = 16
}

struct CompanionCard<Content: View>: View {
    private let emphasized: Bool
    private let content: Content

    init(emphasized: Bool = false, @ViewBuilder content: () -> Content) {
        self.emphasized = emphasized
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(emphasized ? BodyCompanionTheme.surfaceTinted : BodyCompanionTheme.surface, in: RoundedRectangle(cornerRadius: BodyCompanionTheme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BodyCompanionTheme.cornerRadius, style: .continuous)
                    .stroke(emphasized ? BodyCompanionTheme.accent.opacity(0.24) : BodyCompanionTheme.line.opacity(0.72), lineWidth: 1)
            }
            .shadow(color: BodyCompanionTheme.shadow, radius: 14, y: 7)
    }
}

struct CompanionSectionHeading: View {
    let eyebrow: String?
    let title: String
    let detail: String?

    init(eyebrow: String? = nil, title: String, detail: String? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(BodyCompanionTheme.accent)
            }
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(BodyCompanionTheme.ink)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(BodyCompanionTheme.secondaryInk)
            }
        }
    }
}

struct CompanionStatusPill: View {
    let text: String
    let systemImage: String
    let tint: Color

    init(_ text: String, systemImage: String, tint: Color = BodyCompanionTheme.accent) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.10), in: Capsule())
    }
}

struct CompanionPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                BodyCompanionTheme.accent.opacity(configuration.isPressed ? 0.78 : 1),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct CompanionOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(BodyCompanionTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(BodyCompanionTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BodyCompanionTheme.line, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension View {
    func companionScreenBackground() -> some View {
        background(BodyCompanionTheme.canvas.ignoresSafeArea())
            .tint(BodyCompanionTheme.accent)
    }
}
