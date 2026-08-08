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
    case reviewing

    public var displayName: String {
        switch self {
        case .none: "未标记"
        case .marked: "已标记"
        case .reviewing: "待复核"
        }
    }

    public var isVisible: Bool { self != .none }
}

/// A deliberately small first-pass vocabulary for the map editor. The typed
/// Signal Intake ontology remains authoritative when the user continues.
public enum BodyMarkSensation: String, CaseIterable, Codable, Hashable, Sendable {
    case sharp = "sharp"
    case sore = "sore"
    case tender = "tender"
    case itchy = "itchy"
    case dull = "dull"

    public var displayName: String {
        switch self {
        case .sharp: "刺痛"
        case .sore: "酸胀"
        case .tender: "压痛"
        case .itchy: "发痒"
        case .dull: "隐隐不适"
        }
    }

    public var signalCode: SignalSensationCode {
        switch self {
        case .sharp: .sharpPain
        case .sore: .aching
        case .tender: .tenderness
        case .itchy: .itching
        case .dull: .dullPain
        }
    }
}

/// Movement/function cues stay separate from sensation. They are candidates
/// for later typed aggravating-factor or functional-impact fields.
public enum BodyMarkTrigger: String, CaseIterable, Codable, Hashable, Sendable {
    case walking = "walking"
    case raisingArm = "raising_arm"
    case rotating = "rotating"
    case extending = "extending"

    public var displayName: String {
        switch self {
        case .walking: "走路"
        case .raisingArm: "举手"
        case .rotating: "转动"
        case .extending: "伸直"
        }
    }
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
    public var sensation: BodyMarkSensation?
    public var triggers: Set<BodyMarkTrigger>
    public var intensity: Int?
    /// Pure visual differentiation. It has no business meaning.
    public var colorToken: Int

    public init(
        id: UUID? = nil,
        kind: BodyMarkKind,
        location: BodyLocation,
        zoneVisualState: BodyZoneVisualState? = nil,
        sensation: BodyMarkSensation? = nil,
        triggers: Set<BodyMarkTrigger> = [],
        intensity: Int? = nil,
        colorToken: Int = 0
    ) {
        self.id = id ?? location.id
        self.kind = kind
        self.location = location
        self.zoneVisualState = zoneVisualState ?? (kind == .zone ? .marked : .none)
        self.sensation = sensation
        self.triggers = triggers
        self.intensity = intensity.map { min(max($0, 0), 10) }
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
    case rejectedPinLimit
    case rejectedInvalidIntensity
}
