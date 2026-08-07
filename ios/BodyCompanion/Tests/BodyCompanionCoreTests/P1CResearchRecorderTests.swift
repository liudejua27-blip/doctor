import Foundation
import XCTest
@testable import BodyCompanionCore

@MainActor
final class P1CResearchRecorderTests: XCTestCase {
    func testDisabledRecorderFailsClosedWithoutCreatingActiveTask() {
        let recorder = P1CResearchRecorder()

        XCTAssertThrowsError(
            try recorder.start(
                participantAlias: "synthetic-01",
                taskID: .runningKnee,
                buildVersion: "debug.1",
                entryMode: .twoD,
                startedAt: Date(timeIntervalSince1970: 10)
            )
        ) { error in
            XCTAssertEqual(error as? P1CResearchError, .disabled)
        }
        XCTAssertNil(recorder.activeRecordID)
        XCTAssertTrue(recorder.records.isEmpty)
    }

    func testCompletedRecordContainsOnlyBoundedMetadataAndStableDates() throws {
        let recorder = P1CResearchRecorder(enabled: true)
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let ended = started.addingTimeInterval(12.5)

        try recorder.start(
            participantAlias: "synthetic-01",
            taskID: .runningKnee,
            buildVersion: "debug.1",
            featureFlags: ["P1C_30S_UX_PROTOTYPE"],
            entryMode: .twoD,
            startedAt: started
        )
        try recorder.recordUnderstanding(.position, result: .correct)
        try recorder.recordUnderstanding(.unconfirmedBoundary, result: .correct)
        let record = try recorder.finish(outcome: .completed, endedAt: ended)

        XCTAssertEqual(record.duration, 12.5, accuracy: 0.001)
        XCTAssertEqual(record.outcome, .completed)
        XCTAssertNil(record.stopRule)
        let data = try JSONEncoder().encode(record)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schema_version"] as? String, "1.0")
        XCTAssertEqual(object["entry_mode"] as? String, "2d")
        XCTAssertEqual(object["started_at"] as? String, "2023-11-14T22:13:20.000Z")
        XCTAssertEqual(object["ended_at"] as? String, "2023-11-14T22:13:32.500Z")
        let serialized = String(data: data, encoding: .utf8)!.lowercased()
        for forbidden in ["raw_user_text", "sensation", "intensity", "user_id", "body_location", "prompt"] {
            XCTAssertFalse(serialized.contains(forbidden), "unexpected forbidden field: \(forbidden)")
        }
    }

    func testRecorderCapturesOnlyEnumsCountsAndFallback() throws {
        let recorder = P1CResearchRecorder(enabled: true)
        try recorder.start(
            participantAlias: "synthetic-02",
            taskID: .threeDFallback,
            buildVersion: "debug.2",
            featureFlags: ["P1C_AUX", "P1C_30S_UX_PROTOTYPE", "P1C_AUX"],
            entryMode: .threeD,
            startedAt: Date(timeIntervalSince1970: 20)
        )
        try recorder.recordError(.fallbackRestartRequired)
        try recorder.recordError(.locationMisunderstood)
        try recorder.recordUnderstanding(.safetyAction, result: .notAsked)
        try recorder.markFallbackUsed()
        try recorder.recordResearcherClarification()
        try recorder.recordResearcherClarification()

        let record = try recorder.finish(outcome: .cancelled, endedAt: Date(timeIntervalSince1970: 21))
        XCTAssertEqual(record.featureFlags, ["P1C_30S_UX_PROTOTYPE", "P1C_AUX"])
        XCTAssertEqual(record.errorCategories, [.fallbackRestartRequired, .locationMisunderstood].sorted { $0.rawValue < $1.rawValue })
        XCTAssertTrue(record.fallbackUsed)
        XCTAssertEqual(record.researcherClarificationCount, 2)
    }

