import BodyCompanionCore
import SwiftUI

struct CompanionTodayView: View {
    let router: RouterPath
    let intakeModel: SignalIntakeModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                CompanionWelcomeMark()

                CompanionSectionHeading(
                    eyebrow: "你的身体助手",
                    title: "先把这次不适记录清楚",
                    detail: "从主观位置开始，逐步补充感觉、时间和影响。你随时可以复核。"
                )

                CompanionCard(emphasized: true) {
                    VStack(alignment: .leading, spacing: 16) {
                        CompanionStatusPill(
                            intakeModel.hasResumableDraft ? "本次打开中有未确认草稿" : "从一条新记录开始",
                            systemImage: intakeModel.hasResumableDraft ? "pencil.and.list.clipboard" : "plus.circle.fill",
                            tint: intakeModel.hasResumableDraft ? BodyCompanionTheme.warm : BodyCompanionTheme.accent
                        )
                        Text("告诉我，你感觉在身体哪里？")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(BodyCompanionTheme.ink)
                        Text("身体地图只表达“我感觉在这里”，不判断病因或受损组织。")
                            .font(.subheadline)
                            .foregroundStyle(BodyCompanionTheme.secondaryInk)
                        CompanionIntakeEntryActions(
                            router: router,
                            intakeModel: intakeModel,
                            freshTitle: "记录这次不适",
                            freshSystemImage: "figure.stand"
                        )
                    }
                }

                CompanionJourneyStrip()

                CompanionSectionHeading(
                    title: "从当时的情境回想",
                    detail: "这些只是帮助你回忆的入口，不会自动写成原因或身体档案。"
                )
                contextCueCards

                CompanionTrustCard()
            }
            .padding(20)
        }
        .accessibilityIdentifier("screen.today")
        .navigationTitle("今天")
        .safeAreaPadding(.top)
        .companionScreenBackground()
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
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.context-cues.vertical")
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
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.context-cues.horizontal")
        }
    }
}

struct CompanionRecordsView: View {
    let router: RouterPath
    let intakeModel: SignalIntakeModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CompanionSectionHeading(
                    eyebrow: "记录",
                    title: "草稿与正式记录，始终分开",
                    detail: "当前内部样机只保留本次打开期间的未确认草稿；尚未连接正式档案服务。"
                )

                if intakeModel.hasResumableDraft {
                    CompanionCard(emphasized: true) {
                        VStack(alignment: .leading, spacing: 13) {
                            CompanionStatusPill("本次打开中的草稿", systemImage: "pencil.line", tint: BodyCompanionTheme.warm)
                            Text("已标记 \(intakeModel.draft.locations.count) 个位置")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(BodyCompanionTheme.ink)
                            Text("当前阶段：\(intakeModel.phase.displayName)。它还不是已保存的身体记录。")
                                .font(.subheadline)
                                .foregroundStyle(BodyCompanionTheme.secondaryInk)
                            CompanionIntakeEntryActions(
                                router: router,
                                intakeModel: intakeModel,
                                freshTitle: "从人体开始记录",
                                freshSystemImage: "plus"
                            )
                        }
                    }
                }

                CompanionCard {
                    VStack(alignment: .leading, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(BodyCompanionTheme.accentSoft)
                                .frame(width: 54, height: 54)
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.title2)
                                .foregroundStyle(BodyCompanionTheme.accent)
                        }
                        Text("还没有可读取的正式记录")
                            .font(.headline)
                            .foregroundStyle(BodyCompanionTheme.ink)
                        Text("未来的记录检索会基于你确认的结构化事实，而不是让 AI 猜测或假装记得整段对话。")
                            .font(.subheadline)
                            .foregroundStyle(BodyCompanionTheme.secondaryInk)
                        if !intakeModel.hasResumableDraft {
                            CompanionIntakeEntryActions(
                                router: router,
                                intakeModel: intakeModel,
                                freshTitle: "开始第一条记录",
                                freshSystemImage: "plus"
                            )
                        }
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

struct CompanionAssistantView: View {
    let router: RouterPath
    let intakeModel: SignalIntakeModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                CompanionSectionHeading(
                    eyebrow: "AI 身体助手",
                    title: "先完成安全、可复核的记录",
                    detail: "它不是 AI 医生。普通对话只有在服务端确定性安全门允许时才可能发生。"
                )

