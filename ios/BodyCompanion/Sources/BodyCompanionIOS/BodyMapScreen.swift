import BodyCompanionCore
import SwiftUI

public struct BodyMapScreen: View {
    @State private var model: BodyMapModel
    @State private var cameraPreset: BodyCameraPreset = .front
    private let onLocationsChanged: ([BodyLocation]) -> Void
    private let prototype3DEnabled: Bool

    /// `prototype3DEnabled` is intentionally explicit. The current executable
    /// is an internal prototype; a production caller must leave it false until
    /// an approved BodyAssetManifest is wired into the release target.
    public init(
        model: BodyMapModel = BodyMapModel(),
        prototype3DEnabled: Bool = false,
        onLocationsChanged: @escaping ([BodyLocation]) -> Void = { _ in }
    ) {
        _model = State(initialValue: model)
        self.prototype3DEnabled = prototype3DEnabled
        self.onLocationsChanged = onLocationsChanged
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("身体地图模式", selection: Binding(
                    get: { model.mode },
                    set: { newMode in
                        if newMode == .threeD { model.request3D() } else { model.switchTo2D() }
                    }
                )) {
                    ForEach(BodyMapMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityHint("2D 提供完整触控区域和部位列表；3D 在不可用时会回退到 2D。")

                modeContent

                Text("标记只表示你主观指出的不适位置，不代表疼痛来源、受损组织或医学定位。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("位置说明：标记只表示你主观指出的不适位置，不代表疼痛来源、受损组织或医学定位。")

                if !model.markerDrafts.isEmpty {
                    DraftMarkerList(model: model, onLocationsChanged: onLocationsChanged)

                    NavigationLink(value: AppRoute.intake) {
                        Label("继续填写结构化描述", systemImage: "list.clipboard")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("记录身体信号")
    }

    @ViewBuilder
    private var modeContent: some View {
        switch model.mode {
        case .twoD:
            BodyMap2DView(model: model, onLocationsChanged: onLocationsChanged)
        case .threeD:
            if case .loading = model.loadState {
                ProgressView("加载原生 3D…")
                    .frame(maxWidth: .infinity, minHeight: 320)
                    .task {
                        // A production manifest is fail-closed. The explicit
                        // prototype flag is the only path that can load the
                        // original procedural candidate in this harness.
                        if prototype3DEnabled {
                            model.mark3DReady()
                        } else {
                            model.mark3DFailed("3D 资产尚未批准，已回退到 2D")
                        }
                    }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if prototype3DEnabled {
                        Label("内部候选模型 · 未经生产审核", systemImage: "flask")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("内部候选模型，未经生产审核")
                    }

                    Picker("3D 视角", selection: $cameraPreset) {
                        ForEach(BodyCameraPreset.allCases, id: \.self) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)

                    BodySceneView(
                        allowsPrototypeCandidate: prototype3DEnabled,
                        cameraPreset: cameraPreset,
                        markers: model.markerDrafts,
                        onReady: { model.mark3DReady() },
                        onFailure: { model.mark3DFailed($0) },
                        onHitEvidence: { evidence in
                            guard let option = BodyRegionCatalog.option(forEntityID: evidence.entityID),
                                  let location = BodyLocationMapper.from3D(
                                      evidence,
                                      regionID: option.regionID,
                                      laterality: option.laterality,
                                      surface: option.surface,
                                      depth: option.depth
                                  ) else { return }
                            model.select(location)
                            onLocationsChanged(model.markerDrafts)
                        }
                    )
                    .frame(minHeight: 320)
                    .accessibilityLabel("原生 3D 身体地图；可拖动旋转、双指缩放并轻点部位。若不可用，可切换到 2D 或部位列表。")
                }
            }
        }
    }
}

private struct BodyMap2DView: View {
    let model: BodyMapModel
    let onLocationsChanged: ([BodyLocation]) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Picker("视图", selection: Binding(get: { model.view }, set: { model.view = $0 })) {
                Text("前面").tag(BodyMapView.front)
                Text("后面").tag(BodyMapView.back)
            }
            .pickerStyle(.segmented)

            BodyMapCanvas(view: model.view, markers: model.markerDrafts) { point in
                guard let option = BodyRegionCatalog.hitTest(point: point, view: model.view) else { return }
                select(option: option, point: point, source: .bodyMap2D)
            }
            .frame(maxWidth: .infinity)

            AccessibleRegionPicker(model: model, onLocationsChanged: onLocationsChanged)
        }
    }

    private func select(option: BodyRegionOption, point: Point2D?, source: BodyMapSource) {
        let selection = BodyRegionSelection(
            regionID: option.regionID,
            laterality: option.laterality,
            surface: option.surface,
            depth: option.depth,
            source: source,
            view: model.view,
            point: point,
            userLabel: option.label
        )
        model.select(BodyLocationMapper.from2D(selection))
        onLocationsChanged(model.markerDrafts)
    }
}

private struct BodyMapCanvas: View {
    let view: BodyMapView
    let markers: [BodyLocation]
    let onSelect: (Point2D) -> Void

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = CGSize(width: min(proxy.size.width, 360), height: 520)
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.secondary.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.secondary.opacity(0.25)))

