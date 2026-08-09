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

    func testTextRegionSelectionAlwaysCreatesZoneAreaWhenPinModeIsActive() throws {
        let option = try XCTUnwrap(
            BodyRegionCatalog.options(matching: "膝", for: .front)
                .first { $0.regionID == "body.knee.general" && $0.laterality == .left }
        )
        let model = BodyMapModel()
        model.markingMode = .pin

        let first = model.applyTextRegionSelection(option, view: .front)
        let markerID = try XCTUnwrap(model.selectedMarkID)
        let mark = try XCTUnwrap(model.selectedMark())

        XCTAssertEqual(first, .added(markerID))
        XCTAssertEqual(model.markingMode, .pin)
        XCTAssertEqual(mark.kind, .zone)
        XCTAssertEqual(mark.location.shape, .area)
        XCTAssertEqual(mark.location.source.interaction, .bodyPartSearch)
        XCTAssertEqual(mark.location.anchor2D?.view, .front)
        XCTAssertNil(mark.location.anchor2D?.point)
        XCTAssertEqual(mark.location.anchor2D?.regionMaskID, "body.knee.general")
        XCTAssertNil(mark.location.anchor3D)
        XCTAssertNil(mark.location.modelAsset)
        XCTAssertEqual(mark.location.mapping.method, .directUserSelection)
        XCTAssertEqual(mark.location.mapping.confidence, 1)
        XCTAssertFalse(mark.location.mapping.reviewedByUser)

        XCTAssertEqual(model.applyTextRegionSelection(option, view: .front), .updated(markerID))
        XCTAssertEqual(model.marks.count, 1)
        XCTAssertEqual(model.marks.first?.kind, .zone)
    }

    func testThreeDReadyRequiresAnActiveRequestedLoad() {
        let model = BodyMapModel()

        model.mark3DReady(for: UUID())
        XCTAssertEqual(model.mode, .twoD)
        XCTAssertEqual(model.loadState, .interactive)

        model.mode = .threeD
        model.mark3DReady(for: UUID())
        XCTAssertEqual(model.loadState, .interactive)

        let firstAttempt = model.request3D()
        XCTAssertEqual(model.loadState, .loading)
        model.mark3DReady(for: firstAttempt)
        XCTAssertEqual(model.loadState, .loading)
        model.mark3DLoadAttempted(for: firstAttempt)
        XCTAssertTrue(model.hasRecordedCurrentThreeDLoadAttempt)
        model.mark3DReady(for: firstAttempt)
        XCTAssertEqual(model.loadState, .threeDReady)

        model.switchTo2D()
        XCTAssertEqual(model.mode, .twoD)
        XCTAssertEqual(model.loadState, .interactive)

        let replacementAttempt = model.request3D()
        model.mark3DLoadAttempted(for: replacementAttempt)
        model.mark3DReady(for: firstAttempt)
        model.mark3DFailed("stale", for: firstAttempt)
        XCTAssertEqual(model.mode, .threeD)
        XCTAssertEqual(model.loadState, .loading)
        model.mark3DReady(for: replacementAttempt)
        XCTAssertEqual(model.loadState, .threeDReady)
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
