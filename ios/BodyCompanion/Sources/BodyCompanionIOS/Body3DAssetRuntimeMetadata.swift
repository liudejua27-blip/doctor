import Foundation
import BodyCompanionCore

public struct Body3DCameraPresetMetadata: Hashable, Sendable {
    public let distanceMeters: Float
    public let fovDegrees: Float
    public let pitchDegrees: Float
    public let yawDegrees: Float

    public init(distanceMeters: Float, fovDegrees: Float, pitchDegrees: Float, yawDegrees: Float) {
        self.distanceMeters = distanceMeters
        self.fovDegrees = fovDegrees
        self.pitchDegrees = pitchDegrees
        self.yawDegrees = yawDegrees
    }
}

/// The result of resolving a collision face.  This is still a user-location
/// candidate; it is never an anatomical or medical assertion.
public struct Body3DRegionResolution: Hashable, Sendable {
    public let option: BodyRegionOption
    public let confidence: Double
    public let boundaryCandidates: [String]

    public init(option: BodyRegionOption, confidence: Double, boundaryCandidates: [String] = []) {
        self.option = option
        self.confidence = min(max(confidence, 0), 1)
        self.boundaryCandidates = boundaryCandidates
    }
}

public final class Body3DAssetRuntimeMetadata: @unchecked Sendable {
    public static let shared = Body3DAssetRuntimeMetadata()

    public let cameraPresets: [BodyCameraPreset: Body3DCameraPresetMetadata]
    public let collisionMeshID: String?
    public let collisionTriangleCount: Int
    public let loadedFromArtifacts: Bool

    private let faceRanges: [_FaceRange]
    private let meshResolutions: [String: Body3DRegionResolution]

    private static let regionMapFileName = "body-neutral-procedural-v1.region_map"
    private static let correspondenceFileName = "body-neutral-procedural-v1.surface_correspondence"
    private static let cameraPresetFileName = "body-neutral-procedural-v1.camera_presets"

    private init() {
        let parsed = Self.loadArtifacts()
        cameraPresets = parsed.cameraPresets
        collisionMeshID = parsed.collisionMeshID
        collisionTriangleCount = parsed.collisionTriangleCount
        loadedFromArtifacts = parsed.loadedFromArtifacts
        faceRanges = parsed.faceRanges
        meshResolutions = parsed.meshResolutions
    }

    /// Resolves a semantic mesh only for display/marker migration helpers. Hit
    /// resolution must use `resolveRegion(from:)` with a collision face.
    public func resolveRegion(forMeshID meshID: String) -> BodyRegionOption? {
        meshResolutions[meshID]?.option
    }

    /// A face index is mandatory for the 3D candidate. iOS 17 hit results that
    /// do not expose TriangleHit deliberately return nil and remain on the 2D
    /// or accessible-list path.
    public func resolveRegion(from evidence: BodyHitEvidence) -> Body3DRegionResolution? {
        guard loadedFromArtifacts,
              evidence.assetID == BodyAssetCandidateNeutralProcedural.assetID,
              evidence.assetVersion == BodyAssetCandidateNeutralProcedural.assetVersion,
              let meshID = evidence.meshID,
              meshID == collisionMeshID,
              let triangleIndex = evidence.triangleIndex else {
            return nil
        }
        return faceRanges.first {
            $0.meshID == meshID && triangleIndex >= $0.start && triangleIndex <= $0.end
        }.map {
            Body3DRegionResolution(
                option: $0.option,
                confidence: $0.confidence,
                boundaryCandidates: $0.boundaryCandidates
            )
        }
    }

    public func cameraPreset(_ preset: BodyCameraPreset) -> Body3DCameraPresetMetadata? {
        cameraPresets[preset]
    }

    private struct LoadedArtifactState {
        let faceRanges: [_FaceRange]
        let meshResolutions: [String: Body3DRegionResolution]
        let cameraPresets: [BodyCameraPreset: Body3DCameraPresetMetadata]
        let collisionMeshID: String?
        let collisionTriangleCount: Int
        let loadedFromArtifacts: Bool
    }