                CompanionCard(emphasized: true) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .center, spacing: 14) {
                            CompanionAssistantOrb()
                            VStack(alignment: .leading, spacing: 5) {
                                Text("当前准备度")
                                    .font(.headline)
                                    .foregroundStyle(BodyCompanionTheme.ink)
                                Text(readinessText)
                                    .font(.subheadline)
                                    .foregroundStyle(BodyCompanionTheme.secondaryInk)
                            }
                        }
                        CompanionStatusPill("普通对话尚未接入", systemImage: "lock.fill", tint: BodyCompanionTheme.warm)
                            .accessibilityIdentifier("analysis.standard-chat-unavailable")
                        CompanionIntakeEntryActions(
                            router: router,
                            intakeModel: intakeModel,
                            freshTitle: "从身体地图开始",
                            freshSystemImage: "arrow.right"
                        )
                    }
                }

                CompanionCard {
                    VStack(alignment: .leading, spacing: 13) {
                        Text("三道可信边界")
                            .font(.headline)
                            .foregroundStyle(BodyCompanionTheme.ink)
                        AssistantBoundaryRow(icon: "shield.lefthalf.filled", title: "规则先行", text: "确定性安全检查先于任何普通模型分析")
                        AssistantBoundaryRow(icon: "questionmark.bubble", title: "一次一问", text: "未来只处理应用服务批准的单个问题，不自由选题")
                        AssistantBoundaryRow(icon: "checkmark.seal", title: "由你确认", text: "AI 整理内容始终标成候选，不自动写入正式档案")
                    }
                }

                CompanionCard {
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: "exclamationmark.shield")
                            .font(.title3)
                            .foregroundStyle(BodyCompanionTheme.warm)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("未命中当前规则，不等于安全")
                                .font(.headline)
                                .foregroundStyle(BodyCompanionTheme.ink)
                            Text("信息不足、规则不可用或场景未审核时，流程会保守停下并保留手动记录入口。")
                                .font(.subheadline)
                                .foregroundStyle(BodyCompanionTheme.secondaryInk)
                        }
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

    private var readinessText: String {
        if intakeModel.draft.locations.isEmpty {
            return "还需要先标记主观位置"
        }
        return "已标记 \(intakeModel.draft.locations.count) 个位置 · \(intakeModel.phase.displayName)"
    }
}

struct CompanionProfileView: View {
    let router: RouterPath

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CompanionSectionHeading(
                    eyebrow: "我的",
                    title: "数据和能力，由你掌控",
                    detail: "未确认草稿、AI 候选和正式记录使用不同边界，不会悄悄合并。"
                )

                CompanionCard {
                    VStack(alignment: .leading, spacing: 14) {
                        CapabilityRow(icon: "person.text.rectangle", title: "个人身体档案", detail: "尚未连接", state: "关闭")
                        Divider()
                        CapabilityRow(icon: "square.and.arrow.up", title: "导出与分享", detail: "需要身份、同意和二次确认", state: "关闭")
                        Divider()
                        CapabilityRow(icon: "brain.head.profile", title: "云端 AI", detail: "没有真实 Provider 或长期记忆", state: "关闭")
                        Divider()
                        CapabilityRow(icon: "figure.stand", title: "2D / 部位列表", detail: "当前可靠的主观位置入口", state: "可用")
                    }
                }

                CompanionCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("隐私承诺", systemImage: "hand.raised.fill")
                            .font(.headline)
                            .foregroundStyle(BodyCompanionTheme.ink)
                        Text("当前内部 Host 不连接网络、Provider、正式资料、持久化或遥测；终止 App 后不承诺恢复本次草稿。")
                            .font(.subheadline)
                            .foregroundStyle(BodyCompanionTheme.secondaryInk)
                        Button("查看内部设置") { router.path.append(.settings) }
                            .buttonStyle(CompanionOutlineButtonStyle())
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("我的")
        .safeAreaPadding(.top)
        .companionScreenBackground()
        .accessibilityIdentifier("screen.profile")
    }
}

