import Foundation
import XCTest
@testable import BodyCompanionCore

final class BodyAssetManifestTests: XCTestCase {
    func testCandidateManifestIsValidButRuntimeFallsBack() throws {
        let manifest = try makeManifest(status: .candidate)

        XCTAssertEqual(manifest.releaseStatus, .candidate)
        XCTAssertEqual(
            BodyAssetRuntimeGate.evaluate(manifest, requestedVariant: .defaultNeutral),
            .fallback(.statusNotApproved)
        )
    }

    func testApprovedManifestProducesMetadataOnlyDecision() throws {
        let manifest = try makeManifest(status: .approved)

        XCTAssertEqual(
            BodyAssetRuntimeGate.evaluate(manifest, requestedVariant: .defaultNeutral),
            .metadataEligible(assetID: "synthetic-default", assetVersion: "1.0.0")
        )
    }

    func testApprovedManifestRequiresRightsAndReleaseEvidence() {
        XCTAssertThrowsError(try makeManifest(status: .approved, commercialUse: false)) { error in
            XCTAssertEqual(error as? BodyAssetManifestError, .approvedGateIncomplete)
        }
        XCTAssertThrowsError(try makeManifest(status: .approved, appStoreDistribution: false)) { error in
            XCTAssertEqual(error as? BodyAssetManifestError, .approvedGateIncomplete)
        }
        XCTAssertThrowsError(try makeManifest(status: .approved, signatureStatus: .unverified)) { error in
            XCTAssertEqual(error as? BodyAssetManifestError, .approvedGateIncomplete)
        }
    }

    func testCoordinateSystemMustUseTheDocumentedRealityKitConvention() {
        XCTAssertThrowsError(try makeManifest(status: .candidate, convention: "z_up_left_handed")) { error in
            XCTAssertEqual(error as? BodyAssetManifestError, .invalidCoordinateSystem)
        }
        XCTAssertThrowsError(try makeManifest(status: .candidate, rootOrigin: "camera_origin")) { error in
            XCTAssertEqual(error as? BodyAssetManifestError, .invalidCoordinateSystem)
        }
        XCTAssertThrowsError(try makeManifest(status: .candidate, canonicalTransform: Array(repeating: .infinity, count: 16))) { error in
            XCTAssertEqual(error as? BodyAssetManifestError, .invalidCoordinateSystem)
        }
    }

    func testRequiredArtifactsAndLODsAreLinked() {
        XCTAssertThrowsError(try makeManifest(status: .candidate, includeCollision: false)) { error in
            XCTAssertEqual(error as? BodyAssetManifestError, .missingRequiredArtifact)
        }
        XCTAssertThrowsError(try makeManifest(status: .candidate, includeLODRender: false)) { error in
            XCTAssertEqual(error as? BodyAssetManifestError, .invalidLOD)
        }
    }

    func testHashesAndArtifactIDsAreStrict() {
        XCTAssertThrowsError(try makeManifest(status: .candidate, sourceSHA256: "sha256:not-a-hash")) { error in
            XCTAssertEqual(error as? BodyAssetManifestError, .invalidHash)
        }
        XCTAssertThrowsError(try makeManifest(status: .candidate, duplicateArtifactID: true)) { error in
            XCTAssertEqual(error as? BodyAssetManifestError, .duplicateArtifactID)
        }
        XCTAssertThrowsError(try makeManifest(status: .candidate, topologyID: String(repeating: "t", count: 121))) { error in
            XCTAssertEqual(error as? BodyAssetManifestError, .invalidTopologyID)
        }
        XCTAssertThrowsError(try makeManifest(status: .candidate, artifactID: String(repeating: "r", count: 121))) { error in
            XCTAssertEqual(error as? BodyAssetManifestError, .invalidArtifact)
        }
        XCTAssertThrowsError(try makeManifest(status: .candidate, sourceURL: "ftp://synthetic.example/body")) { error in
            XCTAssertEqual(error as? BodyAssetManifestError, .invalidURL)
        }
    }

    func testProfessionalManifestCannotBeApprovedBeforeReviewAndPerformance() throws {
        let pending = try makeManifest(
            status: .candidate,
            variant: .professionalMuscleJoint,
            reviewStatus: .pending,
            performanceStatus: .pending
        )
        XCTAssertEqual(
            BodyAssetRuntimeGate.evaluate(pending, requestedVariant: .professionalMuscleJoint),
            .fallback(.statusNotApproved)
        )
        XCTAssertThrowsError(
            try makeManifest(
                status: .approved,
                variant: .professionalMuscleJoint,
                reviewStatus: .pending,
                performanceStatus: .pending
            )
        ) { error in
            XCTAssertEqual(error as? BodyAssetManifestError, .approvedGateIncomplete)
        }
    }

