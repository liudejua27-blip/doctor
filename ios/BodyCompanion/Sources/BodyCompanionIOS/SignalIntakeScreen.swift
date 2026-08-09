import BodyCompanionCore
import SwiftUI

/// The typed intake surface. Network and Agent calls intentionally do not
/// happen in this view; the model only drives a fail-closed local state.
public struct SignalIntakeScreen: View {
    @State private var model: SignalIntakeModel
    @State private var intensityContext: SignalIntensityContext = .current
    @State private var intensityValue = 0
    @State private var hasIntensity = false
    @State private var onsetMode: SignalOnsetMode = .unknown
    @State private var course: SignalCourse = .unknown
    @State private var temporalText = ""
    @State private var functionDomain: SignalFunctionalDomain = .other
    @State private var functionSeverity: SignalImpactSeverity = .unknown
    @State private var functionText = ""
    @State private var factorText = ""
    @State private var factorEffect: SignalFactorEffect = .worse
    @State private var backgroundText = ""
    @State private var rawUserText = ""
    @State private var otherSensationText = ""
    @State private var selectedSensationMarkerIDs: Set<UUID> = []
    @State private var isMoreSensationsExpanded = false
    @State private var inlineError: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(model: SignalIntakeModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        Form {
            progressSection
            locationSection
            sensationSection
            intensitySection
            temporalSection
            factorsSection
            functionSection
            backgroundSection
            rawTextSection
            safetySection
            reviewSection
        }
        .scrollContentBackground(.hidden)
        .background(BodyCompanionTheme.canvas)
        .tint(BodyCompanionTheme.accent)
        .navigationTitle("描述这次感受")
        .accessibilityIdentifier("screen.signal-intake")
        .alert("当前步骤无法继续", isPresented: Binding(
            get: { inlineError != nil },
            set: { if !$0 { inlineError = nil } }
        )) {
            Button("知道了", role: .cancel) { inlineError = nil }
        } message: {
            Text(inlineError ?? "")
        }
        .onAppear {
            if let intensity = model.draft.facts.intensity {
                intensityContext = intensity.context
                intensityValue = intensity.value
                hasIntensity = true
            }
            if let temporal = model.draft.facts.temporal {
                onsetMode = temporal.onsetMode
                course = temporal.course
                temporalText = temporal.userText ?? ""
            }
            if let function = model.draft.facts.functionalImpacts.first {
                functionDomain = function.domain
                functionSeverity = function.severity
                functionText = function.userText ?? ""
            }
            rawUserText = model.draft.facts.rawUserText ?? ""
            otherSensationText = model.draft.facts.sensations.first(where: { $0.code == .other })?.userLabel ?? ""
            synchronizeSensationMarkerSelection()
        }
    }

    private var progressSection: some View {
        Section {
            CompanionStatusPill("第 2 步 / 共 3 步", systemImage: "text.bubble")
                .accessibilityLabel("第 2 步，共 3 步")
            Label(model.phase.displayName, systemImage: phaseIcon)
                .font(.headline)
                .foregroundStyle(BodyCompanionTheme.ink)
                .accessibilityLabel("当前步骤：\(model.phase.displayName)")
            Text("用你自己的语言补充感受。所有内容在你确认前都只是未确认草稿。")
                .font(.footnote)
                .foregroundStyle(BodyCompanionTheme.secondaryInk)
            if model.unconfirmedCandidateCount > 0 {
                Label("有 \(model.unconfirmedCandidateCount) 项 AI/资料候选等待确认", systemImage: "questionmark.circle")
                    .foregroundStyle(BodyCompanionTheme.warm)
                    .accessibilityLabel("有 \(model.unconfirmedCandidateCount) 项候选等待确认")
            }
        } header: {
            Text("这次记录")
        }
    }

