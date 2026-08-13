import BodyCompanionIOS
import Foundation
import SwiftUI

@main
struct BodyCompanionPrototypeApp: App {
    private static let configurableHeightPresetHeightsMeters: [Float] = {
        let environment = ProcessInfo.processInfo.environment
        if let presetHeights = heightPresetHeightsMeters(from: environment) {
            return presetHeights
        }
        return defaultHeightPresetHeightsMeters + extraHeightPresetHeightsMeters
    }()

    private static let defaultHeightPresetHeightsMeters: [Float] = [1.60, 1.70, 1.80]
    private static let extraHeightPresetHeightsMeters: [Float] = [1.55, 1.65, 1.75, 1.85]

    private static let runtimeConfiguration: InternalP0RuntimeConfiguration = {
        let environment = ProcessInfo.processInfo.environment
        let profileHeightMeters = userProfileHeightMeters(from: environment)
        return InternalP0RuntimeConfiguration(
            candidate3DEnabled: true,
            userProfileHeightMeters: profileHeightMeters
        )
    }()

    var body: some Scene {
        WindowGroup {
            AppShell(
                runtimeConfiguration: Self.runtimeConfiguration,
                heightPresetHeightsMeters: Self.configurableHeightPresetHeightsMeters
            )
        }
    }

    private static func heightPresetHeightsMeters(from environment: [String: String]) -> [Float]? {
        if let rawPresetHeights = environment["BODY_COMPANION_HEIGHT_PRESET_SET"] {
            let parsed = rawPresetHeights
                .split(separator: ",")
                .compactMap { segment in
                    normalizedHeightMeters(from: String(segment))
                }
            if !parsed.isEmpty { return parsed }
        }
        return nil
    }

    private static func userProfileHeightMeters(from environment: [String: String]) -> Float? {
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
