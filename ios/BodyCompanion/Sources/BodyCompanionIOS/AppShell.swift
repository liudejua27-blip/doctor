import BodyCompanionCore
import SwiftUI

public struct AppShell: View {
    @State private var selectedTab: AppTab = .today
    @State private var todayRouter = RouterPath()
    @State private var recordsRouter = RouterPath()
    @State private var analysisRouter = RouterPath()
    @State private var profileRouter = RouterPath()
    @State private var intakeModel = SignalIntakeModel()
    private let runtimeConfiguration: InternalP0RuntimeConfiguration

    public init(runtimeConfiguration: InternalP0RuntimeConfiguration = .safeDefault) {
        self.runtimeConfiguration = runtimeConfiguration
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            tab("今天", systemImage: "sun.max", tab: .today, router: todayRouter) {
                TodayView(router: todayRouter, intakeModel: intakeModel)
            }
            tab("记录", systemImage: "figure.stand", tab: .records, router: recordsRouter) {
                RecordsView(router: recordsRouter, intakeModel: intakeModel)
            }
            tab("AI 身体助手", systemImage: "sparkles", tab: .analysis, router: analysisRouter) {
                AnalysisView(router: analysisRouter, intakeModel: intakeModel)
            }
            tab("我的", systemImage: "person.crop.circle", tab: .profile, router: profileRouter) {
                ProfileView(router: profileRouter)
            }
        }
        .tint(BodyCompanionTheme.accent)
    }

    @ViewBuilder
    private func tab<Content: View>(
        _ title: String,
        systemImage: String,
        tab: AppTab,
        router: RouterPath,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack(path: Binding(get: { router.path }, set: { router.path = $0 })) {
            content()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .assessment:
                        BodyMapScreen(
                            model: intakeModel.bodyMapModel,
                            prototype3DEnabled: runtimeConfiguration.candidate3DEnabled,
                            onLocationsChanged: { locations in intakeModel.setLocations(locations) }
                        )
                    case .intake:
                        SignalIntakeScreen(model: intakeModel)
                    case .episode(let id):
                        Text("Episode \(id)")
                    case .report(let id):
                        Text("报告 \(id)")
                    case .settings:
                        Text("设置")
                    }
                }
        }
        .tabItem { Label(title, systemImage: systemImage) }
        .tag(tab)
    }
}

private struct TodayView: View {
    let router: RouterPath
    let intakeModel: SignalIntakeModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                CompanionSectionHeading(
                    eyebrow: "身体信号记录",
                    title: "把这次不舒服，说清楚。",
                    detail: "从位置开始，逐步补充感觉、时间和对工作或运动的影响。"
                )

                CompanionCard(emphasized: true) {
                    VStack(alignment: .leading, spacing: 16) {
                        CompanionStatusPill("准备开始一条新记录", systemImage: "plus.circle.fill")
                        Text("身体地图会帮你表达“我感觉在这里”。")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(BodyCompanionTheme.ink)
                        Text("这不是诊断；每一步都可以保留为未确认草稿，稍后继续。")
                            .font(.subheadline)
                            .foregroundStyle(BodyCompanionTheme.secondaryInk)
                        IntakeEntryActions(
                            router: router,
                            intakeModel: intakeModel,
                            freshTitle: "记录这次不适",
                            freshSystemImage: "figure.stand"
                        )
                    }
                }

                CompanionSectionHeading(
                    title: "适合从这里开始",
                    detail: "运动后与工作后都走同一条安全、可复核的记录流程。"
                )

                contextCueCards

