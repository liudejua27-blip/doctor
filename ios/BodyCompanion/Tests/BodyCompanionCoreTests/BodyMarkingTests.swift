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

    func testRepeatedZoneSelectionOnlySelectsExistingDraftWithoutCreatingCheckIn() {
        let model = BodyMapModel()
        model.markingMode = .zone

        let first = model.applySelection(location())
        XCTAssertEqual(model.marks.count, 1)
        XCTAssertEqual(model.marks[0].zoneVisualState, .marked)

        let markerID = model.marks[0].id
        XCTAssertEqual(first, .added(markerID))
        XCTAssertEqual(model.applySelection(location()), .updated(markerID))
        XCTAssertEqual(model.marks.count, 1)
        XCTAssertEqual(model.marks[0].id, markerID)
        XCTAssertEqual(model.marks[0].zoneVisualState, .marked)
        XCTAssertEqual(model.selectedMarkID, markerID)
        XCTAssertEqual(model.focusedRegionID, "body.knee.general")

        model.removeDraft(id: markerID)
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

    func testTotalMarkerLimitIsTwentyAcrossZoneAndPinWithoutDiscardingMarks() {
        let model = BodyMapModel()

        for index in 0..<BodyMapModel.maximumMarkerCount {
            let side: Laterality = index.isMultiple(of: 2) ? .left : .right
            model.markingMode = index.isMultiple(of: 2) ? .zone : .pin
            XCTAssertEqual(
                model.applySelection(location("body.test.region.\(index)", laterality: side)).isAdded,
                true
            )
        }

        XCTAssertEqual(model.marks.count, BodyMapModel.maximumMarkerCount)
        XCTAssertEqual(model.marks.filter { $0.kind == .zone }.count, 10)
        XCTAssertEqual(model.marks.filter { $0.kind == .pin }.count, 10)
        model.markingMode = .zone
        XCTAssertEqual(model.applySelection(location("body.test.extra.zone", laterality: .midline)), .rejectedMarkerLimit)
        model.markingMode = .pin
        XCTAssertEqual(model.applySelection(location("body.test.extra.pin", laterality: .midline)), .rejectedMarkerLimit)
        XCTAssertEqual(model.marks.count, BodyMapModel.maximumMarkerCount)
        XCTAssertEqual(model.lastMutation, .rejectedMarkerLimit)
        model.clearInteractionNotice()
        XCTAssertNil(model.lastMutation)
    }

    func testCanonicalLocationProjectionRejectsOverLimitWithoutTruncatingMarks() {
        let existing = location()
        let model = BodyMapModel(markerDrafts: [existing])
        let overLimit = (0...BodyMapModel.maximumMarkerCount).map { index in
            location("body.test.region.\(index)", laterality: index.isMultiple(of: 2) ? .left : .right)
        }

        XCTAssertFalse(model.synchronizeLocationProjection(overLimit))
        XCTAssertEqual(model.markerDrafts, [existing])
        XCTAssertEqual(model.lastMutation, .rejectedMarkerLimit)
    }

    func testDuplicateLocationIDIsRejectedBeforeMapAndDraftCanFork() {
        let firstLocation = location()
        let model = BodyMapModel()
        model.markingMode = .pin

        XCTAssertTrue(model.applySelection(firstLocation).isAdded)
        XCTAssertEqual(model.applySelection(firstLocation), .rejectedDuplicateLocation)
        XCTAssertEqual(model.marks.map(\.location.id), [firstLocation.id])
        XCTAssertEqual(model.lastMutation, .rejectedDuplicateLocation)

        let malformedRestore = BodyMapModel(markerDrafts: [firstLocation, firstLocation])
        XCTAssertTrue(malformedRestore.marks.isEmpty)
        XCTAssertEqual(malformedRestore.lastMutation, .rejectedDuplicateLocation)
    }

    func testExistingPinCanBeSelectedWithoutChangingItsLocation() {
        let model = BodyMapModel()
        model.markingMode = .pin
        _ = model.applySelection(location("body.knee.general"))
        guard let id = model.selectedMarkID else {
            return XCTFail("new pin should be selected")
        }

        let originalLocation = model.selectedMark()?.location
        model.selectMark(id: id)
        XCTAssertEqual(model.selectedMarkID, id)
        XCTAssertEqual(model.selectedMark()?.location, originalLocation)
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

}

private extension BodyMarkMutation {
    var isAdded: Bool {
        if case .added = self { return true }
        return false
    }
}
