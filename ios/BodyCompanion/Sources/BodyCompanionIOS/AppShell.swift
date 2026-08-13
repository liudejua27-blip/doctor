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
    private let userProfileHeightMeters: Float?
    private let heightPresetHeightsMeters: [Float]?

    public init(
        runtimeConfiguration: InternalP0RuntimeConfiguration = .safeDefault,
        userProfileHeightMeters: Float? = nil,
        heightPresetHeightsMeters: [Float]? = nil
    ) {
        self.runtimeConfiguration = runtimeConfiguration
        self.userProfileHeightMeters = userProfileHeightMeters ?? runtimeConfiguration.userProfileHeightMeters
        self.heightPresetHeightsMeters = heightPresetHeightsMeters
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            tab("今天", systemImage: "sun.max", tab: .today, router: todayRouter) {
                CompanionTodayView(router: todayRouter, intakeModel: intakeModel)
            }
            tab("记录", systemImage: "figure.stand", tab: .records, router: recordsRouter) {
                CompanionRecordsView(router: recordsRouter, intakeModel: intakeModel)
            }
            tab("AI 身体助手", systemImage: "sparkles", tab: .analysis, router: analysisRouter) {
                CompanionAssistantView(router: analysisRouter, intakeModel: intakeModel)
            }
            tab("我的", systemImage: "person.crop.circle", tab: .profile, router: profileRouter) {
                CompanionProfileView(router: profileRouter)
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
                            userProfileHeightMeters: userProfileHeightMeters,
                            heightPresetHeightsMeters: heightPresetHeightsMeters,
                            prototype3DEnabled: runtimeConfiguration.candidate3DEnabled,
                            onLocationsChanged: { locations in intakeModel.setLocations(locations) },
                            onContinue: { router.path.append(.intake) }
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
