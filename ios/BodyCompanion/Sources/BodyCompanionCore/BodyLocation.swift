import Foundation

public enum Laterality: String, Codable, CaseIterable, Sendable {
    case left
    case right
    case midline
    case bilateral
    case unspecified
}

public enum BodySurface: String, Codable, CaseIterable, Sendable {
    case anterior
    case posterior
    case medial
    case lateral
    case superior
    case inferior
    case circumferential
    case unspecified
}

public enum BodyDepth: String, Codable, CaseIterable, Sendable {
    case superficial
    case deep
    case jointNearby = "joint_nearby"
    case unspecified
}

public enum BodyShape: String, Codable, Sendable {
    case point
    case area
    case path
}

public enum BodyMapSource: String, Codable, CaseIterable, Sendable {
    case bodyMap2D = "body_map_2d"
    case bodyMap3D = "body_map_3d"
    case bodyPartSearch = "body_part_search"
    case documentImport = "document_import"
    case agentNormalization = "agent_normalization"
}

public enum BodyMapView: String, Codable, CaseIterable, Sendable {
    case front
    case back
}

public enum BodyModelVariant: String, Codable, Sendable {
    case defaultNeutral = "default_neutral"
    case professionalMuscleJoint = "professional_muscle_joint"
}

public enum BodyCoordinateConvention: String, Codable, Sendable {
    case realityKitYUpRightHanded = "realitykit_y_up_right_handed"
}

public enum BodyMappingMethod: String, Codable, Sendable {
    case directUserSelection = "direct_user_selection"
    case assetRegionMap = "asset_region_map"
    case crossAssetMigration = "cross_asset_migration"
    case agentNormalization = "agent_normalization"
    case manualReview = "manual_review"
}

public struct Point2D: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }
}

public struct Point3D: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct Barycentric: Codable, Hashable, Sendable {
    public let u: Double
    public let v: Double
    public let w: Double

    public init(u: Double, v: Double, w: Double) {
        precondition(u >= 0 && v >= 0 && w >= 0 && u <= 1 && v <= 1 && w <= 1, "barycentric values must be within [0, 1]")
        self.u = u
        self.v = v
        self.w = w
    }
}

public struct UV: Codable, Hashable, Sendable {
    public let u: Double
    public let v: Double

    public init(u: Double, v: Double) {
        precondition(u >= 0 && v >= 0 && u <= 1 && v <= 1, "UV values must be within [0, 1]")
        self.u = u
        self.v = v
    }
}

public struct BodyLocationAnchor2D: Codable, Hashable, Sendable {
    public let view: BodyMapView
    public let assetID: String
    public let assetVersion: String
    public let point: Point2D?
    public let path: [Point2D]?
    public let regionMaskID: String?

    public init(
        view: BodyMapView,
        assetID: String,
        assetVersion: String,
        point: Point2D? = nil,
        path: [Point2D]? = nil,
        regionMaskID: String? = nil
    ) {
        precondition(point != nil || path != nil || regionMaskID != nil, "2D anchor requires a surface reference")
        self.view = view
        self.assetID = assetID
        self.assetVersion = assetVersion
        self.point = point
        self.path = path
        self.regionMaskID = regionMaskID
    }

    private enum CodingKeys: String, CodingKey {
        case view
        case assetID = "asset_id"
        case assetVersion = "asset_version"
        case point
        case path
        case regionMaskID = "region_mask_id"
    }
}

public struct BodyLocationAnchor3D: Codable, Hashable, Sendable {
    public let entityID: String
    public let meshID: String?
    public let localPosition: Point3D
    public let localNormal: Point3D
    public let triangleIndex: Int?
    public let barycentric: Barycentric?
    public let uv: UV?

