import Foundation
import Observation

/// Client-side state for converting a user's subjective body signal into
/// typed, reviewable facts. It is deliberately not a medical conclusion.
public enum SignalIntakePhase: String, Codable, CaseIterable, Sendable {
    case choosingLocation = "choosing_location"
    case collectingFacts = "collecting_facts"
    case safetyReview = "safety_review"
    case safetyAction = "safety_action"
    case agentDraft = "agent_draft"
    case reviewFacts = "review_facts"
    case awaitingApproval = "awaiting_approval"
    case offlineDraft = "offline_draft"
    case failed

    public var displayName: String {
        switch self {
        case .choosingLocation: "选择位置"
        case .collectingFacts: "填写身体感受"
        case .safetyReview: "安全检查"
        case .safetyAction: "安全行动优先"
        case .agentDraft: "整理候选信息"
        case .reviewFacts: "复核事实"
        case .awaitingApproval: "等待你批准保存"
        case .offlineDraft: "离线未确认草稿"
        case .failed: "需要重试"
        }
    }
}

public enum SignalFactGroup: String, Codable, CaseIterable, Hashable, Sendable {
    case location
    case sensation
    case intensity
    case temporal
    case aggravatingFactors = "aggravating_factors"
    case relievingFactors = "relieving_factors"
    case functionalImpact = "functional_impact"
    case background
}

public enum SignalFactSource: String, Codable, CaseIterable, Sendable {
    case user
    case agentCandidate = "agent_candidate"
    case profile
    case system
}

public enum SignalFactStatus: String, Codable, CaseIterable, Sendable {
    case userEntered = "user_entered"
    case candidate
    case reviewed
    case unknown
}

public enum SignalSensationCode: String, Codable, CaseIterable, Hashable, Sendable {
    case aching
    case dullPain = "dull_pain"
    case sharpPain = "sharp_pain"
    case stabbing
    case throbbing
    case tenderness
    case pressure
    case burning
    case electric
    case radiating
    case tingling
    case numbness
    case reducedSensation = "reduced_sensation"
    case tightness
    case stiffness
    case cramping
    case catching
    case clicking
    case weakness
    case instability
    case givingWay = "giving_way"
    case movementFear = "movement_fear"
    case swelling
    case redness
    case warmth
    case bruising
    case itching
    case fatigue
    case heaviness
    case postActivitySoreness = "post_activity_soreness"
    case other
    case unknown

    public var displayName: String {
        switch self {
        case .aching: "酸胀"
        case .dullPain: "隐痛"
        case .sharpPain: "锐痛"
        case .stabbing: "刺痛"
        case .throbbing: "搏动感"
        case .tenderness: "触碰敏感"
        case .pressure: "压迫感"
        case .burning: "灼热感"
        case .electric: "电击样感"
        case .radiating: "向周围扩散"
        case .tingling: "麻刺感"
        case .numbness: "麻木"
        case .reducedSensation: "感觉减弱"
        case .tightness: "紧绷"
        case .stiffness: "僵硬"
        case .cramping: "痉挛感"
        case .catching: "卡住感"
        case .clicking: "咔哒感"
        case .weakness: "无力感"
        case .instability: "不稳感"
        case .givingWay: "打软腿/失去支撑感"
        case .movementFear: "因动作而害怕"
        case .swelling: "肿胀"
        case .redness: "发红"
        case .warmth: "发热"
        case .bruising: "淤青"
        case .itching: "瘙痒"
        case .fatigue: "疲劳"
        case .heaviness: "沉重感"
        case .postActivitySoreness: "活动后不适"
        case .other: "其他"
        case .unknown: "说不清/不想回答"
        }
    }

    /// Keep the first page short while still exposing the complete ontology
    /// through an explicit “更多感觉” path.
    public static var commonCases: [SignalSensationCode] {
        [.aching, .dullPain, .sharpPain, .stabbing, .tightness, .stiffness, .swelling, .weakness, .other, .unknown]
    }
}

public enum SignalIntensityContext: String, Codable, CaseIterable, Sendable {
    case current
    case peak
    case rest
    case duringActivity = "during_activity"
    case afterActivity = "after_activity"

    public var displayName: String {
        switch self {
        case .current: "现在"
        case .peak: "最明显时"
        case .rest: "休息时"
        case .duringActivity: "活动中"
        case .afterActivity: "活动后"
        }
    }
}

