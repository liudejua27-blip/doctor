import BodyCompanionCore
import Foundation
import SwiftUI

private struct HeightProfilePreset: Hashable, Identifiable {
    let id: String
    let heightMeters: Float?

    init(heightMeters: Float) {
        self.heightMeters = heightMeters
        self.id = String(format: "%.2f", heightMeters)
    }

    private init(custom: Void) {
        self.heightMeters = nil
        self.id = "custom"
    }

    static let custom = HeightProfilePreset(custom: ())
    static let supportedHeightRangeMeters: ClosedRange<Float> = 1.35...2.20

    var label: String {
        guard let heightMeters else { return "自定义" }
        return String(format: "%.2fm", heightMeters)
    }

    static let defaultHeights: [Float] = [1.60, 1.70, 1.80]

    static func presetOptions(from rawHeights: [Float]) -> [HeightProfilePreset] {
        let normalized = rawHeights
            .compactMap(Self.normalizedHeightMeters)
            .sorted()
            .reduce(into: [Float]()) { acc, value in
                if acc.first(where: { abs($0 - value) < 0.0001 }) == nil {
                    acc.append(value)
                }
            }
        return normalized.map(HeightProfilePreset.init(heightMeters:))
    }

    static func nearestPreset(
        for heightMeters: Float,
        from presets: [HeightProfilePreset]
    ) -> HeightProfilePreset? {
        let candidates = presets.compactMap { preset in
            preset.heightMeters.map { (height: $0, preset: preset) }
        }
        return candidates.min(by: { abs($0.height - heightMeters) < abs($1.height - heightMeters) })?.preset
    }

    static func normalizedHeightMeters(_ value: Float?) -> Float? {
        guard let value else { return nil }
        guard value > 0 else { return nil }
        let meters = value > 3 ? value / 100 : value
        guard supportedHeightRangeMeters.contains(meters) else { return nil }
        return meters
    }
}

public struct BodyMapScreen: View {
    @State private var model: BodyMapModel
    @State private var cameraPreset: BodyCameraPreset = .front
    @State private var selectedHeightPreset: HeightProfilePreset = .custom
    @State private var customHeightInput: String = "1.75"
    @State private var isTextRegionPickerPresented = false
    private let heightProfilePresets: [HeightProfilePreset]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let onLocationsChanged: ([BodyLocation]) -> Bool
    private let onContinue: () -> Void
    private let prototype3DEnabled: Bool
    private let profileHeightMeters: Float?

    private static let defaultHeightMeters: Float = 1.75
    private static let customHeightSnapToleranceMeters: Float = 0.05

