import BodyCompanionIOS
import SwiftUI

@main
struct BodyCompanionInternalApp: App {
    var body: some Scene {
        WindowGroup {
            AppShell(runtimeConfiguration: InternalHostLaunchOptions.runtimeConfiguration)
        }
    }
}
