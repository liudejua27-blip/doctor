import BodyCompanionCore
import SwiftUI

#if os(iOS)
import RealityKit
import UIKit

/// Native RealityKit adapter. It emits hit evidence only; it never owns a
/// BodyLocation, Episode, Agent conclusion, or health record.
public struct BodySceneView: UIViewRepresentable {
    public let onReady: () -> Void
    public let onFailure: (String) -> Void
    public let onHitEvidence: (BodyHitEvidence) -> Void

    public init(
        onReady: @escaping () -> Void,
        onFailure: @escaping (String) -> Void,
        onHitEvidence: @escaping (BodyHitEvidence) -> Void
    ) {
        self.onReady = onReady
        self.onFailure = onFailure
        self.onHitEvidence = onHitEvidence
    }

    public func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        // Production asset loading is intentionally not wired until AssetManifest
        // and licensing gates are approved. An empty native scene is safer than a
        // visual model with unverified anatomy or coordinates.
        DispatchQueue.main.async {
            onFailure("approved AssetManifest not configured; using 2D fallback")
        }
        return view
    }

    public func updateUIView(_ uiView: ARView, context: Context) {}
}
#else

/// The prototype harness is macOS-compilable but the RealityKit view is iOS-only.
public struct BodySceneView: View {
    public let onFailure: (String) -> Void

    public init(
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
