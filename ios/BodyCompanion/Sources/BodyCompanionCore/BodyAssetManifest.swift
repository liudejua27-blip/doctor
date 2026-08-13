import Foundation

public enum BodyAssetVariant: String, Codable, CaseIterable, Sendable {
    case defaultNeutral = "default_neutral"
    case professionalMuscleJoint = "professional_muscle_joint"
    case bodyMap2D = "body_map_2d"
}

public enum BodyAssetReleaseStatus: String, Codable, CaseIterable, Sendable {
    case candidate
    case approved
    case blocked
    case retired
}

public enum BodyAssetSignatureStatus: String, Codable, CaseIterable, Sendable {
    case unverified
    case verified
    case revoked
}

public enum BodyAssetAnatomyReviewStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case approved
    case rejected
}

public enum BodyAssetPerformanceStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case passed
    case failed
}

public enum BodyAssetArtifactRole: String, Codable, CaseIterable, Sendable {
    case render
    case collision
    case texture
    case regionMap = "region_map"
    case surfaceCorrespondence = "surface_correspondence"
    case cameraPreset = "camera_preset"
}

public enum BodyAssetArtifactFormat: String, Codable, CaseIterable, Sendable {
    case usdz
    case usdc
    case json
    case png
    case jpg
    case bin
}

public enum BodyAssetFallbackKind: String, Codable, CaseIterable, Sendable {
    case bodyMap2D = "body_map_2d"
    case defaultNeutral = "default_neutral"
    case accessibleList = "accessible_list"
}

public enum BodyAssetCandidateNeutralProcedural {
    public static let assetID = "body-neutral-procedural-v1"
    public static let assetVersion = "1.2.0"
    public static let topologyID = "body-neutral-procedural-topology-v2"
    public static let modelResourceName = "BodyNeutralPrototype"
    public static let modelResourceExtension = "usdz"
    public static let collisionResourceName = "BodyNeutralPrototypeCollision"
    public static let collisionResourceExtension = "usdz"
    public static let collisionMeshID = "body_collision_v1"

    // Canonical-space constants are frozen with assetVersion/topologyID. They
    // must be revised together instead of being inferred from runtime bounds.
    public static let canonicalHeightMeters: Float = 1.86
    public static let canonicalGroundYMeters: Float = 0
}

public enum BodyAssetManifestError: String, Error, Equatable, Sendable {
    case unsupportedSchemaVersion
    case invalidAssetID
    case invalidAssetVersion
    case invalidTopologyID
    case invalidURL
    case invalidTimestamp
    case invalidHash
    case invalidCoordinateSystem
    case invalidArtifact
    case duplicateArtifactID
    case missingRequiredArtifact
    case invalidLOD
    case duplicateLODID
    case invalidMappings
    case invalidReview
    case invalidPerformance
    case invalidAttribution
    case invalidFallback
    case approvedGateIncomplete
    case unknownField
}

public struct BodyAssetSource: Codable, Equatable, Hashable, Sendable {
    public let author: String
    public let publisher: String
    public let sourceURL: String
    public let obtainedAt: String

    public init(author: String, publisher: String, sourceURL: String, obtainedAt: String) {
        self.author = author
        self.publisher = publisher
        self.sourceURL = sourceURL
        self.obtainedAt = obtainedAt
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case author
        case publisher
        case sourceURL = "source_url"
        case obtainedAt = "obtained_at"
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownBodyAssetKeys(decoder, allowed: CodingKeys.allCases)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        author = try values.decode(String.self, forKey: .author)
        publisher = try values.decode(String.self, forKey: .publisher)
        sourceURL = try values.decode(String.self, forKey: .sourceURL)
        obtainedAt = try values.decode(String.self, forKey: .obtainedAt)
    }
}

public struct BodyAssetRights: Codable, Equatable, Hashable, Sendable {
    public let licenseName: String
    public let licenseURL: String
    public let commercialUse: Bool
    public let appStoreDistribution: Bool
    public let modificationAllowed: Bool
    public let derivativeDistributionAllowed: Bool
    public let attributionRequired: Bool

