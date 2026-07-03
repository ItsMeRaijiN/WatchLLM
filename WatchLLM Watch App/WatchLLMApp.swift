import SwiftUI

@main
struct WatchLLMApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ChatView()
            }
        }
    }
}
