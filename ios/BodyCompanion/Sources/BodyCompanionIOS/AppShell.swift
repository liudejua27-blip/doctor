import BodyCompanionCore
import SwiftUI

public struct AppShell: View {
    @State private var selectedTab: AppTab = .today
    @State private var todayRouter = RouterPath()
    @State private var recordsRouter = RouterPath()
    @State private var analysisRouter = RouterPath()
    @State private var profileRouter = RouterPath()
    @State private var intakeModel = SignalIntakeModel()

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            tab("今天", systemImage: "sun.max", tab: .today, router: todayRouter) {
                TodayView(router: todayRouter, intakeModel: intakeModel)
            }
            tab("记录", systemImage: "figure.stand", tab: .records, router: recordsRouter) {
                RecordsView(router: recordsRouter, intakeModel: intakeModel)
            }
            tab("AI 分析", systemImage: "sparkles", tab: .analysis, router: analysisRouter) {
                AnalysisView(router: analysisRouter)
            }
            tab("我的", systemImage: "person.crop.circle", tab: .profile, router: profileRouter) {
                ProfileView(router: profileRouter)
            }
        }
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
                            onLocationsChanged: { intakeModel.setLocations($0) }
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

    var body: some View {
        List {
            Section("今天") {
                Text("把身体感受记录下来，后续再比较变化。")
                Button("开始记录") {
                    intakeModel.reset()
                    router.path.append(.assessment)
                }
                    .frame(minHeight: 44)
            }
        }
        .navigationTitle("今天")
    }
}

private struct RecordsView: View {
    let router: RouterPath
    let intakeModel: SignalIntakeModel

    var body: some View {
        List {
            Text("还没有已确认的身体记录")
            Button("创建位置草稿") {
                intakeModel.reset()
                router.path.append(.assessment)
            }
                .frame(minHeight: 44)
        }
        .navigationTitle("记录")
    }
}

private struct AnalysisView: View {
    let router: RouterPath

    var body: some View {
        ContentUnavailableView("AI 分析样机", systemImage: "sparkles", description: Text("完成位置和结构化描述后，AI 才能在安全规则允许时进行追问。"))
            .toolbar { Button("开始") { router.path.append(.assessment) } }
            .navigationTitle("AI 分析")
    }
}

private struct ProfileView: View {
    let router: RouterPath

    var body: some View {
        List {
            Section("个人身体档案") {
                Text("仅保存用户确认的结构化事实")
                Button("设置") { router.path.append(.settings) }
                    .frame(minHeight: 44)
            }
        }
        .navigationTitle("我的")
    }
}