                CompanionCard {
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: "lock.shield")
                            .font(.title3)
                            .foregroundStyle(BodyCompanionTheme.mint)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("你掌控每一条记录")
                                .font(.headline)
                                .foregroundStyle(BodyCompanionTheme.ink)
                            Text("只有你确认的结构化事实才会进入正式身体档案。")
                                .font(.subheadline)
                                .foregroundStyle(BodyCompanionTheme.secondaryInk)
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("今天")
        .safeAreaPadding(.top)
        .companionScreenBackground()
        .accessibilityIdentifier("screen.today")
    }

    @ViewBuilder
    private var contextCueCards: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                ContextCueCard(
                    icon: "figure.run",
                    title: "运动或训练后",
                    detail: "跑步、健身、球类等",
                    identifier: "today.context-cue.exercise"
                )
                ContextCueCard(
                    icon: "laptopcomputer",
                    title: "久坐或工作后",
                    detail: "颈肩腰、重复操作等",
                    identifier: "today.context-cue.work"
                )
            }
        } else {
            HStack(spacing: 12) {
                ContextCueCard(
                    icon: "figure.run",
                    title: "运动或训练后",
                    detail: "跑步、健身、球类等",
                    identifier: "today.context-cue.exercise"
                )
                ContextCueCard(
                    icon: "laptopcomputer",
                    title: "久坐或工作后",
                    detail: "颈肩腰、重复操作等",
                    identifier: "today.context-cue.work"
                )
            }
        }
    }
}

private struct RecordsView: View {
    let router: RouterPath
    let intakeModel: SignalIntakeModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CompanionSectionHeading(
                    eyebrow: "记录",
                    title: "从一次身体感受开始",
                    detail: "当前样机尚未接入正式档案；这里不会把草稿误写成已保存记录。"
                )
                CompanionCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "rectangle.and.pencil.and.ellipsis")
                            .font(.title)
                            .foregroundStyle(BodyCompanionTheme.accent)
                        Text("还没有已确认的身体记录")
                            .font(.headline)
                            .foregroundStyle(BodyCompanionTheme.ink)
                        Text("先标记位置，再用自己的语言补充这次的感受。")
                            .font(.subheadline)
                            .foregroundStyle(BodyCompanionTheme.secondaryInk)
                        IntakeEntryActions(
                            router: router,
                            intakeModel: intakeModel,
                            freshTitle: "从人体开始记录",
                            freshSystemImage: "plus"
                        )
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("记录")
        .safeAreaPadding(.top)
        .companionScreenBackground()
        .accessibilityIdentifier("screen.records")
    }
}

private struct AnalysisView: View {
    let router: RouterPath
    let intakeModel: SignalIntakeModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                CompanionSectionHeading(
                    eyebrow: "AI 身体助手",
                    title: "先理解这次记录，再决定是否继续追问。",
                    detail: "它不是 AI 医生，也不会在安全流程前给出普通建议。"
                )

                CompanionCard(emphasized: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        CompanionStatusPill("普通对话尚未接入", systemImage: "lock.fill", tint: BodyCompanionTheme.warm)
                            .accessibilityIdentifier("analysis.standard-chat-unavailable")
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "sparkles")
                                .font(.title)
                                .foregroundStyle(BodyCompanionTheme.accent)
                                .frame(width: 34)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("从本次身体感受开始")
                                    .font(.headline)
                                    .foregroundStyle(BodyCompanionTheme.ink)
                                Text("完成位置、结构化事实与安全检查后，才能进入一次一问的受限追问。")
                                    .font(.subheadline)
                                    .foregroundStyle(BodyCompanionTheme.secondaryInk)
                            }
                        }
                        IntakeEntryActions(
                            router: router,
                            intakeModel: intakeModel,
                            freshTitle: "开始记录这次不适",
                            freshSystemImage: "arrow.right"
                        )
                    }
                }

                CompanionCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("它会如何帮助你")
                            .font(.headline)
                            .foregroundStyle(BodyCompanionTheme.ink)
                        AssistantBoundaryRow(icon: "mappin.and.ellipse", text: "把“哪里不舒服”整理成可复核的位置事实")
                        AssistantBoundaryRow(icon: "text.bubble", text: "只在允许时，一次补充一个高价值问题")
                        AssistantBoundaryRow(icon: "checklist", text: "把 AI 整理的内容明确标成“待你确认”")
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("AI 身体助手")
        .safeAreaPadding(.top)
        .companionScreenBackground()
        .accessibilityIdentifier("screen.analysis")
    }
}

