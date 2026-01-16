import Foundation
import Combine
import FirebaseAuth

/// Manages user authentication using phone numbers
class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var phoneNumber: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var verificationID: String?
    private let auth = Auth.auth()
    
    init() {
        // Check if user is already authenticated
        checkAuthState()
        
        // Listen for auth state changes
        auth.addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.currentUser = user
                self?.isAuthenticated = user != nil
                if let phoneNumber = user?.phoneNumber {
                    self?.phoneNumber = phoneNumber
                    // Save phone number locally
                    UserDefaults.standard.set(phoneNumber, forKey: "userPhoneNumber")
                }
            }
        }
    }
    
    /// Check if user is already authenticated
    private func checkAuthState() {
        if let user = auth.currentUser {
            self.currentUser = user
            self.isAuthenticated = true
            self.phoneNumber = user.phoneNumber ?? UserDefaults.standard.string(forKey: "userPhoneNumber")
        } else {
            // Check if we have a saved phone number
            if let savedPhone = UserDefaults.standard.string(forKey: "userPhoneNumber") {
                self.phoneNumber = savedPhone
            }
        }
    }
    
    /// Send verification code to phone number
    func sendVerificationCode(to phoneNumber: String) async throws {
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        do {
            // Format phone number (ensure it starts with +)
            let formattedPhone = phoneNumber.hasPrefix("+") ? phoneNumber : "+\(phoneNumber)"
            
            // Send verification code
            let verificationID = try await PhoneAuthProvider.provider().verifyPhoneNumber(
                formattedPhone,
                uiDelegate: nil
            )
            
            DispatchQueue.main.async {
                self.verificationID = verificationID
                self.phoneNumber = formattedPhone
                self.isLoading = false
            }
        } catch {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
            throw error
        }
    }
    
    /// Verify the code and sign in the user
    func verifyCode(_ code: String) async throws {
        guard let verificationID = verificationID else {
            throw AuthError.missingVerificationID
        }
        
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        do {
            let credential = PhoneAuthProvider.provider().credential(
                withVerificationID: verificationID,
                verificationCode: code
            )
            
            // Sign in with credential
            let result = try await auth.signIn(with: credential)
            
            DispatchQueue.main.async {
                self.currentUser = result.user
                self.isAuthenticated = true
                self.phoneNumber = result.user.phoneNumber
                self.isLoading = false
                
                // Save phone number locally
                if let phoneNumber = result.user.phoneNumber {
                    UserDefaults.standard.set(phoneNumber, forKey: "userPhoneNumber")
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
            throw error
        }
    }
    
    /// Sign out the current user
    func signOut() throws {
        try auth.signOut()
        DispatchQueue.main.async {
            self.isAuthenticated = false
            self.currentUser = nil
            self.phoneNumber = nil
            self.verificationID = nil
            // Clear saved phone number
            UserDefaults.standard.removeObject(forKey: "userPhoneNumber")
        }
    }
    
    /// Get the current user's UID (for Firestore document ID)
    var userID: String? {
        return currentUser?.uid
    }
}

enum AuthError: LocalizedError {
    case missingVerificationID
    
    var errorDescription: String? {
        switch self {
        case .missingVerificationID:
            return "Verification ID is missing. Please request a new code."
        }
    }
}
