import SwiftUI
import UIKit

@objc(PhoneSceneDelegate)
class PhoneSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: ContentView())
        self.window = window
        window.makeKeyAndVisible()
        
        // Cold-launch external navigation URL jump
        if let firstURLContext = connectionOptions.urlContexts.first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                AudioPlayerManager.shared.handleIncomingNavigationURL(firstURLContext.url)
            }
        }
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let firstURLContext = URLContexts.first else { return }
        AudioPlayerManager.shared.handleIncomingNavigationURL(firstURLContext.url)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        if AudioPlayerManager.shared.travelMode == .transit && AudioPlayerManager.shared.transitPlans.isEmpty {
            AudioPlayerManager.shared.refreshTransitPlansForCurrentLocation(force: false)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        AudioPlayerManager.shared.configureAudioSession()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        if AudioPlayerManager.shared.travelMode == .transit && AudioPlayerManager.shared.transitPlans.isEmpty {
            AudioPlayerManager.shared.refreshTransitPlansForCurrentLocation(force: false)
        }
    }
    
    func application(_ application: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        AudioPlayerManager.shared.handleIncomingNavigationURL(url)
        return true
    }
    
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if connectingSceneSession.role.rawValue == "CPTemplateApplicationSceneSessionRoleApplication" {
            let config = UISceneConfiguration(name: "CarPlayConfiguration", sessionRole: connectingSceneSession.role)
            config.delegateClass = CarPlaySceneDelegate.self
            return config
        }
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = PhoneSceneDelegate.self
        return config
    }
}

@main
struct KOnNaviCompanionApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        AudioPlayerManager.shared.configureAudioSession()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    AudioPlayerManager.shared.handleIncomingNavigationURL(url)
                }
        }
    }
}
