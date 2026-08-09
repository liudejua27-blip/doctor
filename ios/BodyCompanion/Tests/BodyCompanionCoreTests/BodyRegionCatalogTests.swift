import XCTest
@testable import BodyCompanionCore

final class BodyRegionCatalogTests: XCTestCase {
    func testFrontAndBackExposeStableFullBodyCatalog() {
        let front = BodyRegionCatalog.options(for: .front)
        let back = BodyRegionCatalog.options(for: .back)

        XCTAssertGreaterThanOrEqual(front.count, 20)
        XCTAssertGreaterThanOrEqual(back.count, 20)
        XCTAssertEqual(Set(front.map(\.id)).count, front.count)
        XCTAssertEqual(Set(back.map(\.id)).count, back.count)
        XCTAssertTrue(front.contains { $0.regionID == "body.chest.general" && $0.laterality == .left })
        XCTAssertTrue(back.contains { $0.regionID == "body.upper_back.general" && $0.laterality == .right })
    }

    func testHitTestingPrefersSpecificKneeAreaAndPreservesSide() {
        let left = BodyRegionCatalog.hitTest(point: Point2D(x: 0.445, y: 0.775), view: .front)
        let right = BodyRegionCatalog.hitTest(point: Point2D(x: 0.555, y: 0.775), view: .back)

        XCTAssertEqual(left?.regionID, "body.knee.general")
        XCTAssertEqual(left?.laterality, .left)
        XCTAssertEqual(right?.regionID, "body.knee.general")
        XCTAssertEqual(right?.laterality, .right)
    }

    func testEveryCatalogSelectionUsesVersioned2DAssetAndOntology() {
        for option in BodyRegionCatalog.all {
            let view: BodyMapView = option.frontGeometry == nil ? .back : .front
            let location = BodyLocationMapper.from2D(
                BodyRegionSelection(
                    regionID: option.regionID,
                    laterality: option.laterality,
                    surface: option.surface,
                    depth: option.depth,
                    source: .bodyMap2D,
                    view: view,
                    userLabel: option.label
                )
            )
            XCTAssertEqual(location.ontologyVersion, BodyRegionCatalog.ontologyVersion)
            XCTAssertEqual(location.anchor2D?.assetID, BodyRegionCatalog.assetID)
            XCTAssertEqual(location.anchor2D?.assetVersion, BodyRegionCatalog.assetVersion)
            XCTAssertEqual(location.shape, .area)
        }
    }

    func testLocalTextSearchMatchesChineseAndEnglishAfterCurrentViewFilter() {
        let frontKnees = BodyRegionCatalog.options(matching: " 膝 ", for: .front)
        let backKnees = BodyRegionCatalog.options(matching: "KNEE", for: .back)

        XCTAssertEqual(frontKnees.map(\.id), [
            "body.knee.general|left",
            "body.knee.general|right",
        ])
        XCTAssertEqual(backKnees.map(\.id), frontKnees.map(\.id))
        XCTAssertTrue(BodyRegionCatalog.options(matching: "upper back", for: .front).isEmpty)
        XCTAssertEqual(
            BodyRegionCatalog.options(matching: "   ", for: .front),
            BodyRegionCatalog.options(for: .front)
        )
    }

    func testLocalTextSearchReturnsNoMatchWithoutChangingCatalogVocabulary() {
        XCTAssertTrue(BodyRegionCatalog.options(matching: "not-a-catalog-region", for: .front).isEmpty)
        XCTAssertTrue(BodyRegionCatalog.options(matching: "not-a-catalog-region", for: .back).isEmpty)
    }

    func test3DResolverAcceptsOnlyStableProjectEntityNames() {
        XCTAssertEqual(BodyRegionCatalog.option(forEntityID: "body_left_knee")?.laterality, .left)
        XCTAssertEqual(BodyRegionCatalog.option(forEntityID: "body_right_forearm")?.regionID, "body.forearm.general")
        XCTAssertEqual(BodyRegionCatalog.option(forEntityID: "body_torso")?.regionID, "body.torso.general")
        XCTAssertEqual(BodyRegionCatalog.option(forEntityID: "body_pelvis")?.regionID, "body.pelvis.general")
        XCTAssertNil(BodyRegionCatalog.option(forEntityID: "arbitrary_mesh_17"))
    }

    func testSegmentedCandidateEntitiesMapToStableRegions() {
        XCTAssertEqual(BodyRegionCatalog.option(forEntityID: "body_left_chest")?.regionID, "body.chest.general")
        XCTAssertEqual(BodyRegionCatalog.option(forEntityID: "body_right_upper_back")?.surface, .posterior)
        XCTAssertEqual(BodyRegionCatalog.option(forEntityID: "body_left_shoulder")?.laterality, .left)
        XCTAssertEqual(BodyRegionCatalog.option(forEntityID: "body_right_hip")?.regionID, "body.hip.general")
    }
}
