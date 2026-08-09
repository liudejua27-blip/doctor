import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Visual tokens for the internal, Chinese-first prototype shell. These
/// tokens do not carry health, safety, or persistence semantics.
enum BodyCompanionTheme {
    /// The shell has no health-state colours. These semantic display tokens
    /// adapt to system appearance and Increased Contrast only; colour never
    /// carries a safety, diagnosis, or persistence meaning.
    static let canvas = adaptive(
        light: rgb(0.958, 0.973, 0.988),
        dark: rgb(0.035, 0.090, 0.157),
        highContrastLight: rgb(0.940, 0.962, 0.985),
        highContrastDark: rgb(0.012, 0.043, 0.086)
    )
    static let surface = adaptive(
        light: .white,
        dark: rgb(0.071, 0.145, 0.235),
        highContrastLight: .white,
        highContrastDark: rgb(0.031, 0.078, 0.141)
    )
    static let surfaceTinted = adaptive(
        light: rgb(0.912, 0.953, 0.976),
        dark: rgb(0.086, 0.196, 0.314),
        highContrastLight: rgb(0.885, 0.936, 0.970),
        highContrastDark: rgb(0.055, 0.137, 0.235)
    )
    static let ink = adaptive(
        light: rgb(0.047, 0.110, 0.204),
        dark: rgb(0.941, 0.969, 1.000),
        highContrastLight: rgb(0.000, 0.051, 0.125),
        highContrastDark: .white
    )
    static let secondaryInk = adaptive(
        light: rgb(0.235, 0.314, 0.439),
        dark: rgb(0.773, 0.843, 0.925),
        highContrastLight: rgb(0.141, 0.204, 0.306),
        highContrastDark: rgb(0.851, 0.918, 0.984)
    )
    /// Accent is suitable for icons and control chrome. Readable text keeps
    /// using `ink` rather than a low-contrast tinted foreground.
    static let accent = adaptive(
        light: rgb(0.020, 0.345, 0.698),
        dark: rgb(0.525, 0.761, 1.000),
        highContrastLight: rgb(0.000, 0.247, 0.537),
        highContrastDark: rgb(0.651, 0.820, 1.000)
    )
    static let primaryButtonFill = adaptive(
        light: rgb(0.020, 0.345, 0.698),
        dark: rgb(0.090, 0.333, 0.635),
        highContrastLight: rgb(0.000, 0.235, 0.510),
        highContrastDark: rgb(0.039, 0.235, 0.502)
    )
    static let accentSoft = adaptive(
        light: rgb(0.808, 0.921, 0.992),
        dark: rgb(0.102, 0.278, 0.451),
        highContrastLight: rgb(0.725, 0.878, 0.988),
        highContrastDark: rgb(0.071, 0.208, 0.376)
    )
    static let mint = adaptive(
        light: rgb(0.024, 0.451, 0.361),
        dark: rgb(0.408, 0.863, 0.706),
        highContrastLight: rgb(0.000, 0.329, 0.263),
        highContrastDark: rgb(0.561, 0.949, 0.784)
    )
    static let warm = adaptive(
        light: rgb(0.647, 0.227, 0.035),
        dark: rgb(1.000, 0.675, 0.486),
        highContrastLight: rgb(0.478, 0.137, 0.000),
        highContrastDark: rgb(1.000, 0.765, 0.588)
    )
    static let line = adaptive(
        light: rgb(0.682, 0.741, 0.816),
        dark: rgb(0.235, 0.353, 0.498),
        highContrastLight: rgb(0.518, 0.608, 0.710),
        highContrastDark: rgb(0.365, 0.514, 0.686)
    )
    static let shadow = adaptive(
        light: rgb(0.102, 0.224, 0.390, alpha: 0.09),
        dark: .black.opacity(0.30),
        highContrastLight: rgb(0.047, 0.110, 0.204, alpha: 0.14),
        highContrastDark: .black.opacity(0.42)
    )

    static let cornerRadius: CGFloat = 24
    static let compactCornerRadius: CGFloat = 16

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> Color {
        Color(red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(alpha))
    }

    private static func adaptive(
        light: Color,
        dark: Color,
        highContrastLight: Color,
        highContrastDark: Color
    ) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let isHighContrast = traits.accessibilityContrast == .high
            switch (isDark, isHighContrast) {
            case (false, false): return UIColor(light)
            case (false, true): return UIColor(highContrastLight)
            case (true, false): return UIColor(dark)
            case (true, true): return UIColor(highContrastDark)
            }
        })
        #else
        light
        #endif
    }
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
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(text)
                .foregroundStyle(BodyCompanionTheme.ink)
        }
            .font(.caption.weight(.semibold))
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
                BodyCompanionTheme.primaryButtonFill.opacity(configuration.isPressed ? 0.78 : 1),
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
