import Foundation
import Combine
import Supabase
import UIKit

/// Manages user authentication using Supabase Email OTP (Magic Code)
///
/// SECURITY FEATURES:
/// - Email stored in Keychain (not UserDefaults)
/// - OTP verification rate limiting with lockout
/// - Sanitized error messages (no internal details exposed)
/// - Session re-validation on app foreground
@MainActor
class SupabaseAuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var email: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var rateLimitMessage: String?

    private var authStateTask: Task<Void, Never>?
    private var foregroundObserver: NSObjectProtocol?

    /// OTP rate limiter for security
    private let otpRateLimiter = OTPRateLimiter()

    init() {
        AppLogger.debug("SupabaseAuthManager: Initializing...")
        loadEmailFromKeychain()
        setupAuthStateListener()
        setupForegroundObserver()
        checkAuthState()
    }

    deinit {
        authStateTask?.cancel()
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Keychain Storage

    /// Load email from Keychain
    private func loadEmailFromKeychain() {
        if let savedEmail = KeychainHelper.load(forKey: .userEmail) {
            self.email = savedEmail
            AppLogger.debug("SupabaseAuthManager: Loaded email from Keychain")
        }
    }

    /// Save email to Keychain
    private func saveEmailToKeychain(_ email: String) {
        do {
            try KeychainHelper.save(email, forKey: .userEmail)
            AppLogger.debug("SupabaseAuthManager: Saved email to Keychain")
        } catch {
            AppLogger.warning("SupabaseAuthManager: Failed to save email to Keychain")
        }
    }

    /// Remove email from Keychain
    private func removeEmailFromKeychain() {
        KeychainHelper.delete(forKey: .userEmail)
        AppLogger.debug("SupabaseAuthManager: Removed email from Keychain")
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

    /// Set up observer to re-validate session when app enters foreground
    private func setupForegroundObserver() {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.revalidateSession()
            }
        }
    }

    /// Re-validate the session when app enters foreground
    private func revalidateSession() async {
        guard isAuthenticated else { return }

        do {
            // Attempt to refresh the session
            _ = try await SupabaseConfig.client.auth.session
            AppLogger.debug("SupabaseAuthManager: Session re-validated")
        } catch {
            // Session invalid - sign out
            AppLogger.warning("SupabaseAuthManager: Session invalid on foreground, signing out")
            self.currentUser = nil
            self.isAuthenticated = false
            self.email = nil
            removeEmailFromKeychain()

            NotificationCenter.default.post(
                name: .supabaseAuthStateChanged,
                object: nil,
                userInfo: nil
            )
        }
    }

    private func handleAuthStateChange(event: AuthChangeEvent, session: Session?) async {
        switch event {
        case .initialSession, .signedIn:
            if let session = session {
                self.currentUser = session.user
                self.isAuthenticated = true
                self.email = session.user.email

                // Save email to Keychain (secure storage)
                if let email = session.user.email {
                    saveEmailToKeychain(email)
                }

                // Reset rate limiter on successful auth
                await otpRateLimiter.recordSuccess()

                // Notify SupabaseManager of auth change
                NotificationCenter.default.post(
                    name: .supabaseAuthStateChanged,
                    object: nil,
                    userInfo: ["userId": session.user.id]
                )

                AppLogger.debug("SupabaseAuthManager: User signed in")
            }
        case .signedOut:
            self.currentUser = nil
            self.isAuthenticated = false
            self.email = nil
            removeEmailFromKeychain()

            // Notify SupabaseManager
            NotificationCenter.default.post(
                name: .supabaseAuthStateChanged,
                object: nil,
                userInfo: nil
            )

            AppLogger.debug("SupabaseAuthManager: User signed out")
        case .tokenRefreshed:
            AppLogger.debug("SupabaseAuthManager: Token refreshed")
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
                self.email = session.user.email ?? KeychainHelper.load(forKey: .userEmail)
                AppLogger.debug("SupabaseAuthManager: Found existing session")
            } catch {
                // No active session - try to load cached email
                if let savedEmail = KeychainHelper.load(forKey: .userEmail) {
                    self.email = savedEmail
                }
                AppLogger.debug("SupabaseAuthManager: No existing session")
            }
        }
    }

    // MARK: - Email OTP Authentication

    /// Send verification code to email via Supabase OTP
    /// - Parameter email: User's email address
    func sendVerificationCode(to email: String) async throws {
        isLoading = true
        errorMessage = nil
        rateLimitMessage = nil

        do {
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            AppLogger.debug("SupabaseAuthManager: Sending OTP...")

            // Send OTP via Supabase Email
            try await SupabaseConfig.client.auth.signInWithOTP(
                email: trimmedEmail
            )

            self.email = trimmedEmail
            self.isLoading = false

            // Notify rate limiter that a new code was sent
            await otpRateLimiter.newCodeRequested()

            AppLogger.debug("SupabaseAuthManager: OTP sent successfully")
        } catch {
            AppLogger.warning("SupabaseAuthManager: Error sending OTP")
            self.isLoading = false
            self.errorMessage = mapErrorToSafeMessage(error)
            throw error
        }
    }

    /// Verify the OTP code and sign in the user
    /// - Parameter code: The 6-digit verification code
    func verifyCode(_ code: String) async throws {
        guard let email = email else {
            AppLogger.warning("SupabaseAuthManager: Missing email")
            throw SupabaseAuthError.missingEmail
        }

        // Check rate limit BEFORE attempting verification
        let (allowed, message) = await otpRateLimiter.canVerify()
        if !allowed {
            rateLimitMessage = message
            throw SupabaseAuthError.rateLimited(message: message ?? "Too many attempts")
        }

        isLoading = true
        errorMessage = nil
        rateLimitMessage = nil

        // Record the attempt
        await otpRateLimiter.recordAttempt()

        do {
            AppLogger.debug("SupabaseAuthManager: Verifying OTP...")

            let session = try await SupabaseConfig.client.auth.verifyOTP(
                email: email,
                token: code,
                type: .email
            )

            self.currentUser = session.user
            self.isAuthenticated = true
            self.isLoading = false

            // Save email to Keychain
            saveEmailToKeychain(email)

            // Record success (resets rate limiter)
            await otpRateLimiter.recordSuccess()

            AppLogger.debug("SupabaseAuthManager: Verification successful")
        } catch {
            // Record failure for rate limiting
            await otpRateLimiter.recordFailure()

            // Check if now locked out
            if await otpRateLimiter.isLockedOut() {
                let seconds = await otpRateLimiter.lockoutRemainingSeconds()
                let minutes = seconds / 60
                rateLimitMessage = "Too many failed attempts. Try again in \(minutes) minutes."
                AppLogger.warning("SupabaseAuthManager: User locked out after too many failed OTP attempts")
            }

            // Show remaining attempts
            let remaining = await otpRateLimiter.remainingAttempts()
            if remaining > 0 && remaining < 3 {
                rateLimitMessage = "\(remaining) attempt\(remaining == 1 ? "" : "s") remaining"
            }

            AppLogger.warning("SupabaseAuthManager: Error verifying OTP")
            self.isLoading = false
            self.errorMessage = mapErrorToSafeMessage(error)
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
            removeEmailFromKeychain()
            AppLogger.debug("SupabaseAuthManager: Signed out successfully")
        } catch {
            AppLogger.warning("SupabaseAuthManager: Error signing out")
            throw error
        }
    }

    // MARK: - Helpers

    /// Get the current user's UUID
    var userID: UUID? {
        return currentUser?.id
    }

    /// Map errors to safe, user-friendly messages
    /// SECURITY: Never expose internal error details to users
    private func mapErrorToSafeMessage(_ error: Error) -> String {
        let errorDescription = error.localizedDescription.lowercased()

        // Check for specific, safe-to-expose error types
        if errorDescription.contains("invalid") || errorDescription.contains("incorrect") {
            return "Invalid verification code. Please check and try again."
        } else if errorDescription.contains("expired") {
            return "Verification code expired. Please request a new code."
        } else if errorDescription.contains("rate") || errorDescription.contains("limit") || errorDescription.contains("too many") {
            return "Too many attempts. Please wait and try again."
        } else if errorDescription.contains("network") || errorDescription.contains("connection") || errorDescription.contains("offline") {
            return "Network error. Please check your connection."
        } else if errorDescription.contains("email") && (errorDescription.contains("format") || errorDescription.contains("invalid")) {
            return "Please enter a valid email address."
        }

        // SECURITY: Return generic message for all other errors
        // Never expose: server errors, database errors, internal states
        AppLogger.debug("SupabaseAuthManager: Unmapped error type: \(type(of: error))")
        return "Unable to complete request. Please try again."
    }
}

// MARK: - Errors

enum SupabaseAuthError: LocalizedError {
    case missingEmail
    case rateLimited(message: String)

    var errorDescription: String? {
        switch self {
        case .missingEmail:
            return "Email is missing. Please enter your email address."
        case .rateLimited(let message):
            return message
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let supabaseAuthStateChanged = Notification.Name("supabaseAuthStateChanged")
}
