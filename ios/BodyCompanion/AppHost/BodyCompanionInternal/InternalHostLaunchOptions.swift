import BodyCompanionIOS
import Foundation

/// Launch-only switches for the internal Simulator harness.
///
/// Values are read once and are not persisted. UI smoke always wins over a
/// manually requested candidate 3D flag, keeping its route deterministic.
enum InternalHostLaunchOptions {
    static var runtimeConfiguration: InternalP0RuntimeConfiguration {
        let environment = ProcessInfo.processInfo.environment
        let candidateRequested = environment["BODY_COMPANION_ENABLE_CANDIDATE_3D"] == "1"
        let isUISmoke = environment["BODY_COMPANION_UI_SMOKE"] == "1"
        let profileHeightMeters = Self.userProfileHeightMeters(from: environment)
        return InternalP0RuntimeConfiguration(
            candidate3DEnabled: candidateRequested && !isUISmoke,
            userProfileHeightMeters: profileHeightMeters
        )
    }

    private static func userProfileHeightMeters(
        from environment: [String: String]
    ) -> Float? {
        if let rawHeight = environment["BODY_COMPANION_USER_HEIGHT_METERS"] {
            return normalizedHeightMeters(from: rawHeight)
        }
        if let rawHeightCM = environment["BODY_COMPANION_USER_HEIGHT_CM"] {
            return normalizedHeightMeters(from: rawHeightCM)
        }
        return nil
    }

    private static func normalizedHeightMeters(from raw: String) -> Float? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: ",", with: ".")
        guard let parsed = Float(normalized), parsed > 0 else { return nil }
        if parsed > 3 { return parsed / 100 }
        return parsed
    }
}
