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
    public var markingMode: BodyMarkingMode = .zone
    public private(set) var marks: [BodyMark] = []
    public private(set) var selectedMarkID: UUID?
    public private(set) var focusedRegionID: String?
    /// The most recent user-facing map mutation. This is UI feedback only;
    /// it is never serialized as a health fact or sent to the Agent.
    public private(set) var lastMutation: BodyMarkMutation?

    public var markerDrafts: [BodyLocation] {
        marks.map(\.location)
    }

    public var markerCount: Int { marks.count }

    public init(markerDrafts: [BodyLocation] = []) {
        guard markerDrafts.count <= Self.maximumMarkerCount else {
            lastMutation = .rejectedMarkerLimit
            return
        }
        guard Set(markerDrafts.map(\.id)).count == markerDrafts.count else {
            lastMutation = .rejectedDuplicateLocation
            return
        }
        marks = markerDrafts.enumerated().map { index, location in
            BodyMark(kind: .pin, location: location, colorToken: index)
        }
    }

    public func select(_ location: BodyLocation) {
        _ = applySelection(location)
    }

    @discardableResult
    public func applySelection(_ location: BodyLocation) -> BodyMarkMutation {
        let mutation: BodyMarkMutation
        switch markingMode {
        case .zone:
            mutation = toggleZone(location)
        case .pin:
            mutation = addPin(location)
        }
        lastMutation = mutation
        return mutation
    }

    @discardableResult
    public func toggleZone(_ location: BodyLocation) -> BodyMarkMutation {
        if marks.contains(where: { $0.location.id == location.id }) {
            return .rejectedDuplicateLocation
        }
        if let mark = marks.first(where: {
            $0.kind == .zone && $0.location.regionID == location.regionID &&
                $0.location.laterality == location.laterality
        }) {
            // A repeated tap is selection, not a health-state or deletion
            // shortcut. The user must use an explicit delete action for a
            // provisional zone draft.
            selectedMarkID = mark.id
            focusedRegionID = location.regionID
            return .updated(mark.id)
        }

        guard marks.count < Self.maximumMarkerCount else {
            return .rejectedMarkerLimit
        }

        let mark = BodyMark(kind: .zone, location: location, colorToken: 0)
        marks.append(mark)
        selectedMarkID = mark.id
        focusedRegionID = location.regionID
        return .added(mark.id)
    }

    @discardableResult
    public func addPin(_ location: BodyLocation) -> BodyMarkMutation {
        guard !marks.contains(where: { $0.location.id == location.id }) else {
            return .rejectedDuplicateLocation
        }
        guard marks.count < Self.maximumMarkerCount else {
            return .rejectedMarkerLimit
        }
        let mark = BodyMark(
            kind: .pin,
            location: location,
            colorToken: marks.filter { $0.kind == .pin }.count
        )
        marks.append(mark)
        selectedMarkID = mark.id
        return .added(mark.id)
    }

    public func selectMark(id: UUID?) {
        selectedMarkID = id.flatMap { candidate in
            marks.first { $0.id == candidate || $0.location.id == candidate }?.id
        }
        lastMutation = nil
    }

    /// Selects an already rendered 2D Pin before the tap is interpreted as a
    /// request to create a new Pin. The tolerance is an interaction hit area,
    /// not an anatomical mapping rule.
    @discardableResult
    public func selectExistingPin(at point: Point2D, view: BodyMapView, tolerance: Double = 0.045) -> Bool {
        let candidate = marks
            .filter { $0.kind == .pin }
            .compactMap { mark -> (BodyMark, Double)? in
                guard let anchor = mark.location.anchor2D,
                      anchor.view == view,
                      let markerPoint = anchor.point else { return nil }
                let dx = markerPoint.x - point.x
                let dy = markerPoint.y - point.y
                let distanceSquared = (dx * dx) + (dy * dy)
                guard distanceSquared <= tolerance * tolerance else { return nil }
                return (mark, distanceSquared)
            }
            .min { $0.1 < $1.1 }
        guard let candidate else { return false }
        selectedMarkID = candidate.0.id
        focusedRegionID = candidate.0.location.regionID
        return true
    }

    public func focus(regionID: String?) {
        focusedRegionID = regionID
    }

    public func clearInteractionNotice() {
        lastMutation = nil
    }

    public func clearMarkers() {
        marks.removeAll()
        selectedMarkID = nil
        focusedRegionID = nil
        lastMutation = nil
    }

    /// Restores the last known-good visual projection if the canonical typed
    /// draft rejects a map change. This prevents the map from showing a
    /// location that the structured record, safety review, and later handoff
    /// do not contain. Only a previously owned collection may be restored.
    public func restoreMarks(_ restored: [BodyMark]) {
        guard restored.count <= Self.maximumMarkerCount else {
            lastMutation = .rejectedMarkerLimit
            return
        }
        guard Set(restored.map(\.location.id)).count == restored.count else {
            lastMutation = .rejectedDuplicateLocation
            return
        }
        marks = restored
        selectedMarkID = nil
        focusedRegionID = nil
        lastMutation = .rejectedDraftSynchronization
    }

    public func removeDraft(id: UUID) {
        let removedMarkIDs = Set(marks.filter { $0.id == id || $0.location.id == id }.map(\.id))
        marks.removeAll { removedMarkIDs.contains($0.id) }
        if let selectedMarkID, removedMarkIDs.contains(selectedMarkID) { self.selectedMarkID = nil }
        if let focusedRegionID, !marks.contains(where: { $0.location.regionID == focusedRegionID && $0.isVisible }) {
            self.focusedRegionID = nil
        }
        lastMutation = nil
    }

    public func selectedMark() -> BodyMark? {
        guard let selectedMarkID else { return nil }
        return marks.first { $0.id == selectedMarkID }
    }

    /// Matches `ios-signal-intake.locations.maxItems`. Both Zone and Pin
    /// consume one canonical BodyLocation, so the UI must never accept a
    /// collection that the typed draft cannot represent.
    public static let maximumMarkerCount = 20

    public func switchTo2D(reason: String? = nil) {
        mode = .twoD
        loadState = reason.map(BodyMapLoadState.fallback2D) ?? .interactive
        lastMutation = nil
    }

    public func request3D() {
        mode = .threeD
        loadState = .loading
        lastMutation = nil
    }

    public func mark3DReady() {
        guard mode == .threeD else { return }
        loadState = .interactive
    }

    public func mark3DFailed(_ message: String) {
        switchTo2D(reason: message)
    }
}