    public init(
        entityID: String,
        meshID: String? = nil,
        localPosition: Point3D,
        localNormal: Point3D,
        triangleIndex: Int? = nil,
        barycentric: Barycentric? = nil,
        uv: UV? = nil
    ) {
        precondition((triangleIndex == nil) == (barycentric == nil), "triangle and barycentric must be paired")
        self.entityID = entityID
        self.meshID = meshID
        self.localPosition = localPosition
        self.localNormal = localNormal
        self.triangleIndex = triangleIndex
        self.barycentric = barycentric
        self.uv = uv
    }

    private enum CodingKeys: String, CodingKey {
        case entityID = "entity_id"
        case meshID = "mesh_id"
        case localPosition = "local_position"
        case localNormal = "local_normal"
        case triangleIndex = "triangle_index"
        case barycentric
        case uv
    }

    public static func == (lhs: BodyLocationAnchor3D, rhs: BodyLocationAnchor3D) -> Bool {
        lhs.entityID == rhs.entityID && lhs.meshID == rhs.meshID && lhs.localPosition == rhs.localPosition &&
            lhs.localNormal == rhs.localNormal && lhs.triangleIndex == rhs.triangleIndex &&
            lhs.barycentric?.u == rhs.barycentric?.u && lhs.barycentric?.v == rhs.barycentric?.v &&
            lhs.barycentric?.w == rhs.barycentric?.w && lhs.uv == rhs.uv
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(entityID)
        hasher.combine(meshID)
        hasher.combine(localPosition)
        hasher.combine(localNormal)
        hasher.combine(triangleIndex)
        hasher.combine(barycentric?.u)
        hasher.combine(barycentric?.v)
        hasher.combine(barycentric?.w)
        hasher.combine(uv)
    }
}

public struct BodyLocationModelAsset: Codable, Hashable, Sendable {
    public let assetID: String
    public let assetVersion: String
    public let variant: BodyModelVariant
    public let coordinateConvention: BodyCoordinateConvention

    public init(
        assetID: String,
        assetVersion: String,
        variant: BodyModelVariant,
        coordinateConvention: BodyCoordinateConvention = .realityKitYUpRightHanded
    ) {
        self.assetID = assetID
        self.assetVersion = assetVersion
        self.variant = variant
        self.coordinateConvention = coordinateConvention
    }

    private enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case assetVersion = "asset_version"
        case variant
        case coordinateConvention = "coordinate_convention"
    }
}

public struct BodyLocationMapping: Codable, Hashable, Sendable {
    public let method: BodyMappingMethod
    public let confidence: Double
    public let reviewedByUser: Bool
    public let migrationID: String?

    public init(method: BodyMappingMethod, confidence: Double, reviewedByUser: Bool, migrationID: String? = nil) {
        self.method = method
        self.confidence = min(max(confidence, 0), 1)
        self.reviewedByUser = reviewedByUser
        self.migrationID = migrationID
    }

    private enum CodingKeys: String, CodingKey {
        case method
        case confidence
        case reviewedByUser = "reviewed_by_user"
        case migrationID = "migration_id"
    }
}

public struct BodyLocationSource: Codable, Hashable, Sendable {
    public let interaction: BodyMapSource
    public let sourceTurnID: UUID?
    public let sourceDocumentID: UUID?

    public init(interaction: BodyMapSource, sourceTurnID: UUID? = nil, sourceDocumentID: UUID? = nil) {
        self.interaction = interaction
        self.sourceTurnID = sourceTurnID
        self.sourceDocumentID = sourceDocumentID
    }

    private enum CodingKeys: String, CodingKey {
        case interaction
        case sourceTurnID = "source_turn_id"
        case sourceDocumentID = "source_document_id"
    }
}