    public init(
        licenseName: String,
        licenseURL: String,
        commercialUse: Bool,
        appStoreDistribution: Bool,
        modificationAllowed: Bool,
        derivativeDistributionAllowed: Bool,
        attributionRequired: Bool
    ) {
        self.licenseName = licenseName
        self.licenseURL = licenseURL
        self.commercialUse = commercialUse
        self.appStoreDistribution = appStoreDistribution
        self.modificationAllowed = modificationAllowed
        self.derivativeDistributionAllowed = derivativeDistributionAllowed
        self.attributionRequired = attributionRequired
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case licenseName = "license_name"
        case licenseURL = "license_url"
        case commercialUse = "commercial_use"
        case appStoreDistribution = "app_store_distribution"
        case modificationAllowed = "modification_allowed"
        case derivativeDistributionAllowed = "derivative_distribution_allowed"
        case attributionRequired = "attribution_required"
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownBodyAssetKeys(decoder, allowed: CodingKeys.allCases)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        licenseName = try values.decode(String.self, forKey: .licenseName)
        licenseURL = try values.decode(String.self, forKey: .licenseURL)
        commercialUse = try values.decode(Bool.self, forKey: .commercialUse)
        appStoreDistribution = try values.decode(Bool.self, forKey: .appStoreDistribution)
        modificationAllowed = try values.decode(Bool.self, forKey: .modificationAllowed)
        derivativeDistributionAllowed = try values.decode(Bool.self, forKey: .derivativeDistributionAllowed)
        attributionRequired = try values.decode(Bool.self, forKey: .attributionRequired)
    }
}

public struct BodyAssetIntegrity: Codable, Equatable, Hashable, Sendable {
    public let sourceSHA256: String
    public let manifestSHA256: String
    public let signatureStatus: BodyAssetSignatureStatus
    public let signingKeyID: String?

    public init(sourceSHA256: String, manifestSHA256: String, signatureStatus: BodyAssetSignatureStatus, signingKeyID: String?) {
        self.sourceSHA256 = sourceSHA256
        self.manifestSHA256 = manifestSHA256
        self.signatureStatus = signatureStatus
        self.signingKeyID = signingKeyID
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceSHA256 = "source_sha256"
        case manifestSHA256 = "manifest_sha256"
        case signatureStatus = "signature_status"
        case signingKeyID = "signing_key_id"
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(sourceSHA256, forKey: .sourceSHA256)
        try values.encode(manifestSHA256, forKey: .manifestSHA256)
        try values.encode(signatureStatus, forKey: .signatureStatus)
        try values.encode(signingKeyID, forKey: .signingKeyID)
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownBodyAssetKeys(decoder, allowed: CodingKeys.allCases)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sourceSHA256 = try values.decode(String.self, forKey: .sourceSHA256)
        manifestSHA256 = try values.decode(String.self, forKey: .manifestSHA256)
        signatureStatus = try values.decode(BodyAssetSignatureStatus.self, forKey: .signatureStatus)
        guard values.contains(.signingKeyID) else { throw BodyAssetManifestError.invalidHash }
        signingKeyID = try values.decodeIfPresent(String.self, forKey: .signingKeyID)
    }
}

public struct BodyAssetCoordinateSystem: Codable, Equatable, Hashable, Sendable {
    public let convention: String
    public let unit: String
    public let rootOrigin: String
    public let canonicalTransform: [Double]

    public init(convention: String, unit: String, rootOrigin: String, canonicalTransform: [Double]) {
        self.convention = convention
        self.unit = unit
        self.rootOrigin = rootOrigin
        self.canonicalTransform = canonicalTransform
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case convention
        case unit
        case rootOrigin = "root_origin"
        case canonicalTransform = "canonical_transform"
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownBodyAssetKeys(decoder, allowed: CodingKeys.allCases)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        convention = try values.decode(String.self, forKey: .convention)
        unit = try values.decode(String.self, forKey: .unit)
        rootOrigin = try values.decode(String.self, forKey: .rootOrigin)
        canonicalTransform = try values.decode([Double].self, forKey: .canonicalTransform)
    }
}