public enum SignalOnsetMode: String, Codable, CaseIterable, Sendable {
    case sudden
    case gradual
    case afterSpecificEvent = "after_specific_event"
    case unknown

    public var displayName: String {
        switch self {
        case .sudden: "突然出现"
        case .gradual: "逐渐出现"
        case .afterSpecificEvent: "某个事件后出现"
        case .unknown: "说不清/不想回答"
        }
    }
}

public enum SignalCourse: String, Codable, CaseIterable, Sendable {
    case continuous
    case intermittent
    case recurrent
    case singleOccurrence = "single_occurrence"
    case unknown

    public var displayName: String {
        switch self {
        case .continuous: "持续"
        case .intermittent: "间歇出现"
        case .recurrent: "反复出现"
        case .singleOccurrence: "只出现过一次"
        case .unknown: "说不清/不想回答"
        }
    }
}

public enum SignalFactorEffect: String, Codable, CaseIterable, Sendable {
    case worse
    case better
    case uncertain
}

public enum SignalFunctionalDomain: String, Codable, CaseIterable, Sendable {
    case sleep
    case sitting
    case standing
    case walking
    case running
    case stairs
    case lifting
    case work
    case training
    case selfCare = "self_care"
    case other

    public var displayName: String {
        switch self {
        case .sleep: "睡眠"
        case .sitting: "坐着"
        case .standing: "站立"
        case .walking: "走路"
        case .running: "跑步"
        case .stairs: "上下楼"
        case .lifting: "搬/举重物"
        case .work: "工作"
        case .training: "训练"
        case .selfCare: "日常自理"
        case .other: "其他"
        }
    }
}

public enum SignalImpactSeverity: String, Codable, CaseIterable, Sendable {
    case none
    case mild
    case moderate
    case severe
    case unable
    case unknown

    public var displayName: String {
        switch self {
        case .none: "没有明显影响"
        case .mild: "轻微影响"
        case .moderate: "中等影响"
        case .severe: "明显影响"
        case .unable: "无法完成"
        case .unknown: "说不清/不想回答"
        }
    }
}

public enum SignalBackgroundCategory: String, Codable, CaseIterable, Sendable {
    case activityChange = "activity_change"
    case specificIncident = "specific_incident"
    case workContext = "work_context"
    case priorSameRegionIssue = "prior_same_region_issue"
    case surgeryHistory = "surgery_history"
    case medicationContext = "medication_context"
    case healthContext = "health_context"
    case other
}

public enum SignalSafetyStatus: String, Codable, CaseIterable, Sendable {
    case notRun = "not_run"
    case noRuleTriggered = "no_rule_triggered"
    case r0
    case r1
    case r2
    case undetermined
    case unavailable

    public var displayName: String {
        switch self {
        case .notRun: "尚未完成安全检查"
        case .noRuleTriggered: "当前回答未触发已审核规则（不等于安全）"
        case .r0: "需要立即获得紧急帮助"
        case .r1: "需要尽快获得专业评估"
        case .r2: "建议尽快预约专业评估"
        case .undetermined: "安全信息尚未解决"
        case .unavailable: "安全规则暂不可用"
        }
    }

    public var ordinaryAgentAllowed: Bool {
        self == .r2 || self == .noRuleTriggered
    }
}

public enum SignalIntakeTransitionError: String, Error, Equatable, Sendable {
    case noLocations
    case wrongPhase
    case requiredFactsMissing
    case safetyNotComplete
    case ordinaryAgentSuppressed
    case approvalNotReady
    case invalidIntensity
    case invalidValue
    case unknownField

    public var errorDescription: String? {
        switch self {
        case .noLocations: "请先选择至少一个身体位置。"
        case .wrongPhase: "当前步骤不能执行这个操作。"
        case .requiredFactsMissing: "请完成必填事实，或明确选择不知道/不想回答。"
        case .safetyNotComplete: "安全检查尚未完成，不能进入普通分析或保存审批。"
        case .ordinaryAgentSuppressed: "当前安全行动优先，暂不进入普通分析。"
        case .approvalNotReady: "事实复核或安全状态尚未完成。"
        case .invalidIntensity: "程度必须在 0 到 10 之间。"
        case .invalidValue: "输入内容不符合当前字段要求。"
        case .unknownField: "收到未支持的字段。"
        }
    }
}

