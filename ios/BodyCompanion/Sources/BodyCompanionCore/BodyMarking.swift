import Foundation

/// The two input modes intentionally share one draft collection. Switching
/// modes changes how the next selection is interpreted; it never discards the
/// other mode's marks.
public enum BodyMarkingMode: String, CaseIterable, Codable, Hashable, Sendable {
    case zone
    case pin

    public var displayName: String {
        switch self {
        case .zone: "区域"
        case .pin: "针点"
        }
    }
}

/// Visual emphasis only. These values are not a clinical outcome, a trend,
/// or a CheckIn and must never be serialized as a health fact.
public enum BodyZoneVisualState: String, CaseIterable, Codable, Hashable, Sendable {
    case none
    case marked

    public var displayName: String {
        switch self {
        case .none: "未标记"
        case .marked: "已标记"
        }
    }

    public var isVisible: Bool { self != .none }
}

public enum BodyMarkKind: String, Codable, Hashable, Sendable {
    case zone
    case pin

    public var displayName: String {
        switch self {
        case .zone: "区域"
        case .pin: "针点"
        }
    }
}

/// A transient, user-controlled view state layered on top of a canonical
/// BodyLocation candidate. It is not a BodySignalEvent and cannot be used as
/// proof of tissue, disease, treatment response, or safety.
public struct BodyMark: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var kind: BodyMarkKind
    public var location: BodyLocation
    public var zoneVisualState: BodyZoneVisualState
    /// Pure visual differentiation. It has no business meaning.
    public var colorToken: Int

    public init(
        id: UUID? = nil,
        kind: BodyMarkKind,
        location: BodyLocation,
        zoneVisualState: BodyZoneVisualState? = nil,
        colorToken: Int = 0
    ) {
        self.id = id ?? location.id
        self.kind = kind
        self.location = location
        self.zoneVisualState = zoneVisualState ?? (kind == .zone ? .marked : .none)
        self.colorToken = max(0, colorToken)
    }

    public var isVisible: Bool {
        kind == .pin || zoneVisualState.isVisible
    }

    public var displayLabel: String {
        location.userLabel ?? location.regionID
    }
}

public enum BodyMarkMutation: Equatable, Sendable {
    case added(UUID)
    case updated(UUID)
    case removed(UUID)
    case rejectedMarkerLimit
    case rejectedDuplicateLocation
    case rejectedDraftSynchronization
}