public struct BodyAssetArtifact: Codable, Equatable, Hashable, Sendable {
    public let artifactID: String
    public let role: BodyAssetArtifactRole
    public let format: BodyAssetArtifactFormat
    public let uri: String
    public let sha256: String
    public let required: Bool
    public let meshID: String?
    public let triangleCount: Int?
    public let geometrySHA256: String?

    public init(
        artifactID: String,
        role: BodyAssetArtifactRole,
        format: BodyAssetArtifactFormat,
        uri: String,
        sha256: String,
        required: Bool,
        meshID: String? = nil,
        triangleCount: Int? = nil,
        geometrySHA256: String? = nil
    ) {
        self.artifactID = artifactID
        self.role = role
        self.format = format
        self.uri = uri
        self.sha256 = sha256
        self.required = required
        self.meshID = meshID
        self.triangleCount = triangleCount
        self.geometrySHA256 = geometrySHA256
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case artifactID = "artifact_id"
        case role
        case format
        case uri
        case sha256
        case required
        case meshID = "mesh_id"
        case triangleCount = "triangle_count"
        case geometrySHA256 = "geometry_sha256"
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownBodyAssetKeys(decoder, allowed: CodingKeys.allCases)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        artifactID = try values.decode(String.self, forKey: .artifactID)
        role = try values.decode(BodyAssetArtifactRole.self, forKey: .role)
        format = try values.decode(BodyAssetArtifactFormat.self, forKey: .format)
        uri = try values.decode(String.self, forKey: .uri)
        sha256 = try values.decode(String.self, forKey: .sha256)
        required = try values.decode(Bool.self, forKey: .required)
        meshID = try values.decodeIfPresent(String.self, forKey: .meshID)
        triangleCount = try values.decodeIfPresent(Int.self, forKey: .triangleCount)
        geometrySHA256 = try values.decodeIfPresent(String.self, forKey: .geometrySHA256)
    }
}

public struct BodyAssetLOD: Codable, Equatable, Hashable, Sendable {
    public let lodID: String
    public let renderArtifactID: String
    public let triangleCount: Int
    public let surfaceCorrespondenceVersion: String

    public init(lodID: String, renderArtifactID: String, triangleCount: Int, surfaceCorrespondenceVersion: String) {
        self.lodID = lodID
        self.renderArtifactID = renderArtifactID
        self.triangleCount = triangleCount
        self.surfaceCorrespondenceVersion = surfaceCorrespondenceVersion
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case lodID = "lod_id"
        case renderArtifactID = "render_artifact_id"
        case triangleCount = "triangle_count"
        case surfaceCorrespondenceVersion = "surface_correspondence_version"
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownBodyAssetKeys(decoder, allowed: CodingKeys.allCases)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        lodID = try values.decode(String.self, forKey: .lodID)
        renderArtifactID = try values.decode(String.self, forKey: .renderArtifactID)
        triangleCount = try values.decode(Int.self, forKey: .triangleCount)
        surfaceCorrespondenceVersion = try values.decode(String.self, forKey: .surfaceCorrespondenceVersion)
    }
}

public struct BodyAssetMappings: Codable, Equatable, Hashable, Sendable {
    public let ontologyVersion: String
    public let regionMapVersion: String
    public let surfaceCorrespondenceVersion: String
    public let resolverVersion: String

    public init(ontologyVersion: String, regionMapVersion: String, surfaceCorrespondenceVersion: String, resolverVersion: String) {
        self.ontologyVersion = ontologyVersion
        self.regionMapVersion = regionMapVersion
        self.surfaceCorrespondenceVersion = surfaceCorrespondenceVersion
        self.resolverVersion = resolverVersion
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case ontologyVersion = "ontology_version"
        case regionMapVersion = "region_map_version"
        case surfaceCorrespondenceVersion = "surface_correspondence_version"
        case resolverVersion = "resolver_version"
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownBodyAssetKeys(decoder, allowed: CodingKeys.allCases)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ontologyVersion = try values.decode(String.self, forKey: .ontologyVersion)
        regionMapVersion = try values.decode(String.self, forKey: .regionMapVersion)
        surfaceCorrespondenceVersion = try values.decode(String.self, forKey: .surfaceCorrespondenceVersion)
        resolverVersion = try values.decode(String.self, forKey: .resolverVersion)
    }
}