                NeutralBodySilhouette()
                    .fill(Color.accentColor.opacity(0.13))
                    .overlay(NeutralBodySilhouette().stroke(Color.accentColor.opacity(0.42), lineWidth: 1.5))
                    .frame(width: canvasSize.width * 0.78, height: canvasSize.height * 0.86)

                ForEach(BodyRegionCatalog.options(for: view)) { option in
                    if let geometry = option.geometry(for: view) {
                        BodyRegionHitShape(geometry: geometry)
                            .fill(Color.accentColor.opacity(0.035))
                            .overlay(BodyRegionHitShape(geometry: geometry).stroke(Color.accentColor.opacity(0.16), lineWidth: 1))
                            .frame(width: canvasSize.width, height: canvasSize.height)
                            .contentShape(BodyRegionHitShape(geometry: geometry))
                            .accessibilityHidden(true)
                    }
                }

                ForEach(markers) { marker in
                    if let anchor = marker.anchor2D, anchor.view == view, let point = anchor.point {
                        Circle()
                            .fill(Color.red)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .frame(width: 16, height: 16)
                            .position(x: point.x * canvasSize.width, y: point.y * canvasSize.height)
                            .accessibilityHidden(true)
                    }
                }

                VStack {
                    HStack {
                        Label(view == .front ? "前面" : "后面", systemImage: view == .front ? "person" : "person.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.thinMaterial, in: Capsule())
                        Spacer()
                        Text("轻点标记位置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    Spacer()
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                let x = min(max(value.location.x / canvasSize.width, 0), 1)
                let y = min(max(value.location.y / canvasSize.height, 0), 1)
                onSelect(Point2D(x: x, y: y))
            })
            .accessibilityElement(children: .contain)
            .accessibilityLabel("全身 2D 身体地图，当前为\(view == .front ? "前面" : "后面")")
            .accessibilityHint("轻点你感到不适的大致区域，或向下使用部位列表以精确选择。")
        }
        .frame(height: 520)
    }
}