/// Makes the in-memory P0 draft decision visible at every entry point. It
/// never claims the draft was saved and only resets after explicit consent.
private struct IntakeEntryActions: View {
    let router: RouterPath
    let intakeModel: SignalIntakeModel
    let freshTitle: String
    let freshSystemImage: String
    @State private var showStartOverConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if intakeModel.hasResumableDraft {
                CompanionStatusPill("有一条未确认草稿", systemImage: "pencil.and.list.clipboard", tint: BodyCompanionTheme.warm)
                Text("已标记 \(intakeModel.draft.locations.count) 个位置 · \(intakeModel.phase.displayName)")
                    .font(.footnote)
                    .foregroundStyle(BodyCompanionTheme.secondaryInk)
                Button(action: continueCurrentDraft) {
                    Label("继续这条草稿", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(CompanionPrimaryButtonStyle())
                .accessibilityHint("继续当前会话中的未确认草稿，不会新建或保存正式记录")
                .accessibilityIdentifier("intake-entry.resume-draft")

                Button("新建一条记录", role: .destructive) {
                    showStartOverConfirmation = true
                }
                .buttonStyle(CompanionOutlineButtonStyle())
                .accessibilityHint("需要先确认放弃当前会话中的未确认草稿")
                .accessibilityIdentifier("intake-entry.start-over")
            } else {
                Button(action: startFreshDraft) {
                    Label(freshTitle, systemImage: freshSystemImage)
                }
                .buttonStyle(CompanionPrimaryButtonStyle())
                .accessibilityHint("从 2D 或 3D 人体地图选择你感觉不适的位置")
                .accessibilityIdentifier("intake-entry.start-record")
            }
        }
        .confirmationDialog("新建一条记录？", isPresented: $showStartOverConfirmation, titleVisibility: .visible) {
            Button("放弃当前未确认草稿并新建", role: .destructive, action: startFreshDraft)
                .accessibilityIdentifier("intake-entry.confirm-discard")
            Button("取消", role: .cancel) {}
                .accessibilityIdentifier("intake-entry.cancel-discard")
        } message: {
            Text("这会放弃当前会话中的未确认草稿。它尚未成为正式身体记录。")
        }
    }

    private func continueCurrentDraft() {
        switch intakeModel.resumeDestination {
        case .bodyMap:
            router.path.append(.assessment)
        case .structuredIntake:
            router.path.append(.intake)
        case nil:
            router.path.append(.assessment)
        }
    }

    private func startFreshDraft() {
        if intakeModel.hasResumableDraft {
            intakeModel.reset()
        }
        router.path.append(.assessment)
    }
}

private struct ProfileView: View {
    let router: RouterPath

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CompanionSectionHeading(
                    eyebrow: "我的",
                    title: "身体档案由你确认",
                    detail: "未确认草稿、AI 候选和正式记录始终分开。"
                )
                CompanionCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "person.text.rectangle")
                            .font(.title)
                            .foregroundStyle(BodyCompanionTheme.mint)
                        Text("个人身体档案")
                            .font(.headline)
                            .foregroundStyle(BodyCompanionTheme.ink)
                        Text("本样机还没有连接正式档案、导出或分享服务。")
                            .font(.subheadline)
                            .foregroundStyle(BodyCompanionTheme.secondaryInk)
                        Button("设置") { router.path.append(.settings) }
                            .buttonStyle(CompanionOutlineButtonStyle())
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("我的")
        .safeAreaPadding(.top)
        .companionScreenBackground()
    }
}

private struct ContextCueCard: View {
    let icon: String
    let title: String
    let detail: String
    let identifier: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(BodyCompanionTheme.accent)
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BodyCompanionTheme.ink)
            Text(detail)
                .font(.caption)
                .foregroundStyle(BodyCompanionTheme.secondaryInk)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: dynamicTypeSize.isAccessibilitySize ? nil : 132,
            alignment: .leading
        )
        .padding(14)
        .background(BodyCompanionTheme.surface, in: RoundedRectangle(cornerRadius: BodyCompanionTheme.compactCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BodyCompanionTheme.compactCornerRadius, style: .continuous)
                .stroke(BodyCompanionTheme.line.opacity(0.8), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

private struct AssistantBoundaryRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(BodyCompanionTheme.accent)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(BodyCompanionTheme.secondaryInk)
        }
    }
}