public struct BodyAssetReview: Codable, Equatable, Hashable, Sendable {
    public let anatomyStatus: BodyAssetAnatomyReviewStatus
    public let reviewerAlias: String
    public let reviewedAt: String?
    public let scope: String

    public init(anatomyStatus: BodyAssetAnatomyReviewStatus, reviewerAlias: String, reviewedAt: String?, scope: String) {
        self.anatomyStatus = anatomyStatus
        self.reviewerAlias = reviewerAlias
        self.reviewedAt = reviewedAt
        self.scope = scope
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case anatomyStatus = "anatomy_status"
        case reviewerAlias = "reviewer_alias"
        case reviewedAt = "reviewed_at"
        case scope
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(anatomyStatus, forKey: .anatomyStatus)
        try values.encode(reviewerAlias, forKey: .reviewerAlias)
        try values.encode(reviewedAt, forKey: .reviewedAt)
        try values.encode(scope, forKey: .scope)
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownBodyAssetKeys(decoder, allowed: CodingKeys.allCases)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        anatomyStatus = try values.decode(BodyAssetAnatomyReviewStatus.self, forKey: .anatomyStatus)
        reviewerAlias = try values.decode(String.self, forKey: .reviewerAlias)
        guard values.contains(.reviewedAt) else { throw BodyAssetManifestError.invalidReview }
        reviewedAt = try values.decodeIfPresent(String.self, forKey: .reviewedAt)
        scope = try values.decode(String.self, forKey: .scope)
    }
}

public struct BodyAssetPerformance: Codable, Equatable, Hashable, Sendable {
    public let status: BodyAssetPerformanceStatus
    public let targetDeviceFamily: String
    public let coldStartMS: Double
    public let p95HitMS: Double
    public let minimumFPS: Double
    public let memoryMB: Double

    public init(status: BodyAssetPerformanceStatus, targetDeviceFamily: String, coldStartMS: Double, p95HitMS: Double, minimumFPS: Double, memoryMB: Double) {
        self.status = status
        self.targetDeviceFamily = targetDeviceFamily
        self.coldStartMS = coldStartMS
        self.p95HitMS = p95HitMS
        self.minimumFPS = minimumFPS
        self.memoryMB = memoryMB
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case status
        case targetDeviceFamily = "target_device_family"
        case coldStartMS = "cold_start_ms"
        case p95HitMS = "p95_hit_ms"
        case minimumFPS = "minimum_fps"
        case memoryMB = "memory_mb"
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownBodyAssetKeys(decoder, allowed: CodingKeys.allCases)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        status = try values.decode(BodyAssetPerformanceStatus.self, forKey: .status)
        targetDeviceFamily = try values.decode(String.self, forKey: .targetDeviceFamily)
        coldStartMS = try values.decode(Double.self, forKey: .coldStartMS)
        p95HitMS = try values.decode(Double.self, forKey: .p95HitMS)
        minimumFPS = try values.decode(Double.self, forKey: .minimumFPS)
        memoryMB = try values.decode(Double.self, forKey: .memoryMB)
    }
}

public struct BodyAssetAttribution: Codable, Equatable, Hashable, Sendable {
    public let text: String
    public let placement: String

    public init(text: String, placement: String) {
        self.text = text
        self.placement = placement
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case text
        case placement
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownBodyAssetKeys(decoder, allowed: CodingKeys.allCases)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        text = try values.decode(String.self, forKey: .text)
        placement = try values.decode(String.self, forKey: .placement)
    }
}

public struct BodyAssetFallback: Codable, Equatable, Hashable, Sendable {
    public let fallbackKind: BodyAssetFallbackKind
    public let fallbackAssetID: String?

