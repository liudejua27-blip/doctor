import Foundation

/// The only entry modes that P1-C research is allowed to compare.
public enum P1CEntryMode: String, Codable, CaseIterable, Hashable, Sendable {
    case twoD = "2d"
    case threeD = "3d"
    case list
}

public enum P1CTaskID: String, Codable, CaseIterable, Hashable, Sendable {
    case runningKnee = "UX-P1C-01"
    case deskNeckShoulder = "UX-P1C-02"
    case threeDFallback = "UX-P1C-03"
    case safetyActionFirst = "UX-P1C-04"
    case candidateCorrection = "UX-P1C-05"
}

public enum P1CResearchOutcome: String, Codable, CaseIterable, Sendable {
    case completed
    case stopped
    case cancelled
    case failed
}

public enum P1CErrorCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case locationMisunderstood = "location_misunderstood"
    case sensationConfused = "sensation_confused"
    case safetyActionDelayed = "safety_action_delayed"
    case ordinarySuggestionChosen = "ordinary_suggestion_chosen"
    case fallbackRestartRequired = "fallback_restart_required"
    case unconfirmedAsSaved = "unconfirmed_as_saved"
    case healthContentLogged = "health_content_logged"
    case accessibilityBlocked = "accessibility_blocked"
    case other
}

public enum P1CStopRule: String, Codable, CaseIterable, Hashable, Sendable {
    case missedSafetyAction = "missed_safety_action"
    case markerInterpretedAsDiagnosis = "marker_interpreted_as_diagnosis"
    case threeDFallbackBlocked = "three_d_fallback_blocked"
    case unconfirmedAsSaved = "unconfirmed_as_saved"
    case healthContentLogged = "health_content_logged"
    case accessibilityBlocked = "accessibility_blocked"
}

public enum P1CUnderstandingResult: String, Codable, CaseIterable, Sendable {
    case correct
    case incorrect
    case notAsked = "not_asked"
}

public enum P1CUnderstandingDimension: String, CaseIterable, Sendable {
    case position
    case safetyAction = "safety_action"
    case unconfirmedBoundary = "unconfirmed_boundary"
}

public enum P1CResearchError: String, Error, Equatable, Sendable {
    case disabled
    case activeTaskExists
    case noActiveTask
    case invalidParticipantAlias
    case invalidBuildVersion
    case invalidFeatureFlag
    case invalidTimestamp
    case tooManyErrorCategories
    case clarificationLimitExceeded
    case stoppedTaskRequiresStoppedOutcome
    case stoppedOutcomeRequiresStopRule
}

extension P1CResearchError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .disabled: "P1-C 研究记录功能未启用。"
        case .activeTaskExists: "已有一个 P1-C 任务正在记录。"
        case .noActiveTask: "当前没有正在记录的 P1-C 任务。"
        case .invalidParticipantAlias: "参与者别名只能包含受限字符。"
        case .invalidBuildVersion: "构建版本只能包含受限字符。"
        case .invalidFeatureFlag: "Feature flag 格式无效。"
        case .invalidTimestamp: "任务结束时间不能早于开始时间。"
        case .tooManyErrorCategories: "错误类别不能超过八个。"
        case .clarificationLimitExceeded: "研究员澄清次数不能超过 99 次。"
        case .stoppedTaskRequiresStoppedOutcome: "触发停止规则的任务不能记录为完成。"
        case .stoppedOutcomeRequiresStopRule: "stopped 结果必须带有停止规则。"
        }
    }
}

/// A finalized P1-C record. It intentionally has no health-content fields.
public struct P1CUXResearchRecord: Codable, Equatable, Identifiable, Sendable {
    public let schemaVersion: String
    public let id: UUID
    public let participantAlias: String
    public let taskID: P1CTaskID
    public let buildVersion: String
    public let featureFlags: [String]
    public let entryMode: P1CEntryMode
    public let startedAt: Date
    public let endedAt: Date
    public let outcome: P1CResearchOutcome
    public let errorCategories: [P1CErrorCategory]
    public let stopRule: P1CStopRule?
    public let positionUnderstanding: P1CUnderstandingResult
    public let safetyActionUnderstanding: P1CUnderstandingResult
    public let unconfirmedBoundaryUnderstanding: P1CUnderstandingResult
    public let fallbackUsed: Bool
    public let researcherClarificationCount: Int

