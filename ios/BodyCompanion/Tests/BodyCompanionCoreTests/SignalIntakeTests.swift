import Foundation
import XCTest
@testable import BodyCompanionCore

@MainActor
final class SignalIntakeTests: XCTestCase {
    func testCannotLeaveLocationStepWithoutLocation() {
        let model = SignalIntakeModel()

        XCTAssertThrowsError(try model.beginSafetyReview()) { error in
            XCTAssertEqual(error as? SignalIntakeTransitionError, .wrongPhase)
        }
        XCTAssertEqual(model.phase, .choosingLocation)
    }

    func testExplicitUnknownRequiredFactsCanReachSafetyReview() throws {
        let model = SignalIntakeModel()
        model.setLocations([makeLocation()])
        XCTAssertFalse(model.markReviewed(.sensation))
        XCTAssertThrowsError(try model.beginSafetyReview())
        for group in SignalIntakeDraft.requiredFactGroups {
            model.markUnknown(group)
        }

        try model.beginSafetyReview()
        XCTAssertEqual(model.phase, .safetyReview)
        XCTAssertTrue(model.draft.unknownGroups.isSuperset(of: SignalIntakeDraft.requiredFactGroups))
    }

    func testUnavailableSafetyOnlyCreatesOfflineDraft() throws {
        let model = readyForSafety()
        try model.applySafety(
            SignalSafetyState(
                status: .unavailable,
                ordinaryAgentAllowed: false,
                displayMessage: "安全规则服务暂不可用；不继续普通分析。"
            )
        )

        XCTAssertEqual(model.phase, .offlineDraft)
        XCTAssertFalse(model.safety.ordinaryAgentAllowed)
        XCTAssertThrowsError(try model.requestApproval()) { error in
            XCTAssertEqual(error as? SignalIntakeTransitionError, .wrongPhase)
        }
    }

    func testR0SuppressesOrdinaryAgentAndPreservesReviewPath() throws {
        let model = readyForSafety()
        try model.applySafety(SignalSafetyState(status: .r0, ordinaryAgentAllowed: false))
        XCTAssertEqual(model.phase, .safetyAction)
        XCTAssertThrowsError(try model.finishAgentDraft())

        try model.acknowledgeSafetyAction()
        XCTAssertEqual(model.phase, .reviewFacts)
        try model.saveOfflineDraft()
        XCTAssertEqual(model.phase, .offlineDraft)
    }

    func testNoRuleTriggeredCanPrepareApprovalButIsNotSafetyClaim() throws {
        XCTAssertThrowsError(
            try SignalSafetyState(status: .noRuleTriggered, ordinaryAgentAllowed: true, displayMessage: "目前安全").validate()
        )
        let model = readyForSafety()
        try model.applySafety(
            SignalSafetyState(
                status: .noRuleTriggered,
                ordinaryAgentAllowed: true,
                displayMessage: "当前回答未触发已审核规则（不等于安全）"
            )
        )
        XCTAssertEqual(model.phase, .agentDraft)
        try model.finishAgentDraft()
        try model.requestApproval()

        XCTAssertEqual(model.phase, .awaitingApproval)
        try model.draft.validate()
        let encoded = try JSONEncoder().encode(model.draft)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["schema_version"] as? String, "1.1")
        let facts = try XCTUnwrap(object["facts"] as? [String: Any])
        XCTAssertNotNil(facts["aggravating_factors"])
        XCTAssertNotNil(facts["functional_impacts"])
        let sensations = try XCTUnwrap(facts["sensations"] as? [[String: Any]])
        XCTAssertEqual(sensations.count, 0)
        let safety = try XCTUnwrap(object["safety"] as? [String: Any])
        XCTAssertNotNil(safety["ordinary_agent_allowed"])
        XCTAssertNil(object["event_id"])
        XCTAssertNil(object["approval_id"])
        XCTAssertNil(object["report_id"])
    }

    func testCandidateSourceDoesNotBecomeConfirmedWhenReviewing() {
        var facts = SignalIntakeFacts()
        facts.sensations = [
            SignalSensation(code: .tightness, source: .agentCandidate, status: .candidate)
        ]
        var draft = SignalIntakeDraft(facts: facts)
        draft.reviewedGroups = [.sensation]

        XCTAssertEqual(draft.facts.sensations.first?.source, .agentCandidate)
        XCTAssertEqual(draft.facts.sensations.first?.status, .candidate)
    }

    func testOtherSensationRequiresUserLabelBeforeReview() throws {
        let model = SignalIntakeModel()
        model.setLocations([makeLocation()])
        model.toggleSensation(.other)
        XCTAssertFalse(model.markReviewed(.sensation))
        XCTAssertThrowsError(try model.beginSafetyReview())

        try model.setOtherSensationLabel("用户自定义感觉")
        XCTAssertTrue(model.markReviewed(.sensation))
    }

    func testIntensityRejectsOutOfRangeAndOfflineMappingKeepsUnknown() throws {
        XCTAssertThrowsError(try SignalIntensity(context: .current, value: 11)) { error in
            XCTAssertEqual(error as? SignalIntakeTransitionError, .invalidIntensity)
        }

        let model = SignalIntakeModel()
        model.setLocations([makeLocation()])
        model.markUnknown(.sensation)
        model.markUnknown(.intensity)
        model.markUnknown(.temporal)
        model.markUnknown(.functionalImpact)
        let offline = model.offlineFacts()
        XCTAssertTrue(offline.sensationCodes.isEmpty)
        XCTAssertNil(offline.intensity)
        XCTAssertEqual(offline.timePattern, "")
    }

    func testDraftRevisionAdvancesOnFactChanges() {
        let model = SignalIntakeModel()
        let initial = model.draft.draftRevision
        model.setLocations([makeLocation()])
        model.toggleSensation(.stiffness)
        XCTAssertGreaterThan(model.draft.draftRevision, initial)
    }

    func testSensationKeepsExplicitLocationMarkerRelation() {
        let model = SignalIntakeModel()
        let first = makeLocation()
        let second = makeLocation()
        model.setLocations([first, second])
        model.toggleSensation(.stiffness)

        XCTAssertEqual(model.draft.facts.sensations.first?.locationMarkerIDs, [first.id, second.id])

        model.removeLocation(id: second.id)
        XCTAssertEqual(model.draft.facts.sensations.first?.locationMarkerIDs, [first.id])
        XCTAssertFalse(model.draft.reviewedGroups.contains(.sensation))
    }

    func testDraftDecoderRejectsUnknownTopLevelField() throws {
        let encoded = try JSONEncoder().encode(SignalIntakeDraft())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["unexpected_field"] = true
        let data = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try JSONDecoder().decode(SignalIntakeDraft.self, from: data)) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("unknown P1D field should be rejected")
            }
        }
    }

    private func readyForSafety() -> SignalIntakeModel {
        let model = SignalIntakeModel()
        model.setLocations([makeLocation()])
        for group in SignalIntakeDraft.requiredFactGroups {
            model.markUnknown(group)
        }
        try! model.beginSafetyReview()
        return model
    }

    private func makeLocation() -> BodyLocation {
        BodyLocationMapper.from2D(
            BodyRegionSelection(
                regionID: "body.knee.general",
                laterality: .left,
                surface: .anterior,
                source: .bodyMap2D,
                view: .front,
                point: Point2D(x: 0.42, y: 0.64),
                userLabel: "左膝附近"
            )
        )
    }
}
