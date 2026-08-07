import Foundation
import Observation

public enum BodyMapMode: String, CaseIterable, Sendable {
    case twoD = "2D"
    case threeD = "3D"
}

public enum BodyMapLoadState: Equatable, Sendable {
    case idle
    case loading
    case interactive
    case failed(String)
    case fallback2D(String)
}

@MainActor
@Observable
public final class BodyMapModel {
    public var mode: BodyMapMode = .twoD
    public var view: BodyMapView = .front
    public var loadState: BodyMapLoadState = .interactive
    public private(set) var markerDrafts: [BodyLocation] = []

    public init() {}

    public func select(_ location: BodyLocation) {
        markerDrafts.append(location)
    }

    public func clearMarkers() {
        markerDrafts.removeAll()
    }

    public func removeDraft(id: UUID) {
        markerDrafts.removeAll { $0.id == id }
    }

    public func switchTo2D(reason: String? = nil) {
        mode = .twoD
        loadState = reason.map(BodyMapLoadState.fallback2D) ?? .interactive
    }

    public func request3D() {
        mode = .threeD
        loadState = .loading
    }

    public func mark3DReady() {
        guard mode == .threeD else { return }
        loadState = .interactive
    }

    public func mark3DFailed(_ message: String) {
        switchTo2D(reason: message)
    }
}