    public var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }

    fileprivate init(active: ActiveP1CTask, endedAt: Date, outcome: P1CResearchOutcome) {
        schemaVersion = "1.0"
        id = active.id
        participantAlias = active.participantAlias
        taskID = active.taskID
        buildVersion = active.buildVersion
        featureFlags = active.featureFlags
        entryMode = active.entryMode
        startedAt = active.startedAt
        self.endedAt = endedAt
        self.outcome = outcome
        errorCategories = active.errorCategories.sorted { $0.rawValue < $1.rawValue }
        stopRule = active.stopRule
        positionUnderstanding = active.positionUnderstanding
        safetyActionUnderstanding = active.safetyActionUnderstanding
        unconfirmedBoundaryUnderstanding = active.unconfirmedBoundaryUnderstanding
        fallbackUsed = active.fallbackUsed
        researcherClarificationCount = active.researcherClarificationCount
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case id = "record_id"
        case participantAlias = "participant_alias"
        case taskID = "task_id"
        case buildVersion = "build_version"
        case featureFlags = "feature_flags"
        case entryMode = "entry_mode"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case outcome
        case errorCategories = "error_categories"
        case stopRule = "stop_rule"
        case positionUnderstanding = "position_understanding"
        case safetyActionUnderstanding = "safety_action_understanding"
        case unconfirmedBoundaryUnderstanding = "unconfirmed_boundary_understanding"
        case fallbackUsed = "fallback_used"
        case researcherClarificationCount = "researcher_clarification_count"
    }

    public func encode(to encoder: Encoder) throws {
        var all = encoder.container(keyedBy: CodingKeys.self)
        try all.encode(schemaVersion, forKey: .schemaVersion)
        try all.encode(id, forKey: .id)
        try all.encode(participantAlias, forKey: .participantAlias)
        try all.encode(taskID, forKey: .taskID)
        try all.encode(buildVersion, forKey: .buildVersion)
        try all.encode(featureFlags, forKey: .featureFlags)
        try all.encode(entryMode, forKey: .entryMode)
        try all.encode(Self.iso8601(startedAt), forKey: .startedAt)
        try all.encode(Self.iso8601(endedAt), forKey: .endedAt)
        try all.encode(outcome, forKey: .outcome)
        try all.encode(errorCategories, forKey: .errorCategories)
        try all.encode(stopRule, forKey: .stopRule)
        try all.encode(positionUnderstanding, forKey: .positionUnderstanding)
        try all.encode(safetyActionUnderstanding, forKey: .safetyActionUnderstanding)
        try all.encode(unconfirmedBoundaryUnderstanding, forKey: .unconfirmedBoundaryUnderstanding)
        try all.encode(fallbackUsed, forKey: .fallbackUsed)
        try all.encode(researcherClarificationCount, forKey: .researcherClarificationCount)
    }

    public init(from decoder: Decoder) throws {
        let allKeys = try decoder.container(keyedBy: AnyP1CCodingKey.self).allKeys
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        if allKeys.contains(where: { !allowed.contains($0.stringValue) }) {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown P1-C research field"))
        }

        let all = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try all.decode(String.self, forKey: .schemaVersion)
        guard schemaVersion == "1.0" else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unsupported P1-C research schema"))
        }
        id = try all.decode(UUID.self, forKey: .id)
        participantAlias = try all.decode(String.self, forKey: .participantAlias)
        taskID = try all.decode(P1CTaskID.self, forKey: .taskID)
        buildVersion = try all.decode(String.self, forKey: .buildVersion)
        featureFlags = try all.decode([String].self, forKey: .featureFlags)
        entryMode = try all.decode(P1CEntryMode.self, forKey: .entryMode)
        startedAt = try Self.parseISO8601(try all.decode(String.self, forKey: .startedAt), decoder: decoder)
        endedAt = try Self.parseISO8601(try all.decode(String.self, forKey: .endedAt), decoder: decoder)
        outcome = try all.decode(P1CResearchOutcome.self, forKey: .outcome)
        errorCategories = try all.decode([P1CErrorCategory].self, forKey: .errorCategories)
        stopRule = try all.decodeIfPresent(P1CStopRule.self, forKey: .stopRule)
        positionUnderstanding = try all.decode(P1CUnderstandingResult.self, forKey: .positionUnderstanding)
        safetyActionUnderstanding = try all.decode(P1CUnderstandingResult.self, forKey: .safetyActionUnderstanding)
        unconfirmedBoundaryUnderstanding = try all.decode(P1CUnderstandingResult.self, forKey: .unconfirmedBoundaryUnderstanding)
        fallbackUsed = try all.decode(Bool.self, forKey: .fallbackUsed)
        researcherClarificationCount = try all.decode(Int.self, forKey: .researcherClarificationCount)

        if endedAt < startedAt
            || !P1CResearchRecorder.isParticipantAlias(participantAlias)
            || !P1CResearchRecorder.isBuildVersion(buildVersion)
            || featureFlags.isEmpty
            || featureFlags.count > 16
            || !featureFlags.allSatisfy(P1CResearchRecorder.isFeatureFlag)
            || Set(featureFlags).count != featureFlags.count
            || errorCategories.count > 8
            || Set(errorCategories).count != errorCategories.count
            || researcherClarificationCount < 0
            || researcherClarificationCount > 99 {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "invalid P1-C research record relation"))
        }
        if outcome == .stopped && stopRule == nil || outcome == .completed && stopRule != nil {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "invalid P1-C stop relation"))
        }
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func parseISO8601(_ value: String, decoder: Decoder) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) { return date }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "invalid P1-C timestamp"))
    }
}

