import SwiftUI
import UserNotifications

// This file is the entry point of your SwiftUI application.

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Initialize Supabase client (triggers lazy initialization)
        _ = SupabaseConfig.client
        print("Supabase client initialized")
        print("   URL: \(SupabaseConfig.projectURL)")

        // Set up notification center delegate
        UNUserNotificationCenter.current().delegate = self

        return true
    }

    // Handle notification received while app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.sound, .badge])
    }

    // Handle notification interaction
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

@main
struct HoidmaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @Environment(\.scenePhase) private var scenePhase

    // UI test detection
    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing") ||
        ProcessInfo.processInfo.environment["UI_TESTING"] == "1"
    }

    // Use Supabase AuthManager
    @StateObject private var authManager = SupabaseAuthManager()

    // Biometric authentication manager
    @StateObject private var biometricAuth = BiometricAuthManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if isUITesting {
                    ContentView()
                } else if !authManager.isAuthenticated {
                    // Not logged in - show email auth
                    EmailAuthView()
                } else {
                    // Logged in - show main content
                    ContentView()
                }
            }
            .environmentObject(authManager)
            .environmentObject(biometricAuth)
            .task {
                if isUITesting {
                    authManager.isAuthenticated = true
                    biometricAuth.isUnlocked = true
                    print("UI TESTING MODE: Forcing authenticated state")
                }
            }
        }
    }
}