public struct SignalSensation: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var code: SignalSensationCode
    public var userLabel: String?
    /// The locations to which the user explicitly associates this sensation.
    /// An adapter must never infer this relationship by copying a sensation
    /// to every selected marker.
    public var locationMarkerIDs: [UUID]
    public var source: SignalFactSource
    public var status: SignalFactStatus

    public init(
        id: UUID = UUID(),
        code: SignalSensationCode,
        userLabel: String? = nil,
        locationMarkerIDs: [UUID] = [],
        source: SignalFactSource = .user,
        status: SignalFactStatus = .userEntered
    ) {
        self.id = id
        self.code = code
        self.userLabel = userLabel
        self.locationMarkerIDs = locationMarkerIDs
        self.source = source
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case id = "sensation_id"
        case code
        case userLabel = "user_label"
        case locationMarkerIDs = "location_marker_ids"
        case source
        case status
    }
}

public struct SignalIntensity: Codable, Equatable, Hashable, Sendable {
    public var context: SignalIntensityContext
    public var value: Int
    public var source: SignalFactSource
    public var status: SignalFactStatus

    public init(
        context: SignalIntensityContext,
        value: Int,
        source: SignalFactSource = .user,
        status: SignalFactStatus = .userEntered
    ) throws {
        guard (0...10).contains(value) else { throw SignalIntakeTransitionError.invalidIntensity }
        self.context = context
        self.value = value
        self.source = source
        self.status = status
    }
}

public struct SignalTemporalPattern: Codable, Equatable, Hashable, Sendable {
    public var onsetMode: SignalOnsetMode
    public var course: SignalCourse
    public var userText: String?
    public var source: SignalFactSource
    public var status: SignalFactStatus

    public init(
        onsetMode: SignalOnsetMode,
        course: SignalCourse,
        userText: String? = nil,
        source: SignalFactSource = .user,
        status: SignalFactStatus = .userEntered
    ) {
        self.onsetMode = onsetMode
        self.course = course
        self.userText = userText
        self.source = source
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case onsetMode = "onset_mode"
        case course
        case userText = "user_text"
        case source
        case status
    }
}

public struct SignalFactor: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var label: String
    public var effect: SignalFactorEffect
    public var source: SignalFactSource
    public var status: SignalFactStatus

    public init(
        id: UUID = UUID(),
        label: String,
        effect: SignalFactorEffect,
        source: SignalFactSource = .user,
        status: SignalFactStatus = .userEntered
    ) {
        self.id = id
        self.label = label
        self.effect = effect
        self.source = source
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case id = "factor_id"
        case label
        case effect
        case source
        case status
    }
}

public struct SignalFunctionalImpact: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var domain: SignalFunctionalDomain
    public var severity: SignalImpactSeverity
    public var userText: String?
    public var source: SignalFactSource
    public var status: SignalFactStatus

    public init(
        id: UUID = UUID(),
        domain: SignalFunctionalDomain,
        severity: SignalImpactSeverity,
        userText: String? = nil,
        source: SignalFactSource = .user,
        status: SignalFactStatus = .userEntered
    ) {
        self.id = id
        self.domain = domain
        self.severity = severity
        self.userText = userText
        self.source = source
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case id = "impact_id"
        case domain
        case severity
        case userText = "user_text"
        case source
        case status
    }
}

public struct SignalBackgroundFact: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var category: SignalBackgroundCategory
    public var value: String
    public var source: SignalFactSource
    public var status: SignalFactStatus

    public init(
        id: UUID = UUID(),
        category: SignalBackgroundCategory,
        value: String,
        source: SignalFactSource = .user,
        status: SignalFactStatus = .candidate
    ) {
        self.id = id
        self.category = category
        self.value = value
        self.source = source
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case id = "fact_id"
        case category
        case value
        case source
        case status
    }
}

public struct SignalIntakeFacts: Codable, Equatable, Sendable {
    public var sensations: [SignalSensation]
    public var intensity: SignalIntensity?
    public var temporal: SignalTemporalPattern?
    public var aggravatingFactors: [SignalFactor]
    public var relievingFactors: [SignalFactor]
    public var functionalImpacts: [SignalFunctionalImpact]
    public var backgroundFacts: [SignalBackgroundFact]
    public var rawUserText: String?

