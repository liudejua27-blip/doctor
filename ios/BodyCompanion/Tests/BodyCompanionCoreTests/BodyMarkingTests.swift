import XCTest
@testable import BodyCompanionCore

@MainActor
final class BodyMarkingTests: XCTestCase {
    private func location(
        _ regionID: String = "body.knee.general",
        laterality: Laterality = .left
    ) -> BodyLocation {
        BodyLocationMapper.from2D(
            BodyRegionSelection(
                regionID: regionID,
                laterality: laterality,
                surface: .lateral,
                source: .bodyMap2D,
                view: .front,
                point: Point2D(x: 0.44, y: 0.77),
                userLabel: "左膝附近"
            )
        )
    }

    func testZoneSelectionIsVisualOnlyAndCyclesWithoutCreatingCheckIn() {
        let model = BodyMapModel()
        model.markingMode = .zone

        let first = model.applySelection(location())
        XCTAssertEqual(model.marks.count, 1)
        XCTAssertEqual(model.marks[0].zoneVisualState, .marked)
        XCTAssertEqual(model.marks[0].sensation, nil)
        XCTAssertEqual(model.marks[0].intensity, nil)

        let markerID = model.marks[0].id
        XCTAssertEqual(first, .added(markerID))
        XCTAssertEqual(model.applySelection(location()), .updated(markerID))
        XCTAssertEqual(model.marks[0].zoneVisualState, .reviewing)
        XCTAssertEqual(model.applySelection(location()), .removed(markerID))
        XCTAssertTrue(model.marks.isEmpty)
    }

    func testZoneAndPinModesPersistTogether() {
        let model = BodyMapModel()
        model.markingMode = .zone
        _ = model.applySelection(location("body.shoulder.general", laterality: .right))

        model.markingMode = .pin
        _ = model.applySelection(location("body.knee.general", laterality: .left))

        XCTAssertEqual(model.marks.count, 2)
        XCTAssertEqual(Set(model.marks.map(\.kind)), [.zone, .pin])
        XCTAssertEqual(model.marks.filter { $0.kind == .zone }.count, 1)
        XCTAssertEqual(model.marks.filter { $0.kind == .pin }.count, 1)
    }

    func testPinLimitIsTwentyAndDoesNotDiscardExistingMarks() {
        let model = BodyMapModel()
        model.markingMode = .pin

        for index in 0..<BodyMapModel.maximumPinCount {
            let side: Laterality = index.isMultiple(of: 2) ? .left : .right
            XCTAssertEqual(model.applySelection(location("body.knee.general", laterality: side)).isAdded, true)
        }

        XCTAssertEqual(model.marks.filter { $0.kind == .pin }.count, BodyMapModel.maximumPinCount)
        XCTAssertEqual(model.applySelection(location("body.head.general", laterality: .midline)), .rejectedPinLimit)
        XCTAssertEqual(model.marks.count, BodyMapModel.maximumPinCount)
        XCTAssertEqual(model.lastMutation, .rejectedPinLimit)
        model.clearInteractionNotice()
        XCTAssertNil(model.lastMutation)
    }

    func testExistingPinCanBeSelectedAndEdited() {
        let model = BodyMapModel()
        model.markingMode = .pin
        _ = model.applySelection(location("body.knee.general"))
        guard let id = model.selectedMarkID else {
            return XCTFail("new pin should be selected")
        }

        XCTAssertTrue(model.setSensation(.sharp, for: id))
        XCTAssertTrue(model.toggleTrigger(.walking, for: id))
        XCTAssertEqual(model.setIntensity(0, for: id), .updated(id))
        XCTAssertEqual(model.selectedMark()?.sensation, .sharp)
        XCTAssertEqual(model.selectedMark()?.triggers, [.walking])
        XCTAssertEqual(model.selectedMark()?.intensity, 0)
        XCTAssertEqual(model.setIntensity(10, for: id), .updated(id))
        XCTAssertEqual(model.setIntensity(11, for: id), .rejectedInvalidIntensity)
        XCTAssertEqual(model.selectedMark()?.intensity, 10)
    }

    func testExistingTwoDPinIsSelectedBeforeAddingAnother() {
        let model = BodyMapModel()
        model.markingMode = .pin
        let firstLocation = location()
        _ = model.applySelection(firstLocation)

        XCTAssertTrue(model.selectExistingPin(at: Point2D(x: 0.445, y: 0.775), view: .front))
        XCTAssertEqual(model.marks.count, 1)
        XCTAssertEqual(model.selectedMarkID, model.marks[0].id)
        XCTAssertEqual(model.focusedRegionID, "body.knee.general")
        XCTAssertFalse(model.selectExistingPin(at: Point2D(x: 0.1, y: 0.1), view: .front))
    }

    func testPinColorTokenIsNotBusinessState() {
        let model = BodyMapModel()
        model.markingMode = .pin
        _ = model.applySelection(location("body.knee.general", laterality: .left))
        _ = model.applySelection(location("body.knee.general", laterality: .right))

        XCTAssertEqual(model.marks.map(\.colorToken), [0, 1])
        XCTAssertNil(model.marks.first?.sensation)
        XCTAssertNil(model.marks.last?.intensity)
    }

    func testRemovingFocusedMarkClearsFocusButLeavesOtherRegion() {
        let model = BodyMapModel()
        model.markingMode = .zone
        _ = model.applySelection(location("body.knee.general"))
        let kneeID = model.marks[0].id
        _ = model.applySelection(location("body.shoulder.general", laterality: .right))
        XCTAssertEqual(model.focusedRegionID, "body.shoulder.general")

        model.removeDraft(id: kneeID)
        XCTAssertEqual(model.marks.count, 1)
        XCTAssertEqual(model.focusedRegionID, "body.shoulder.general")
        model.removeDraft(id: model.marks[0].id)
        XCTAssertNil(model.focusedRegionID)
    }

    func testBodyMarksProjectToTypedDraftWithoutConfirmingFacts() {
        let bodyMap = BodyMapModel()
        bodyMap.markingMode = .pin
        _ = bodyMap.applySelection(location())
        guard let id = bodyMap.selectedMarkID else { return XCTFail("pin should be selected") }
        _ = bodyMap.setSensation(.itchy, for: id)
        _ = bodyMap.toggleTrigger(.walking, for: id)
        _ = bodyMap.setIntensity(4, for: id)

        let intake = SignalIntakeModel(bodyMapModel: bodyMap)
        let initialRevision = intake.draft.draftRevision
        intake.applyBodyMarks(bodyMap.marks)

        XCTAssertEqual(intake.draft.draftRevision, initialRevision + 1)
        XCTAssertEqual(intake.draft.locations.map(\.id), [bodyMap.marks[0].location.id])
        XCTAssertEqual(intake.draft.facts.sensations.first?.code, .itching)
        XCTAssertEqual(intake.draft.facts.sensations.first?.locationMarkerIDs, [bodyMap.marks[0].location.id])
        XCTAssertEqual(intake.draft.facts.intensity?.value, 4)
        XCTAssertEqual(intake.draft.facts.aggravatingFactors.first?.label, "走路")
        XCTAssertFalse(intake.draft.reviewedGroups.contains(.sensation))
        XCTAssertFalse(intake.draft.reviewedGroups.contains(.intensity))
    }
}

private extension BodyMarkMutation {
    var isAdded: Bool {
        if case .added = self { return true }
        return false
    }
}
