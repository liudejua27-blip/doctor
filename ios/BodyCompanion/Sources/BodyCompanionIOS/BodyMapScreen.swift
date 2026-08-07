import BodyCompanionCore
import SwiftUI

public struct BodyMapScreen: View {
    @State private var model: BodyMapModel
    private let onLocationsChanged: ([BodyLocation]) -> Void

    public init(
        model: BodyMapModel = BodyMapModel(),
        onLocationsChanged: @escaping ([BodyLocation]) -> Void = { _ in }
    ) {
        _model = State(initialValue: model)
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
                    .task { model.mark3DFailed("3D 资产尚未批准，已回退到 2D") }
            } else {
                BodySceneView(
                    onReady: { model.mark3DReady() },
                    onFailure: { model.mark3DFailed($0) },
                    onHitEvidence: { _ in }
                )
                .frame(minHeight: 320)
                .accessibilityLabel("原生 3D 身体地图；如果不可用，可切换到 2D 或部位列表。")
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

            HStack(spacing: 20) {
                regionButton(side: .left)
                RoundedRectangle(cornerRadius: 36)
                    .fill(Color.blue.opacity(0.08))
                    .overlay(Text("身体\n2D").multilineTextAlignment(.center))
                    .frame(width: 120, height: 240)
                    .accessibilityHidden(true)
                regionButton(side: .right)
            }

            AccessibleRegionPicker(model: model, onLocationsChanged: onLocationsChanged)
        }
    }

    private func regionButton(side: Laterality) -> some View {
        Button {
            let selection = BodyRegionSelection(
                regionID: "body.knee.general",
                laterality: side,
                surface: model.view == .front ? .anterior : .posterior,
                source: .bodyMap2D,
                view: model.view,
                point: Point2D(x: side == .left ? 0.42 : 0.58, y: 0.64),
                userLabel: side == .left ? "左膝附近" : "右膝附近"
            )
            model.select(BodyLocationMapper.from2D(selection))
            onLocationsChanged(model.markerDrafts)
        } label: {
            Label(side == .left ? "左膝附近" : "右膝附近", systemImage: "mappin.and.ellipse")
        }
        .buttonStyle(.bordered)
        .frame(minWidth: 80, minHeight: 44)
    }
}

private struct AccessibleRegionPicker: View {
    let model: BodyMapModel
    let onLocationsChanged: ([BodyLocation]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("部位列表")
                .font(.headline)
            ForEach([Laterality.left, .right], id: \.self) { side in
                Button(side == .left ? "选择左膝附近" : "选择右膝附近") {
                    let selection = BodyRegionSelection(
                        regionID: "body.knee.general",
                        laterality: side,
                        surface: model.view == .front ? .anterior : .posterior,
                        source: .bodyPartSearch,
                        view: model.view,
                        userLabel: side == .left ? "左膝附近" : "右膝附近"
                    )
                    model.select(BodyLocationMapper.from2D(selection))
                    onLocationsChanged(model.markerDrafts)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
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
