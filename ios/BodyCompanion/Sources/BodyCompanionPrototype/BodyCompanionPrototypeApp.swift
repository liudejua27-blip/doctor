import BodyCompanionIOS
import SwiftUI

@main
struct BodyCompanionPrototypeApp: App {
    var body: some Scene {
        WindowGroup {
            AppShell(runtimeConfiguration: .internalCandidate3D)
        }
    }
}
