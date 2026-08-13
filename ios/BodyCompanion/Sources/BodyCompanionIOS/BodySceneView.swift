import BodyCompanionCore
import SwiftUI

#if os(iOS)
import RealityKit
import UIKit

public enum BodyCameraPreset: String, CaseIterable, Hashable, Sendable {
    case front
    case back
    case left
    case right
    case top

    public var label: String {
        switch self {
        case .front: return "前"
        case .back: return "后"
        case .left: return "左"
        case .right: return "右"
        case .top: return "上"
        }
    }
}

/// Native RealityKit adapter. It emits hit evidence and mirrors BodyMark
/// state; it never owns a BodyLocation, Episode, Agent conclusion, or record.
public struct BodySceneView: UIViewRepresentable {
    public let allowsPrototypeCandidate: Bool
    public let cameraPreset: BodyCameraPreset
    public let userHeightMeters: Float?
    public let marks: [BodyMark]
    public let focusedRegionID: String?
    public let selectedMarkID: UUID?
    public let onLoadAttempted: () -> Void
    public let onReady: () -> Void
    public let onFailure: (String) -> Void
    public let onHitEvidence: (BodyHitEvidence) -> Void
    public let onMarkerTapped: (UUID) -> Void

    public init(
        allowsPrototypeCandidate: Bool = false,
        cameraPreset: BodyCameraPreset = .front,
        userHeightMeters: Float? = nil,
        markers: [BodyLocation] = [],
        marks: [BodyMark] = [],
        focusedRegionID: String? = nil,
        selectedMarkID: UUID? = nil,
        onLoadAttempted: @escaping () -> Void,
        onReady: @escaping () -> Void,
        onFailure: @escaping (String) -> Void,
        onHitEvidence: @escaping (BodyHitEvidence) -> Void,
        onMarkerTapped: @escaping (UUID) -> Void = { _ in }
    ) {
        self.allowsPrototypeCandidate = allowsPrototypeCandidate
        self.cameraPreset = cameraPreset
        self.userHeightMeters = userHeightMeters
        self.marks = marks.isEmpty
            ? markers.enumerated().map { index, marker in BodyMark(kind: .pin, location: marker, colorToken: index) }
            : marks
        self.focusedRegionID = focusedRegionID
        self.selectedMarkID = selectedMarkID
        self.onLoadAttempted = onLoadAttempted
        self.onReady = onReady
        self.onFailure = onFailure
        self.onHitEvidence = onHitEvidence
        self.onMarkerTapped = onMarkerTapped
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            allowsPrototypeCandidate: allowsPrototypeCandidate,
            cameraPreset: cameraPreset,
            userHeightMeters: userHeightMeters,
            marks: marks,
            focusedRegionID: focusedRegionID,
            selectedMarkID: selectedMarkID,
            onLoadAttempted: onLoadAttempted,
            onReady: onReady,
            onFailure: onFailure,
            onHitEvidence: onHitEvidence,
            onMarkerTapped: onMarkerTapped
        )
    }

    public func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.backgroundColor = .systemBackground
        view.isOpaque = false
        context.coordinator.attach(to: view)
        return view
    }

    public func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.cameraPreset = cameraPreset
        context.coordinator.focusedRegionID = focusedRegionID
        context.coordinator.selectedMarkID = selectedMarkID
        context.coordinator.setUserHeightMeters(userHeightMeters)
        context.coordinator.syncMarks(marks)
        context.coordinator.applyCameraPresetIfNeeded()
    }

    @MainActor
    public final class Coordinator: NSObject {
        private struct ScenePlacement {
            let scale: Float
            let rootPosition: SIMD3<Float>
            let focusTarget: SIMD3<Float>
            let focusDistance: Float
        }

        private let allowsPrototypeCandidate: Bool
        private static let minUserHeightMeters: Float = 1.35
        private static let maxUserHeightMeters: Float = 2.20
        private static let minModelScale: Float = 0.45
        private static let maxModelScale: Float = 2.2
        private static let focusHeightRatio: Float = 0.5
        private static let cameraDistanceHeightRatio: Float = 1.56
        private static let focusedDistanceMultiplier: Float = 0.74
        private static let rootEntityName = "body_visual_root"
        private static let sceneAnchorName = "body_scene_anchor"
        private static let collisionRootName = "body_collision_root"
        private static let bodyCollisionGroup = CollisionGroup(rawValue: 1 << 8)
        private static let markerCollisionGroup = CollisionGroup(rawValue: 1 << 9)

        private let onLoadAttempted: () -> Void
        private let onReady: () -> Void
        private let onFailure: (String) -> Void
        private let onHitEvidence: (BodyHitEvidence) -> Void
        private let onMarkerTapped: (UUID) -> Void
        private var userHeightMeters: Float?
        private weak var arView: ARView?
        private var visualRoot: Entity?
        private var collisionRoot: Entity?
        private var camera: PerspectiveCamera?
        private var markerEntities: [UUID: ModelEntity] = [:]
        private var regionEntities: [String: ModelEntity] = [:]
        private var hasLoaded = false
        private var hasReportedFailure = false
        private var appliedCameraPreset: BodyCameraPreset?
        private var appliedFocusedRegionID: String?
        fileprivate var cameraPreset: BodyCameraPreset
        fileprivate var focusedRegionID: String?
        fileprivate var selectedMarkID: UUID?
        private var currentMarks: [BodyMark]
        private var baseScale: Float = 1
        private var userScale: Float = 1
        private var preferredFocusTarget: SIMD3<Float>
        private var focusDistance: Float
        private var appliedUserHeightMeters: Float?

        private static let pinPalette: [UIColor] = [
            .systemRed, .systemBlue, .systemOrange, .systemPurple, .systemGreen,
            .systemPink, .systemTeal, .systemIndigo, .systemYellow, .systemCyan,
            .systemMint, .systemBrown,
        ]

        init(
            allowsPrototypeCandidate: Bool,
            cameraPreset: BodyCameraPreset,
            userHeightMeters: Float?,
            marks: [BodyMark],
            focusedRegionID: String?,
            selectedMarkID: UUID?,
            onLoadAttempted: @escaping () -> Void,
            onReady: @escaping () -> Void,
            onFailure: @escaping (String) -> Void,
            onHitEvidence: @escaping (BodyHitEvidence) -> Void,
            onMarkerTapped: @escaping (UUID) -> Void
        ) {
            self.allowsPrototypeCandidate = allowsPrototypeCandidate
            self.cameraPreset = cameraPreset
            self.currentMarks = marks
            self.focusedRegionID = focusedRegionID
            self.selectedMarkID = selectedMarkID
            self.onLoadAttempted = onLoadAttempted
            self.onReady = onReady
            self.onFailure = onFailure
            self.onHitEvidence = onHitEvidence
            self.onMarkerTapped = onMarkerTapped
            self.userHeightMeters = userHeightMeters
            self.preferredFocusTarget = SIMD3<Float>(
                0,
                BodyAssetCandidateNeutralProcedural.canonicalHeightMeters * Coordinator.focusHeightRatio,
                0
            )
            self.focusDistance = BodyAssetCandidateNeutralProcedural.canonicalHeightMeters * Coordinator.cameraDistanceHeightRatio
            super.init()
        }

        func attach(to view: ARView) {
            arView = view

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            view.addGestureRecognizer(pan)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            view.addGestureRecognizer(pinch)

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.require(toFail: pan)
            view.addGestureRecognizer(tap)

            guard allowsPrototypeCandidate else {
                reportFailure("approved AssetManifest 未配置；生产路径保持 2D 回退")
                return
            }
            guard Body3DAssetRuntimeMetadata.shared.loadedFromArtifacts else {
                reportFailure("3D 映射产物未通过校验；已回退到 2D")
                return
            }
            loadPrototypeAsset()
        }

        private func loadPrototypeAsset() {
            guard let arView else { return }
            // This acknowledgement is intentionally emitted before any Bundle
            // lookup or RealityKit load. It carries no model/health data and
            // exists only to prove the current internal probe reached loader
            // entry; the parent validates its per-request attempt identity.
            onLoadAttempted()
            // The internal AppHost is the only target that owns candidate
            // resources. Reusable/production package products have no 3D
            // candidate files and deliberately fall back when this lookup is
            // empty.
            guard let renderURL = Bundle.main.url(forResource: BodyAssetCandidateNeutralProcedural.modelResourceName, withExtension: BodyAssetCandidateNeutralProcedural.modelResourceExtension),
                  let collisionURL = Bundle.main.url(forResource: BodyAssetCandidateNeutralProcedural.collisionResourceName, withExtension: BodyAssetCandidateNeutralProcedural.collisionResourceExtension) else {
                reportFailure("内部候选 3D 资产缺失；已回退到 2D")
                return
            }

            do {
                let renderEntity = try Entity.load(contentsOf: renderURL)
                let collisionEntity = try Entity.load(contentsOf: collisionURL)
                collisionEntity.generateCollisionShapes(recursive: true)
                configureCollisionEntities(in: collisionEntity)

                let root = Entity()
                root.name = Self.rootEntityName
                let placement = Self.prepareScenePlacement(userHeightMeters: userHeightMeters)
                root.scale = SIMD3<Float>(repeating: placement.scale)
                root.position = placement.rootPosition
                baseScale = placement.scale
                userScale = 1
                preferredFocusTarget = placement.focusTarget
                focusDistance = placement.focusDistance
                root.addChild(renderEntity)
                let collisionRoot = Entity()
                collisionRoot.name = Self.collisionRootName
                collisionRoot.addChild(collisionEntity)
                root.addChild(collisionRoot)

                let anchor = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
                anchor.name = Self.sceneAnchorName
                anchor.addChild(root)
                arView.scene.addAnchor(anchor)

                let cameraAnchor = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
                let camera = PerspectiveCamera()
                camera.name = "body_camera"
                cameraAnchor.addChild(camera)
                arView.scene.addAnchor(cameraAnchor)
                self.camera = camera
                self.visualRoot = root
                self.collisionRoot = collisionRoot
                self.appliedUserHeightMeters = userHeightMeters
                indexRegionEntities(from: renderEntity)
                self.hasLoaded = true
                applyCameraPresetIfNeeded(force: true)
                syncMarks(currentMarks)
                DispatchQueue.main.async { [onReady] in onReady() }
            } catch {
                reportFailure("内部候选 3D 资产加载失败；已回退到 2D")
            }
        }

        private func indexRegionEntities(
            from entity: Entity,
            inheritedOption: BodyRegionOption? = nil
        ) {
            let option = BodyRegionCatalog.option(forEntityID: entity.name) ?? inheritedOption
            if let model = entity as? ModelEntity,
               let option {
                regionEntities[option.id] = model
            }
            for child in entity.children {
                indexRegionEntities(from: child, inheritedOption: option)
            }
        }

        func syncMarks(_ marks: [BodyMark]) {
            currentMarks = marks
            guard let root = visualRoot else { return }

            let visibleMarks = marks.filter(\.isVisible)
            let staleIDs = markerEntities.keys.filter { id in !visibleMarks.contains(where: { $0.id == id }) }
            for id in staleIDs {
                markerEntities[id]?.removeFromParent()
                markerEntities.removeValue(forKey: id)
            }

            for mark in visibleMarks where mark.kind == .pin {
                guard let anchor = mark.location.anchor3D else { continue }
                let position = SIMD3<Float>(
                    Float(anchor.localPosition.x),
                    Float(anchor.localPosition.y),
                    Float(anchor.localPosition.z)
                )
                let parent = markerParent(for: anchor) ?? root
                let dot: ModelEntity
                if let existing = markerEntities[mark.id] {
                    dot = existing
                    if dot.parent !== parent {
                        parent.addChild(dot)
                    }
                } else {
                    dot = ModelEntity(mesh: .generateSphere(radius: 0.028))
                    dot.name = "marker_" + mark.id.uuidString
                    dot.generateCollisionShapes(recursive: true)
                    configureMarkerCollision(dot)
                    parent.addChild(dot)
                    markerEntities[mark.id] = dot
                }
                dot.position = position
                let color = Self.pinPalette[mark.colorToken % Self.pinPalette.count]
                dot.model?.materials = [
                    SimpleMaterial(color: mark.id == selectedMarkID ? color.withAlphaComponent(1) : color.withAlphaComponent(0.86), isMetallic: false),
                ]
            }

            updateRegionHighlights()
        }

        private func updateRegionHighlights() {
            for (key, entity) in regionEntities {
                let mark = currentMarks.first {
                    guard $0.kind == .zone,
                          $0.isVisible,
                          let option = BodyRegionCatalog.option(
                              regionID: $0.location.regionID,
                              laterality: $0.location.laterality,
                              surface: $0.location.surface
                          ) else {
                        return false
                    }
                    return option.id == key
                }
                let isFocused = mark?.location.regionID == focusedRegionID
                let color: UIColor = if mark == nil {
                    UIColor(red: 0.68, green: 0.78, blue: 0.84, alpha: 1)
                } else if isFocused {
                    .systemOrange
                } else {
                    .systemTeal
                }
                entity.model?.materials = [SimpleMaterial(color: color, isMetallic: false)]
            }
        }

        func applyCameraPresetIfNeeded(force: Bool = false) {
            guard hasLoaded, let camera else { return }
            let focusChanged = appliedFocusedRegionID != focusedRegionID
            guard force || appliedCameraPreset != cameraPreset || focusChanged else { return }
            appliedCameraPreset = cameraPreset
            appliedFocusedRegionID = focusedRegionID

            let target = focusTarget() ?? preferredFocusTarget
            let presetDistance = Body3DAssetRuntimeMetadata.shared.cameraPreset(cameraPreset)?.distanceMeters
                ?? BodyAssetCandidateNeutralProcedural.canonicalHeightMeters * Self.cameraDistanceHeightRatio
            let distance: Float = focusedRegionID == nil
                ? max(1.0, presetDistance)
                : max(0.95, presetDistance * Self.focusedDistanceMultiplier)
            let yOffset = max(0.03, target.y * 0.08)
            let position: SIMD3<Float>
            switch cameraPreset {
            case .front: position = target + SIMD3<Float>(0, yOffset, distance)
            case .back: position = target + SIMD3<Float>(0, yOffset, -distance)
            case .left: position = target + SIMD3<Float>(-distance, yOffset, 0)
            case .right: position = target + SIMD3<Float>(distance, yOffset, 0)
            case .top: position = target + SIMD3<Float>(0, distance + yOffset, 0)
            }
            if let preset = Body3DAssetRuntimeMetadata.shared.cameraPreset(cameraPreset) {
                var cameraComponent = camera.camera
                cameraComponent.fieldOfViewInDegrees = preset.fovDegrees
                camera.camera = cameraComponent
            }
            camera.look(at: target, from: position, relativeTo: nil)
            updateRegionHighlights()
        }

        private func focusTarget() -> SIMD3<Float>? {
            guard let focusedRegionID else { return nil }
            guard let match = regionEntities.first(where: { key, _ in key.hasPrefix(focusedRegionID + "|") }) else {
                return nil
            }
            return match.value.position(relativeTo: nil)
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let root = visualRoot, let view = arView else { return }
            let delta = gesture.translation(in: view)
            let yaw = simd_quatf(angle: Float(delta.x) * 0.008, axis: SIMD3<Float>(0, 1, 0))
            let pitch = simd_quatf(angle: Float(-delta.y) * 0.004, axis: SIMD3<Float>(1, 0, 0))
            root.orientation = yaw * pitch * root.orientation
            gesture.setTranslation(.zero, in: view)
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let root = visualRoot else { return }
            let factor = min(max(Float(gesture.scale), 0.92), 1.1)
            let nextUserScale = min(max(userScale * factor, 0.55), 2.0)
            userScale = nextUserScale
            root.scale = SIMD3<Float>(repeating: baseScale * userScale)
            gesture.scale = 1
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = arView else { return }
            let hits = view.hitTest(
                gesture.location(in: view),
                query: .nearest,
                mask: Self.bodyCollisionGroup.union(Self.markerCollisionGroup)
            )
            guard let hit = hits.first else { return }

            if let markerID = markerID(from: hit.entity) {
                onMarkerTapped(markerID)
                return
            }
            guard let collisionEntity = stableCollisionEntity(from: hit.entity) else { return }
            let entityID = BodyAssetCandidateNeutralProcedural.collisionMeshID

            let position = collisionEntity.convert(position: hit.position, from: nil)
            let convertedNormal = collisionEntity.convert(normal: hit.normal, from: nil)
            let normal = simd_length(convertedNormal) > 0 ? simd_normalize(convertedNormal) : SIMD3<Float>(0, 0, 1)
            let triangleInfo = extractTriangleInfo(from: hit)
            guard triangleInfo.triangleIndex != nil, triangleInfo.barycentric != nil else {
                reportFailure("当前设备未提供可审计的三角面命中；已回退到 2D")
                return
            }
            onHitEvidence(
                BodyHitEvidence(
                    entityID: entityID,
                    meshID: BodyAssetCandidateNeutralProcedural.collisionMeshID,
                    localPosition: Point3D(x: Double(position.x), y: Double(position.y), z: Double(position.z)),
                    localNormal: Point3D(x: Double(normal.x), y: Double(normal.y), z: Double(normal.z)),
                    triangleIndex: triangleInfo.triangleIndex,
                    barycentric: triangleInfo.barycentric,
                    uv: nil,
                    assetID: BodyAssetCandidateNeutralProcedural.assetID,
                    assetVersion: BodyAssetCandidateNeutralProcedural.assetVersion
                )
            )
        }

        fileprivate func setUserHeightMeters(_ userHeightMeters: Float?) {
            guard hasLoaded, let root = visualRoot else { return }
            if userHeightMeters == self.appliedUserHeightMeters { return }
            self.userHeightMeters = userHeightMeters
            self.appliedUserHeightMeters = userHeightMeters

            let placement = Self.prepareScenePlacement(userHeightMeters: userHeightMeters)
            root.scale = SIMD3<Float>(repeating: placement.scale * userScale)
            root.position = placement.rootPosition
            baseScale = placement.scale
            preferredFocusTarget = placement.focusTarget
            focusDistance = placement.focusDistance
            applyCameraPresetIfNeeded(force: true)
        }

        private func markerID(from entity: Entity) -> UUID? {
            var current: Entity? = entity
            while let candidate = current {
                guard candidate.name.hasPrefix("marker_") else {
                    current = candidate.parent
                    continue
                }
                return UUID(uuidString: String(candidate.name.dropFirst("marker_".count)))
            }
            return nil
        }

        private func stableCollisionEntity(from entity: Entity) -> Entity? {
            var current: Entity? = entity
            while let candidate = current {
                if candidate.name == BodyAssetCandidateNeutralProcedural.collisionMeshID {
                    return candidate
                }
                current = candidate.parent
            }
            return nil
        }

        private func markerParent(for anchor: BodyLocationAnchor3D) -> Entity? {
            if anchor.meshID == BodyAssetCandidateNeutralProcedural.collisionMeshID {
                return collisionRoot
            }
            guard let option = BodyRegionCatalog.option(forEntityID: anchor.entityID) else { return nil }
            return regionEntities[option.id]
        }

        private func configureCollisionEntities(in entity: Entity) {
            if var collision = entity.components[CollisionComponent.self] {
                collision.filter = CollisionFilter(
                    group: Self.bodyCollisionGroup,
                    mask: Self.bodyCollisionGroup.union(Self.markerCollisionGroup)
                )
                entity.components.set(collision)
            }
            for child in entity.children {
                configureCollisionEntities(in: child)
            }
        }

        private func configureMarkerCollision(_ entity: Entity) {
            guard var collision = entity.components[CollisionComponent.self] else { return }
            collision.filter = CollisionFilter(
                group: Self.markerCollisionGroup,
                mask: Self.bodyCollisionGroup.union(Self.markerCollisionGroup)
            )
            entity.components.set(collision)
        }

        private static func targetHeight(for userHeightMeters: Float?) -> Float {
            guard let userHeight = userHeightMeters else {
                return BodyAssetCandidateNeutralProcedural.canonicalHeightMeters
            }
            return max(minUserHeightMeters, min(maxUserHeightMeters, userHeight))
        }

        private static func prepareScenePlacement(userHeightMeters: Float?) -> ScenePlacement {
            // Canonical height and ground are versioned asset facts. Runtime
            // visual bounds may vary after RealityKit processing and must not
            // redefine the body-space origin, axes, or reference height.
            let targetHeight = Self.targetHeight(for: userHeightMeters)
            let scale = max(
                Self.minModelScale,
                min(
                    Self.maxModelScale,
                    targetHeight / BodyAssetCandidateNeutralProcedural.canonicalHeightMeters
                )
            )
            let position = SIMD3<Float>(
                0,
                -BodyAssetCandidateNeutralProcedural.canonicalGroundYMeters * scale,
                0
            )
            let target = SIMD3<Float>(0, targetHeight * Self.focusHeightRatio, 0)
            let distance = max(1.0, min(4.2, targetHeight * Self.cameraDistanceHeightRatio))
            return ScenePlacement(scale: scale, rootPosition: position, focusTarget: target, focusDistance: distance)
        }

        private func extractTriangleInfo(
            from hit: CollisionCastHit
        ) -> (triangleIndex: Int?, barycentric: (Double, Double, Double)?) {
            guard #available(iOS 18.0, *),
                  let triangleHit = hit.triangleHit else {
                return (triangleIndex: nil, barycentric: nil)
            }

            let u = Double(triangleHit.uv.x)
            let v = Double(triangleHit.uv.y)
            let w = 1 - u - v
            guard triangleHit.faceIndex >= 0,
                  u.isFinite, v.isFinite, w.isFinite,
                  u >= 0, v >= 0, w >= 0,
                  u <= 1, v <= 1, w <= 1 else {
                return (triangleIndex: nil, barycentric: nil)
            }
            return (
                triangleIndex: triangleHit.faceIndex,
                barycentric: (u, v, w)
            )
        }

        private func reportFailure(_ message: String) {
            guard !hasReportedFailure else { return }
            hasReportedFailure = true
            DispatchQueue.main.async { [onFailure] in onFailure(message) }
        }
    }
}
#else

public enum BodyCameraPreset: String, CaseIterable, Hashable, Sendable {
    case front
    case back
    case left
    case right
    case top

    public var label: String { rawValue }
}

/// The prototype harness is macOS-compilable but the RealityKit view is iOS-only.
public struct BodySceneView: View {
    public init(
        allowsPrototypeCandidate: Bool = false,
        cameraPreset: BodyCameraPreset = .front,
        userHeightMeters: Float? = nil,
        markers: [BodyLocation] = [],
        marks: [BodyMark] = [],
        focusedRegionID: String? = nil,
        selectedMarkID: UUID? = nil,
        onLoadAttempted: @escaping () -> Void = {},
        onReady: @escaping () -> Void = {},
        onFailure: @escaping (String) -> Void = { _ in },
        onHitEvidence: @escaping (BodyHitEvidence) -> Void = { _ in },
        onMarkerTapped: @escaping (UUID) -> Void = { _ in }
    ) {}

    public var body: some View {
        ContentUnavailableView("iOS 3D preview", systemImage: "iphone", description: Text("请在 iOS target 中运行原生 RealityKit 适配器。"))
    }
}
#endif