    private struct _FaceRange: Hashable, Sendable {
        let meshID: String
        let start: Int
        let end: Int
        let option: BodyRegionOption
        let confidence: Double
        let boundaryCandidates: [String]
    }

    private static func loadArtifacts() -> LoadedArtifactState {
        // Candidate assets are intentionally owned by the internal AppHost,
        // not by the reusable BodyCompanionIOS package product. A production
        // app therefore cannot ship these files accidentally; missing files
        // fail closed to the 2D path.
        guard let regionURL = Bundle.main.url(forResource: regionMapFileName, withExtension: "json"),
              let correspondenceURL = Bundle.main.url(forResource: correspondenceFileName, withExtension: "json"),
              let cameraPresetURL = Bundle.main.url(forResource: cameraPresetFileName, withExtension: "json") else {
            return LoadedArtifactState(faceRanges: [], meshResolutions: [:], cameraPresets: [:], collisionMeshID: nil, collisionTriangleCount: 0, loadedFromArtifacts: false)
        }

        do {
            let decoder = JSONDecoder()
            let regionPayload = try decoder.decode(_RegionMapPayload.self, from: Data(contentsOf: regionURL))
            let correspondencePayload = try decoder.decode(_SurfaceCorrespondencePayload.self, from: Data(contentsOf: correspondenceURL))
            let cameraPayload = try decoder.decode(_CameraPresetPayload.self, from: Data(contentsOf: cameraPresetURL))

            guard regionPayload.assetID == BodyAssetCandidateNeutralProcedural.assetID,
                  regionPayload.assetVersion == BodyAssetCandidateNeutralProcedural.assetVersion,
                  regionPayload.topologyID == BodyAssetCandidateNeutralProcedural.topologyID,
                  correspondencePayload.assetID == regionPayload.assetID,
                  correspondencePayload.assetVersion == regionPayload.assetVersion,
                  correspondencePayload.topologyID == regionPayload.topologyID,
                  correspondencePayload.collisionMeshID == regionPayload.collisionMeshID,
                  correspondencePayload.entries.count == regionPayload.entries.count else {
                throw _ArtifactError.identityMismatch
            }

            var ranges: [_FaceRange] = []
            var meshResolutions: [String: Body3DRegionResolution] = [:]
            var expectedFaceStart = 0
            for entry in regionPayload.entries.sorted(by: { $0.faceStart < $1.faceStart }) {
                guard !entry.meshID.isEmpty,
                      entry.collisionMeshID == regionPayload.collisionMeshID,
                      entry.faceStart == expectedFaceStart,
                      entry.faceEnd >= entry.faceStart,
                      entry.faceEnd < regionPayload.collisionTriangleCount,
                      let option = Self.option(regionID: entry.regionID, laterality: entry.laterality, surface: entry.surface) else {
                    throw _ArtifactError.invalidFaceRange
                }
                let candidates = entry.boundaryCandidates.map { "\($0.regionID)|\($0.laterality.rawValue)|\($0.surface.rawValue)" }
                ranges.append(_FaceRange(
                    meshID: entry.collisionMeshID,
                    start: entry.faceStart,
                    end: entry.faceEnd,
                    option: option,
                    confidence: entry.confidence,
                    boundaryCandidates: candidates
                ))
                meshResolutions[entry.meshID] = Body3DRegionResolution(option: option, confidence: entry.confidence, boundaryCandidates: candidates)
                expectedFaceStart = entry.faceEnd + 1
            }
            guard expectedFaceStart == regionPayload.collisionTriangleCount else {
                throw _ArtifactError.invalidFaceRange
            }

            let regionIDs = Set(regionPayload.entries.map { $0.regionID + "|" + $0.laterality.rawValue })
            let groupedCorrespondence = Dictionary(grouping: correspondencePayload.entries, by: \.renderMeshID)
            guard groupedCorrespondence.values.allSatisfy({ $0.count == 1 }) else {
                throw _ArtifactError.duplicateEntry
            }
            let correspondenceByMesh = groupedCorrespondence.compactMapValues(\.first)
            let correspondenceIDs = Set(correspondenceByMesh.keys)
            guard regionIDs.count == regionPayload.entries.count,
                  correspondenceIDs.count == correspondencePayload.entries.count,
                  correspondenceIDs == Set(regionPayload.entries.map(\.meshID)) else {
                throw _ArtifactError.duplicateEntry
            }
            for entry in regionPayload.entries {
                guard let correspondence = correspondenceByMesh[entry.meshID],
                      correspondence.collisionMeshID == regionPayload.collisionMeshID,
                      correspondence.collisionFaceRanges.count == 1,
                      correspondence.collisionFaceRanges[0].start == entry.faceStart,
                      correspondence.collisionFaceRanges[0].end == entry.faceEnd else {
                    throw _ArtifactError.invalidFaceRange
                }
            }

            var cameras: [BodyCameraPreset: Body3DCameraPresetMetadata] = [:]
            for preset in cameraPayload.presets {
                guard let name = BodyCameraPreset(rawValue: preset.name.lowercased()),
                      preset.distanceM.isFinite, preset.distanceM > 0,
                      preset.fovDeg.isFinite, preset.fovDeg > 0, preset.fovDeg < 180,
                      preset.pitchDeg.isFinite, preset.yawDeg.isFinite else {
                    throw _ArtifactError.invalidCameraPreset
                }
                cameras[name] = Body3DCameraPresetMetadata(
                    distanceMeters: Float(preset.distanceM),
                    fovDegrees: Float(preset.fovDeg),
                    pitchDegrees: Float(preset.pitchDeg),
                    yawDegrees: Float(preset.yawDeg)
                )
            }
            guard cameras.count == BodyCameraPreset.allCases.count else {
                throw _ArtifactError.invalidCameraPreset
            }
            return LoadedArtifactState(
                faceRanges: ranges,
                meshResolutions: meshResolutions,
                cameraPresets: cameras,
                collisionMeshID: regionPayload.collisionMeshID,
                collisionTriangleCount: regionPayload.collisionTriangleCount,
                loadedFromArtifacts: true
            )
        } catch {
            return LoadedArtifactState(faceRanges: [], meshResolutions: [:], cameraPresets: [:], collisionMeshID: nil, collisionTriangleCount: 0, loadedFromArtifacts: false)
        }
    }