    /// `prototype3DEnabled` is intentionally explicit. The current executable
    /// is an internal prototype; a production caller must leave it false until
    /// an approved BodyAssetManifest is wired into the release target.
    public init(
        model: BodyMapModel = BodyMapModel(),
        userProfileHeightMeters: Float? = nil,
        heightPresetHeightsMeters: [Float]? = nil,
        prototype3DEnabled: Bool = false,
        onLocationsChanged: @escaping ([BodyLocation]) -> Bool = { _ in true },
        onContinue: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: model)
        let normalizedProfileHeight = Self.normalizedHeightMeters(from: userProfileHeightMeters)
        let normalizedPresetHeights = heightPresetHeightsMeters.flatMap(HeightProfilePreset.presetOptions(from:)) ?? HeightProfilePreset.presetOptions(from: HeightProfilePreset.defaultHeights)
        heightProfilePresets = normalizedPresetHeights
        profileHeightMeters = normalizedProfileHeight
        let preset = normalizedProfileHeight.flatMap {
            HeightProfilePreset.nearestPreset(for: $0, from: normalizedPresetHeights)
        } ?? normalizedPresetHeights.first(where: { $0.id == "1.70" })
            ?? normalizedPresetHeights.first
            ?? HeightProfilePreset(heightMeters: 1.70)
        _selectedHeightPreset = State(initialValue: preset)
        _customHeightInput = State(
            initialValue: {
                if let normalized = normalizedProfileHeight {
                    return String(format: "%.2f", normalized)
                }
                return String(format: "%.2f", Self.defaultHeightMeters)
            }()
        )
        self.prototype3DEnabled = prototype3DEnabled
        self.onLocationsChanged = onLocationsChanged
        self.onContinue = onContinue
    }

    private static func normalizedHeightMeters(from value: Float?) -> Float? {
        HeightProfilePreset.normalizedHeightMeters(value)
    }

    private static func normalizedHeightMeters(from input: String) -> Float? {
        let normalized = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: ",", with: ".")
        guard let parsed = Float(normalized) else { return nil }
        return HeightProfilePreset.normalizedHeightMeters(parsed)
    }

    private func syncInitialHeightPresetIfNeeded() {
        guard let profileHeightMeters else { return }
        selectedHeightPreset = HeightProfilePreset.nearestPreset(
            for: profileHeightMeters,
            from: heightProfilePresets
        ) ?? selectedHeightPreset
        customHeightInput = String(format: "%.2f", profileHeightMeters)
    }

    public var body: some View {
        VStack(spacing: 0) {
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

                            markerCountSummary
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
                        MarkSummaryPanel(
                            model: model,
                            suppressAutomaticEditor: isTextRegionPickerPresented
                        )
                    }
                }
                .padding(20)
            }
            // Keep the screen identifier on the scrolling content. The bottom
            // action is a sibling so an older SwiftUI runtime cannot omit it
            // from the accessibility tree as a conditional safe-area inset.
            .accessibilityIdentifier("screen.body-map")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            continuationFooter
        }
        .navigationTitle("记录这次不适")
        .safeAreaPadding(.top)
        .companionScreenBackground()
        .sheet(isPresented: $isTextRegionPickerPresented) {
            NavigationStack {
                AccessibleRegionPicker(
                    model: model,
                    showsViewPicker: true,
                    identifierPrefix: "body-map.text-picker"
                )
                .navigationTitle("用文字选择部位")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成", action: finishTextRegionPicker)
                            .accessibilityIdentifier("body-map.text-picker-done")
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            syncInitialHeightPresetIfNeeded()
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

    private var hasLocationSelection: Bool {
        !model.marks.isEmpty
    }

    private var continuationAction: some View {
        Button(action: onContinue) {
            Label(
                hasLocationSelection ? "下一步：描述你的感受" : "先选择一个不适位置",
                systemImage: hasLocationSelection ? "arrow.right" : "mappin.slash"
            )
        }
        .buttonStyle(CompanionPrimaryButtonStyle())
        .disabled(!hasLocationSelection)
        .opacity(hasLocationSelection ? 1 : 0.52)
        .accessibilityLabel(hasLocationSelection ? "下一步：描述你的感受" : "先选择一个不适位置")
        .accessibilityHint(
            hasLocationSelection
                ? "进入结构化草稿填写，后续仍可返回修改位置"
                : "请先从人体地图或文字部位列表选择至少一个位置"
        )
        .accessibilityIdentifier("body-map.next")
    }

    private var continuationFooter: some View {
        Group {
            if hasLocationSelection {
                continuationAction
            } else {
                continuationUnavailableState
            }
        }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(BodyCompanionTheme.canvas)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(BodyCompanionTheme.line.opacity(0.72))
                    .frame(height: 1)
            }
            .layoutPriority(1)
    }

    private var continuationUnavailableState: some View {
        Label("先选择一个不适位置", systemImage: "mappin.slash")
            .font(.body.weight(.semibold))
            .foregroundStyle(BodyCompanionTheme.secondaryInk)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                BodyCompanionTheme.surfaceTinted.opacity(0.7),
                in: RoundedRectangle(cornerRadius: BodyCompanionTheme.cornerRadius, style: .continuous)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("先选择一个不适位置")
            .accessibilityHint("请先从人体地图或文字部位列表选择至少一个位置")
            .accessibilityIdentifier("body-map.continuation-unavailable")
    }

    private func finishTextRegionPicker() {
        // A text-list choice creates a broad, provisional location. Returning
        // to the map should show that location in the summary, not immediately
        // present the separate marker editor. Clearing this visual selection
        // neither removes the BodyLocation nor changes the typed draft.
        model.selectMark(id: nil)
        isTextRegionPickerPresented = false
    }

    @ViewBuilder
    private var modeContent: some View {
        switch model.mode {
        case .twoD:
            BodyMap2DView(model: model) {
                isTextRegionPickerPresented = true
            }
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
    private var markerCountSummary: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                markerCountPill
                markerCountDetail
            }
        } else {
            HStack(spacing: 8) {
                markerCountPill
                markerCountDetail
            }
        }
    }

    private var markerCountPill: some View {
        Group {
            if model.marks.isEmpty {
                CompanionStatusPill(
                    "尚未选择位置",
                    systemImage: "mappin.slash",
                    tint: BodyCompanionTheme.secondaryInk
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("尚未选择位置")
                .accessibilityValue("0 / \(BodyMapModel.maximumMarkerCount)")
                .accessibilityIdentifier("body-map.marker-count-empty")
            } else {
                CompanionStatusPill(
                    "位置 \(model.markerCount) / \(BodyMapModel.maximumMarkerCount)",
                    systemImage: "mappin.and.ellipse",
                    tint: model.markerCount >= BodyMapModel.maximumMarkerCount
                        ? BodyCompanionTheme.warm
                        : BodyCompanionTheme.accent
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("已选位置")
                .accessibilityValue("\(model.markerCount) / \(BodyMapModel.maximumMarkerCount)")
                .accessibilityIdentifier("body-map.marker-count-summary")
            }
        }
    }

    private var markerCountDetail: some View {
        Text("区域和针点合计最多 20 个；选中已有针点不会重复新增。")
            .font(.caption)
            .foregroundStyle(BodyCompanionTheme.secondaryInk)
    }

    private var userHeightForThreeD: Float? {
        guard let selectedHeight = selectedHeightPreset.heightMeters else {
            return Self.normalizedHeightMeters(from: customHeightInput)
        }
        return selectedHeight
    }

    private var heightProfilePickerItems: [HeightProfilePreset] {
        heightProfilePresets + [HeightProfilePreset.custom]
    }

    private var heightHint: String {
        if let height = userHeightForThreeD {
            return "身高参考：\(String(format: "%.2f", height))m"
        }
        return "请填写 1.35–2.20 米（例如 1.75）后生效"
    }

    private func snapCustomHeightToNearestPresetIfNeeded() {
        guard selectedHeightPreset == .custom else { return }
        guard let customHeight = Self.normalizedHeightMeters(from: customHeightInput) else { return }
        guard let nearestPreset = HeightProfilePreset.nearestPreset(for: customHeight, from: heightProfilePresets) else {
            return
        }
        let delta = abs(customHeight - (nearestPreset.heightMeters ?? customHeight))
        guard delta <= Self.customHeightSnapToleranceMeters else { return }
        selectedHeightPreset = nearestPreset
        customHeightInput = String(format: "%.2f", nearestPreset.heightMeters ?? customHeight)
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

            Picker("人体高度档位", selection: $selectedHeightPreset) {
                ForEach(heightProfilePickerItems) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .pickerStyle(.segmented)

            if selectedHeightPreset == .custom {
                HStack(spacing: 8) {
                    TextField("输入身高（米）", text: $customHeightInput)
                        .textFieldStyle(.roundedBorder)
                        .bodyMapDecimalInput()
                        .onChange(of: customHeightInput) { _, newValue in
                            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                selectedHeightPreset = .custom
                            }
                        }
                        .onSubmit {
                            snapCustomHeightToNearestPresetIfNeeded()
                        }
                        .submitLabel(.done)
                        .accessibilityIdentifier("body-map.threed-height-custom")
                    Text("m")
                        .foregroundStyle(BodyCompanionTheme.secondaryInk)
                }
                Text(heightHint)
                    .font(.caption2)
                    .foregroundStyle(BodyCompanionTheme.secondaryInk)
                    .accessibilityIdentifier("body-map.threed-height-hint")
            } else {
                Text(heightHint)
                    .font(.caption2)
                    .foregroundStyle(BodyCompanionTheme.secondaryInk)
                    .accessibilityIdentifier("body-map.threed-height-hint")
            }

            Button {
                isTextRegionPickerPresented = true
            } label: {
                Label("用文字选择部位", systemImage: "text.magnifyingglass")
            }
            .buttonStyle(CompanionOutlineButtonStyle())
            .accessibilityHint("无需操作 3D 人体，也能搜索并选择一个大致身体区域")
            .accessibilityIdentifier("body-map.text-picker-open")

            if let focusedRegionID = model.focusedRegionID {
                focusedRegionControls(regionID: focusedRegionID)
            }

            BodySceneView(
                allowsPrototypeCandidate: true,
                cameraPreset: cameraPreset,
                userHeightMeters: userHeightForThreeD,
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
                model.mark3DLoadingTimedOut("内部候选 3D 初始化超时；已回退到 2D", for: attemptID)
            }
        } else {
            // This should be unreachable because request3D() creates the ID
            // before mode changes. Fail closed if a future caller violates it.
            ProgressView("内部候选 3D 状态无效；正在回退到 2D…")
                .frame(maxWidth: .infinity, minHeight: 320)
                .task { model.mark3DFailed("内部候选 3D 状态无效；已回退到 2D") }
        }
    }

    @ViewBuilder
    private func focusedRegionControls(regionID: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                focusedRegionLabel(regionID: regionID)
                resetFocusButton
            }
        } else {
            HStack(spacing: 8) {
                focusedRegionLabel(regionID: regionID)
                Spacer()
                resetFocusButton
            }
        }
    }

    private func focusedRegionLabel(regionID: String) -> some View {
        Label("正在查看：\(regionID)", systemImage: "scope")
            .font(.caption)
            .foregroundStyle(BodyCompanionTheme.secondaryInk)
            .accessibilityLabel("正在聚焦\(regionID)")
    }

    private var resetFocusButton: some View {
        Button("返回全身") {
            model.focus(regionID: nil)
        }
        .buttonStyle(.bordered)
        .frame(minHeight: 44)
        .accessibilityIdentifier("body-map.reset-focus")
    }
}

