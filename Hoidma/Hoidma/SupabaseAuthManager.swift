import Foundation
import Combine
import Supabase

/// Manages user authentication using Supabase Email OTP (Magic Code)
@MainActor
class SupabaseAuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var email: String?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var authStateTask: Task<Void, Never>?

    init() {
        print("SupabaseAuthManager: Initializing...")
        setupAuthStateListener()
        checkAuthState()
    }

    deinit {
        authStateTask?.cancel()
    }

    // MARK: - Auth State Management

    /// Listen for auth state changes
    private func setupAuthStateListener() {
        authStateTask = Task {
            for await (event, session) in SupabaseConfig.client.auth.authStateChanges {
                await handleAuthStateChange(event: event, session: session)
            }
        }
    }

    private func handleAuthStateChange(event: AuthChangeEvent, session: Session?) async {
        switch event {
        case .initialSession, .signedIn:
            if let session = session {
                self.currentUser = session.user
                self.isAuthenticated = true
                self.email = session.user.email

                // Save email locally
                if let email = session.user.email {
                    UserDefaults.standard.set(email, forKey: "userEmail")
                }

                // Notify SupabaseManager of auth change
                NotificationCenter.default.post(
                    name: .supabaseAuthStateChanged,
                    object: nil,
                    userInfo: ["userId": session.user.id]
                )

                print("SupabaseAuthManager: User signed in - \(session.user.id)")
            }
        case .signedOut:
            self.currentUser = nil
            self.isAuthenticated = false
            self.email = nil
            UserDefaults.standard.removeObject(forKey: "userEmail")

            // Notify SupabaseManager
            NotificationCenter.default.post(
                name: .supabaseAuthStateChanged,
                object: nil,
                userInfo: nil
            )

            print("SupabaseAuthManager: User signed out")
        case .tokenRefreshed:
            print("SupabaseAuthManager: Token refreshed")
        default:
            break
        }
    }

    /// Check if user is already authenticated on app launch
    private func checkAuthState() {
        Task {
            do {
                let session = try await SupabaseConfig.client.auth.session
                self.currentUser = session.user
                self.isAuthenticated = true
                self.email = session.user.email ?? UserDefaults.standard.string(forKey: "userEmail")
                print("SupabaseAuthManager: Found existing session for user \(session.user.id)")
            } catch {
                // No active session
                if let savedEmail = UserDefaults.standard.string(forKey: "userEmail") {
                    self.email = savedEmail
                }
                print("SupabaseAuthManager: No existing session")
            }
        }
    }

    // MARK: - Email OTP Authentication

    /// Send verification code to email via Supabase OTP
    /// - Parameter email: User's email address
    func sendVerificationCode(to email: String) async throws {
        isLoading = true
        errorMessage = nil

        do {
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            print("SupabaseAuthManager: Sending OTP to \(trimmedEmail)...")

            // Send OTP via Supabase Email
            try await SupabaseConfig.client.auth.signInWithOTP(
                email: trimmedEmail
            )

            self.email = trimmedEmail
            self.isLoading = false

            print("SupabaseAuthManager: OTP sent successfully to email")
        } catch {
            print("SupabaseAuthManager: Error sending OTP: \(error.localizedDescription)")
            self.isLoading = false
            self.errorMessage = mapError(error)
            throw error
        }
    }

    /// Verify the OTP code and sign in the user
    /// - Parameter code: The 6-digit verification code
    func verifyCode(_ code: String) async throws {
        guard let email = email else {
            print("SupabaseAuthManager: Missing email")
            throw SupabaseAuthError.missingEmail
        }

        isLoading = true
        errorMessage = nil

        do {
            print("SupabaseAuthManager: Verifying OTP for \(email)...")

            let session = try await SupabaseConfig.client.auth.verifyOTP(
                email: email,
                token: code,
                type: .email
            )

            self.currentUser = session.user
            self.isAuthenticated = true
            self.isLoading = false

            // Save email
            UserDefaults.standard.set(email, forKey: "userEmail")

            print("SupabaseAuthManager: Verification successful")
            print("   User ID: \(session.user.id)")
            print("   Email: \(session.user.email ?? "nil")")
        } catch {
            print("SupabaseAuthManager: Error verifying OTP: \(error.localizedDescription)")
            self.isLoading = false
            self.errorMessage = mapError(error)
            throw error
        }
    }

    /// Sign out the current user
    func signOut() async throws {
        do {
            try await SupabaseConfig.client.auth.signOut()
            self.isAuthenticated = false
            self.currentUser = nil
            self.email = nil
            UserDefaults.standard.removeObject(forKey: "userEmail")
            print("SupabaseAuthManager: Signed out successfully")
        } catch {
            print("SupabaseAuthManager: Error signing out: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Helpers

    /// Get the current user's UUID
    var userID: UUID? {
        return currentUser?.id
    }

    /// Map errors to user-friendly messages
    private func mapError(_ error: Error) -> String {
        let errorDescription = error.localizedDescription.lowercased()

        if errorDescription.contains("invalid") {
            return "Invalid verification code. Please try again."
        } else if errorDescription.contains("expired") {
            return "Verification code expired. Please request a new one."
        } else if errorDescription.contains("rate") || errorDescription.contains("limit") {
            return "Too many attempts. Please wait a moment and try again."
        } else if errorDescription.contains("network") {
            return "Network error. Please check your connection."
        } else if errorDescription.contains("email") && errorDescription.contains("format") {
            return "Please enter a valid email address."
        }

        return "An error occurred: \(error.localizedDescription)"
    }
}

// MARK: - Errors

enum SupabaseAuthError: LocalizedError {
    case missingEmail

    var errorDescription: String? {
        switch self {
        case .missingEmail:
            return "Email is missing. Please enter your email address."
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let supabaseAuthStateChanged = Notification.Name("supabaseAuthStateChanged")
}
