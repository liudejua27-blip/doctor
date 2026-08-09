import Foundation
import XCTest
@testable import BodyCompanionCore

@MainActor
final class SignalIntakeTests: XCTestCase {
    func testEntryPolicyMakesResumeAndFreshStartExplicit() {
        let model = SignalIntakeModel()
        let initialDraftID = model.draft.sessionID

        XCTAssertFalse(model.hasResumableDraft)
        XCTAssertNil(model.resumeDestination)

        model.setLocations([makeLocation()])
        XCTAssertTrue(model.hasResumableDraft)
        XCTAssertEqual(model.resumeDestination, .structuredIntake)
        XCTAssertEqual(model.draft.sessionID, initialDraftID)

        model.reset()
        XCTAssertFalse(model.hasResumableDraft)
        XCTAssertNil(model.resumeDestination)
        XCTAssertNotEqual(model.draft.sessionID, initialDraftID)
    }

    func testRemovingTypedLocationAlsoRemovesItsMapDraft() {
        let location = makeLocation()
        let map = BodyMapModel()
        _ = map.addPin(location)
        let model = SignalIntakeModel(bodyMapModel: map)
        model.setLocations(map.markerDrafts)

        model.removeLocation(id: location.id)

        XCTAssertTrue(model.draft.locations.isEmpty)
        XCTAssertTrue(map.marks.isEmpty)
    }

    func testSetLocationsRejectsOverLimitCollectionWithoutTruncatingDraft() {
        let model = SignalIntakeModel()
        let existing = makeLocation()
        XCTAssertTrue(model.setLocations([existing]))
        let overLimit = (0...BodyMapModel.maximumMarkerCount).map { index in
            makeLocation(regionID: "body.test.region.\(index)")
        }

        XCTAssertFalse(model.setLocations(overLimit))
        XCTAssertEqual(model.draft.locations.map(\.id), [existing.id])

        XCTAssertFalse(model.setLocations([existing, existing]))
        XCTAssertEqual(model.draft.locations.map(\.id), [existing.id])
    }

    func testMapLocationSyncPreservesTypedFactsAndExplicitRelations() throws {
        let first = makeLocation()
        let second = makeLocation()
        let map = BodyMapModel()
        _ = map.addPin(first)
        let model = SignalIntakeModel(bodyMapModel: map)
        model.setLocations(map.markerDrafts)
        try model.setSensation(.stiffness, selected: true, locationMarkerIDs: [first.id])
        XCTAssertTrue(model.markReviewed(.sensation))
        try model.setIntensity(context: .current, value: 4)
        XCTAssertTrue(model.markReviewed(.intensity))
        try model.addFactor(label: "跑步", effect: .worse)

        _ = map.addPin(second)
        model.setLocations(map.markerDrafts)

        XCTAssertEqual(model.draft.locations.map(\.id), [first.id, second.id])
        XCTAssertEqual(model.draft.facts.sensations.first?.locationMarkerIDs, [first.id])
        XCTAssertEqual(model.draft.facts.intensity?.value, 4)
        XCTAssertEqual(model.draft.facts.aggravatingFactors.map(\.label), ["跑步"])
        XCTAssertFalse(model.draft.reviewedGroups.contains(.sensation))
        XCTAssertTrue(model.draft.reviewedGroups.contains(.intensity))
    }

    func testRemovingLastSensationLocationDropsInvalidRelationAndRequiresReview() throws {
        let first = makeLocation()
        let second = makeLocation()
        let model = SignalIntakeModel()
        model.setLocations([first, second])
        try model.setSensation(.stiffness, selected: true, locationMarkerIDs: [first.id])
        XCTAssertTrue(model.markReviewed(.sensation))

        model.removeLocation(id: first.id)

        XCTAssertEqual(model.draft.locations.map(\.id), [second.id])
        XCTAssertTrue(model.draft.facts.sensations.isEmpty)
        XCTAssertFalse(model.draft.reviewedGroups.contains(.sensation))
        XCTAssertFalse(model.draft.unknownGroups.contains(.sensation))
        XCTAssertNoThrow(try model.draft.validate())
    }

    func testAddingLocationInvalidatesGlobalUnknownSensationAnswer() {
        let first = makeLocation()
        let second = makeLocation()
        let model = SignalIntakeModel()
        model.setLocations([first])
        model.markUnknown(.sensation)
        XCTAssertTrue(model.draft.unknownGroups.contains(.sensation))

        model.setLocations([first, second])

        XCTAssertFalse(model.draft.reviewedGroups.contains(.sensation))
        XCTAssertFalse(model.draft.unknownGroups.contains(.sensation))
    }

