import Foundation
import Observation

public enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case today
    case records
    case analysis
    case profile

    public var id: String { rawValue }
}

public enum AppRoute: Hashable, Sendable {
    case assessment
    case intake
    case episode(String)
    case report(String)
    case settings
}

@MainActor
@Observable
public final class RouterPath {
    public var path: [AppRoute] = []

    public init() {}

    public func reset() {
        path.removeAll()
    }
}