public struct BodyLocation: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let regionID: String
    public let ontologyVersion: String
    public let laterality: Laterality
    public let surface: BodySurface
    public let depth: BodyDepth
    public let shape: BodyShape
    public let userLabel: String?
    public let anchor2D: BodyLocationAnchor2D?
    public let anchor3D: BodyLocationAnchor3D?
    public let modelAsset: BodyLocationModelAsset?
    public let mapping: BodyLocationMapping
    public let source: BodyLocationSource
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        regionID: String,
        ontologyVersion: String,
        laterality: Laterality,
        surface: BodySurface,
        depth: BodyDepth,
        shape: BodyShape,
        userLabel: String? = nil,
        anchor2D: BodyLocationAnchor2D? = nil,
        anchor3D: BodyLocationAnchor3D? = nil,
        modelAsset: BodyLocationModelAsset? = nil,
        mapping: BodyLocationMapping,
        source: BodyLocationSource,
        createdAt: Date = .now
    ) {
        precondition(anchor3D == nil || modelAsset != nil, "3D anchor requires a model asset")
        if shape == .path {
            precondition(anchor2D?.path != nil, "path shape requires a 2D path anchor")
        }
        if shape == .point {
            precondition(anchor2D?.point != nil || anchor3D != nil, "point shape requires a point anchor")
        }
        if source.interaction == .bodyMap2D {
            precondition(anchor2D != nil, "2D body-map source requires a 2D anchor")
        }
        if source.interaction == .bodyMap3D {
            precondition(anchor3D != nil && modelAsset != nil, "3D body-map source requires anchor and asset")
        }
        self.id = id
        self.regionID = regionID
        self.ontologyVersion = ontologyVersion
        self.laterality = laterality
        self.surface = surface
        self.depth = depth
        self.shape = shape
        self.userLabel = userLabel
        self.anchor2D = anchor2D
        self.anchor3D = anchor3D
        self.modelAsset = modelAsset
        self.mapping = mapping
        self.source = source
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id = "marker_id"
        case regionID = "region_id"
        case ontologyVersion = "ontology_version"
        case laterality
        case surface
        case depth
        case shape
        case userLabel = "user_label"
        case anchor2D = "anchor_2d"
        case anchor3D = "anchor_3d"
        case modelAsset = "model_asset"
        case mapping
        case source
        case createdAt = "created_at"
    }
}

public struct BodyHitEvidence: Hashable, Sendable {
    public let entityID: String
    public let meshID: String?
    public let localPosition: Point3D
    public let localNormal: Point3D?
    public let triangleIndex: Int?
    public let barycentric: (Double, Double, Double)?
    public let uv: UV?
    public let assetID: String
    public let assetVersion: String

    public init(
        entityID: String,
        meshID: String? = nil,
        localPosition: Point3D,
        localNormal: Point3D? = nil,
        triangleIndex: Int? = nil,
        barycentric: (Double, Double, Double)? = nil,
        uv: UV? = nil,
        assetID: String,
        assetVersion: String
    ) {
        self.entityID = entityID
        self.meshID = meshID
        self.localPosition = localPosition
        self.localNormal = localNormal
        self.triangleIndex = triangleIndex
        self.barycentric = barycentric
        self.uv = uv
        self.assetID = assetID
        self.assetVersion = assetVersion
    }

    public static func == (lhs: BodyHitEvidence, rhs: BodyHitEvidence) -> Bool {
        lhs.entityID == rhs.entityID && lhs.meshID == rhs.meshID && lhs.localPosition == rhs.localPosition &&
            lhs.localNormal == rhs.localNormal && lhs.triangleIndex == rhs.triangleIndex &&
            lhs.barycentric?.0 == rhs.barycentric?.0 && lhs.barycentric?.1 == rhs.barycentric?.1 &&
            lhs.barycentric?.2 == rhs.barycentric?.2 &&
            lhs.uv?.u == rhs.uv?.u && lhs.uv?.v == rhs.uv?.v &&
            lhs.assetID == rhs.assetID && lhs.assetVersion == rhs.assetVersion
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(entityID)
        hasher.combine(meshID)
        hasher.combine(localPosition)
        hasher.combine(localNormal)
        hasher.combine(triangleIndex)
        hasher.combine(barycentric?.0)
        hasher.combine(barycentric?.1)
        hasher.combine(barycentric?.2)
        hasher.combine(uv?.u)
        hasher.combine(uv?.v)
        hasher.combine(assetID)
        hasher.combine(assetVersion)
    }
}