    func testStopRuleCannotBeRecordedAsCompleted() throws {
        let recorder = makeRecorder()
        try recorder.triggerStop(.missedSafetyAction)

        XCTAssertThrowsError(try recorder.finish(outcome: .completed, endedAt: Date(timeIntervalSince1970: 2))) { error in
            XCTAssertEqual(error as? P1CResearchError, .stoppedTaskRequiresStoppedOutcome)
        }
        XCTAssertNotNil(recorder.activeRecordID)
        let record = try recorder.finish(outcome: .stopped, endedAt: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(record.outcome, .stopped)
        XCTAssertEqual(record.stopRule, .missedSafetyAction)
    }

    func testStoppedOutcomeRequiresStopRule() throws {
        let recorder = makeRecorder()
        XCTAssertThrowsError(try recorder.finish(outcome: .stopped, endedAt: Date(timeIntervalSince1970: 2))) { error in
            XCTAssertEqual(error as? P1CResearchError, .stoppedOutcomeRequiresStopRule)
        }
        XCTAssertTrue(recorder.records.isEmpty)
    }

    func testEndBeforeStartKeepsActiveTaskUnchanged() throws {
        let recorder = makeRecorder()
        XCTAssertThrowsError(try recorder.finish(outcome: .cancelled, endedAt: Date(timeIntervalSince1970: 0))) { error in
            XCTAssertEqual(error as? P1CResearchError, .invalidTimestamp)
        }
        XCTAssertNotNil(recorder.activeRecordID)
        XCTAssertTrue(recorder.records.isEmpty)
    }

    func testSecondTaskCannotOverwriteFirstTask() throws {
        let recorder = makeRecorder()
        XCTAssertThrowsError(
            try recorder.start(
                participantAlias: "synthetic-02",
                taskID: .deskNeckShoulder,
                buildVersion: "debug.1",
                entryMode: .list,
                startedAt: Date(timeIntervalSince1970: 1)
            )
        ) { error in
            XCTAssertEqual(error as? P1CResearchError, .activeTaskExists)
        }
        XCTAssertNotNil(recorder.activeRecordID)
    }

    func testDeleteIsIdempotentAndClearsActiveAndFinalizedRecords() throws {
        let recorder = makeRecorder()
        _ = try recorder.finish(outcome: .cancelled, endedAt: Date(timeIntervalSince1970: 2))
        try recorder.start(
            participantAlias: "synthetic-02",
            taskID: .deskNeckShoulder,
            buildVersion: "debug.1",
            entryMode: .list,
            startedAt: Date(timeIntervalSince1970: 3)
        )

        XCTAssertEqual(recorder.deleteAll(), 2)
        XCTAssertEqual(recorder.deleteAll(), 0)
        XCTAssertNil(recorder.activeRecordID)
        XCTAssertTrue(recorder.records.isEmpty)
    }

    func testDecoderRejectsUnknownFieldAndUnsupportedSchema() throws {
        let recorder = makeRecorder()
        let record = try recorder.finish(outcome: .cancelled, endedAt: Date(timeIntervalSince1970: 2))
        let encoded = try JSONEncoder().encode(record)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["unexpected_health_field"] = "not allowed"
        let unknownData = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(P1CUXResearchRecord.self, from: unknownData))

        object.removeValue(forKey: "unexpected_health_field")
        object["schema_version"] = "9.0"
        let versionData = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(P1CUXResearchRecord.self, from: versionData))
    }

    func testInvalidTokensAndFlagsFailBeforeCreatingTask() {
        let recorder = P1CResearchRecorder(enabled: true)
        XCTAssertThrowsError(
            try recorder.start(
                participantAlias: "has space",
                taskID: .runningKnee,
                buildVersion: "debug.1",
                entryMode: .twoD,
                startedAt: Date(timeIntervalSince1970: 1)
            )
        ) { error in
            XCTAssertEqual(error as? P1CResearchError, .invalidParticipantAlias)
        }
        XCTAssertThrowsError(
            try recorder.start(
                participantAlias: "synthetic-01",
                taskID: .runningKnee,
                buildVersion: "debug.1",
                featureFlags: ["P1C_30S_UX_PROTOTYPE", "raw-health"],
                entryMode: .twoD,
                startedAt: Date(timeIntervalSince1970: 1)
            )
        ) { error in
            XCTAssertEqual(error as? P1CResearchError, .invalidFeatureFlag)
        }
        XCTAssertThrowsError(
            try recorder.start(
                participantAlias: "synthetic/01",
                taskID: .runningKnee,
                buildVersion: "debug.1",
                entryMode: .twoD,
                startedAt: Date(timeIntervalSince1970: 1)
            )
        ) { error in
            XCTAssertEqual(error as? P1CResearchError, .invalidParticipantAlias)
        }
        XCTAssertNoThrow(
            try recorder.start(
                participantAlias: "synthetic-01",
                taskID: .runningKnee,
                buildVersion: "release+1/arm64",
                featureFlags: ["P1C_30S_UX_PROTOTYPE"],
                entryMode: .twoD,
                startedAt: Date(timeIntervalSince1970: 1)
            )
        )
        XCTAssertNotNil(recorder.activeRecordID)
    }

    private func makeRecorder() -> P1CResearchRecorder {
        let recorder = P1CResearchRecorder(enabled: true)
        try! recorder.start(
            participantAlias: "synthetic-01",
            taskID: .runningKnee,
            buildVersion: "debug.1",
            entryMode: .twoD,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        return recorder
    }
}