fileprivate struct ActiveP1CTask {
    let id: UUID
    let participantAlias: String
    let taskID: P1CTaskID
    let buildVersion: String
    let featureFlags: [String]
    let entryMode: P1CEntryMode
    let startedAt: Date
    var errorCategories: Set<P1CErrorCategory> = []
    var stopRule: P1CStopRule?
    var positionUnderstanding: P1CUnderstandingResult = .notAsked
    var safetyActionUnderstanding: P1CUnderstandingResult = .notAsked
    var unconfirmedBoundaryUnderstanding: P1CUnderstandingResult = .notAsked
    var fallbackUsed = false
    var researcherClarificationCount = 0
}

fileprivate struct AnyP1CCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

/// In-memory, metadata-only research recorder. It is not a product analytics
/// SDK, a health-data store, or evidence that P1-C research passed.
@MainActor
public final class P1CResearchRecorder {
    public static let featureFlag = "P1C_30S_UX_PROTOTYPE"

    public let enabled: Bool
    public private(set) var records: [P1CUXResearchRecord] = []
    public private(set) var activeRecordID: UUID?
    private var activeTask: ActiveP1CTask?

    public init(enabled: Bool = false) {
        self.enabled = enabled
    }

    public func start(
        participantAlias: String,
        taskID: P1CTaskID,
        buildVersion: String,
        featureFlags: [String] = [P1CResearchRecorder.featureFlag],
        entryMode: P1CEntryMode,
        startedAt: Date = Date()
    ) throws {
        try ensureEnabled()
        guard activeTask == nil else { throw P1CResearchError.activeTaskExists }
        guard Self.isParticipantAlias(participantAlias) else { throw P1CResearchError.invalidParticipantAlias }
        guard Self.isBuildVersion(buildVersion) else { throw P1CResearchError.invalidBuildVersion }
        let normalizedFlags = Array(Set(featureFlags)).sorted()
        guard normalizedFlags.count <= 16, !normalizedFlags.isEmpty, normalizedFlags.allSatisfy(Self.isFeatureFlag) else {
            throw P1CResearchError.invalidFeatureFlag
        }

        let task = ActiveP1CTask(
            id: UUID(),
            participantAlias: participantAlias,
            taskID: taskID,
            buildVersion: buildVersion,
            featureFlags: normalizedFlags,
            entryMode: entryMode,
            startedAt: startedAt
        )
        activeTask = task
        activeRecordID = task.id
    }