    public init(
        sensations: [SignalSensation] = [],
        intensity: SignalIntensity? = nil,
        temporal: SignalTemporalPattern? = nil,
        aggravatingFactors: [SignalFactor] = [],
        relievingFactors: [SignalFactor] = [],
        functionalImpacts: [SignalFunctionalImpact] = [],
        backgroundFacts: [SignalBackgroundFact] = [],
        rawUserText: String? = nil
    ) {
        self.sensations = sensations
        self.intensity = intensity
        self.temporal = temporal
        self.aggravatingFactors = aggravatingFactors
        self.relievingFactors = relievingFactors
        self.functionalImpacts = functionalImpacts
        self.backgroundFacts = backgroundFacts
        self.rawUserText = rawUserText
    }

    public var asOfflineFacts: UnconfirmedDraftFacts {
        UnconfirmedDraftFacts(
            sensationCodes: sensations.map { $0.code.rawValue },
            intensity: intensity?.value,
            timePattern: [temporal?.onsetMode.displayName, temporal?.course.displayName, temporal?.userText]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "；"),
            aggravatingFactors: aggravatingFactors.map(\.label),
            relievingFactors: relievingFactors.map(\.label),
            functionalImpacts: functionalImpacts.map { "\($0.domain.rawValue):\($0.severity.rawValue)" },
            backgroundFacts: backgroundFacts.map(\.value),
            rawUserText: rawUserText
        )
    }

    private enum CodingKeys: String, CodingKey {
        case sensations
        case intensity
        case temporal
        case aggravatingFactors = "aggravating_factors"
        case relievingFactors = "relieving_factors"
        case functionalImpacts = "functional_impacts"
        case backgroundFacts = "background_facts"
        case rawUserText = "raw_user_text"
    }
}

public struct SignalSafetyState: Codable, Equatable, Sendable {
    public var status: SignalSafetyStatus
    public var ordinaryAgentAllowed: Bool
    public var ruleSetVersion: String?
    public var displayMessage: String?

    public init(
        status: SignalSafetyStatus = .notRun,
        ordinaryAgentAllowed: Bool? = nil,
        ruleSetVersion: String? = nil,
        displayMessage: String? = nil
    ) {
        self.status = status
        self.ordinaryAgentAllowed = ordinaryAgentAllowed ?? status.ordinaryAgentAllowed
        self.ruleSetVersion = ruleSetVersion
        self.displayMessage = displayMessage
    }

    public func validate() throws {
        let expected = status.ordinaryAgentAllowed
        guard ordinaryAgentAllowed == expected else { throw SignalIntakeTransitionError.safetyNotComplete }
        if status == .noRuleTriggered, let message = displayMessage, message.contains("安全"), !message.contains("不等于安全") {
            throw SignalIntakeTransitionError.safetyNotComplete
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case status
        case ordinaryAgentAllowed = "ordinary_agent_allowed"
        case ruleSetVersion = "rule_set_version"
        case displayMessage = "display_message"
    }

    public init(from decoder: Decoder) throws {
        try rejectSignalIntakeUnknownKeys(decoder, allowed: CodingKeys.allCases)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(SignalSafetyStatus.self, forKey: .status)
        ordinaryAgentAllowed = try container.decode(Bool.self, forKey: .ordinaryAgentAllowed)
        ruleSetVersion = try container.decodeIfPresent(String.self, forKey: .ruleSetVersion)
        displayMessage = try container.decodeIfPresent(String.self, forKey: .displayMessage)
    }
}

public struct SignalIntakeDraft: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = "1.1"
    public static let requiredFactGroups: Set<SignalFactGroup> = [.sensation, .intensity, .temporal, .functionalImpact]

    public let schemaVersion: String
    public let sessionID: UUID
    public var draftRevision: Int
    public var phase: SignalIntakePhase
    public var locations: [BodyLocation]
    public var facts: SignalIntakeFacts
    public var safety: SignalSafetyState
    public var reviewedGroups: Set<SignalFactGroup>
    public var unknownGroups: Set<SignalFactGroup>
    public var lastErrorCode: String?
    public var updatedAt: Date