    private var locationSection: some View {
        Section {
            Text("标记只表示你主观指出的不适位置，不代表疼痛来源、受损组织或医学定位。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel("位置说明：标记只表示你主观指出的不适位置，不代表疼痛来源、受损组织或医学定位。")
            if model.draft.locations.isEmpty {
                Text("还没有位置。请返回 2D/3D 人体地图或部位列表选择。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.draft.locations) { location in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(location.userLabel ?? location.regionID, systemImage: "mappin.and.ellipse")
                        Button("删除") { model.removeLocation(id: location.id) }
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("signal-intake.location-\(location.id.uuidString)")
                }
            }
        } header: {
            Text("位置（\(model.draft.locations.count)）")
        }
    }

    private var sensationSection: some View {
        Section {
            if model.isSensationEditingBlockedBySafetyAction {
                Label(
                    "当前安全行动优先；此内部原型暂不支持直接修改感觉。",
                    systemImage: "exclamationmark.shield"
                )
                .font(.footnote)
                .foregroundStyle(BodyCompanionTheme.secondaryInk)
                .accessibilityIdentifier("sensation-picker.safety-editing-locked")
            }
            if requiresExplicitSensationLocationSelection {
                Text("先选择接下来要添加的感觉对应哪些位置。已存在的感觉可在各自下方单独调整。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(model.draft.locations) { location in
                    Toggle(location.userLabel ?? location.regionID, isOn: Binding(
                        get: { selectedSensationMarkerIDs.contains(location.id) },
                        set: { selected in
                            if selected {
                                selectedSensationMarkerIDs.insert(location.id)
                            } else {
                                selectedSensationMarkerIDs.remove(location.id)
                            }
                        }
                    ))
                    .frame(minHeight: 44)
                    .accessibilityHint("选择后，新添加的感觉只会关联到这个位置。")
                }
                .disabled(model.isSensationEditingBlockedBySafetyAction)
            }
            sensationChoices(displayedCommonSensationCodes)
            Button {
                isMoreSensationsExpanded.toggle()
            } label: {
                Label(
                    isMoreSensationsExpanded
                        ? "收起更多感觉"
                        : "更多感觉（\(SignalSensationCode.additionalCases.count) 项）",
                    systemImage: isMoreSensationsExpanded ? "chevron.up.circle" : "chevron.down.circle"
                )
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("sensation-picker.more-open")
            .accessibilityLabel(isMoreSensationsExpanded ? "收起更多感觉" : "更多感觉，共 \(SignalSensationCode.additionalCases.count) 项")
            .accessibilityValue(isMoreSensationsExpanded ? "已展开" : "已收起")
            if isMoreSensationsExpanded {
                sensationChoices(SignalSensationCode.additionalCases)
            }
            if model.draft.unknownGroups.contains(.sensation) {
                Text("已记录为：说不清/不想回答")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if model.draft.facts.sensations.contains(where: { $0.code == .other }) {
                TextField("请补充其他感觉（必填）", text: $otherSensationText, axis: .vertical)
                    .lineLimit(2...4)
                    .disabled(model.isSensationEditingBlockedBySafetyAction)
                Button("保存其他感觉") {
                    perform {
                        try model.setOtherSensationLabel(otherSensationText)
                    }
                }
                .disabled(
                    model.isSensationEditingBlockedBySafetyAction ||
                        otherSensationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .frame(minHeight: 44)
            }
            pairedActions(identifier: "sensation-picker.actions") {
                Button("确认感觉") { model.markReviewed(.sensation) }
                    .accessibilityIdentifier("sensation-picker.review")
                    .frame(minHeight: 44)
                Button(unknownSensationButtonTitle) {
                    perform { try model.markUnknown(.sensation) }
                }
                    .accessibilityIdentifier("sensation-picker.unknown-all")
                    .frame(minHeight: 44)
            }
            .disabled(model.isSensationEditingBlockedBySafetyAction)
        } header: {
            Text("感觉")
        } footer: {
            Text("不预设任何感觉；每个主动选择的感觉都必须明确关联到一个或多个位置。若不同位置的感觉不同，请分别选择；“这些位置都说不清”只在你主动确认后应用到全部当前位置。")
        }
    }

    private var requiresExplicitSensationLocationSelection: Bool {
        model.draft.locations.count > 1
    }

    private var unknownSensationButtonTitle: String {
        requiresExplicitSensationLocationSelection ? "这些位置的感觉都说不清" : "说不清/不想回答"
    }

    /// Keep the single-location unknown action unambiguous. If an older or
    /// adapter-provided per-marker unknown is already present, show it only as
    /// an editable existing answer rather than adding a second initial choice.
    private var displayedCommonSensationCodes: [SignalSensationCode] {
        var codes = SignalSensationCode.commonCases(forLocationCount: model.draft.locations.count)
        if !requiresExplicitSensationLocationSelection, isSensationSelected(.unknown) {
            codes.append(.unknown)
        }
        return codes
    }

    @ViewBuilder
    private func sensationChoices(_ codes: [SignalSensationCode]) -> some View {
        ForEach(codes, id: \.self) { code in
            VStack(alignment: .leading, spacing: 8) {
                Toggle(sensationDisplayName(for: code), isOn: Binding(
                    get: { isSensationSelected(code) },
                    set: { selected in setSensationSelection(code, selected: selected) }
                ))
                .frame(minHeight: 44)
                if isSensationSelected(code), requiresExplicitSensationLocationSelection {
                    sensationAssociationPicker(for: code)
                }
            }
            .disabled(model.isSensationEditingBlockedBySafetyAction)
        }
    }

    private func isSensationSelected(_ code: SignalSensationCode) -> Bool {
        model.draft.facts.sensations.contains { $0.code == code }
    }

    private func sensationDisplayName(for code: SignalSensationCode) -> String {
        guard code == .unknown else { return code.displayName }
        if requiresExplicitSensationLocationSelection {
            return "部分位置的感觉说不清"
        }
        return "已记录：说不清/不想回答（可关闭）"
    }

    private func selectedMarkerIDsForNewSensation() -> [UUID] {
        if let onlyLocation = model.draft.locations.first, model.draft.locations.count == 1 {
            return [onlyLocation.id]
        }
        return model.draft.locations.map(\.id).filter { selectedSensationMarkerIDs.contains($0) }
    }

    private func sensationMarkerIDs(for code: SignalSensationCode) -> Set<UUID> {
        Set(model.draft.facts.sensations.first(where: { $0.code == code })?.locationMarkerIDs ?? [])
    }

    @ViewBuilder
    private func sensationAssociationPicker(for code: SignalSensationCode) -> some View {
        Text("“\(sensationDisplayName(for: code))”对应的位置")
            .font(.footnote.weight(.medium))
            .foregroundStyle(BodyCompanionTheme.secondaryInk)
        ForEach(model.draft.locations) { location in
            Toggle(location.userLabel ?? location.regionID, isOn: Binding(
                get: { sensationMarkerIDs(for: code).contains(location.id) },
                set: { selected in setSensationAssociation(code, markerID: location.id, selected: selected) }
            ))
            .font(.footnote)
            .frame(minHeight: 40)
            .accessibilityHint("调整“\(code.displayName)”是否关联到这个位置。")
        }
    }

    private func setSensationSelection(_ code: SignalSensationCode, selected: Bool) {
        if selected {
            let markerIDs = selectedMarkerIDsForNewSensation()
            guard !markerIDs.isEmpty else {
                inlineError = "请先选择这个感觉对应的位置。"
                return
            }
            perform {
                try model.setSensation(code, selected: true, locationMarkerIDs: markerIDs)
            }
        } else {
            perform {
                try model.setSensation(code, selected: false, locationMarkerIDs: [])
            }
        }
    }

    private func setSensationAssociation(_ code: SignalSensationCode, markerID: UUID, selected: Bool) {
        var markerIDs = sensationMarkerIDs(for: code)
        if selected {
            markerIDs.insert(markerID)
        } else {
            guard markerIDs.count > 1 else {
                inlineError = "每个感觉至少需要关联一个位置；如不再需要该感觉，请关闭感觉本身。"
                return
            }
            markerIDs.remove(markerID)
        }
        let orderedMarkerIDs = model.draft.locations.map(\.id).filter { markerIDs.contains($0) }
        perform {
            try model.setSensation(code, selected: true, locationMarkerIDs: orderedMarkerIDs)
        }
    }

    private func synchronizeSensationMarkerSelection() {
        let activeMarkerIDs = Set(model.draft.locations.map(\.id))
        if activeMarkerIDs.count == 1 {
            selectedSensationMarkerIDs = activeMarkerIDs
        } else {
            selectedSensationMarkerIDs.formIntersection(activeMarkerIDs)
        }
    }

    private var intensitySection: some View {
        Section {
            Toggle("填写程度（0–10）", isOn: $hasIntensity)
                .frame(minHeight: 44)
            if hasIntensity {
                Picker("程度上下文", selection: $intensityContext) {
                    ForEach(SignalIntensityContext.allCases, id: \.self) { context in
                        Text(context.displayName).tag(context)
                    }
                }
                Slider(value: Binding(
                    get: { Double(intensityValue) },
                    set: { intensityValue = Int($0.rounded()) }
                ), in: 0...10, step: 1) {
                    Text("程度")
                } minimumValueLabel: {
                    Text("0")
                } maximumValueLabel: {
                    Text("10")
                }
                .accessibilityValue("\(intensityValue) / 10")
                Text("当前选择：\(intensityValue) / 10（仅表示你的主观程度）")
                    .font(.footnote)
                Button("保存程度") {
                    perform {
                        try model.setIntensity(context: intensityContext, value: intensityValue)
                        model.markReviewed(.intensity)
                    }
                }
                .frame(minHeight: 44)
            }
            Button("程度说不清/不想回答") {
                perform { try model.markUnknown(.intensity) }
            }
                .frame(minHeight: 44)
        } header: {
            Text("程度")
        } footer: {
            Text("未填写与 0 分不同；0 分也必须由你主动选择。")
        }
    }

    private var temporalSection: some View {
        Section {
            Picker("大约何时开始", selection: $onsetMode) {
                ForEach(SignalOnsetMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            Picker("变化过程", selection: $course) {
                ForEach(SignalCourse.allCases, id: \.self) { value in
                    Text(value.displayName).tag(value)
                }
            }
            TextField("补充时间或原话（可选）", text: $temporalText, axis: .vertical)
                .lineLimit(2...4)
            pairedActions(identifier: "temporal.actions") {
                Button("保存时间信息") {
                    model.setTemporal(onsetMode: onsetMode, course: course, userText: temporalText.nilIfEmpty)
                    model.markReviewed(.temporal)
                }
                .accessibilityIdentifier("temporal.save")
                .frame(minHeight: 44)
                Button("未知") { perform { try model.markUnknown(.temporal) } }
                    .accessibilityIdentifier("temporal.unknown")
                    .frame(minHeight: 44)
            }
        } header: {
            Text("时间")
        }
    }

    private var factorsSection: some View {
        Section {
            Picker("影响方向", selection: $factorEffect) {
                Text("可能加重").tag(SignalFactorEffect.worse)
                Text("可能缓解").tag(SignalFactorEffect.better)
                Text("不确定").tag(SignalFactorEffect.uncertain)
            }
            TextField("例如：跑步、久坐、休息", text: $factorText)
            Button("添加因素") {
                perform {
                    try model.addFactor(label: factorText, effect: factorEffect)
                    factorText = ""
                }
            }
            .disabled(factorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .frame(minHeight: 44)
            ForEach(model.draft.facts.aggravatingFactors) { factor in
                Label("可能加重：\(factor.label)", systemImage: "arrow.up.right")
            }
            ForEach(model.draft.facts.relievingFactors) { factor in
                Label("可能缓解：\(factor.label)", systemImage: "arrow.down.right")
            }
            Button("没有要补充的诱因/缓解因素") {
                model.markReviewed(.aggravatingFactors)
                model.markReviewed(.relievingFactors)
            }
            .frame(minHeight: 44)
        } header: {
            Text("诱发与缓解（可选）")
        }
    }

    private var functionSection: some View {
        Section {
            Picker("受影响的活动", selection: $functionDomain) {
                ForEach(SignalFunctionalDomain.allCases, id: \.self) { domain in
                    Text(domain.displayName).tag(domain)
                }
            }
            Picker("影响程度", selection: $functionSeverity) {
                ForEach(SignalImpactSeverity.allCases, id: \.self) { severity in
                    Text(severity.displayName).tag(severity)
                }
            }
            TextField("补充说明（可选）", text: $functionText, axis: .vertical)
                .lineLimit(2...4)
            Button("保存功能影响") {
                model.setFunctionalImpact(domain: functionDomain, severity: functionSeverity, userText: functionText.nilIfEmpty)
                model.markReviewed(.functionalImpact)
            }
            .frame(minHeight: 44)
            Button("功能影响说不清/不想回答") {
                perform { try model.markUnknown(.functionalImpact) }
            }
                .frame(minHeight: 44)
        } header: {
            Text("功能影响")
        }
    }

    private var backgroundSection: some View {
        Section {
            TextField("例如：最近增加了训练量或久坐时间", text: $backgroundText, axis: .vertical)
                .lineLimit(2...4)
            Button("保留为待确认背景") {
                perform {
                    try model.addBackgroundFact(value: backgroundText)
                    backgroundText = ""
                }
            }
            .disabled(backgroundText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .frame(minHeight: 44)
            ForEach(model.draft.facts.backgroundFacts) { fact in
                Label("待确认：\(fact.value)", systemImage: "questionmark.circle")
            }
            Button("没有要补充的背景") { model.markReviewed(.background) }
                .frame(minHeight: 44)
        } header: {
            Text("背景信息（可选）")
        } footer: {
            Text("背景候选不会自动写入个人身体档案。")
        }
    }

    private var rawTextSection: some View {
        Section {
            TextEditor(text: $rawUserText)
                .frame(minHeight: 80)
                .accessibilityLabel("用自己的话补充身体感受；内容仍是未确认草稿")
            Button("保存原话到未确认草稿") {
                perform { try model.setRawUserText(rawUserText.nilIfEmpty) }
            }
            .frame(minHeight: 44)
        } header: {
            Text("用自己的话补充（可选）")
        }
    }

    private var safetySection: some View {
        Section {
            Label(model.safety.status.displayName, systemImage: safetyIcon)
                .accessibilityLabel("安全状态：\(model.safety.status.displayName)")
            if let message = model.safety.displayMessage, !message.isEmpty {
                Text(message).font(.footnote)
            }
            switch model.phase {
            case .collectingFacts:
                Button("进入安全检查") { perform { try model.beginSafetyReview() } }
                    .frame(maxWidth: .infinity, minHeight: 44)
            case .safetyReview:
                Button("尝试安全检查（样机无服务连接）") {
                    // The prototype has no server connection. Explicitly
                    // select the unavailable path instead of inventing a safe result.
                    perform {
                        try model.applySafety(SignalSafetyState(
                            status: .unavailable,
                            ordinaryAgentAllowed: false,
                            displayMessage: "安全规则服务尚未连接；只保留未确认草稿，不继续普通分析。"
                        ))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            case .safetyAction:
                Text("安全行动必须先于普通分析。看完固定行动入口后，可以选择仅复核事实。")
                    .font(.footnote)
                Button("我已看到安全行动，进入事实复核") {
                    perform { try model.acknowledgeSafetyAction() }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            case .agentDraft:
                Text("这是服务端候选整理阶段；任何候选仍需你逐项确认。")
                    .font(.footnote)
                Button("查看并复核候选") {
                    perform { try model.finishAgentDraft() }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            case .reviewFacts:
                if model.safety.ordinaryAgentAllowed {
                    Button("复核完成，准备保存审批") {
                        perform { try model.requestApproval() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    Button("保留为未确认草稿（样机状态）") {
                        perform { try model.saveOfflineDraft() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
            case .awaitingApproval:
                Text("这里只表示准备审批，不代表已创建正式身体事件。")
                    .font(.footnote)
                Button("返回修改") { perform { try model.returnToFactReview() } }
                    .frame(maxWidth: .infinity, minHeight: 44)
            case .offlineDraft:
                Text("安全规则或网络不可用；当前内容仍是未确认草稿，不显示普通分析。P4 加密持久化尚未接入此页面。")
                    .font(.footnote)
                Button("恢复填写") { perform { try model.resumeOfflineDraft() } }
                    .frame(maxWidth: .infinity, minHeight: 44)
            case .failed:
                Text("发生可解释错误：\(model.draft.lastErrorCode ?? "unknown_error")")
                    .font(.footnote)
                Button("重试") { perform { try model.retryAfterFailure() } }
                    .frame(maxWidth: .infinity, minHeight: 44)
            case .choosingLocation:
                Text("先在人体地图或部位列表选择位置。")
                    .font(.footnote)
            }
        } header: {
            Text("安全状态")
        } footer: {
            Text("NoRuleTriggered 只表示当前规则集未命中，不等于安全；安全规则不可用时不会继续普通分析。")
        }
    }

    private var reviewSection: some View {
        Section {
            ReviewRow(title: "位置", reviewed: model.draft.reviewedGroups.contains(.location) || !model.draft.locations.isEmpty)
            ReviewRow(title: "感觉", reviewed: model.draft.reviewedGroups.contains(.sensation))
            ReviewRow(title: "程度", reviewed: model.draft.reviewedGroups.contains(.intensity))
            ReviewRow(title: "时间", reviewed: model.draft.reviewedGroups.contains(.temporal))
            ReviewRow(title: "功能影响", reviewed: model.draft.reviewedGroups.contains(.functionalImpact))
            Text("任何 AI/资料候选仍显示为待确认；只有服务端批准流程才能创建正式事件。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("复核摘要")
        }
    }

    private var phaseIcon: String {
        switch model.phase {
        case .choosingLocation: "mappin"
        case .collectingFacts: "square.and.pencil"
        case .safetyReview, .safetyAction: "exclamationmark.shield"
        case .agentDraft: "sparkles"
        case .reviewFacts: "checklist"
        case .awaitingApproval: "checkmark.seal"
        case .offlineDraft: "wifi.slash"
        case .failed: "xmark.octagon"
        }
    }

    private var safetyIcon: String {
        switch model.safety.status {
        case .r0, .r1: "exclamationmark.triangle.fill"
        case .r2: "person.crop.circle.badge.questionmark"
        case .noRuleTriggered: "checkmark.shield"
        case .notRun, .undetermined, .unavailable: "questionmark.shield"
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            inlineError = nil
        } catch {
            inlineError = (error as? SignalIntakeTransitionError)?.errorDescription ?? error.localizedDescription
        }
    }

    @ViewBuilder
    private func pairedActions<Content: View>(
        identifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("\(identifier).vertical")
        } else {
            HStack(spacing: 12) {
                content()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("\(identifier).horizontal")
        }
    }
}

private struct ReviewRow: View {
    let title: String
    let reviewed: Bool

    var body: some View {
        Label(
            reviewed ? "已复核：\(title)" : "待复核：\(title)",
            systemImage: reviewed ? "checkmark.circle" : "circle"
        )
        .foregroundStyle(reviewed ? .primary : .secondary)
        .accessibilityLabel(reviewed ? "已复核：\(title)" : "待复核：\(title)")
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