    func testSameMarkerIDLocationReplacementSynchronizesMapAndRequiresSensationReviewAgain() throws {
        let first = makeLocation()
        let replacement = makeLocation(
            regionID: "body.shoulder.general",
            laterality: .right,
            markerID: first.id
        )
        let map = BodyMapModel()
        map.markingMode = .zone
        _ = map.applySelection(first)
        XCTAssertEqual(map.marks.count, 1)
        let model = SignalIntakeModel(bodyMapModel: map)
        XCTAssertTrue(model.setLocations(map.markerDrafts))
        try model.setSensation(.stiffness, selected: true, locationMarkerIDs: [first.id])
        XCTAssertTrue(model.markReviewed(.sensation))

        XCTAssertTrue(model.setLocations([replacement]))

        XCTAssertEqual(model.draft.locations.first?.regionID, "body.shoulder.general")
        XCTAssertEqual(map.markerDrafts, [replacement])
        XCTAssertEqual(map.marks.first?.kind, .zone)
        XCTAssertEqual(model.draft.facts.sensations.first?.locationMarkerIDs, [first.id])
        XCTAssertFalse(model.draft.reviewedGroups.contains(.sensation))
        XCTAssertFalse(model.draft.unknownGroups.contains(.sensation))
    }

    func testCanonicalLocationDeletionProjectsToMapAndRemovesEmptySensationRelation() throws {
        let first = makeLocation()
        let second = makeLocation(regionID: "body.shoulder.general", laterality: .right)
        let map = BodyMapModel()
        map.markingMode = .zone
        _ = map.applySelection(first)
        map.markingMode = .pin
        _ = map.applySelection(second)
        XCTAssertEqual(map.marks.count, 2)
        let model = SignalIntakeModel(bodyMapModel: map)
        XCTAssertTrue(model.setLocations(map.markerDrafts))
        try model.setSensation(.stiffness, selected: true, locationMarkerIDs: [first.id])
        XCTAssertTrue(model.markReviewed(.sensation))

        XCTAssertTrue(model.setLocations([second]))

        XCTAssertEqual(map.markerDrafts, [second])
        XCTAssertTrue(model.draft.facts.sensations.isEmpty)
        XCTAssertFalse(model.draft.reviewedGroups.contains(.sensation))
        XCTAssertFalse(model.draft.unknownGroups.contains(.sensation))
        XCTAssertNoThrow(try model.draft.validate())
    }

    func testTextRegionSelectionSynchronizesOneAreaRevisionAndDoesNotDuplicateIt() throws {
        let map = BodyMapModel()
        let model = SignalIntakeModel(bodyMapModel: map)
        map.markingMode = .pin
        let option = try XCTUnwrap(
            BodyRegionCatalog.options(matching: "knee", for: .front)
                .first { $0.regionID == "body.knee.general" && $0.laterality == .left }
        )
        let revisionBefore = model.draft.draftRevision

        if case .added = map.applyTextRegionSelection(option, view: .front) {
            // Expected: a first text selection creates one broad Zone draft.
        } else {
            XCTFail("first text selection should add one Zone draft")
        }
        XCTAssertTrue(model.setLocations(map.markerDrafts))
        let location = try XCTUnwrap(model.draft.locations.first)
        let revisionAfterFirstSelection = model.draft.draftRevision

        XCTAssertEqual(map.marks.first?.kind, .zone)
        XCTAssertEqual(model.draft.locations, map.markerDrafts)
        XCTAssertEqual(location.shape, .area)
        XCTAssertEqual(location.source.interaction, .bodyPartSearch)
        XCTAssertNil(location.anchor2D?.point)
        XCTAssertEqual(location.anchor2D?.regionMaskID, "body.knee.general")
        XCTAssertEqual(revisionAfterFirstSelection, revisionBefore + 1)

        XCTAssertEqual(map.applyTextRegionSelection(option, view: .front), .updated(map.marks[0].id))
        XCTAssertTrue(model.setLocations(map.markerDrafts))
        XCTAssertEqual(model.draft.draftRevision, revisionAfterFirstSelection)
        XCTAssertNoThrow(try model.draft.validate())
    }

