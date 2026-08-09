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
        return InternalP0RuntimeConfiguration(
            candidate3DEnabled: candidateRequested && !isUISmoke
        )
    }
}