    public func recordError(_ category: P1CErrorCategory) throws {
        try ensureEnabled()
        guard activeTask != nil else { throw P1CResearchError.noActiveTask }
        if activeTask?.errorCategories.contains(category) == false,
           activeTask?.errorCategories.count == 8 {
            throw P1CResearchError.tooManyErrorCategories
        }
        activeTask?.errorCategories.insert(category)
    }

    public func recordUnderstanding(_ dimension: P1CUnderstandingDimension, result: P1CUnderstandingResult) throws {
        try ensureEnabled()
        guard activeTask != nil else { throw P1CResearchError.noActiveTask }
        switch dimension {
        case .position: activeTask?.positionUnderstanding = result
        case .safetyAction: activeTask?.safetyActionUnderstanding = result
        case .unconfirmedBoundary: activeTask?.unconfirmedBoundaryUnderstanding = result
        }
    }

    public func markFallbackUsed() throws {
        try ensureEnabled()
        guard activeTask != nil else { throw P1CResearchError.noActiveTask }
        activeTask?.fallbackUsed = true
    }

    public func recordResearcherClarification() throws {
        try ensureEnabled()
        guard activeTask != nil else { throw P1CResearchError.noActiveTask }
        guard activeTask?.researcherClarificationCount ?? 0 < 99 else {
            throw P1CResearchError.clarificationLimitExceeded
        }
        activeTask?.researcherClarificationCount += 1
    }

    public func triggerStop(_ rule: P1CStopRule) throws {
        try ensureEnabled()
        guard activeTask != nil else { throw P1CResearchError.noActiveTask }
        activeTask?.stopRule = rule
    }

    @discardableResult
    public func finish(outcome: P1CResearchOutcome, endedAt: Date = Date()) throws -> P1CUXResearchRecord {
        try ensureEnabled()
        guard let activeTask else { throw P1CResearchError.noActiveTask }
        guard endedAt >= activeTask.startedAt else { throw P1CResearchError.invalidTimestamp }
        if activeTask.stopRule != nil && outcome == .completed {
            throw P1CResearchError.stoppedTaskRequiresStoppedOutcome
        }
        if outcome == .stopped && activeTask.stopRule == nil {
            throw P1CResearchError.stoppedOutcomeRequiresStopRule
        }

        let record = P1CUXResearchRecord(active: activeTask, endedAt: endedAt, outcome: outcome)
        records.append(record)
        self.activeTask = nil
        activeRecordID = nil
        return record
    }

    /// Idempotently removes both finalized metadata and any active task.
    @discardableResult
    public func deleteAll() -> Int {
        let removed = records.count + (activeTask == nil ? 0 : 1)
        records.removeAll()
        activeTask = nil
        activeRecordID = nil
        return removed
    }

    private func ensureEnabled() throws {
        guard enabled else { throw P1CResearchError.disabled }
    }

    nonisolated fileprivate static func isParticipantAlias(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            isASCIIAlphaNumeric(scalar) || scalar == "." || scalar == "_" || scalar == "-"
        }
    }

    nonisolated fileprivate static func isBuildVersion(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 80 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            isASCIIAlphaNumeric(scalar) || scalar == "." || scalar == "_" || scalar == "+" || scalar == "-" || scalar == "/"
        }
    }

    nonisolated fileprivate static func isFeatureFlag(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 80 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 65 && scalar.value <= 90)
                || (scalar.value >= 48 && scalar.value <= 57)
                || scalar == "." || scalar == "_" || scalar == "-"
        }
    }

    nonisolated fileprivate static func isASCIIAlphaNumeric(_ scalar: Unicode.Scalar) -> Bool {
        (scalar.value >= 65 && scalar.value <= 90)
            || (scalar.value >= 97 && scalar.value <= 122)
            || (scalar.value >= 48 && scalar.value <= 57)
    }
}