    func testBlockedAndRetiredManifestsAlwaysFallback() throws {
        for status in [BodyAssetReleaseStatus.blocked, .retired] {
            let manifest = try makeManifest(status: status)
            XCTAssertEqual(
                BodyAssetRuntimeGate.evaluate(manifest, requestedVariant: .defaultNeutral),
                .fallback(.statusNotApproved)
            )
        }
        XCTAssertEqual(
            BodyAssetRuntimeGate.evaluate(nil, requestedVariant: .defaultNeutral),
            .fallback(.noManifest)
        )
    }

    func testRequestedVariantMismatchFallsBackWithoutLoading() throws {
        let manifest = try makeManifest(status: .approved)

        XCTAssertEqual(
            BodyAssetRuntimeGate.evaluate(manifest, requestedVariant: .professionalMuscleJoint),
            .fallback(.requestedVariantMismatch)
        )
    }

    func testUnknownTopLevelFieldAndUnsupportedArtifactFormatAreRejected() throws {
        let manifest = try makeManifest(status: .candidate)
        let encoded = try JSONEncoder().encode(manifest)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["user_id"] = "should-never-be-here"
        let unknownData = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(BodyAssetManifest.self, from: unknownData)) { error in
            XCTAssertEqual(error as? BodyAssetManifestError, .unknownField)
        }