public struct BodyRegionSelection: Hashable, Sendable {
    public let regionID: String
    public let laterality: Laterality
    public let surface: BodySurface
    public let depth: BodyDepth
    public let source: BodyMapSource
    public let view: BodyMapView?
    public let point: Point2D?
    public let userLabel: String?

    public init(
        regionID: String,
        laterality: Laterality,
        surface: BodySurface,
        depth: BodyDepth = .unspecified,
        source: BodyMapSource,
        view: BodyMapView? = nil,
        point: Point2D? = nil,
        userLabel: String? = nil
    ) {
        self.regionID = regionID
        self.laterality = laterality
        self.surface = surface
        self.depth = depth
        self.source = source
        self.view = view
        self.point = point
        self.userLabel = userLabel
    }
}

public enum BodyLocationMapper {
    public static let ontologyVersion = BodyRegionCatalog.ontologyVersion

    public static func from2D(_ selection: BodyRegionSelection, markerID: UUID = UUID()) -> BodyLocation {
        let anchor = BodyLocationAnchor2D(
            view: selection.view ?? .front,
            assetID: BodyRegionCatalog.assetID,
            assetVersion: BodyRegionCatalog.assetVersion,
            point: selection.point,
            regionMaskID: selection.point == nil ? selection.regionID : nil
        )
        return BodyLocation(
            id: markerID,
            regionID: selection.regionID,
            ontologyVersion: ontologyVersion,
            laterality: selection.laterality,
            surface: selection.surface,
            depth: selection.depth,
            shape: selection.point == nil ? .area : .point,
            userLabel: selection.userLabel,
            anchor2D: anchor,
            mapping: BodyLocationMapping(method: .directUserSelection, confidence: 1, reviewedByUser: false),
            source: BodyLocationSource(interaction: selection.source)
        )
    }

    public static func from3D(
        _ evidence: BodyHitEvidence,
        regionID: String,
        laterality: Laterality,
        surface: BodySurface,
        depth: BodyDepth = .unspecified,
        mappingConfidence: Double = 0,
        markerID: UUID = UUID()
    ) -> BodyLocation? {
        guard let normal = evidence.localNormal else { return nil }
        if (evidence.triangleIndex == nil) != (evidence.barycentric == nil) {
            return nil
        }
        if let barycentric = evidence.barycentric {
            let sum = barycentric.0 + barycentric.1 + barycentric.2
            guard barycentric.0 >= 0, barycentric.1 >= 0, barycentric.2 >= 0,
                  barycentric.0 <= 1, barycentric.1 <= 1, barycentric.2 <= 1,
                  abs(sum - 1) <= 0.0001 else {
                return nil
            }
        }
        let barycentric = evidence.barycentric.map { Barycentric(u: $0.0, v: $0.1, w: $0.2) }
        let anchor = BodyLocationAnchor3D(
            entityID: evidence.entityID,
            meshID: evidence.meshID,
            localPosition: evidence.localPosition,
            localNormal: normal,
            triangleIndex: evidence.triangleIndex,
            barycentric: barycentric,
            uv: evidence.uv
        )
        return BodyLocation(
            id: markerID,
            regionID: regionID,
            ontologyVersion: ontologyVersion,
            laterality: laterality,
            surface: surface,
            depth: depth,
            shape: .point,
            anchor3D: anchor,
            modelAsset: BodyLocationModelAsset(
                assetID: evidence.assetID,
                assetVersion: evidence.assetVersion,
                variant: .defaultNeutral
            ),
            mapping: BodyLocationMapping(method: .assetRegionMap, confidence: mappingConfidence, reviewedByUser: false),
            source: BodyLocationSource(interaction: .bodyMap3D)
        )
    }
}