/// Makes the in-memory P0 draft decision visible at every entry point. It
/// never claims the draft was persisted and only resets after explicit consent.
struct CompanionIntakeEntryActions: View {
    let router: RouterPath
    let intakeModel: SignalIntakeModel
    let freshTitle: String
    let freshSystemImage: String
    @State private var showStartOverConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if intakeModel.hasResumableDraft {
                Text("本次打开期间保留 · 尚未正式保存")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BodyCompanionTheme.secondaryInk)
                Button(action: continueCurrentDraft) {
                    Label("继续这条草稿", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(CompanionPrimaryButtonStyle())
                .accessibilityHint("继续当前打开期间的未确认草稿，不会新建或保存正式记录")
                .accessibilityIdentifier("intake-entry.resume-draft")

                Button("新建一条记录", role: .destructive) {
                    showStartOverConfirmation = true
                }
                .buttonStyle(CompanionOutlineButtonStyle())
                .accessibilityHint("需要先确认放弃当前打开期间的未确认草稿")
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
            Text("这会放弃当前打开期间的未确认草稿。它尚未成为正式身体记录。")
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

private struct CompanionWelcomeMark: View {
    var body: some View {
        HStack(spacing: 11) {
            CompanionAssistantOrb()
            VStack(alignment: .leading, spacing: 2) {
                Text("你好")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BodyCompanionTheme.secondaryInk)
                Text("今天身体感觉怎么样？")
                    .font(.headline)
                    .foregroundStyle(BodyCompanionTheme.ink)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("你好，今天身体感觉怎么样")
    }
}

private struct CompanionAssistantOrb: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [BodyCompanionTheme.accentSoft, BodyCompanionTheme.surfaceTinted],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 52, height: 52)
            Image(systemName: "waveform.path.ecg")
                .font(.title3.weight(.semibold))
                .foregroundStyle(BodyCompanionTheme.accent)
        }
        .accessibilityHidden(true)
    }
}

private struct CompanionJourneyStrip: View {
    private let steps = [
        ("1", "标记位置", "mappin.and.ellipse"),
        ("2", "描述感受", "text.bubble"),
        ("3", "安全检查", "shield.lefthalf.filled"),
        ("4", "你确认", "checkmark.seal"),
    ]

    var body: some View {
        CompanionCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("一次记录，四个清楚步骤")
                    .font(.headline)
                    .foregroundStyle(BodyCompanionTheme.ink)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 8) {
                        journeySteps
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        journeySteps
                    }
                }
                Text("这里只说明流程，不代表安全检查或正式保存已经完成。")
                    .font(.caption)
                    .foregroundStyle(BodyCompanionTheme.secondaryInk)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("记录流程：标记位置，描述感受，安全检查，由你确认。当前只是流程说明。")
        .accessibilityIdentifier("today.journey")
    }

    @ViewBuilder
    private var journeySteps: some View {
        ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(BodyCompanionTheme.accentSoft)
                        .frame(width: 30, height: 30)
                    Image(systemName: step.2)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BodyCompanionTheme.accent)
                }
                Text(step.1)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BodyCompanionTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct CompanionTrustCard: View {
    var body: some View {
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
                    Text("AI 候选与用户确认事实分开。当前样机也不会把健康对话发送到日志或云端。")
                        .font(.subheadline)
                        .foregroundStyle(BodyCompanionTheme.secondaryInk)
                }
            }
        }
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
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(BodyCompanionTheme.accentSoft)
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(BodyCompanionTheme.accent)
            }
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BodyCompanionTheme.ink)
            Text(detail)
                .font(.caption)
                .foregroundStyle(BodyCompanionTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? nil : 138, alignment: .leading)
        .padding(14)
        .background(BodyCompanionTheme.surface, in: RoundedRectangle(cornerRadius: BodyCompanionTheme.compactCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BodyCompanionTheme.compactCornerRadius, style: .continuous)
                .stroke(BodyCompanionTheme.line.opacity(0.8), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(detail)")
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier(identifier)
    }
}

private struct AssistantBoundaryRow: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .foregroundStyle(BodyCompanionTheme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BodyCompanionTheme.ink)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(BodyCompanionTheme.secondaryInk)
            }
        }
    }
}

private struct CapabilityRow: View {
    let icon: String
    let title: String
    let detail: String
    let state: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(BodyCompanionTheme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BodyCompanionTheme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(BodyCompanionTheme.secondaryInk)
            }
            Spacer(minLength: 8)
            Text(state)
                .font(.caption.weight(.bold))
                .foregroundStyle(state == "可用" ? BodyCompanionTheme.mint : BodyCompanionTheme.secondaryInk)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(BodyCompanionTheme.surfaceTinted, in: Capsule())
        }
    }
}