        var artifacts = try XCTUnwrap(object["artifacts"] as? [[String: Any]])
        artifacts[0]["format"] = "glb"
        object.removeValue(forKey: "user_id")
        object["artifacts"] = artifacts
        let unsupportedData = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(BodyAssetManifest.self, from: unsupportedData))
    }

    func testBodyMap2DRequiresRegionMapArtifact() throws {
        XCTAssertNoThrow(try makeManifest(status: .candidate, variant: .bodyMap2D, includeRegionMap: true))
        XCTAssertThrowsError(try makeManifest(status: .candidate, variant: .bodyMap2D, includeRegionMap: false)) { error in
            XCTAssertEqual(error as? BodyAssetManifestError, .missingRequiredArtifact)
        }
    }

    func testSameManifestIdentityProducesAnIdempotentDecision() throws {
        let manifest = try makeManifest(status: .approved)
        let first = BodyAssetRuntimeGate.evaluate(manifest, requestedVariant: .defaultNeutral)
        let second = BodyAssetRuntimeGate.evaluate(manifest, requestedVariant: .defaultNeutral)

        XCTAssertEqual(first, second)
        XCTAssertEqual(manifest.id, "synthetic-default")
        XCTAssertEqual(manifest.assetVersion, "1.0.0")
    }

    func testNestedUnknownFieldsAndMissingNullableKeysAreRejected() throws {
        let manifest = try makeManifest(status: .candidate)
        let encoded = try JSONEncoder().encode(manifest)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        var source = try XCTUnwrap(object["source"] as? [String: Any])
        source["raw_health_text"] = "must not cross the asset boundary"
        object["source"] = source
        let nestedUnknownData = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(BodyAssetManifest.self, from: nestedUnknownData)) { error in
            XCTAssertEqual(error as? BodyAssetManifestError, .unknownField)
        }

        var integrity = try XCTUnwrap(object["integrity"] as? [String: Any])
        integrity.removeValue(forKey: "signing_key_id")
        object["source"] = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])["source"]
        object["integrity"] = integrity
        let missingNullableKeyData = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(BodyAssetManifest.self, from: missingNullableKeyData)) { error in
            XCTAssertEqual(error as? BodyAssetManifestError, .invalidHash)
        }
    }

    private func makeManifest(
        status: BodyAssetReleaseStatus,
        variant: BodyAssetVariant = .defaultNeutral,
        topologyID: String = "synthetic-topology-v1",
        artifactID: String = "synthetic-render",
        sourceURL: String = "https://synthetic.example/body",
        licenseURL: String = "https://synthetic.example/license",
        commercialUse: Bool = true,
        appStoreDistribution: Bool = true,
        signatureStatus: BodyAssetSignatureStatus? = nil,
        reviewStatus: BodyAssetAnatomyReviewStatus? = nil,
        performanceStatus: BodyAssetPerformanceStatus? = nil,
        convention: String = "realitykit_y_up_right_handed",
        rootOrigin: String = "feet_midpoint_ground_projection",
        canonicalTransform: [Double] = [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        ],
        includeCollision: Bool = true,
        includeLODRender: Bool = true,
        includeRegionMap: Bool = true,
        duplicateArtifactID: Bool = false,
        sourceSHA256: String = "sha256:" + String(repeating: "0", count: 64)
    ) throws -> BodyAssetManifest {
        let timestamp = "2026-08-06T00:00:00.000Z"
        let isApproved = status == .approved
        let resolvedSignature = signatureStatus ?? (isApproved ? .verified : .unverified)
        let resolvedReview = reviewStatus ?? (isApproved ? .approved : .pending)
        let resolvedPerformance = performanceStatus ?? (isApproved ? .passed : .pending)
        let renderID = artifactID
        var artifacts = [
            BodyAssetArtifact(
                artifactID: renderID,
                role: .render,
                format: .usdz,
                uri: "bundle://synthetic/default.usdz",
                sha256: sourceSHA256 == "sha256:not-a-hash" ? sourceSHA256 : "sha256:" + String(repeating: "1", count: 64),
                required: true
            ),
        ]
        if includeCollision {
            artifacts.append(
                BodyAssetArtifact(
                    artifactID: duplicateArtifactID ? renderID : "synthetic-collision",
                    role: .collision,
                    format: .usdc,
                    uri: "bundle://synthetic/collision.usdc",
                    sha256: "sha256:" + String(repeating: "2", count: 64),
                    required: true
                )
            )
        }
        if variant == .bodyMap2D && includeRegionMap {
            artifacts.append(
                BodyAssetArtifact(
                    artifactID: "synthetic-region-map",
                    role: .regionMap,
                    format: .json,
                    uri: "bundle://synthetic/region-map.json",
                    sha256: "sha256:" + String(repeating: "3", count: 64),
                    required: true
                )
            )
        }

        return try BodyAssetManifest(
            assetID: variant == .professionalMuscleJoint ? "synthetic-professional" : (variant == .bodyMap2D ? "synthetic-2d" : "synthetic-default"),
            assetVersion: "1.0.0",
            variant: variant,
            topologyID: topologyID,
            releaseStatus: status,
            source: BodyAssetSource(
                author: "synthetic-author",
                publisher: "synthetic-publisher",
                sourceURL: sourceURL,
                obtainedAt: timestamp
            ),
            rights: BodyAssetRights(
                licenseName: "Synthetic License",
                licenseURL: licenseURL,
                commercialUse: commercialUse,
                appStoreDistribution: appStoreDistribution,
                modificationAllowed: true,
                derivativeDistributionAllowed: true,
                attributionRequired: true
            ),
            integrity: BodyAssetIntegrity(
                sourceSHA256: sourceSHA256,
                manifestSHA256: "sha256:" + String(repeating: "4", count: 64),
                signatureStatus: resolvedSignature,
                signingKeyID: resolvedSignature == .verified ? "synthetic-key" : nil
            ),
            coordinateSystem: BodyAssetCoordinateSystem(
                convention: convention,
                unit: "meter",
                rootOrigin: rootOrigin,
                canonicalTransform: canonicalTransform
            ),
            artifacts: artifacts,
            lods: [
                BodyAssetLOD(
                    lodID: "lod-0",
                    renderArtifactID: includeLODRender ? renderID : "missing-render",
                    triangleCount: 1200,
                    surfaceCorrespondenceVersion: "surface-v1"
                ),
            ],
            mappings: BodyAssetMappings(
                ontologyVersion: "body-ontology-v1",
                regionMapVersion: "region-map-v1",
                surfaceCorrespondenceVersion: "surface-v1",
                resolverVersion: "resolver-v1"
            ),
            review: BodyAssetReview(
                anatomyStatus: resolvedReview,
                reviewerAlias: "synthetic-review",
                reviewedAt: resolvedReview == .approved ? timestamp : nil,
                scope: "metadata fixture only"
            ),
            performance: BodyAssetPerformance(
                status: resolvedPerformance,
                targetDeviceFamily: "synthetic-device",
                coldStartMS: resolvedPerformance == .pending ? 0 : 80,
                p95HitMS: resolvedPerformance == .pending ? 0 : 4,
                minimumFPS: resolvedPerformance == .pending ? 0 : 60,
                memoryMB: resolvedPerformance == .pending ? 0 : 256
            ),
            attribution: BodyAssetAttribution(text: "Synthetic fixture", placement: "app_about"),
            fallback: BodyAssetFallback(fallbackKind: .bodyMap2D, fallbackAssetID: nil),
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }
}