private struct NeutralBodySilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = rect.midX
        let head = CGRect(x: center - rect.width * 0.105, y: rect.minY, width: rect.width * 0.21, height: rect.height * 0.14)
        path.addEllipse(in: head)
        path.addRoundedRect(
            in: CGRect(x: center - rect.width * 0.07, y: rect.minY + rect.height * 0.12, width: rect.width * 0.14, height: rect.height * 0.08),
            cornerSize: CGSize(width: 10, height: 10)
        )
        path.addRoundedRect(
            in: CGRect(x: center - rect.width * 0.23, y: rect.minY + rect.height * 0.18, width: rect.width * 0.46, height: rect.height * 0.30),
            cornerSize: CGSize(width: rect.width * 0.12, height: rect.width * 0.12)
        )
        path.addRoundedRect(
            in: CGRect(x: center - rect.width * 0.39, y: rect.minY + rect.height * 0.19, width: rect.width * 0.12, height: rect.height * 0.33),
            cornerSize: CGSize(width: rect.width * 0.06, height: rect.width * 0.06)
        )
        path.addRoundedRect(
            in: CGRect(x: center + rect.width * 0.27, y: rect.minY + rect.height * 0.19, width: rect.width * 0.12, height: rect.height * 0.33),
            cornerSize: CGSize(width: rect.width * 0.06, height: rect.width * 0.06)
        )
        path.addRoundedRect(
            in: CGRect(x: center - rect.width * 0.19, y: rect.minY + rect.height * 0.43, width: rect.width * 0.16, height: rect.height * 0.44),
            cornerSize: CGSize(width: rect.width * 0.07, height: rect.width * 0.07)
        )
        path.addRoundedRect(
            in: CGRect(x: center + rect.width * 0.03, y: rect.minY + rect.height * 0.43, width: rect.width * 0.16, height: rect.height * 0.44),
            cornerSize: CGSize(width: rect.width * 0.07, height: rect.width * 0.07)
        )
        path.addRoundedRect(
            in: CGRect(x: center - rect.width * 0.19, y: rect.minY + rect.height * 0.84, width: rect.width * 0.12, height: rect.height * 0.14),
            cornerSize: CGSize(width: rect.width * 0.05, height: rect.width * 0.05)
        )
        path.addRoundedRect(
            in: CGRect(x: center + rect.width * 0.07, y: rect.minY + rect.height * 0.84, width: rect.width * 0.12, height: rect.height * 0.14),
            cornerSize: CGSize(width: rect.width * 0.05, height: rect.width * 0.05)
        )
        return path
    }
}

private struct BodyRegionHitShape: Shape {
    let geometry: BodyRegionGeometry

    func path(in rect: CGRect) -> Path {
        switch geometry {
        case let .ellipse(center, radius):
            return Path(ellipseIn: CGRect(
                x: center.x * rect.width - radius.x * rect.width,
                y: center.y * rect.height - radius.y * rect.height,
                width: radius.x * 2 * rect.width,
                height: radius.y * 2 * rect.height
            ))
        case let .rectangle(origin, size):
            return Path(CGRect(
                x: origin.x * rect.width,
                y: origin.y * rect.height,
                width: size.x * rect.width,
                height: size.y * rect.height
            ))
        }
    }
}

private struct AccessibleRegionPicker: View {
    let model: BodyMapModel
    let onLocationsChanged: ([BodyLocation]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("部位列表")
                .font(.headline)
            Text("如果触控不方便，可以从列表选择大致位置。")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(BodyRegionCatalog.options(for: model.view)) { option in
                Button {
                    let selection = BodyRegionSelection(
                        regionID: option.regionID,
                        laterality: option.laterality,
                        surface: option.surface,
                        depth: option.depth,
                        source: .bodyPartSearch,
                        view: model.view,
                        userLabel: option.label
                    )
                    model.select(BodyLocationMapper.from2D(selection))
                    onLocationsChanged(model.markerDrafts)
                } label: {
                    HStack {
                        Text(option.label)
                        Spacer()
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityLabel("选择\(option.label)")
                .accessibilityHint("添加一个待确认的位置标记")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct DraftMarkerList: View {
    let model: BodyMapModel
    let onLocationsChanged: ([BodyLocation]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("待确认位置")
                .font(.headline)
            ForEach(model.markerDrafts) { marker in
                HStack {
                    Text(marker.userLabel ?? marker.regionID)
                    Spacer()
                    Button("删除") {
                        model.removeDraft(id: marker.id)
                        onLocationsChanged(model.markerDrafts)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("待确认位置：\(marker.userLabel ?? marker.regionID)")
            }
        }
    }
}
