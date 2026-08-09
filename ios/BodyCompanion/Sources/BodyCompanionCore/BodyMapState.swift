import Foundation
import Observation

public enum BodyMapMode: String, CaseIterable, Sendable {
    case twoD = "2D"
    case threeD = "3D"
}

public enum BodyMapLoadState: Equatable, Sendable {
    case idle
    case loading
    /// A candidate scene may use this only after the active RealityKit loader
    /// reports `onReady`. It is deliberately distinct from 2D interactive.
    case threeDReady
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
    /// An opaque, in-memory identity for the currently requested candidate
    /// Scene. It is UI lifecycle state only: never a BodyLocation, health fact,
    /// persisted value, or Agent input.
    public private(set) var activeThreeDAttemptID: UUID?
    /// A Scene records this only after it has attached and is about to query
    /// the candidate Bundle / invoke its loader. It remains available after a
    /// fail-closed fallback solely as internal probe evidence.
    public private(set) var lastRecordedThreeDLoadAttemptID: UUID?
    /// The most recent user-facing map mutation. This is UI feedback only;
    /// it is never serialized as a health fact or sent to the Agent.
    public private(set) var lastMutation: BodyMarkMutation?

    public var markerDrafts: [BodyLocation] {
        marks.map(\.location)
    }

    public var markerCount: Int { marks.count }

    public var hasRecordedCurrentThreeDLoadAttempt: Bool {
        guard let activeThreeDAttemptID else { return false }
        return activeThreeDAttemptID == lastRecordedThreeDLoadAttemptID
    }

    public var hasRecordedThreeDLoadAttempt: Bool {
        lastRecordedThreeDLoadAttemptID != nil
    }

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

    /// Mirrors an already validated canonical location collection without
    /// importing any SignalIntake fact into the map. Existing marks keep their
    /// visual-only kind, colour token, and selection identity; only their
    /// `BodyLocation` candidate is replaced. New locations use the same
    /// neutral Pin projection as restoration because a BodyLocation does not
    /// encode a Zone/Pin presentation choice.
    ///
    /// This is intentionally the only reverse projection used by
    /// `SignalIntakeModel`: it prevents a same-ID location edit from leaving
    /// the map rendering stale while keeping sensation, intensity, factors,
    /// and safety outside the map boundary.
    @discardableResult
    public func synchronizeLocationProjection(_ locations: [BodyLocation]) -> Bool {
        guard locations.count <= Self.maximumMarkerCount else {
            lastMutation = .rejectedMarkerLimit
            return false
        }
        guard Set(locations.map(\.id)).count == locations.count else {
            lastMutation = .rejectedDuplicateLocation
            return false
        }
        guard markerDrafts != locations else { return true }

        let existingMarksByLocationID = Dictionary(
            uniqueKeysWithValues: marks.map { ($0.location.id, $0) }
        )
        var nextPinColorToken = marks
            .filter { $0.kind == .pin }
            .map(\.colorToken)
            .max()
            .map { $0 + 1 } ?? 0

        marks = locations.map { location in
            if var existing = existingMarksByLocationID[location.id] {
                existing.location = location
                return existing
            }
            defer { nextPinColorToken += 1 }
            return BodyMark(kind: .pin, location: location, colorToken: nextPinColorToken)
        }

        if let selectedMarkID,
           let selected = marks.first(where: { $0.id == selectedMarkID || $0.location.id == selectedMarkID }) {
            self.selectedMarkID = selected.id
            focusedRegionID = selected.location.regionID
        } else {
            selectedMarkID = nil
            if let focusedRegionID,
               !marks.contains(where: { $0.location.regionID == focusedRegionID && $0.isVisible }) {
                self.focusedRegionID = nil
            }
        }
        return true
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
        // Invalidates every callback owned by the outgoing Scene before the
        // visible mode changes. Keep the last acknowledgement only for the
        // internal candidate probe's fail-closed evidence, never as data.
        activeThreeDAttemptID = nil
        mode = .twoD
        loadState = reason.map(BodyMapLoadState.fallback2D) ?? .interactive
        lastMutation = nil
    }

    /// Begins a new candidate request. A newer request supersedes any prior
    /// Scene immediately, so an old asynchronous callback cannot mark it ready
    /// or force it back to 2D.
    @discardableResult
    public func request3D() -> UUID {
        let attemptID = UUID()
        activeThreeDAttemptID = attemptID
        lastRecordedThreeDLoadAttemptID = nil
        mode = .threeD
        loadState = .loading
        lastMutation = nil
        return attemptID
    }

    /// Records the loader-entry acknowledgement for the active candidate Scene.
    /// Calling this with an expired or replaced attempt is deliberately a no-op.
    public func mark3DLoadAttempted(for attemptID: UUID) {
        guard isCurrentThreeDLoadingAttempt(attemptID) else { return }
        lastRecordedThreeDLoadAttemptID = attemptID
    }

    /// Only the current Scene that has acknowledged loader entry may mark 3D
    /// ready. This prevents direct mode changes and stale async callbacks from
    /// being displayed as a loaded candidate.
    public func mark3DReady(for attemptID: UUID) {
        guard isCurrentThreeDLoadingAttempt(attemptID),
              lastRecordedThreeDLoadAttemptID == attemptID else { return }
        loadState = .threeDReady
    }

    /// A candidate Scene may fail only its own active request. The unscoped
    /// overload remains for the normal production-gated path, which never
    /// instantiates a candidate Scene and fails closed synchronously.
    public func mark3DFailed(_ message: String, for attemptID: UUID? = nil) {
        if let attemptID {
            guard isCurrentThreeDAttempt(attemptID) else { return }
        } else {
            guard mode == .threeD else { return }
        }
        switchTo2D(reason: message)
    }

    public func isCurrentThreeDReady(for attemptID: UUID) -> Bool {
        guard activeThreeDAttemptID == attemptID, mode == .threeD else { return false }
        return loadState == .threeDReady
    }

    private func isCurrentThreeDLoadingAttempt(_ attemptID: UUID) -> Bool {
        activeThreeDAttemptID == attemptID && mode == .threeD && loadState == .loading
    }

    private func isCurrentThreeDAttempt(_ attemptID: UUID) -> Bool {
        activeThreeDAttemptID == attemptID && mode == .threeD
    }
}
