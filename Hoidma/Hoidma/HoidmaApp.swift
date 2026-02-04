import SwiftUI
import UserNotifications

// This file is the entry point of your SwiftUI application.

// MARK: - Loading Screen View
struct LoadingView: View {
    @ObservedObject var biometricAuth: BiometricAuthManager
    @EnvironmentObject var authManager: SupabaseAuthManager
    var onUnlockTapped: () -> Void
    var onLogoutTapped: () -> Void

    var body: some View {
        ZStack {
            // Background color matching the image to prevent any gaps
            Color(red: 0.0, green: 0.8, blue: 0.2)
                .ignoresSafeArea(.all)

            GeometryReader { geometry in
                Image("loading")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
            .ignoresSafeArea(.all)

            // Buttons at bottom (only show after auth has been attempted)
            if biometricAuth.hasAttemptedAuth {
                VStack {
                    Spacer()

                    VStack(spacing: 16) {
                        // Unlock button
                        Button(action: onUnlockTapped) {
                            Text(biometricAuth.isAuthenticating ? "Authenticating..." : "Unlock")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color(red: 0.0, green: 1.0, blue: 0.3))
                                .cornerRadius(28)
                        }
                        .disabled(biometricAuth.isAuthenticating)
                        .padding(.horizontal, 32)

                        // Log out button
                        Button(action: onLogoutTapped) {
                            Text("Log out")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Color(red: 0.0, green: 1.0, blue: 0.3))
                        }
                    }
                    .padding(.bottom, 60)
                }
            }
        }
        .onAppear {
            // Automatically trigger Face ID when loading screen appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if !biometricAuth.isUnlocked && biometricAuth.biometricAuthEnabled {
                    biometricAuth.authenticate()
                }
            }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Initialize Supabase client (triggers lazy initialization)
        _ = SupabaseConfig.client
        AppLogger.debug("Supabase client initialized")

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

    // Lock app to portrait orientation only
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
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

    // Shared StockViewModel for the app
    @StateObject private var stockViewModel = StockViewModel()

    // Loading state
    @State private var isLoading = true
    @State private var loadingOpacity: Double = 1.0
    @State private var showLockScreen = false  // Show lock screen after initial load

    // Selected tab - reset to home on app launch
    @AppStorage("selectedTab") private var selectedTab: Int = 1

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Main content layer (always rendered underneath)
                Group {
                    if isUITesting {
                        ContentView(viewModel: stockViewModel)
                    } else if !authManager.isAuthenticated {
                        // Not logged in - show email auth
                        EmailAuthView()
                    } else {
                        // Logged in - show main content
                        ContentView(viewModel: stockViewModel)
                    }
                }
                .environmentObject(authManager)
                .environmentObject(biometricAuth)

                // Loading screen overlay - stays visible during initial load and handles biometric auth
                if (isLoading || showLockScreen) && !isUITesting {
                    LoadingView(
                        biometricAuth: biometricAuth,
                        onUnlockTapped: {
                            biometricAuth.authenticate()
                        },
                        onLogoutTapped: {
                            Task {
                                do {
                                    try await authManager.signOut()
                                    showLockScreen = false
                                    isLoading = false
                                } catch {
                                    AppLogger.error("Error signing out: \(error.localizedDescription)")
                                }
                            }
                        }
                    )
                    .environmentObject(authManager)
                    .opacity(loadingOpacity)
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                }
            }
            .task {
                if isUITesting {
                    authManager.isAuthenticated = true
                    biometricAuth.isUnlocked = true
                    stockViewModel.isDataReady = true
                    isLoading = false
                    AppLogger.debug("UI TESTING MODE: Forcing authenticated state")
                    return
                }

                // Wait for minimum loading time
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

                // Start the auth flow
                await handleAuthFlow()
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                handleScenePhaseChange(from: oldPhase, to: newPhase)
            }
            .onChange(of: biometricAuth.isUnlocked) { oldValue, newValue in
                // When biometric auth succeeds, dismiss loading and lock screen
                if newValue {
                    AppLogger.debug("Biometric unlocked - dismissing screens and refreshing prices")
                    selectedTab = 1

                    // Dismiss with fade animation
                    if isLoading || showLockScreen {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            loadingOpacity = 0.0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            isLoading = false
                            showLockScreen = false
                        }
                    }

                    // Refresh stock prices after unlocking
                    if authManager.isAuthenticated {
                        Task { @MainActor in
                            await stockViewModel.updateAllPrices()
                        }
                    }
                }
            }
            .onChange(of: authManager.isAuthenticated) { oldValue, newValue in
                // When auth state changes
                if !newValue && isLoading {
                    // Not authenticated - dismiss to show login
                    dismissLoadingWithFade()
                }
            }
        }
    }

    /// Main authentication flow
    @MainActor
    private func handleAuthFlow() async {
        // Check if user is authenticated
        if !authManager.isAuthenticated {
            // Not logged in - dismiss loading to show login screen
            AppLogger.debug("Not authenticated - showing login")
            dismissLoadingWithFade()
            return
        }

        // User is authenticated - check biometric
        if !biometricAuth.biometricAuthEnabled {
            // Biometric disabled - unlock and proceed
            AppLogger.debug("Biometric disabled - unlocking")
            biometricAuth.isUnlocked = true
            selectedTab = 1
            dismissLoadingWithFade()
            return
        }

        // Biometric enabled - keep loading screen visible
        // LoadingView will automatically trigger Face ID and show Unlock/Log out buttons
        if !biometricAuth.isUnlocked {
            AppLogger.debug("Keeping loading screen - biometric auth will trigger automatically")
            // Loading screen stays visible and handles biometric auth
        } else {
            // Already unlocked
            selectedTab = 1
            dismissLoadingWithFade()
        }
    }

    /// Handle app going to background/foreground
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        guard !isUITesting else { return }

        switch newPhase {
        case .background:
            // Lock the app when going to background
            if authManager.isAuthenticated && biometricAuth.biometricAuthEnabled {
                biometricAuth.lock()
                showLockScreen = true  // Show lock screen when returning
                loadingOpacity = 1.0   // Reset opacity for lock screen
                AppLogger.debug("App locked - went to background")
            }
        case .active:
            // When becoming active, check if we need to re-authenticate
            if authManager.isAuthenticated && biometricAuth.biometricAuthEnabled && !biometricAuth.isUnlocked {
                showLockScreen = true
                loadingOpacity = 1.0  // Reset opacity for lock screen
                AppLogger.debug("App active - showing lock screen for re-authentication")
            }

            // CRITICAL: Refresh stock prices when app becomes active
            // This ensures prices and percentages are up-to-date on each app open
            if authManager.isAuthenticated && biometricAuth.isUnlocked {
                AppLogger.debug("App active - refreshing stock prices")
                Task { @MainActor in
                    await stockViewModel.updateAllPrices()
                }
            }
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    private func dismissLoadingWithFade() {
        guard isLoading else { return }

        AppLogger.debug("Dismissing loading screen")

        // Fade out the loading screen with smooth animation
        withAnimation(.easeInOut(duration: 0.4)) {
            loadingOpacity = 0.0
        }
        // Remove loading view after fade completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isLoading = false
        }
    }
}