private struct BodyMap2DView: View {
    let model: BodyMapModel
    let onOpenTextPicker: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Picker("视图", selection: Binding(get: { model.view }, set: { model.view = $0 })) {
                Text("前面").tag(BodyMapView.front)
                Text("后面").tag(BodyMapView.back)
            }
            .pickerStyle(.segmented)

            Button(action: onOpenTextPicker) {
                Label("用文字选择部位", systemImage: "text.magnifyingglass")
            }
            .buttonStyle(CompanionOutlineButtonStyle())
            .accessibilityHint("搜索或浏览部位目录，选择一个大致区域")
            .accessibilityIdentifier("body-map.text-picker-open")

            BodyMapCanvas(view: model.view, marks: model.marks) { point in
                guard let option = BodyRegionCatalog.hitTest(point: point, view: model.view) else { return }
                select(option: option, point: point, source: .bodyMap2D)
            }
            .frame(maxWidth: .infinity)
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
            point: model.markingMode == .pin ? point : nil,
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    noticeMessage
                    dismissButton
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    noticeMessage
                    dismissButton
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(BodyCompanionTheme.warm.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private var noticeMessage: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(BodyCompanionTheme.warm)
            Text(text)
                .foregroundStyle(BodyCompanionTheme.ink)
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dismissButton: some View {
        Button("知道了", action: onDismiss)
            .font(.footnote.weight(.semibold))
            .frame(minHeight: 44)
            .accessibilityLabel("关闭提示")
            .accessibilityIdentifier("\(identifier).dismiss")
    }
}

private struct BodyMapCanvas: View {
    let view: BodyMapView
    let marks: [BodyMark]
    let onSelect: (Point2D) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                    if let option = BodyRegionCatalog.option(
                        regionID: mark.location.regionID,
                        laterality: mark.location.laterality,
                        surface: mark.location.surface
                    ),
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

