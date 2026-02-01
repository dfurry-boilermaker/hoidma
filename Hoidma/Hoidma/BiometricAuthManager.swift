import Foundation
import LocalAuthentication
import SwiftUI
import Combine

/// Manages biometric authentication (Face ID / Touch ID)
class BiometricAuthManager: ObservableObject {
    @Published var isUnlocked: Bool = true  // Start unlocked, lock when app goes to background
    @Published var isAuthenticating: Bool = false
    @Published var authError: String? = nil

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

        // Check if biometric authentication is available
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Biometrics not available, allow access
            DispatchQueue.main.async {
                self.isUnlocked = true
                self.authError = nil
            }
            return
        }

        // Check if user has disabled biometric auth
        guard biometricAuthEnabled else {
            DispatchQueue.main.async {
                self.isUnlocked = true
            }
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
                            // User chose to enter password - allow access
                            self.isUnlocked = true
                        case .biometryNotEnrolled:
                            self.authError = "\(self.biometricTypeName) is not set up"
                            self.isUnlocked = true // Allow access if not enrolled
                        case .biometryLockout:
                            self.authError = "\(self.biometricTypeName) is locked. Use passcode."
                        default:
                            self.authError = "Authentication failed"
                        }
                    }
                }
            }
        }
    }

    /// Lock the app (require re-authentication)
    func lock() {
        if biometricAuthEnabled && canUseBiometrics {
            isUnlocked = false
            authError = nil
        }
    }

    /// Reset state for fresh start
    func reset() {
        isUnlocked = false
        isAuthenticating = false
        authError = nil
    }
}
