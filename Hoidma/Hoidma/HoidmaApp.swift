import SwiftUI
import FirebaseCore

// This file is the entry point of your SwiftUI application.
// When creating a new project in Xcode, this file is generated for you.

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct HoidmaApp: App {
    // Register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authManager = AuthManager()
    
    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                // User is authenticated, show main app
                ContentView()
                    .environmentObject(authManager)
            } else {
                // User is not authenticated, show phone auth
                PhoneAuthView()
                    .environmentObject(authManager)
            }
        }
    }
}