    public init(
        sessionID: UUID = UUID(),
        draftRevision: Int = 1,
        phase: SignalIntakePhase = .choosingLocation,
        locations: [BodyLocation] = [],
        facts: SignalIntakeFacts = .init(),
        safety: SignalSafetyState = .init(),
        reviewedGroups: Set<SignalFactGroup> = [],
        unknownGroups: Set<SignalFactGroup> = [],
        lastErrorCode: String? = nil,
        updatedAt: Date = .now
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.sessionID = sessionID
        self.draftRevision = draftRevision
        self.phase = phase
        self.locations = locations
        self.facts = facts
        self.safety = safety
        self.reviewedGroups = reviewedGroups
        self.unknownGroups = unknownGroups
        self.lastErrorCode = lastErrorCode
        self.updatedAt = updatedAt
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion, draftRevision >= 1 else { throw SignalIntakeTransitionError.invalidValue }
        guard locations.count <= 20 else { throw SignalIntakeTransitionError.invalidValue }
        guard Set(locations.map(\.id)).count == locations.count else { throw SignalIntakeTransitionError.invalidValue }
        guard unknownGroups.isSubset(of: reviewedGroups) else { throw SignalIntakeTransitionError.requiredFactsMissing }
        try safety.validate()
        if phase != .choosingLocation && locations.isEmpty { throw SignalIntakeTransitionError.noLocations }
        if reviewedGroups.contains(.sensation), !unknownGroups.contains(.sensation), facts.sensations.isEmpty {
            throw SignalIntakeTransitionError.requiredFactsMissing
        }
        if reviewedGroups.contains(.intensity), !unknownGroups.contains(.intensity), facts.intensity == nil {
            throw SignalIntakeTransitionError.requiredFactsMissing
        }
        if reviewedGroups.contains(.temporal), !unknownGroups.contains(.temporal), facts.temporal == nil {
            throw SignalIntakeTransitionError.requiredFactsMissing
        }
        if reviewedGroups.contains(.functionalImpact), !unknownGroups.contains(.functionalImpact), facts.functionalImpacts.isEmpty {
            throw SignalIntakeTransitionError.requiredFactsMissing
        }
        let locationIDs = Set(locations.map(\.id))
        for sensation in facts.sensations {
            guard !sensation.locationMarkerIDs.isEmpty,
                  Set(sensation.locationMarkerIDs).count == sensation.locationMarkerIDs.count,
                  Set(sensation.locationMarkerIDs).isSubset(of: locationIDs)
            else { throw SignalIntakeTransitionError.invalidValue }
        }
        if phase == .agentDraft, !safety.ordinaryAgentAllowed { throw SignalIntakeTransitionError.ordinaryAgentSuppressed }
        if phase == .awaitingApproval {
            guard safety.status == .r2 || safety.status == .noRuleTriggered else { throw SignalIntakeTransitionError.safetyNotComplete }
            guard Self.requiredFactGroups.isSubset(of: reviewedGroups) else { throw SignalIntakeTransitionError.approvalNotReady }
        }
        for sensation in facts.sensations where sensation.code == .other && (sensation.userLabel?.isEmpty ?? true) {
            throw SignalIntakeTransitionError.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case sessionID = "session_id"
        case draftRevision = "draft_revision"
        case phase
        case locations
        case facts
        case safety
        case reviewedGroups = "reviewed_groups"
        case unknownGroups = "unknown_groups"
        case lastErrorCode = "last_error_code"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        try rejectSignalIntakeUnknownKeys(decoder, allowed: CodingKeys.allCases)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        sessionID = try container.decode(UUID.self, forKey: .sessionID)
        draftRevision = try container.decode(Int.self, forKey: .draftRevision)
        phase = try container.decode(SignalIntakePhase.self, forKey: .phase)
        locations = try container.decode([BodyLocation].self, forKey: .locations)
        facts = try container.decode(SignalIntakeFacts.self, forKey: .facts)
        safety = try container.decode(SignalSafetyState.self, forKey: .safety)
        reviewedGroups = try container.decode(Set<SignalFactGroup>.self, forKey: .reviewedGroups)
        unknownGroups = try container.decode(Set<SignalFactGroup>.self, forKey: .unknownGroups)
        lastErrorCode = try container.decodeIfPresent(String.self, forKey: .lastErrorCode)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

@MainActor
@Observable
public final class SignalIntakeModel {
    public private(set) var draft: SignalIntakeDraft
    public let bodyMapModel: BodyMapModel

    public init(draft: SignalIntakeDraft = .init(), bodyMapModel: BodyMapModel = BodyMapModel()) {
        self.draft = draft
        self.bodyMapModel = bodyMapModel
    }

    public var phase: SignalIntakePhase { draft.phase }
    public var safety: SignalSafetyState { draft.safety }
    public var hasLocations: Bool { !draft.locations.isEmpty }
    public var unconfirmedCandidateCount: Int {
        draft.facts.sensations.filter { $0.status == .candidate }.count +
            draft.facts.aggravatingFactors.filter { $0.status == .candidate }.count +
            draft.facts.relievingFactors.filter { $0.status == .candidate }.count +
            draft.facts.backgroundFacts.filter { $0.status == .candidate }.count
    }

    public func setLocations(_ locations: [BodyLocation]) {
        var seen = Set<UUID>()
        draft.locations = Array(locations.prefix(20)).filter { seen.insert($0.id).inserted }
        let markerIDs = draft.locations.map(\.id)
        for index in draft.facts.sensations.indices {
            draft.facts.sensations[index].locationMarkerIDs = markerIDs
        }
        if !draft.facts.sensations.isEmpty {
            draft.reviewedGroups.remove(.sensation)
        }
        if !draft.locations.isEmpty && draft.phase == .choosingLocation {
            draft.phase = .collectingFacts
        }
        touch()
    }

    /// Projects explicit map-editor choices into the typed intake draft. This
    /// remains unreviewed until the user completes the normal fact review; it
    /// does not create an Event or approval.
    public func applyBodyMarks(_ marks: [BodyMark]) {
        setLocations(marks.map(\.location))

        var sensationLocations: [SignalSensationCode: [UUID]] = [:]
        for mark in marks {
            guard let sensation = mark.sensation else { continue }
            sensationLocations[sensation.signalCode, default: []].append(mark.location.id)
        }
        draft.facts.sensations = sensationLocations
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { code, markerIDs in
                SignalSensation(code: code, locationMarkerIDs: markerIDs)
            }
        draft.reviewedGroups.remove(.sensation)
        draft.unknownGroups.remove(.sensation)

        if let intensity = marks.compactMap(\.intensity).first,
           let typedIntensity = try? SignalIntensity(context: .current, value: intensity) {
            draft.facts.intensity = typedIntensity
        } else {
            draft.facts.intensity = nil
        }
        draft.reviewedGroups.remove(.intensity)
        draft.unknownGroups.remove(.intensity)

        draft.facts.aggravatingFactors = marks
            .flatMap { mark in
                mark.triggers.map { trigger in
                    SignalFactor(label: trigger.displayName, effect: .worse)
                }
            }
        draft.reviewedGroups.remove(.aggravatingFactors)
        draft.unknownGroups.remove(.aggravatingFactors)
        touch()
    }

    public func removeLocation(id: UUID) {
        draft.locations.removeAll { $0.id == id }
        let markerIDs = Set(draft.locations.map(\.id))
        for index in draft.facts.sensations.indices {
            draft.facts.sensations[index].locationMarkerIDs.removeAll { !markerIDs.contains($0) }
        }
        if !draft.facts.sensations.isEmpty {
            draft.reviewedGroups.remove(.sensation)
        }
        if draft.locations.isEmpty { draft.phase = .choosingLocation }
        touch()
    }

    public func toggleSensation(_ code: SignalSensationCode) {
        if let index = draft.facts.sensations.firstIndex(where: { $0.code == code }) {
            draft.facts.sensations.remove(at: index)
        } else {
            draft.facts.sensations.append(
                SignalSensation(code: code, locationMarkerIDs: draft.locations.map(\.id))
            )
        }
        draft.reviewedGroups.remove(.sensation)
        draft.unknownGroups.remove(.sensation)
        touch()
    }

    public func setOtherSensationLabel(_ value: String) throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 200 else { throw SignalIntakeTransitionError.invalidValue }
        guard let index = draft.facts.sensations.firstIndex(where: { $0.code == .other }) else {
            throw SignalIntakeTransitionError.invalidValue
        }
        draft.facts.sensations[index].userLabel = normalized
        draft.reviewedGroups.remove(.sensation)
        draft.unknownGroups.remove(.sensation)
        touch()
    }

    public func markUnknown(_ group: SignalFactGroup) {
        draft.reviewedGroups.insert(group)
        draft.unknownGroups.insert(group)
        if group == .sensation { draft.facts.sensations = [] }
        if group == .intensity { draft.facts.intensity = nil }
        if group == .temporal { draft.facts.temporal = nil }
        if group == .functionalImpact { draft.facts.functionalImpacts = [] }
        touch()
    }

    @discardableResult
    public func markReviewed(_ group: SignalFactGroup) -> Bool {
        switch group {
        case .location:
            guard !draft.locations.isEmpty else { return false }
        case .sensation:
            guard !draft.facts.sensations.isEmpty else { return false }
            guard draft.facts.sensations.filter({ $0.code == .other }).allSatisfy({ !($0.userLabel?.isEmpty ?? true) }) else {
                return false
            }
        case .intensity:
            guard draft.facts.intensity != nil else { return false }
        case .temporal:
            guard draft.facts.temporal != nil else { return false }
        case .functionalImpact:
            guard !draft.facts.functionalImpacts.isEmpty else { return false }
        case .aggravatingFactors, .relievingFactors, .background:
            break
        }
        draft.reviewedGroups.insert(group)
        draft.unknownGroups.remove(group)
        touch()
        return true
    }

    public func setIntensity(context: SignalIntensityContext, value: Int) throws {
        draft.facts.intensity = try SignalIntensity(context: context, value: value)
        draft.reviewedGroups.remove(.intensity)
        draft.unknownGroups.remove(.intensity)
        touch()
    }

    public func setTemporal(onsetMode: SignalOnsetMode, course: SignalCourse, userText: String? = nil) {
        draft.facts.temporal = SignalTemporalPattern(onsetMode: onsetMode, course: course, userText: userText)
        draft.reviewedGroups.remove(.temporal)
        draft.unknownGroups.remove(.temporal)
        touch()
    }

    public func addFactor(label: String, effect: SignalFactorEffect) throws {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 200 else { throw SignalIntakeTransitionError.invalidValue }
        let factor = SignalFactor(label: normalized, effect: effect)
        if effect == .better {
            draft.facts.relievingFactors.append(factor)
            draft.reviewedGroups.remove(.relievingFactors)
        } else {
            draft.facts.aggravatingFactors.append(factor)
            draft.reviewedGroups.remove(.aggravatingFactors)
        }
        touch()
    }

    public func setFunctionalImpact(domain: SignalFunctionalDomain, severity: SignalImpactSeverity, userText: String? = nil) {
        draft.facts.functionalImpacts = [SignalFunctionalImpact(domain: domain, severity: severity, userText: userText)]
        draft.reviewedGroups.remove(.functionalImpact)
        draft.unknownGroups.remove(.functionalImpact)
        touch()
    }

    public func addBackgroundFact(category: SignalBackgroundCategory = .other, value: String) throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 1_000 else { throw SignalIntakeTransitionError.invalidValue }
        draft.facts.backgroundFacts.append(
            SignalBackgroundFact(category: category, value: normalized, source: .user, status: .candidate)
        )
        draft.reviewedGroups.remove(.background)
        touch()
    }

    public func setRawUserText(_ value: String?) throws {
        if let value, value.count > 4_000 { throw SignalIntakeTransitionError.invalidValue }
        draft.facts.rawUserText = value
        touch()
    }

    public func beginSafetyReview() throws {
        guard draft.phase == .collectingFacts else { throw SignalIntakeTransitionError.wrongPhase }
        guard !draft.locations.isEmpty else { throw SignalIntakeTransitionError.noLocations }
        try draft.validate()
        guard SignalIntakeDraft.requiredFactGroups.isSubset(of: draft.reviewedGroups) else {
            throw SignalIntakeTransitionError.requiredFactsMissing
        }
        draft.phase = .safetyReview
        draft.lastErrorCode = nil
        touch()
    }

    public func applySafety(_ state: SignalSafetyState) throws {
        guard draft.phase == .safetyReview else { throw SignalIntakeTransitionError.wrongPhase }
        try state.validate()
        draft.safety = state
        switch state.status {
        case .r0, .r1, .undetermined:
            draft.phase = .safetyAction
        case .r2, .noRuleTriggered:
            draft.phase = .agentDraft
        case .unavailable, .notRun:
            draft.phase = .offlineDraft
        }
        touch()
    }

    public func acknowledgeSafetyAction() throws {
        guard draft.phase == .safetyAction else { throw SignalIntakeTransitionError.wrongPhase }
        try draft.validate()
        draft.phase = .reviewFacts
        touch()
    }

    public func finishAgentDraft() throws {
        guard draft.phase == .agentDraft else { throw SignalIntakeTransitionError.wrongPhase }
        guard draft.safety.ordinaryAgentAllowed else { throw SignalIntakeTransitionError.ordinaryAgentSuppressed }
        try draft.validate()
        draft.phase = .reviewFacts
        touch()
    }

    public func requestApproval() throws {
        guard draft.phase == .reviewFacts else { throw SignalIntakeTransitionError.wrongPhase }
        guard draft.safety.status == .r2 || draft.safety.status == .noRuleTriggered else {
            throw SignalIntakeTransitionError.safetyNotComplete
        }
        guard SignalIntakeDraft.requiredFactGroups.isSubset(of: draft.reviewedGroups) else {
            throw SignalIntakeTransitionError.approvalNotReady
        }
        try draft.validate()
        draft.phase = .awaitingApproval
        touch()
    }

    public func returnToFactReview() throws {
        guard draft.phase == .awaitingApproval else { throw SignalIntakeTransitionError.wrongPhase }
        draft.phase = .reviewFacts
        touch()
    }

    /// Enters the offline-draft phase. P4's encrypted persistence adapter must
    /// be called by the application layer; this Core method does not claim a
    /// durable write by itself.
    public func saveOfflineDraft() throws {
        guard draft.phase == .collectingFacts || draft.phase == .reviewFacts || draft.phase == .safetyReview else {
            throw SignalIntakeTransitionError.wrongPhase
        }
        guard !draft.locations.isEmpty else { throw SignalIntakeTransitionError.noLocations }
        try draft.validate()
        draft.phase = .offlineDraft
        touch()
    }

    public func resumeOfflineDraft() throws {
        guard draft.phase == .offlineDraft else { throw SignalIntakeTransitionError.wrongPhase }
        draft.phase = draft.locations.isEmpty ? .choosingLocation : .collectingFacts
        draft.safety = SignalSafetyState()
        draft.lastErrorCode = nil
        touch()
    }

    public func fail(code: String, retryable: Bool = true) {
        draft.phase = .failed
        draft.lastErrorCode = code.isEmpty ? "unknown_error" : String(code.prefix(120))
        touch(incrementRevision: !retryable)
    }

    public func retryAfterFailure() throws {
        guard draft.phase == .failed else { throw SignalIntakeTransitionError.wrongPhase }
        draft.phase = draft.locations.isEmpty ? .choosingLocation : .collectingFacts
        draft.safety = SignalSafetyState()
        draft.lastErrorCode = nil
        touch()
    }

    public func reset() {
        draft = SignalIntakeDraft(sessionID: UUID())
        bodyMapModel.clearMarkers()
    }

    public func offlineFacts() -> UnconfirmedDraftFacts {
        draft.facts.asOfflineFacts
    }

    private func touch(incrementRevision: Bool = true) {
        if incrementRevision { draft.draftRevision += 1 }
        draft.updatedAt = .now
    }
}

private struct SignalIntakeCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private func rejectSignalIntakeUnknownKeys<K: CodingKey>(_ decoder: Decoder, allowed: [K]) throws {
    let container = try decoder.container(keyedBy: SignalIntakeCodingKey.self)
    let allowedKeys = Set(allowed.map(\.stringValue))
    let unknown = container.allKeys.map(\.stringValue).filter { !allowedKeys.contains($0) }
    guard unknown.isEmpty else {
        throw DecodingError.dataCorruptedError(
            forKey: container.allKeys.first ?? SignalIntakeCodingKey(stringValue: "unknown")!,
            in: container,
            debugDescription: "unknown signal intake field(s): \(unknown.joined(separator: ","))"
        )
    }
}