    func testDecodedOrRestoredAgentDraftMustCarryNormalAgentSafety() throws {
        let malformed = SignalIntakeDraft(
            phase: .agentDraft,
            locations: [makeLocation()],
            safety: SignalSafetyState(status: .r2, ordinaryAgentAllowed: false)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        XCTAssertThrowsError(try decoder.decode(SignalIntakeDraft.self, from: encoder.encode(malformed))) { error in
            XCTAssertEqual(error as? SignalIntakeTransitionError, .ordinaryAgentSuppressed)
        }
        XCTAssertThrowsError(try SignalIntakeModel(restoring: malformed)) { error in
            XCTAssertEqual(error as? SignalIntakeTransitionError, .ordinaryAgentSuppressed)
        }
    }

    func testRestorationRequiresMapProjectionToMatchValidatedLocations() throws {
        let location = makeLocation()
        let draft = SignalIntakeDraft(locations: [location])

        XCTAssertThrowsError(try SignalIntakeModel(restoring: draft, bodyMapModel: BodyMapModel())) { error in
            XCTAssertEqual(error as? SignalIntakeTransitionError, .invalidValue)
        }

        let restored = try SignalIntakeModel(restoring: draft)
        XCTAssertEqual(restored.draft.locations, [location])
        XCTAssertEqual(restored.bodyMapModel.markerDrafts, [location])
    }

    func testLocationChangeInvalidatesSafetyAndDownstreamAgentPhase() throws {
        let model = readyForSafety()
        try model.applySafety(SignalSafetyState(status: .noRuleTriggered, ordinaryAgentAllowed: true))
        XCTAssertEqual(model.phase, .agentDraft)
        XCTAssertTrue(model.safety.ordinaryAgentAllowed)

        model.setLocations([model.draft.locations[0], makeLocation()])

        XCTAssertEqual(model.phase, .collectingFacts)
        XCTAssertEqual(model.safety.status, .notRun)
        XCTAssertFalse(model.safety.ordinaryAgentAllowed)
        XCTAssertThrowsError(try model.finishAgentDraft()) { error in
            XCTAssertEqual(error as? SignalIntakeTransitionError, .wrongPhase)
        }
    }

    func testRemovingLastLocationKeepsOtherUnconfirmedFactsVisibleAsResumableDraft() throws {
        let location = makeLocation()
        let model = SignalIntakeModel()
        model.setLocations([location])
        try model.setIntensity(context: .current, value: 4)

        model.removeLocation(id: location.id)

        XCTAssertEqual(model.phase, .choosingLocation)
        XCTAssertTrue(model.hasResumableDraft)
        XCTAssertEqual(model.resumeDestination, .bodyMap)
        XCTAssertEqual(model.draft.facts.intensity?.value, 4)
    }

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

    func testR2UsesProfessionalPreparationWithoutEnteringOrdinaryAgent() throws {
        XCTAssertThrowsError(
            try SignalSafetyState(status: .r2, ordinaryAgentAllowed: true).validate()
        )

        let model = readyForSafety()
        try model.applySafety(SignalSafetyState(status: .r2, ordinaryAgentAllowed: false))

        XCTAssertEqual(model.phase, .safetyAction)
        XCTAssertThrowsError(try model.finishAgentDraft()) { error in
            XCTAssertEqual(error as? SignalIntakeTransitionError, .wrongPhase)
        }

        try model.acknowledgeSafetyAction()
        XCTAssertEqual(model.phase, .reviewFacts)
        try model.requestApproval()
        XCTAssertEqual(model.phase, .awaitingApproval)
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

    func testSensationRequiresExplicitMultiLocationRelationAndDoesNotCopyOnLocationChange() throws {
        let model = SignalIntakeModel()
        let first = makeLocation()
        let second = makeLocation()
        model.setLocations([first, second])
        XCTAssertFalse(model.toggleSensation(.stiffness))
        XCTAssertTrue(model.draft.facts.sensations.isEmpty)

        try model.setSensation(.stiffness, selected: true, locationMarkerIDs: [first.id])
        XCTAssertEqual(model.draft.facts.sensations.first?.locationMarkerIDs, [first.id])

        let third = makeLocation()
        model.setLocations([first, second, third])
        XCTAssertEqual(model.draft.facts.sensations.first?.locationMarkerIDs, [first.id])

        try model.setSensation(.stiffness, selected: true, locationMarkerIDs: [first.id, third.id])
        XCTAssertEqual(model.draft.facts.sensations.first?.locationMarkerIDs, [first.id, third.id])

        model.removeLocation(id: third.id)
        XCTAssertEqual(model.draft.facts.sensations.first?.locationMarkerIDs, [first.id])
        XCTAssertFalse(model.draft.reviewedGroups.contains(.sensation))
    }

    func testSensationRejectsEmptyDuplicateAndUnknownMarkerRelations() {
        let model = SignalIntakeModel()
        let location = makeLocation()
        model.setLocations([location])

        XCTAssertThrowsError(try model.setSensation(.stiffness, selected: true, locationMarkerIDs: []))
        XCTAssertThrowsError(try model.setSensation(.stiffness, selected: true, locationMarkerIDs: [location.id, location.id]))
        XCTAssertThrowsError(try model.setSensation(.stiffness, selected: true, locationMarkerIDs: [UUID()]))
        XCTAssertTrue(model.draft.facts.sensations.isEmpty)
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

    private func makeLocation(
        regionID: String = "body.knee.general",
        laterality: Laterality = .left,
        markerID: UUID = UUID()
    ) -> BodyLocation {
        BodyLocationMapper.from2D(
            BodyRegionSelection(
                regionID: regionID,
                laterality: laterality,
                surface: .anterior,
                source: .bodyMap2D,
                view: .front,
                point: Point2D(x: 0.42, y: 0.64),
                userLabel: "左膝附近"
            ),
            markerID: markerID
        )
    }
}