    private static func option(regionID: String, laterality: Laterality, surface: BodySurface) -> BodyRegionOption? {
        BodyRegionCatalog.option(regionID: canonicalizeRegionID(regionID), laterality: laterality, surface: surface)
    }

    private static func canonicalizeRegionID(_ raw: String) -> String {
        if raw.contains(".") { return raw }
        let mapping: [String: String] = [
            "head": "body.head.general", "neck": "body.neck.general", "shoulder": "body.shoulder.general",
            "chest": "body.chest.general", "upper_back": "body.upper_back.general", "torso": "body.torso.general",
            "abdomen": "body.abdomen.general", "lower_back": "body.lower_back.general", "upper_arm": "body.upper_arm.general",
            "elbow": "body.elbow.general", "forearm": "body.forearm.general", "hand": "body.hand.general",
            "hip": "body.hip.general", "pelvis": "body.pelvis.general", "thigh": "body.thigh.general",
            "knee": "body.knee.general", "calf": "body.calf.general", "foot": "body.ankle_foot.general",
            "ankle_foot": "body.ankle_foot.general",
        ]
        return mapping[raw.trimmingCharacters(in: .whitespacesAndNewlines)] ?? raw
    }

    private enum _ArtifactError: Error {
        case identityMismatch
        case invalidFaceRange
        case duplicateEntry
        case invalidCameraPreset
    }

    private struct _RegionMapPayload: Decodable {
        let assetID: String
        let assetVersion: String
        let topologyID: String
        let collisionMeshID: String
        let collisionTriangleCount: Int
        let entries: [_RegionMapEntry]

        private enum CodingKeys: String, CodingKey {
            case assetID = "asset_id"
            case assetVersion = "asset_version"
            case topologyID = "topology_id"
            case collisionMeshID = "collision_mesh_id"
            case collisionTriangleCount = "collision_triangle_count"
            case entries
        }
    }