                mapOverlay
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
            .accessibilityHint("轻点你感到不适的大致区域，或使用文字部位入口搜索并选择。")
        }
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 420 : 520)
    }

    @ViewBuilder
    private var mapOverlay: some View {
        VStack {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    mapViewPill
                    mapInstruction
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            } else {
                HStack {
                    mapViewPill
                    Spacer()
                    mapInstruction
                }
                .padding(16)
            }
            Spacer()
        }
    }

    private var mapViewPill: some View {
        Label(view == .front ? "前面" : "后面", systemImage: view == .front ? "person" : "person.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(BodyCompanionTheme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
    }

    private var mapInstruction: some View {
        Text("轻点标记位置")
            .font(.caption)
            .foregroundStyle(BodyCompanionTheme.secondaryInk)
    }

    private func pinColor(_ token: Int) -> Color {
        let colors: [Color] = [.red, .blue, .orange, .purple, .green, .pink, .teal, .indigo, .yellow, .cyan, .mint, .brown]
        return colors[abs(token) % colors.count]
    }

    private func markerColor(for mark: BodyMark) -> Color {
        mark.kind == .zone ? BodyCompanionTheme.accent : pinColor(mark.colorToken)
    }
}

private extension View {
    @ViewBuilder
    func bodyMapDecimalInput() -> some View {
#if os(iOS)
        textInputAutocapitalization(.never)
            .keyboardType(.decimalPad)
#else
        self
#endif
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
    @State private var query = ""
    @State private var selectionFeedback: String?

    private var options: [BodyRegionOption] {
        BodyRegionCatalog.options(matching: query, for: model.view)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let selectionFeedback {
                Label(selectionFeedback, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BodyCompanionTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(BodyCompanionTheme.accentSoft.opacity(0.62))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(selectionFeedback)
                    .accessibilityIdentifier("\(identifierPrefix).selection-notice")
            }

            List {
                Section {
                    TextField("搜索部位", text: $query)
                        .accessibilityIdentifier("\(identifierPrefix).search")
                    Text("仅搜索本机目录的中文或英文名称；文字选择只会添加大致区域。")
                        .font(.footnote)
                        .foregroundStyle(BodyCompanionTheme.secondaryInk)
                }

                if showsViewPicker {
                    Section("目录视图") {
                        Picker("选择身体目录", selection: Binding(get: { model.view }, set: { model.view = $0 })) {
                            Text("前面").tag(BodyMapView.front)
                            Text("后面").tag(BodyMapView.back)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityHint("切换前面或后面的目录筛选；不会改变已选择位置的表面语义。")
                    }
                }

                Section("可选部位") {
                    if options.isEmpty {
                        ContentUnavailableView(
                            "没有匹配的部位",
                            systemImage: "magnifyingglass",
                            description: Text("请尝试中文或英文目录名称。")
                        )
                        .accessibilityIdentifier("\(identifierPrefix).empty")
                    } else {
                        ForEach(options) { option in
                            Button {
                                select(option)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(option.label)
                                            .font(.body.weight(.semibold))
                                        Text("\(localizedLaterality(option.laterality)) · \(localizedSurface(option.surface)) · \(model.view == .front ? "前面目录" : "后面目录")")
                                            .font(.caption)
                                            .foregroundStyle(BodyCompanionTheme.secondaryInk)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(BodyCompanionTheme.accent)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .frame(minHeight: 44)
                            .accessibilityLabel("选择\(option.label)，\(localizedLaterality(option.laterality))，\(localizedSurface(option.surface))")
                            .accessibilityHint("添加一个待确认的大致区域，不会创建精确针点")
                            .accessibilityIdentifier("\(identifierPrefix).option-\(stableIdentifier(for: option))")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier(identifierPrefix)
        }
    }

    private func select(_ option: BodyRegionOption) {
        switch model.applyTextRegionSelection(option, view: model.view) {
        case .added:
            selectionFeedback = "已添加待确认位置：\(option.label)"
        case .updated:
            selectionFeedback = "已选中已有待确认位置：\(option.label)"
        case .rejectedMarkerLimit:
            selectionFeedback = "已达到 20 个位置上限，请先编辑或删除已有标记。"
        case .rejectedDuplicateLocation, .rejectedDraftSynchronization, .removed:
            selectionFeedback = "暂时无法更新这个位置，请返回后重试。"
        }
    }

    private func stableIdentifier(for option: BodyRegionOption) -> String {
        option.id.replacingOccurrences(of: "|", with: "-")
    }
}

private struct MarkSummaryPanel: View {
    let model: BodyMapModel
    let suppressAutomaticEditor: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isEditorPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            markerHeader

            ForEach(model.marks) { mark in
                markerRow(mark)
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
            if horizontalSizeClass == .compact, !suppressAutomaticEditor, model.selectedMarkID != nil {
                isEditorPresented = true
            }
        }
        .onChange(of: model.selectedMarkID) { _, selectedID in
            guard horizontalSizeClass == .compact, !suppressAutomaticEditor else { return }
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

    @ViewBuilder
    private var markerHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                markerHeaderTitle
                clearMarkersButton
            }
        } else {
            HStack {
                markerHeaderTitle
                Spacer()
                clearMarkersButton
            }
        }
    }

    private var markerHeaderTitle: some View {
        Text("待确认标记（\(model.marks.count)）")
            .font(.headline)
            .foregroundStyle(BodyCompanionTheme.ink)
            .accessibilityIdentifier("body-map.pending-mark-summary")
    }

    private var clearMarkersButton: some View {
        Button("清空") {
            model.clearMarkers()
        }
        .buttonStyle(.bordered)
        .frame(minHeight: 44)
        .disabled(model.marks.isEmpty)
    }

    @ViewBuilder
    private func markerRow(_ mark: BodyMark) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                markerSelectionButton(mark)
                removeMarkerButton(mark)
            }
        } else {
            HStack(spacing: 10) {
                markerSelectionButton(mark)
                removeMarkerButton(mark)
            }
        }
    }

    private func markerSelectionButton(_ mark: BodyMark) -> some View {
        Button {
            model.selectMark(id: mark.id)
            if horizontalSizeClass == .compact, !suppressAutomaticEditor {
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
    }

    private func removeMarkerButton(_ mark: BodyMark) -> some View {
        Button {
            model.removeDraft(id: mark.id)
        } label: {
            Label("删除位置", systemImage: "trash")
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("删除\(mark.displayLabel)")
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
