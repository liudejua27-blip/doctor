import BodyCompanionCore
import SwiftUI

public struct BodyMapScreen: View {
    @State private var model: BodyMapModel
    @State private var cameraPreset: BodyCameraPreset = .front
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
                        model.clearInteractionNotice()
                        if newMode == .threeD { model.request3D() } else { model.switchTo2D() }
                    }
                )) {
                    ForEach(BodyMapMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityHint("2D 提供完整触控区域和部位列表；3D 在不可用时会回退到 2D。")

                Picker("标记方式", selection: Binding(
                    get: { model.markingMode },
                    set: {
                        model.markingMode = $0
                        model.clearInteractionNotice()
                    }
                )) {
                    ForEach(BodyMarkingMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityHint("区域用于表达大致位置，针点用于表达表面上的精确位置；两种草稿会同时保留。")

                if model.markingMode == .pin {
                    HStack(spacing: 4) {
                        Label("针点", systemImage: "mappin.and.ellipse")
                        Text(String(model.pinCount))
                        Text("/")
                        Text(String(BodyMapModel.maximumPinCount))
                    }
                    .font(.caption)
                    .foregroundStyle(model.pinCount >= BodyMapModel.maximumPinCount ? .orange : .secondary)
                    .accessibilityLabel("针点数量 " + String(model.pinCount) + "，最多 " + String(BodyMapModel.maximumPinCount) + " 个")
                }

                if model.lastMutation == .rejectedPinLimit {
                    BodyMapNotice(
                        text: "已达到 20 个针点上限，请编辑或删除已有针点。",
                        systemImage: "exclamationmark.circle"
                    ) {
                        model.clearInteractionNotice()
                    }
                }

                if case let .fallback2D(reason) = model.loadState {
                    BodyMapNotice(text: reason, systemImage: "arrow.uturn.backward.circle") {
                        model.switchTo2D()
                    }
                }

                modeContent

                Text("标记只表示你主观指出的不适位置，不代表疼痛来源、受损组织或医学定位。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("位置说明：标记只表示你主观指出的不适位置，不代表疼痛来源、受损组织或医学定位。")

                if !model.marks.isEmpty {
                    MarkSummaryPanel(model: model)

                    NavigationLink(value: AppRoute.intake) {
                        Label("继续填写结构化描述", systemImage: "list.clipboard")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("记录身体信号")
        .onChange(of: model.marks) { _, _ in
            // The parent adapter can project the latest user-edited mark
            // descriptors into typed intake without treating them as saved.
            onLocationsChanged(model.markerDrafts)
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        switch model.mode {
        case .twoD:
            BodyMap2DView(model: model)
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

                    if let focusedRegionID = model.focusedRegionID {
                        HStack(spacing: 8) {
                            Label("正在查看：\(focusedRegionID)", systemImage: "scope")
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Button("返回全身") {
                                model.focus(regionID: nil)
                            }
                            .buttonStyle(.bordered)
                            .frame(minHeight: 44)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("正在聚焦\(focusedRegionID)，可返回全身")
                    }

                    BodySceneView(
                        allowsPrototypeCandidate: prototype3DEnabled,
                        cameraPreset: cameraPreset,
                        marks: model.marks,
                        focusedRegionID: model.focusedRegionID,
                        selectedMarkID: model.selectedMarkID,
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
                            let mutation = model.applySelection(location)
                            if mutation == .rejectedPinLimit {
                                return
                            }
                        },
                        onMarkerTapped: { id in
                            model.selectMark(id: id)
                        }
                    )
                    .frame(minHeight: 320)
                    .accessibilityLabel("原生 3D 身体地图；可拖动旋转、双指缩放并轻点部位。当前为\(model.markingMode.displayName)模式。若不可用，可切换到 2D 或部位列表。")
                }
            }
        }
    }
}

private struct BodyMap2DView: View {
    let model: BodyMapModel

    var body: some View {
        VStack(spacing: 12) {
            Picker("视图", selection: Binding(get: { model.view }, set: { model.view = $0 })) {
                Text("前面").tag(BodyMapView.front)
                Text("后面").tag(BodyMapView.back)
            }
            .pickerStyle(.segmented)

            BodyMapCanvas(view: model.view, marks: model.marks) { point in
                guard let option = BodyRegionCatalog.hitTest(point: point, view: model.view) else { return }
                select(option: option, point: point, source: .bodyMap2D)
            }
            .frame(maxWidth: .infinity)

            AccessibleRegionPicker(model: model)
        }
    }

    private func select(option: BodyRegionOption, point: Point2D?, source: BodyMapSource) {
        if model.markingMode == .pin,
           let point,
           model.selectExistingPin(at: point, view: model.view) {
            return
        }
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
        _ = model.applySelection(BodyLocationMapper.from2D(selection))
    }
}

private struct BodyMapNotice: View {
    let text: String
    let systemImage: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Label(text, systemImage: systemImage)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("知道了", action: onDismiss)
                .font(.footnote.weight(.semibold))
                .frame(minHeight: 44)
                .accessibilityLabel("关闭提示")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(.orange)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}

private struct BodyMapCanvas: View {
    let view: BodyMapView
    let marks: [BodyMark]
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

                ForEach(marks.filter { $0.kind == .zone && $0.isVisible }) { mark in
                    if let option = BodyRegionCatalog.option(regionID: mark.location.regionID, laterality: mark.location.laterality),
                       let geometry = option.geometry(for: view) {
                        BodyRegionHitShape(geometry: geometry)
                            .fill(mark.zoneVisualState == .reviewing ? Color.orange.opacity(0.30) : Color.teal.opacity(0.30))
                            .overlay(BodyRegionHitShape(geometry: geometry).stroke(Color.white.opacity(0.9), lineWidth: 2))
                            .frame(width: canvasSize.width, height: canvasSize.height)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }

                ForEach(marks.filter(\.isVisible)) { mark in
                    if let anchor = mark.location.anchor2D, anchor.view == view, let point = anchor.point {
                        Circle()
                            .fill(mark.kind == .zone ? (mark.zoneVisualState == .reviewing ? Color.orange : Color.teal) : pinColor(mark.colorToken))
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .frame(width: mark.kind == .zone ? 20 : 16, height: mark.kind == .zone ? 20 : 16)
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

    private func pinColor(_ token: Int) -> Color {
        let colors: [Color] = [.red, .blue, .orange, .purple, .green, .pink, .teal, .indigo, .yellow, .cyan, .mint, .brown]
        return colors[abs(token) % colors.count]
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
                        point: model.markingMode == .pin
                            ? option.geometry(for: model.view)?.representativePoint
                            : nil,
                        userLabel: option.label
                    )
                    _ = model.applySelection(BodyLocationMapper.from2D(selection))
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

private struct MarkSummaryPanel: View {
    let model: BodyMapModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isEditorPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("待确认标记（\(model.marks.count)）")
                    .font(.headline)
                Spacer()
                Button("清空") {
                    model.clearMarkers()
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .disabled(model.marks.isEmpty)
            }

            ForEach(model.marks) { mark in
                HStack(spacing: 10) {
                    Button {
                        model.selectMark(id: mark.id)
                        if horizontalSizeClass == .compact {
                            isEditorPresented = true
                        }
                    } label: {
                        HStack(spacing: 10) {
                        Image(systemName: mark.kind == .zone ? "square.dashed" : "mappin.circle.fill")
                            .foregroundStyle(mark.kind == .zone ? .teal : pinColor(mark.colorToken))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mark.displayLabel)
                                .font(.body.weight(.semibold))
                            Text(summary(for: mark))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        if mark.id == model.selectedMarkID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(mark.kind.displayName)：\(mark.displayLabel)，\(summary(for: mark))")

                    Button {
                        model.removeDraft(id: mark.id)
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("删除\(mark.displayLabel)")
                }
                .padding(10)
                .background(mark.id == model.selectedMarkID ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }

            if let selected = model.selectedMark() {
                if horizontalSizeClass != .compact {
                    MarkEditor(model: model, mark: selected)
                }
            }
        }
        .onAppear {
            if horizontalSizeClass == .compact, model.selectedMarkID != nil {
                isEditorPresented = true
            }
        }
        .onChange(of: model.selectedMarkID) { _, selectedID in
            guard horizontalSizeClass == .compact else { return }
            isEditorPresented = selectedID != nil
        }
        .sheet(isPresented: $isEditorPresented) {
            NavigationStack {
                ScrollView {
                    if let selected = model.selectedMark() {
                        MarkEditor(model: model, mark: selected)
                            .padding()
                    } else {
                        ContentUnavailableView("没有待编辑标记", systemImage: "mappin.slash")
                    }
                }
                .navigationTitle("编辑身体标记")
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func summary(for mark: BodyMark) -> String {
        var parts = [mark.kind.displayName]
        if mark.kind == .zone { parts.append(mark.zoneVisualState.displayName) }
        if let sensation = mark.sensation { parts.append(sensation.displayName) }
        if let intensity = mark.intensity { parts.append("程度 \(intensity)/10") }
        if !mark.triggers.isEmpty {
            parts.append(mark.triggers.sorted { $0.rawValue < $1.rawValue }.map(\.displayName).joined(separator: "、"))
        }
        return parts.joined(separator: " · ")
    }

    private func pinColor(_ token: Int) -> Color {
        let colors: [Color] = [.red, .blue, .orange, .purple, .green, .pink, .teal, .indigo, .yellow, .cyan, .mint, .brown]
        return colors[abs(token) % colors.count]
    }
}

private struct MarkEditor: View {
    let model: BodyMapModel
    let mark: BodyMark

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("编辑\(mark.kind.displayName)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if mark.kind == .zone {
                    Button {
                        _ = model.toggleZone(mark.location)
                    } label: {
                        Label(mark.zoneVisualState.displayName, systemImage: "circle.lefthalf.filled")
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                }
            }

            Text("感觉（可选；不填写不会自动猜测）")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
                ForEach(BodyMarkSensation.allCases, id: \.self) { sensation in
                    Button {
                        _ = model.setSensation(mark.sensation == sensation ? nil : sensation, for: mark.id)
                    } label: {
                        Text(sensation.displayName)
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.bordered)
                    .tint(mark.sensation == sensation ? .accentColor : .secondary)
                    .accessibilityLabel("感觉\(sensation.displayName)")
                }
            }

            Text("动作/功能线索（可选）")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
                ForEach(BodyMarkTrigger.allCases, id: \.self) { trigger in
                    Button {
                        _ = model.toggleTrigger(trigger, for: mark.id)
                    } label: {
                        Text(trigger.displayName)
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.bordered)
                    .tint(mark.triggers.contains(trigger) ? .orange : .secondary)
                }
            }

            HStack {
                Text("当前程度")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(mark.intensity.map { "\($0)/10" } ?? "未填写")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(mark.intensity ?? 0) },
                    set: { _ = model.setIntensity(Int($0.rounded()), for: mark.id) }
                ),
                in: 0...10,
                step: 1
            )
            .accessibilityValue(mark.intensity.map { "\($0)/10" } ?? "未填写")
            Button("清除程度") {
                _ = model.setIntensity(nil, for: mark.id)
            }
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}
