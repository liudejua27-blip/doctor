import XCTest
@testable import BodyCompanionCore

final class BodyLocationTests: XCTestCase {
    func test2DSelectionProducesCanonicalLocation() {
        let markerID = UUID()
        let selection = BodyRegionSelection(
            regionID: "body.knee.general",
            laterality: .left,
            surface: .anterior,
            source: .bodyMap2D,
            view: .front,
            point: Point2D(x: 0.42, y: 0.64),
            userLabel: "左膝附近"
        )
        let location = BodyLocationMapper.from2D(selection, markerID: markerID)
        XCTAssertEqual(location.id, markerID)
        XCTAssertEqual(location.regionID, "body.knee.general")
        XCTAssertEqual(location.laterality, .left)
        XCTAssertEqual(location.source.interaction, .bodyMap2D)
        XCTAssertEqual(location.shape, .point)
        XCTAssertEqual(location.anchor2D?.point, Point2D(x: 0.42, y: 0.64))
        XCTAssertNil(location.anchor2D?.regionMaskID)
        XCTAssertFalse(location.mapping.reviewedByUser)
    }

    func test2DZoneSelectionProducesAreaAndRegionMaskWithoutPoint() {
        let location = BodyLocationMapper.from2D(
            BodyRegionSelection(
                regionID: "body.lower_back.general",
                laterality: .midline,
                surface: .posterior,
                source: .bodyMap2D,
                view: .back,
                userLabel: "下背部"
            )
        )

        XCTAssertEqual(location.shape, .area)
        XCTAssertEqual(location.anchor2D?.view, .back)
        XCTAssertNil(location.anchor2D?.point)
        XCTAssertEqual(location.anchor2D?.regionMaskID, "body.lower_back.general")
    }

    func testViewSwitchDoesNotChangeDomainIdentity() {
        let markerID = UUID()
        let front = BodyLocationMapper.from2D(
            BodyRegionSelection(
                regionID: "body.knee.general",
                laterality: .right,
                surface: .anterior,
                source: .bodyMap2D,
                view: .front,
                point: Point2D(x: 0.58, y: 0.64)
            ),
            markerID: markerID
        )
        let back = BodyLocationMapper.from2D(
            BodyRegionSelection(
                regionID: front.regionID,
                laterality: front.laterality,
                surface: .posterior,
                source: .bodyMap2D,
                view: .back,
                point: Point2D(x: 0.58, y: 0.64)
            ),
            markerID: markerID
        )
        XCTAssertEqual(front.id, back.id)
        XCTAssertEqual(front.regionID, back.regionID)
        XCTAssertEqual(front.laterality, back.laterality)
    }

    func test3DMappingStoresLocalEvidenceAndNeverWorldCoordinates() {
        let evidence = BodyHitEvidence(
            entityID: "body",
            localPosition: Point3D(x: 0.1, y: 0.2, z: 0.3),
            localNormal: Point3D(x: 0, y: 1, z: 0),
            triangleIndex: 7,
            barycentric: (0.2, 0.3, 0.5),
            assetID: "approved-asset-placeholder",
            assetVersion: "pending"
        )
        let location = BodyLocationMapper.from3D(
            evidence,
            regionID: "body.knee.general",
            laterality: .left,
            surface: .anterior
        )!
        XCTAssertEqual(location.anchor3D?.localPosition.x, 0.1)
        XCTAssertEqual(location.modelAsset?.assetID, "approved-asset-placeholder")
        XCTAssertEqual(location.anchor3D?.triangleIndex, 7)
        XCTAssertEqual(location.anchor3D?.barycentric, Barycentric(u: 0.2, v: 0.3, w: 0.5))
        XCTAssertNil(location.anchor3D?.meshID)
        XCTAssertNil(location.anchor3D?.uv)
        XCTAssertNil(location.anchor2D)
        XCTAssertFalse(location.mapping.reviewedByUser)
    }

    func test3DMappingAcceptsTriangleCoordinatesConvertedToThreeComponentBarycentric() {
        let triangleU = 0.25
        let triangleV = 0.35
        let evidence = BodyHitEvidence(
            entityID: "body_left_knee",
            localPosition: Point3D(x: 0.1, y: 0.2, z: 0.3),
            localNormal: Point3D(x: 0, y: 1, z: 0),
            triangleIndex: 12,
            barycentric: (triangleU, triangleV, 1 - triangleU - triangleV),
            uv: nil,
            assetID: "approved-asset-placeholder",
            assetVersion: "pending"
        )

        let location = BodyLocationMapper.from3D(
            evidence,
            regionID: "body.knee.general",
            laterality: .left,
            surface: .lateral
        )

        XCTAssertEqual(location?.anchor3D?.triangleIndex, 12)
        XCTAssertEqual(location?.anchor3D?.barycentric, Barycentric(u: 0.25, v: 0.35, w: 0.4))
        XCTAssertNil(location?.anchor3D?.uv)
    }

    func testEncodingUsesCanonicalBodyLocationEnvelope() throws {
        let selection = BodyRegionSelection(
            regionID: "body.knee.general",
            laterality: .left,
            surface: .anterior,
            source: .bodyMap2D,
            view: .front,
            point: Point2D(x: 0.42, y: 0.64)
        )
        let location = BodyLocationMapper.from2D(selection)
        let data = try JSONEncoder().encode(location)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["marker_id"])
        XCTAssertNotNil(object["anchor_2d"])
        XCTAssertNotNil(object["mapping"])
        XCTAssertNotNil(object["source"])
        XCTAssertNil(object["anchor_2d_point"])
        XCTAssertNil(object["model_asset_id"])
    }

    func testInvalid3DHitFallsBackInsteadOfCrashing() {
        let evidence = BodyHitEvidence(
            entityID: "body",
            localPosition: Point3D(x: 0, y: 0, z: 0),
            localNormal: Point3D(x: 0, y: 1, z: 0),
            triangleIndex: nil,
            barycentric: (0.2, 0.3, 0.5),
            assetID: "placeholder",
            assetVersion: "pending"
        )
        XCTAssertNil(
            BodyLocationMapper.from3D(
                evidence,
                regionID: "body.knee.general",
                laterality: .left,
                surface: .anterior
            )
        )
    }
}
