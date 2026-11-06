import SwiftUI

@main
struct KOnNaviCompanionApp: App {
    init() {
        // Initialize background audio session on launch
        AudioPlayerManager.shared.configureAudioSession()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