    public init(fallbackKind: BodyAssetFallbackKind, fallbackAssetID: String?) {
        self.fallbackKind = fallbackKind
        self.fallbackAssetID = fallbackAssetID
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case fallbackKind = "fallback_kind"
        case fallbackAssetID = "fallback_asset_id"
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(fallbackKind, forKey: .fallbackKind)
        try values.encode(fallbackAssetID, forKey: .fallbackAssetID)
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownBodyAssetKeys(decoder, allowed: CodingKeys.allCases)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fallbackKind = try values.decode(BodyAssetFallbackKind.self, forKey: .fallbackKind)
        guard values.contains(.fallbackAssetID) else { throw BodyAssetManifestError.invalidFallback }
        fallbackAssetID = try values.decodeIfPresent(String.self, forKey: .fallbackAssetID)
    }
}

public struct BodyAssetManifest: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let schemaVersion: String
    public let id: String
    public let assetVersion: String
    public let variant: BodyAssetVariant
    public let topologyID: String
    public let releaseStatus: BodyAssetReleaseStatus
    public let source: BodyAssetSource
    public let rights: BodyAssetRights
    public let integrity: BodyAssetIntegrity
    public let coordinateSystem: BodyAssetCoordinateSystem
    public let artifacts: [BodyAssetArtifact]
    public let lods: [BodyAssetLOD]
    public let mappings: BodyAssetMappings
    public let review: BodyAssetReview
    public let performance: BodyAssetPerformance
    public let attribution: BodyAssetAttribution
    public let fallback: BodyAssetFallback
    public let createdAt: String
    public let updatedAt: String

    public init(
        schemaVersion: String = "1.0",
        assetID: String,
        assetVersion: String,
        variant: BodyAssetVariant,
        topologyID: String,
        releaseStatus: BodyAssetReleaseStatus,
        source: BodyAssetSource,
        rights: BodyAssetRights,
        integrity: BodyAssetIntegrity,
        coordinateSystem: BodyAssetCoordinateSystem,
        artifacts: [BodyAssetArtifact],
        lods: [BodyAssetLOD],
        mappings: BodyAssetMappings,
        review: BodyAssetReview,
        performance: BodyAssetPerformance,
        attribution: BodyAssetAttribution,
        fallback: BodyAssetFallback,
        createdAt: String,
        updatedAt: String
    ) throws {
        self.schemaVersion = schemaVersion
        self.id = assetID
        self.assetVersion = assetVersion
        self.variant = variant
        self.topologyID = topologyID
        self.releaseStatus = releaseStatus
        self.source = source
        self.rights = rights
        self.integrity = integrity
        self.coordinateSystem = coordinateSystem
        self.artifacts = artifacts
        self.lods = lods
        self.mappings = mappings
        self.review = review
        self.performance = performance
        self.attribution = attribution
        self.fallback = fallback
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        try validate()
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case id = "asset_id"
        case assetVersion = "asset_version"
        case variant
        case topologyID = "topology_id"
        case releaseStatus = "release_status"
        case source
        case rights
        case integrity
        case coordinateSystem = "coordinate_system"
        case artifacts
        case lods
        case mappings
        case review
        case performance
        case attribution
        case fallback
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: AnyBodyAssetCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        guard raw.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw BodyAssetManifestError.unknownField
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(String.self, forKey: .schemaVersion)
        id = try values.decode(String.self, forKey: .id)
        assetVersion = try values.decode(String.self, forKey: .assetVersion)
        variant = try values.decode(BodyAssetVariant.self, forKey: .variant)
        topologyID = try values.decode(String.self, forKey: .topologyID)
        releaseStatus = try values.decode(BodyAssetReleaseStatus.self, forKey: .releaseStatus)
        source = try values.decode(BodyAssetSource.self, forKey: .source)
        rights = try values.decode(BodyAssetRights.self, forKey: .rights)
        integrity = try values.decode(BodyAssetIntegrity.self, forKey: .integrity)
        coordinateSystem = try values.decode(BodyAssetCoordinateSystem.self, forKey: .coordinateSystem)
        artifacts = try values.decode([BodyAssetArtifact].self, forKey: .artifacts)
        lods = try values.decode([BodyAssetLOD].self, forKey: .lods)
        mappings = try values.decode(BodyAssetMappings.self, forKey: .mappings)
        review = try values.decode(BodyAssetReview.self, forKey: .review)
        performance = try values.decode(BodyAssetPerformance.self, forKey: .performance)
        attribution = try values.decode(BodyAssetAttribution.self, forKey: .attribution)
        fallback = try values.decode(BodyAssetFallback.self, forKey: .fallback)
        createdAt = try values.decode(String.self, forKey: .createdAt)
        updatedAt = try values.decode(String.self, forKey: .updatedAt)
        try validate()
    }

    public func validate() throws {
        guard schemaVersion == "1.0" else { throw BodyAssetManifestError.unsupportedSchemaVersion }
        guard Self.isToken(id, pattern: .assetID) else { throw BodyAssetManifestError.invalidAssetID }
        guard Self.isToken(assetVersion, pattern: .version) else { throw BodyAssetManifestError.invalidAssetVersion }
        guard Self.isToken(topologyID, pattern: .topologyID) else { throw BodyAssetManifestError.invalidTopologyID }
        guard Self.isISO8601(source.obtainedAt), Self.isISO8601(createdAt), Self.isISO8601(updatedAt),
              review.reviewedAt == nil || Self.isISO8601(review.reviewedAt!) else {
            throw BodyAssetManifestError.invalidTimestamp
        }
        guard !source.author.isEmpty, source.author.count <= 200,
              !source.publisher.isEmpty, source.publisher.count <= 200,
              !rights.licenseName.isEmpty, rights.licenseName.count <= 160,
              Self.isURL(source.sourceURL), Self.isURL(rights.licenseURL) else { throw BodyAssetManifestError.invalidURL }
        guard Self.isSHA256(integrity.sourceSHA256), Self.isSHA256(integrity.manifestSHA256) else { throw BodyAssetManifestError.invalidHash }
        if integrity.signatureStatus == .verified {
            guard let key = integrity.signingKeyID, Self.isToken(key, pattern: .signingKey) else { throw BodyAssetManifestError.invalidHash }
        }
        guard coordinateSystem.convention == "realitykit_y_up_right_handed",
              coordinateSystem.unit == "meter",
              ["feet_midpoint_ground_projection", "manifest_defined"].contains(coordinateSystem.rootOrigin),
              coordinateSystem.canonicalTransform.count == 16,
              coordinateSystem.canonicalTransform.allSatisfy(\.isFinite) else {
            throw BodyAssetManifestError.invalidCoordinateSystem
        }
        guard !artifacts.isEmpty, artifacts.count <= 32 else { throw BodyAssetManifestError.invalidArtifact }
        let artifactIDs = artifacts.map(\.artifactID)
        guard Set(artifactIDs).count == artifactIDs.count else { throw BodyAssetManifestError.duplicateArtifactID }
        guard artifacts.allSatisfy({
            Self.isToken($0.artifactID, pattern: .artifactID) && Self.isURI($0.uri) && Self.isSHA256($0.sha256)
        }) else { throw BodyAssetManifestError.invalidArtifact }
        let roles = Set(artifacts.filter(\.required).map(\.role))
        let requiredRoles: Set<BodyAssetArtifactRole> = variant == .bodyMap2D ? [.render, .regionMap] : [.render, .collision]
        guard requiredRoles.isSubset(of: roles) else { throw BodyAssetManifestError.missingRequiredArtifact }
        guard !lods.isEmpty, lods.count <= 8 else { throw BodyAssetManifestError.invalidLOD }
        let lodIDs = lods.map(\.lodID)
        guard Set(lodIDs).count == lodIDs.count else { throw BodyAssetManifestError.duplicateLODID }
        let renderIDs = Set(artifacts.filter { $0.role == .render }.map(\.artifactID))
        guard lods.allSatisfy({
            Self.isToken($0.lodID, pattern: .version) &&
            Self.isToken($0.renderArtifactID, pattern: .artifactID) &&
            Self.isToken($0.surfaceCorrespondenceVersion, pattern: .version) &&
            $0.triangleCount > 0 &&
            renderIDs.contains($0.renderArtifactID)
        }) else {
            throw BodyAssetManifestError.invalidLOD
        }
        guard Self.isToken(mappings.ontologyVersion, pattern: .ontologyVersion),
              Self.isToken(mappings.regionMapVersion, pattern: .version),
              Self.isToken(mappings.surfaceCorrespondenceVersion, pattern: .version),
              Self.isToken(mappings.resolverVersion, pattern: .version) else {
            throw BodyAssetManifestError.invalidMappings
        }
        guard Self.isToken(review.reviewerAlias, pattern: .alias), !review.scope.isEmpty, review.scope.count <= 240 else { throw BodyAssetManifestError.invalidReview }
        guard review.anatomyStatus == .approved ? review.reviewedAt != nil : true else { throw BodyAssetManifestError.invalidReview }
        guard !performance.targetDeviceFamily.isEmpty, performance.targetDeviceFamily.count <= 120,
              performance.coldStartMS.isFinite,
              performance.p95HitMS.isFinite,
              performance.minimumFPS.isFinite,
              performance.memoryMB.isFinite,
              performance.coldStartMS >= 0,
              performance.p95HitMS >= 0,
              performance.minimumFPS >= 0,
              performance.memoryMB >= 0,
              performance.status != .passed || (performance.coldStartMS > 0 && performance.p95HitMS > 0 && performance.minimumFPS > 0 && performance.memoryMB > 0) else {
            throw BodyAssetManifestError.invalidPerformance
        }
        guard attribution.text.count <= 1000,
              ["app_about", "settings_licenses", "both", "not_required"].contains(attribution.placement) else {
            throw BodyAssetManifestError.invalidAttribution
        }
        if rights.attributionRequired {
            guard !attribution.text.isEmpty, attribution.placement != "not_required" else { throw BodyAssetManifestError.invalidAttribution }
        }
        if let fallbackAssetID = fallback.fallbackAssetID {
            guard Self.isToken(fallbackAssetID, pattern: .assetID) else { throw BodyAssetManifestError.invalidFallback }
        }
        if releaseStatus == .approved {
            guard rights.commercialUse, rights.appStoreDistribution,
                  integrity.signatureStatus == .verified,
                  integrity.manifestSHA256 != "sha256:" + String(repeating: "0", count: 64),
                  review.anatomyStatus == .approved,
                  performance.status == .passed else {
                throw BodyAssetManifestError.approvedGateIncomplete
            }
            if variant != .bodyMap2D {
                let productionRoles: Set<BodyAssetArtifactRole> = [
                    .render, .collision, .regionMap, .surfaceCorrespondence, .cameraPreset,
                ]
                guard productionRoles.isSubset(of: roles) else {
                    throw BodyAssetManifestError.approvedGateIncomplete
                }

                let requiredRender = artifacts.filter { $0.required && $0.role == .render }
                let requiredCollision = artifacts.filter { $0.required && $0.role == .collision }
                let requiredRegionMap = artifacts.filter { $0.required && $0.role == .regionMap }
                let requiredCorrespondence = artifacts.filter { $0.required && $0.role == .surfaceCorrespondence }
                let requiredCameraPreset = artifacts.filter { $0.required && $0.role == .cameraPreset }
                guard requiredRender.allSatisfy({ [.usdz, .usdc].contains($0.format) }),
                      requiredCollision.allSatisfy({ [.usdz, .usdc, .bin].contains($0.format) }),
                      requiredRegionMap.allSatisfy({ [.json, .bin].contains($0.format) }),
                      requiredCorrespondence.allSatisfy({ [.json, .bin].contains($0.format) }),
                      requiredCameraPreset.allSatisfy({ $0.format == .json }),
                      requiredCollision.allSatisfy({ collision in
                          requiredRender.allSatisfy { render in
                              collision.uri != render.uri && collision.sha256 != render.sha256
                          }
                      }) else {
                    throw BodyAssetManifestError.approvedGateIncomplete
                }
            }
        }
    }

    fileprivate enum TokenPattern { case assetID, version, alias, topologyID, signingKey, artifactID, ontologyVersion }

    fileprivate static func isToken(_ value: String, pattern: TokenPattern) -> Bool {
        let maxLength: Int
        switch pattern {
        case .assetID, .topologyID, .artifactID, .signingKey: maxLength = 120
        case .version, .alias: maxLength = 64
        case .ontologyVersion: maxLength = 32
        }
        let minimumLength = pattern == .assetID ? 2 : 1
        guard value.count >= minimumLength, value.count <= maxLength else { return false }
        guard let first = value.unicodeScalars.first else { return false }
        let firstAllowed: Bool = {
            switch pattern {
            case .assetID:
                return first.value >= 48 && first.value <= 57 || first.value >= 97 && first.value <= 122
            case .version, .alias, .topologyID, .signingKey, .artifactID, .ontologyVersion:
                return (first.value >= 48 && first.value <= 57) || (first.value >= 65 && first.value <= 90) || (first.value >= 97 && first.value <= 122)
            }
        }()
        guard firstAllowed else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            let ascii = (scalar.value >= 48 && scalar.value <= 57) || (scalar.value >= 65 && scalar.value <= 90) || (scalar.value >= 97 && scalar.value <= 122)
            let separator = scalar == "." || scalar == "_" || scalar == "-"
            return ascii || separator
        }
    }

    fileprivate static func isSHA256(_ value: String) -> Bool {
        guard value.count == 71, value.hasPrefix("sha256:") else { return false }
        return value.dropFirst(7).unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 48 && scalar.value <= 57) || (scalar.value >= 97 && scalar.value <= 102)
        }
    }

    fileprivate static func isURL(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return url.scheme == "https" || url.scheme == "http"
    }

    fileprivate static func isURI(_ value: String) -> Bool {
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil, let url = URL(string: value) else { return false }
        return url.scheme == "bundle" || url.scheme == "https"
    }

    fileprivate static func isISO8601(_ value: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatter.date(from: value) != nil { return true }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value) != nil
    }
}

