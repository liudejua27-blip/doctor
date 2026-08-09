import BodyCompanionCore
import SwiftUI

public struct BodyMapScreen: View {
    @State private var model: BodyMapModel
    @State private var cameraPreset: BodyCameraPreset = .front
    @State private var isAccessibleRegionPickerPresented = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let onLocationsChanged: ([BodyLocation]) -> Bool
    private let prototype3DEnabled: Bool

    /// `prototype3DEnabled` is intentionally explicit. The current executable
    /// is an internal prototype; a production caller must leave it false until
    /// an approved BodyAssetManifest is wired into the release target.
    public init(
        model: BodyMapModel = BodyMapModel(),
        prototype3DEnabled: Bool = false,
        onLocationsChanged: @escaping ([BodyLocation]) -> Bool = { _ in true }
    ) {
        _model = State(initialValue: model)
        self.prototype3DEnabled = prototype3DEnabled
        self.onLocationsChanged = onLocationsChanged
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CompanionSectionHeading(
                    eyebrow: "第 1 步 / 共 3 步",
                    title: "哪里不舒服？",
                    detail: "轻点你感觉不适的位置；这只是你的主观位置表达。"
                )

                CompanionCard {
                    VStack(alignment: .leading, spacing: 14) {
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
                        .accessibilityIdentifier("body-map.mode")

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

                        HStack(spacing: 8) {
                            CompanionStatusPill("位置 \(model.markerCount) / \(BodyMapModel.maximumMarkerCount)", systemImage: "mappin.and.ellipse", tint: model.markerCount >= BodyMapModel.maximumMarkerCount ? BodyCompanionTheme.warm : BodyCompanionTheme.accent)
                            Text("区域和针点合计最多 20 个；选中已有针点不会重复新增。")
                                .font(.caption)
                                .foregroundStyle(BodyCompanionTheme.secondaryInk)
                        }
                        .accessibilityLabel("位置标记数量 \(model.markerCount)，区域和针点合计最多 \(BodyMapModel.maximumMarkerCount) 个")
                    }
                }

                if model.lastMutation == .rejectedMarkerLimit {
                    BodyMapNotice(
                        text: "已达到 20 个位置上限，请编辑或删除已有标记。",
                        systemImage: "exclamationmark.circle",
                        identifier: "body-map.limit-notice"
                    ) {
                        model.clearInteractionNotice()
                    }
                }

                if model.lastMutation == .rejectedDuplicateLocation {
                    BodyMapNotice(
                        text: "这个位置标记已存在，未重复加入记录。",
                        systemImage: "exclamationmark.circle",
                        identifier: "body-map.duplicate-notice"
                    ) {
                        model.clearInteractionNotice()
                    }
                }

                if model.lastMutation == .rejectedDraftSynchronization {
                    BodyMapNotice(
                        text: "位置未能同步到当前记录，已恢复到上一次有效状态。",
                        systemImage: "exclamationmark.triangle",
                        identifier: "body-map.sync-notice"
                    ) {
                        model.clearInteractionNotice()
                    }
                }

                if case let .fallback2D(reason) = model.loadState {
                    BodyMapNotice(
                        text: reason,
                        systemImage: "arrow.uturn.backward.circle",
                        identifier: prototype3DEnabled
                            ? "body-map.candidate-3d-fallback-notice"
                            : "body-map.fallback-notice"
                    ) {
                        model.switchTo2D()
                    }
                    if prototype3DEnabled, model.hasRecordedThreeDLoadAttempt {
                        Text("内部候选加载请求已发起；已保留 2D/列表路径。")
                            .font(.caption2)
                            .foregroundStyle(BodyCompanionTheme.secondaryInk)
                            .accessibilityIdentifier("body-map.candidate-3d-load-attempted")
                    }
                }

                CompanionCard {
                    modeContent
                }

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(BodyCompanionTheme.mint)
                        .frame(width: 24)
                    Text("标记只表示你主观指出的不适位置，不代表疼痛来源、受损组织或医学定位。")
                        .font(.footnote)
                        .foregroundStyle(BodyCompanionTheme.secondaryInk)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("位置说明：标记只表示你主观指出的不适位置，不代表疼痛来源、受损组织或医学定位。")

                if !model.marks.isEmpty {
                    MarkSummaryPanel(model: model)

                    NavigationLink(value: AppRoute.intake) {
                        Label("下一步：描述你的感受", systemImage: "arrow.right")
                    }
                    .buttonStyle(CompanionPrimaryButtonStyle())
                    .accessibilityHint("进入结构化草稿填写，后续仍可返回修改位置")
                    .accessibilityIdentifier("body-map.next")
                }
            }
            .padding(20)
        }
        .navigationTitle("记录这次不适")
        .companionScreenBackground()
        .accessibilityIdentifier("screen.body-map")
        .sheet(isPresented: $isAccessibleRegionPickerPresented) {
            NavigationStack {
                ScrollView {
                    AccessibleRegionPicker(
                        model: model,
                        showsViewPicker: true,
                        identifierPrefix: "body-map.sheet-list"
                    )
                        .padding(20)
                }
                .navigationTitle("从列表选择部位")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { isAccessibleRegionPickerPresented = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: model.marks) { previousMarks, _ in
            // The map owns only provisional locations. Typed health facts
            // remain owned by SignalIntakeScreen and are never projected from
            // BodyMark state.
            guard !model.marks.isEmpty || !previousMarks.isEmpty else { return }
            if !onLocationsChanged(model.markerDrafts) {
                model.restoreMarks(previousMarks)
            }
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        switch model.mode {
        case .twoD:
            BodyMap2DView(model: model)
        case .threeD:
            if prototype3DEnabled {
                candidateThreeDContent
            } else {
                ProgressView("加载原生 3D…")
                    .frame(maxWidth: .infinity, minHeight: 320)
                    .task {
                        // A production manifest is fail-closed. Only the
                        // explicit internal candidate path below may create
                        // a RealityKit view; all normal callers return to 2D.
                        model.mark3DFailed("3D 资产尚未批准，已回退到 2D")
                    }
            }
        }
    }

    @ViewBuilder
    private var candidateThreeDContent: some View {
        if let attemptID = model.activeThreeDAttemptID {
            let isReady = model.isCurrentThreeDReady(for: attemptID)
            VStack(alignment: .leading, spacing: 8) {
            if !isReady {
                CompanionStatusPill("正在加载内部候选模型", systemImage: "hourglass", tint: BodyCompanionTheme.warm)
                    .accessibilityLabel("正在加载内部候选模型；未经生产审核")
                    .accessibilityIdentifier("body-map.candidate-3d-loading")
            } else {
                CompanionStatusPill("内部候选模型 · 未经生产审核", systemImage: "flask", tint: BodyCompanionTheme.warm)
                    .accessibilityLabel("内部候选模型，未经生产审核")
                    .accessibilityIdentifier("body-map.candidate-3d-ready")
            }

            if model.hasRecordedCurrentThreeDLoadAttempt {
                Text("内部候选加载请求已发起")
                    .font(.caption2)
                    .foregroundStyle(BodyCompanionTheme.secondaryInk)
                    .accessibilityIdentifier("body-map.candidate-3d-load-attempted")
            }

            Picker("3D 视角", selection: $cameraPreset) {
                ForEach(BodyCameraPreset.allCases, id: \.self) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .pickerStyle(.segmented)

            Button {
                isAccessibleRegionPickerPresented = true
            } label: {
                Label("从列表选择部位", systemImage: "list.bullet")
            }
            .buttonStyle(CompanionOutlineButtonStyle())
            .accessibilityHint("无需操作 3D 人体，也能选择前面或后面的身体部位")
            .accessibilityIdentifier("body-map.3d-list")

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
                allowsPrototypeCandidate: true,
                cameraPreset: cameraPreset,
                marks: model.marks,
                focusedRegionID: model.focusedRegionID,
                selectedMarkID: model.selectedMarkID,
                onLoadAttempted: { model.mark3DLoadAttempted(for: attemptID) },
                onReady: { model.mark3DReady(for: attemptID) },
                onFailure: { model.mark3DFailed($0, for: attemptID) },
                onHitEvidence: { evidence in
                    guard model.isCurrentThreeDReady(for: attemptID),
                          let option = BodyRegionCatalog.option(forEntityID: evidence.entityID),
                          let location = BodyLocationMapper.from3D(
                              evidence,
                              regionID: option.regionID,
                              laterality: option.laterality,
                              surface: option.surface,
                              depth: option.depth
                          ) else { return }
                    let mutation = model.applySelection(location)
                    if mutation == .rejectedMarkerLimit || mutation == .rejectedDuplicateLocation {
                        return
                    }
                },
                onMarkerTapped: { id in
                    model.selectMark(id: id)
                }
            )
            .id(attemptID)
            .frame(minHeight: 320)
            .accessibilityIdentifier("body-map.3d-scene")
            .accessibilityLabel("原生 3D 身体地图；可拖动旋转、双指缩放并轻点部位。当前为\(model.markingMode.displayName)模式。若不可用，可切换到 2D 或部位列表。")
            }
            .task(id: attemptID) {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            model.mark3DFailed("内部候选 3D 初始化超时；已回退到 2D", for: attemptID)
            }
        } else {
            // This should be unreachable because request3D() creates the ID
            // before mode changes. Fail closed if a future caller violates it.
            ProgressView("内部候选 3D 状态无效；正在回退到 2D…")
                .frame(maxWidth: .infinity, minHeight: 320)
                .task { model.mark3DFailed("内部候选 3D 状态无效；已回退到 2D") }
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

            AccessibleRegionPicker(
                model: model,
                showsViewPicker: false,
                identifierPrefix: "body-map.2d-list"
            )
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
    let identifier: String
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
        .accessibilityIdentifier(identifier)
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
                    .fill(BodyCompanionTheme.surfaceTinted)
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(BodyCompanionTheme.line))

                NeutralBodySilhouette()
                    .fill(BodyCompanionTheme.accent.opacity(0.12))
                    .overlay(NeutralBodySilhouette().stroke(BodyCompanionTheme.accent.opacity(0.42), lineWidth: 1.5))
                    .frame(width: canvasSize.width * 0.78, height: canvasSize.height * 0.86)

                ForEach(BodyRegionCatalog.options(for: view)) { option in
                    if let geometry = option.geometry(for: view) {
                        BodyRegionHitShape(geometry: geometry)
                            .fill(BodyCompanionTheme.accent.opacity(0.035))
                            .overlay(BodyRegionHitShape(geometry: geometry).stroke(BodyCompanionTheme.accent.opacity(0.16), lineWidth: 1))
                            .frame(width: canvasSize.width, height: canvasSize.height)
                            .contentShape(BodyRegionHitShape(geometry: geometry))
                            .accessibilityHidden(true)
                    }
                }

                ForEach(marks.filter { $0.kind == .zone && $0.isVisible }) { mark in
                    if let option = BodyRegionCatalog.option(regionID: mark.location.regionID, laterality: mark.location.laterality),
                       let geometry = option.geometry(for: view) {
                        BodyRegionHitShape(geometry: geometry)
                            .fill(BodyCompanionTheme.accent.opacity(0.30))
                            .overlay(BodyRegionHitShape(geometry: geometry).stroke(Color.white.opacity(0.9), lineWidth: 2))
                            .frame(width: canvasSize.width, height: canvasSize.height)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }

                ForEach(marks.filter(\.isVisible)) { mark in
                    if let anchor = mark.location.anchor2D, anchor.view == view, let point = anchor.point {
                        Circle()
                            .fill(markerColor(for: mark))
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
                            .foregroundStyle(BodyCompanionTheme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.thinMaterial, in: Capsule())
                        Spacer()
                        Text("轻点标记位置")
                            .font(.caption)
                            .foregroundStyle(BodyCompanionTheme.secondaryInk)
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

    private func markerColor(for mark: BodyMark) -> Color {
        mark.kind == .zone ? BodyCompanionTheme.accent : pinColor(mark.colorToken)
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
    let showsViewPicker: Bool
    let identifierPrefix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("部位列表")
                .font(.headline)
            Text("如果触控不方便，可以从列表选择大致位置。")
                .font(.caption)
                .foregroundStyle(BodyCompanionTheme.secondaryInk)

            if showsViewPicker {
                Picker("选择身体表面", selection: Binding(get: { model.view }, set: { model.view = $0 })) {
                    Text("前面").tag(BodyMapView.front)
                    Text("后面").tag(BodyMapView.back)
                }
                .pickerStyle(.segmented)
                .accessibilityHint("选择前面或后面的部位列表；与 2D 和 3D 使用同一位置契约。")
            }

            ForEach(Array(BodyRegionCatalog.options(for: model.view).enumerated()), id: \.element.id) { index, option in
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
                            .foregroundStyle(BodyCompanionTheme.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityLabel("选择\(option.label)")
                .accessibilityHint("添加一个待确认的位置标记")
                .accessibilityIdentifier("\(identifierPrefix).option-\(index)")
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
                    .foregroundStyle(BodyCompanionTheme.ink)
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
                            .foregroundStyle(mark.kind == .zone ? BodyCompanionTheme.accent : pinColor(mark.colorToken))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mark.displayLabel)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(BodyCompanionTheme.ink)
                            Text(summary(for: mark))
                                .font(.caption)
                                .foregroundStyle(BodyCompanionTheme.secondaryInk)
                                .lineLimit(2)
                        }
                        Spacer()
                        if mark.id == model.selectedMarkID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(BodyCompanionTheme.accent)
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
                .background(mark.id == model.selectedMarkID ? BodyCompanionTheme.accentSoft : BodyCompanionTheme.surfaceTinted.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if let selected = model.selectedMark() {
                if horizontalSizeClass != .compact {
                    MarkEditor(model: model, mark: selected)
                        .id(selected.id)
                }
            }
        }
        .padding(18)
        .background(BodyCompanionTheme.surface, in: RoundedRectangle(cornerRadius: BodyCompanionTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BodyCompanionTheme.cornerRadius, style: .continuous)
                .stroke(BodyCompanionTheme.line.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: BodyCompanionTheme.shadow, radius: 14, y: 7)
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
                            .id(selected.id)
                            .padding()
                    } else {
                        ContentUnavailableView("没有待编辑标记", systemImage: "mappin.slash")
                    }
                }
                .navigationTitle("编辑身体标记")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { isEditorPresented = false }
                            .accessibilityIdentifier("body-map.mark-editor-done")
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func summary(for mark: BodyMark) -> String {
        [
            mark.kind.displayName,
            localizedLaterality(mark.location.laterality),
            localizedSurface(mark.location.surface)
        ].joined(separator: " · ")
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
                Text("位置详情")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            LabeledContent("标记方式", value: mark.kind.displayName)
            LabeledContent("部位", value: mark.displayLabel)
            LabeledContent("侧别", value: localizedLaterality(mark.location.laterality))
            LabeledContent("表面", value: localizedSurface(mark.location.surface))
            LabeledContent("定位方式", value: mark.kind == .pin ? "精确针点" : "大致区域")
            LabeledContent("位置来源", value: localizedSource(mark.location.source.interaction))

            Text("这里仅记录你指出的位置。感觉、程度和什么动作会加重，请在下一步的结构化描述中填写。")
                .font(.footnote)
                .foregroundStyle(BodyCompanionTheme.secondaryInk)

            Button("删除这个位置", role: .destructive) {
                model.removeDraft(id: mark.id)
            }
            .frame(minHeight: 44)
        }
        .padding(12)
        .background(BodyCompanionTheme.surfaceTinted.opacity(0.65), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private func localizedLaterality(_ laterality: Laterality) -> String {
    switch laterality {
    case .left: "左侧"
    case .right: "右侧"
    case .midline: "中线"
    case .bilateral: "双侧"
    case .unspecified: "未指定"
    }
}

private func localizedSurface(_ surface: BodySurface) -> String {
    switch surface {
    case .anterior: "前面"
    case .posterior: "后面"
    case .medial: "内侧"
    case .lateral: "外侧"
    case .superior: "上方"
    case .inferior: "下方"
    case .circumferential: "环绕"
    case .unspecified: "未指定"
    }
}

private func localizedSource(_ source: BodyMapSource) -> String {
    switch source {
    case .bodyMap2D: "2D 人体图"
    case .bodyMap3D: "3D 人体图"
    case .bodyPartSearch: "部位列表"
    case .documentImport: "导入资料"
    case .agentNormalization: "待确认的系统整理"
    }
}
