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

/// Native RealityKit adapter. It emits hit evidence only; it never owns a
/// BodyLocation, Episode, Agent conclusion, or health record.
public struct BodySceneView: UIViewRepresentable {
    public let allowsPrototypeCandidate: Bool
    public let cameraPreset: BodyCameraPreset
    public let markers: [BodyLocation]
    public let onReady: () -> Void
    public let onFailure: (String) -> Void
    public let onHitEvidence: (BodyHitEvidence) -> Void

    public init(
        allowsPrototypeCandidate: Bool = false,
        cameraPreset: BodyCameraPreset = .front,
        markers: [BodyLocation] = [],
        onReady: @escaping () -> Void,
        onFailure: @escaping (String) -> Void,
        onHitEvidence: @escaping (BodyHitEvidence) -> Void
    ) {
        self.allowsPrototypeCandidate = allowsPrototypeCandidate
        self.cameraPreset = cameraPreset
        self.markers = markers
        self.onReady = onReady
        self.onFailure = onFailure
        self.onHitEvidence = onHitEvidence
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            allowsPrototypeCandidate: allowsPrototypeCandidate,
            cameraPreset: cameraPreset,
            markers: markers,
            onReady: onReady,
            onFailure: onFailure,
            onHitEvidence: onHitEvidence
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
        context.coordinator.syncMarkers(markers)
        context.coordinator.applyCameraPreset()
    }

    @MainActor
    public final class Coordinator: NSObject {
        private let allowsPrototypeCandidate: Bool
        private let onReady: () -> Void
        private let onFailure: (String) -> Void
        private let onHitEvidence: (BodyHitEvidence) -> Void
        private weak var arView: ARView?
        private var visualRoot: Entity?
        private var camera: PerspectiveCamera?
        private var markerEntities: [UUID: ModelEntity] = [:]
        private var hasLoaded = false
        private var hasReportedFailure = false
        fileprivate var cameraPreset: BodyCameraPreset

        init(
            allowsPrototypeCandidate: Bool,
            cameraPreset: BodyCameraPreset,
            markers: [BodyLocation],
            onReady: @escaping () -> Void,
            onFailure: @escaping (String) -> Void,
            onHitEvidence: @escaping (BodyHitEvidence) -> Void
        ) {
            self.allowsPrototypeCandidate = allowsPrototypeCandidate
            self.cameraPreset = cameraPreset
            self.currentMarkers = markers
            self.onReady = onReady
            self.onFailure = onFailure
            self.onHitEvidence = onHitEvidence
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
                self.hasLoaded = true
                applyCameraPreset()
                syncMarkers(currentMarkers)
                onReady()
            } catch {
                reportFailure("内部候选 3D 资产加载失败；已回退到 2D")
            }
        }

        private var currentMarkers: [BodyLocation] = []

        func syncMarkers(_ markers: [BodyLocation]) {
            currentMarkers = markers
            guard let root = visualRoot else { return }

            let staleIDs = markerEntities.keys.filter { id in !markers.contains(where: { $0.id == id }) }
            for id in staleIDs {
                markerEntities[id]?.removeFromParent()
                markerEntities.removeValue(forKey: id)
            }

            for marker in markers {
                guard let anchor = marker.anchor3D else { continue }
                if let existing = markerEntities[marker.id] {
                    existing.position = SIMD3<Float>(Float(anchor.localPosition.x), Float(anchor.localPosition.y), Float(anchor.localPosition.z))
                    continue
                }
                let dot = ModelEntity(
                    mesh: .generateSphere(radius: 0.025),
                    materials: [SimpleMaterial(color: .systemRed, isMetallic: false)]
                )
                dot.name = "marker_\(marker.id.uuidString)"
                dot.position = SIMD3<Float>(Float(anchor.localPosition.x), Float(anchor.localPosition.y), Float(anchor.localPosition.z))
                root.addChild(dot)
                markerEntities[marker.id] = dot
            }
        }

        func applyCameraPreset() {
            guard hasLoaded, let camera else { return }
            let target = SIMD3<Float>(0, 0.9, 0)
            let position: SIMD3<Float>
            switch cameraPreset {
            case .front: position = SIMD3<Float>(0, 0.95, 2.9)
            case .back: position = SIMD3<Float>(0, 0.95, -2.9)
            case .left: position = SIMD3<Float>(-2.9, 0.95, 0)
            case .right: position = SIMD3<Float>(2.9, 0.95, 0)
            case .top: position = SIMD3<Float>(0, 3.2, 0.15)
            }
            camera.look(at: target, from: position, relativeTo: nil)
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
            guard let hit = hits.first, let entityID = stableEntityID(from: hit.entity) else { return }

            let position = root.convert(position: hit.position, from: nil)
            let normal = simd_length(hit.normal) > 0 ? simd_normalize(root.convert(normal: hit.normal, from: nil)) : SIMD3<Float>(0, 0, 1)
            onHitEvidence(
                BodyHitEvidence(
                    entityID: entityID,
                    localPosition: Point3D(x: Double(position.x), y: Double(position.y), z: Double(position.z)),
                    localNormal: Point3D(x: Double(normal.x), y: Double(normal.y), z: Double(normal.z)),
                    assetID: "body-neutral-procedural-v1",
                    assetVersion: "1.0.0"
                )
            )
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
    public let onFailure: (String) -> Void

    public init(
        allowsPrototypeCandidate: Bool = false,
        cameraPreset: BodyCameraPreset = .front,
        markers: [BodyLocation] = [],
        onReady: @escaping () -> Void = {},
        onFailure: @escaping (String) -> Void = { _ in },
        onHitEvidence: @escaping (BodyHitEvidence) -> Void = { _ in }
    ) {
        self.onFailure = onFailure
    }

    public var body: some View {
        ContentUnavailableView("iOS 3D preview", systemImage: "iphone", description: Text("请在 iOS target 中运行原生 RealityKit 适配器。"))
    }
}
#endif
