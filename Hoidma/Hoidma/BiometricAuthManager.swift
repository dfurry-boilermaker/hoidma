import Foundation
import LocalAuthentication
import SwiftUI
import Combine

/// Manages biometric authentication (Face ID / Touch ID)
class BiometricAuthManager: ObservableObject {
    @Published var isUnlocked: Bool = false  // Start locked, require authentication on launch
    @Published var isAuthenticating: Bool = false
    @Published var authError: String? = nil
    @Published var hasAttemptedAuth: Bool = false  // Track if we've tried to authenticate

    /// Whether biometric authentication is enabled by user preference
    @AppStorage("biometricAuthEnabled") var biometricAuthEnabled: Bool = true

    /// Check if biometric authentication is available on this device
    var biometricType: LABiometryType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        return context.biometryType
    }

    /// Human-readable name for the biometric type
    var biometricTypeName: String {
        switch biometricType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return "Biometrics"
        @unknown default:
            return "Biometrics"
        }
    }

    /// Check if biometrics are available
    var canUseBiometrics: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Authenticate using biometrics
    func authenticate() {
        let context = LAContext()
        var error: NSError?

        hasAttemptedAuth = true

        // Check if user has disabled biometric auth - unlock immediately
        guard biometricAuthEnabled else {
            DispatchQueue.main.async {
                self.isUnlocked = true
            }
            return
        }

        // Check if biometric authentication is available
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Biometrics not available - try device passcode instead
            authenticateWithPasscode()
            return
        }

        isAuthenticating = true
        authError = nil

        let reason = "Unlock Hoidma to access your portfolio"

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authenticationError in
            DispatchQueue.main.async {
                self.isAuthenticating = false

                if success {
                    self.isUnlocked = true
                    self.authError = nil
                } else {
                    self.isUnlocked = false
                    if let error = authenticationError as? LAError {
                        switch error.code {
                        case .userCancel:
                            self.authError = "Authentication cancelled"
                        case .userFallback:
                            // SECURITY FIX: User chose fallback - try device passcode authentication
                            // Don't auto-unlock; instead attempt passcode auth
                            self.authenticateWithPasscode()
                        case .biometryNotEnrolled:
                            // SECURITY FIX: Don't auto-unlock when biometrics not set up
                            // Require passcode authentication instead
                            self.authError = "\(self.biometricTypeName) is not set up. Using passcode."
                            self.authenticateWithPasscode()
                        case .biometryLockout:
                            self.authError = "\(self.biometricTypeName) is locked. Use passcode."
                            self.authenticateWithPasscode()
                        default:
                            self.authError = "Authentication failed"
                        }
                    }
                }
            }
        }
    }

    /// SECURITY FIX: Authenticate using device passcode when biometrics unavailable
    private func authenticateWithPasscode() {
        let context = LAContext()

        // Use deviceOwnerAuthentication which allows passcode fallback
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Hoidma to access your portfolio") { success, error in
            DispatchQueue.main.async {
                if success {
                    self.isUnlocked = true
                    self.authError = nil
                } else {
                    self.isUnlocked = false
                    self.authError = "Authentication required"
                }
            }
        }
    }

    /// Lock the app (require re-authentication)
    func lock() {
        if biometricAuthEnabled {
            isUnlocked = false
            authError = nil
            hasAttemptedAuth = false
        }
    }

    /// Reset state for fresh start
    func reset() {
        isUnlocked = false
        isAuthenticating = false
        authError = nil
        hasAttemptedAuth = false
    }

    /// Check if authentication should be required
    var requiresAuthentication: Bool {
        return biometricAuthEnabled && !isUnlocked
    }
}
