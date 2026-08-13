/// Explicit, local-only capabilities for a P0 SwiftUI host.
///
/// This type deliberately carries no account, health, network, persistence,
/// or Agent state. It exists so an internal App host never enables a candidate
/// 3D asset merely because it is a Debug build.
public struct InternalP0RuntimeConfiguration: Sendable, Equatable {
    /// Whether an explicitly requested internal candidate may be attempted.
    /// The normal P0 default remains 2D/list first and fail-closed.
    public let candidate3DEnabled: Bool
    /// Optional user height in meters used as the default 3D height preset source.
    /// Caller should already have validated the value for plausible user input.
    public let userProfileHeightMeters: Float?

    public init(
        candidate3DEnabled: Bool = false,
        userProfileHeightMeters: Float? = nil
    ) {
        self.candidate3DEnabled = candidate3DEnabled
        self.userProfileHeightMeters = userProfileHeightMeters
    }

    /// Safe default for all callers, including Debug builds.
    public static let safeDefault = InternalP0RuntimeConfiguration()

    /// Explicit opt-in for the existing local-only macOS visual harness.
    /// This is not a production-asset approval or a release capability.
    public static let internalCandidate3D = InternalP0RuntimeConfiguration(candidate3DEnabled: true)
}
