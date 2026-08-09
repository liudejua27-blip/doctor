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
        context.coordinator.syncMarks(marks)
        context.coordinator.applyCameraPresetIfNeeded()
    }

    @MainActor
    public final class Coordinator: NSObject {
        private let allowsPrototypeCandidate: Bool
        private let onLoadAttempted: () -> Void
        private let onReady: () -> Void
        private let onFailure: (String) -> Void
        private let onHitEvidence: (BodyHitEvidence) -> Void
        private let onMarkerTapped: (UUID) -> Void
        private weak var arView: ARView?
        private var visualRoot: Entity?
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

        private static let pinPalette: [UIColor] = [
            .systemRed, .systemBlue, .systemOrange, .systemPurple, .systemGreen,
            .systemPink, .systemTeal, .systemIndigo, .systemYellow, .systemCyan,
            .systemMint, .systemBrown,
        ]

        init(
            allowsPrototypeCandidate: Bool,
            cameraPreset: BodyCameraPreset,
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
            loadPrototypeAsset()
        }

        private func loadPrototypeAsset() {
            guard let arView else { return }
            // This acknowledgement is intentionally emitted before any Bundle
            // lookup or RealityKit load. It carries no model/health data and
            // exists only to prove the current internal probe reached loader
            // entry; the parent validates its per-request attempt identity.
            onLoadAttempted()
            guard let url = Bundle.module.url(forResource: "BodyNeutralPrototype", withExtension: "usdz") else {
                reportFailure("内部候选 3D 资产缺失；已回退到 2D")
                return
            }

            do {
                let loaded = try ModelEntity.loadModel(contentsOf: url)
                loaded.name = "body_neutral_prototype"
                loaded.generateCollisionShapes(recursive: true)

                let root = Entity()
                root.name = "body_visual_root"
                root.addChild(loaded)
                root.scale = SIMD3<Float>(repeating: 0.9)
                root.position = SIMD3<Float>(0, 0, 0)

                let anchor = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
                anchor.name = "body_scene_anchor"
                anchor.addChild(root)
                arView.scene.addAnchor(anchor)

                let cameraAnchor = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
                let camera = PerspectiveCamera()
                camera.name = "body_camera"
                cameraAnchor.addChild(camera)
                arView.scene.addAnchor(cameraAnchor)
                self.camera = camera
                self.visualRoot = root
                indexRegionEntities(from: loaded)
                self.hasLoaded = true
                applyCameraPresetIfNeeded(force: true)
                syncMarks(currentMarks)
                DispatchQueue.main.async { [onReady] in onReady() }
            } catch {
                reportFailure("内部候选 3D 资产加载失败；已回退到 2D")
            }
        }

        private func indexRegionEntities(from entity: Entity) {
            if let model = entity as? ModelEntity,
               let option = BodyRegionCatalog.option(forEntityID: entity.name) {
                regionEntities[option.id] = model
            }
            for child in entity.children {
                indexRegionEntities(from: child)
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
                let dot: ModelEntity
                if let existing = markerEntities[mark.id] {
                    dot = existing
                } else {
                    dot = ModelEntity(mesh: .generateSphere(radius: 0.028))
                    dot.name = "marker_" + mark.id.uuidString
                    dot.generateCollisionShapes(recursive: true)
                    root.addChild(dot)
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
                    $0.kind == .zone && $0.isVisible &&
                        "\($0.location.regionID)|\($0.location.laterality.rawValue)" == key
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

            let target = focusTarget() ?? SIMD3<Float>(0, 0.9, 0)
            let distance: Float = focusedRegionID == nil ? 2.9 : 1.25
            let position: SIMD3<Float>
            switch cameraPreset {
            case .front: position = target + SIMD3<Float>(0, 0.08, distance)
            case .back: position = target + SIMD3<Float>(0, 0.08, -distance)
            case .left: position = target + SIMD3<Float>(-distance, 0.08, 0)
            case .right: position = target + SIMD3<Float>(distance, 0.08, 0)
            case .top: position = target + SIMD3<Float>(0, distance, 0.12)
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
            let factor = min(max(Float(gesture.scale), 0.92), 1.08)
            let next = min(max(root.scale.x * factor, 0.55), 1.35)
            root.scale = SIMD3<Float>(repeating: next)
            gesture.scale = 1
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = arView, let root = visualRoot else { return }
            let hits = view.hitTest(gesture.location(in: view), query: .nearest, mask: .all)
            guard let hit = hits.first else { return }

            if let markerID = markerID(from: hit.entity) {
                onMarkerTapped(markerID)
                return
            }
            guard let entityID = stableEntityID(from: hit.entity) else { return }

            let position = root.convert(position: hit.position, from: nil)
            let convertedNormal = root.convert(normal: hit.normal, from: nil)
            let normal = simd_length(convertedNormal) > 0 ? simd_normalize(convertedNormal) : SIMD3<Float>(0, 0, 1)
            onHitEvidence(
                BodyHitEvidence(
                    entityID: entityID,
                    localPosition: Point3D(x: Double(position.x), y: Double(position.y), z: Double(position.z)),
                    localNormal: Point3D(x: Double(normal.x), y: Double(normal.y), z: Double(normal.z)),
                    assetID: "body-neutral-procedural-v1",
                    assetVersion: "1.1.0"
                )
            )
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

        private func stableEntityID(from entity: Entity) -> String? {
            var current: Entity? = entity
            while let candidate = current {
                if candidate.name.hasPrefix("body_") {
                    return candidate.name
                }
                current = candidate.parent
            }
            return nil
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