    private struct _BoundaryCandidate: Decodable {
        let regionID: String
        let laterality: Laterality
        let surface: BodySurface

        private enum CodingKeys: String, CodingKey {
            case regionID = "region_id"
            case laterality
            case surface
        }
    }

    private struct _RegionMapEntry: Decodable {
        let meshID: String
        let collisionMeshID: String
        let faceStart: Int
        let faceEnd: Int
        let regionID: String
        let laterality: Laterality
        let surface: BodySurface
        let confidence: Double
        let boundaryCandidates: [_BoundaryCandidate]

        private enum CodingKeys: String, CodingKey {
            case entryID = "entry_id"
            case meshID = "mesh_id"
            case collisionMeshID = "collision_mesh_id"
            case faceStart = "face_start"
            case faceEnd = "face_end"
            case regionID = "region_id"
            case laterality
            case surface
            case confidence
            case boundaryCandidates = "boundary_candidates"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            meshID = try values.decode(String.self, forKey: .meshID)
            collisionMeshID = try values.decode(String.self, forKey: .collisionMeshID)
            faceStart = try values.decode(Int.self, forKey: .faceStart)
            faceEnd = try values.decode(Int.self, forKey: .faceEnd)
            regionID = try values.decode(String.self, forKey: .regionID)
            laterality = try values.decode(Laterality.self, forKey: .laterality)
            surface = try values.decode(BodySurface.self, forKey: .surface)
            confidence = try values.decode(Double.self, forKey: .confidence)
            boundaryCandidates = try values.decode([_BoundaryCandidate].self, forKey: .boundaryCandidates)
        }
    }

    private struct _SurfaceCorrespondencePayload: Decodable {
        let assetID: String
        let assetVersion: String
        let topologyID: String
        let collisionMeshID: String
        let entries: [_SurfaceCorrespondenceEntry]

        private enum CodingKeys: String, CodingKey {
            case assetID = "asset_id"
            case assetVersion = "asset_version"
            case topologyID = "topology_id"
            case collisionMeshID = "collision_mesh_id"
            case entries
        }
    }

    private struct _SurfaceCorrespondenceEntry: Decodable {
        let renderMeshID: String
        let collisionMeshID: String
        let collisionFaceRanges: [_Range]

        private enum CodingKeys: String, CodingKey {
            case entryID = "entry_id"
            case renderMeshID = "render_mesh_id"
            case collisionMeshID = "collision_mesh_id"
            case renderTriangleRange = "render_triangle_range"
            case renderTriangleCount = "render_triangle_count"
            case renderVertexCount = "render_vertex_count"
            case collisionFaceRanges = "collision_face_ranges"
            case method
            case confidence
            case qualityStatus = "quality_status"
            case boundaryCandidates = "boundary_candidates"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            renderMeshID = try values.decode(String.self, forKey: .renderMeshID)
            collisionMeshID = try values.decode(String.self, forKey: .collisionMeshID)
            _ = try values.decode(_Range.self, forKey: .renderTriangleRange)
            _ = try values.decode(Int.self, forKey: .renderTriangleCount)
            _ = try values.decode(Int.self, forKey: .renderVertexCount)
            collisionFaceRanges = try values.decode([_Range].self, forKey: .collisionFaceRanges)
            _ = try values.decode(String.self, forKey: .method)
            _ = try values.decode(Double.self, forKey: .confidence)
            _ = try values.decode(String.self, forKey: .qualityStatus)
            _ = try values.decode([_BoundaryCandidate].self, forKey: .boundaryCandidates)
        }
    }

    private struct _Range: Decodable {
        let start: Int
        let end: Int
    }

    private struct _CameraPresetPayload: Decodable {
        let presets: [_CameraPresetEntry]
    }

    private struct _CameraPresetEntry: Decodable {
        let name: String
        let distanceM: Double
        let fovDeg: Double
        let pitchDeg: Double
        let yawDeg: Double

        private enum CodingKeys: String, CodingKey {
            case name
            case distanceM = "distance_m"
            case fovDeg = "fov_deg"
            case pitchDeg = "pitch_deg"
            case yawDeg = "yaw_deg"
        }
    }
}