public enum BodyAssetRuntimeFallbackReason: String, Equatable, Sendable {
    case noManifest
    case statusNotApproved
    case requestedVariantMismatch
    case metadataGateRejected
}

public enum BodyAssetRuntimeDecision: Equatable, Sendable {
    case metadataEligible(assetID: String, assetVersion: String)
    case fallback(BodyAssetRuntimeFallbackReason)
}

/// Metadata-only gate. It deliberately does not read, download, hash, or load a model file.
public enum BodyAssetRuntimeGate {
    public static func evaluate(_ manifest: BodyAssetManifest?, requestedVariant: BodyAssetVariant) -> BodyAssetRuntimeDecision {
        guard let manifest else { return .fallback(.noManifest) }
        guard manifest.releaseStatus == .approved else { return .fallback(.statusNotApproved) }
        guard manifest.variant == requestedVariant else { return .fallback(.requestedVariantMismatch) }
        do {
            try manifest.validate()
            return .metadataEligible(assetID: manifest.id, assetVersion: manifest.assetVersion)
        } catch {
            return .fallback(.metadataGateRejected)
        }
    }
}

fileprivate func rejectUnknownBodyAssetKeys<K: CodingKey>(_ decoder: Decoder, allowed: [K]) throws {
    let allowedKeys = Set(allowed.map(\.stringValue))
    let raw = try decoder.container(keyedBy: AnyBodyAssetCodingKey.self)
    guard raw.allKeys.allSatisfy({ allowedKeys.contains($0.stringValue) }) else {
        throw BodyAssetManifestError.unknownField
    }
}

fileprivate struct AnyBodyAssetCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
    init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
}
