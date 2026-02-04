import SwiftUI
import LocalAuthentication

/// Lock screen that requires biometric authentication
struct LockScreenView: View {
    @ObservedObject var biometricAuth: BiometricAuthManager
    @EnvironmentObject var authManager: SupabaseAuthManager
    @Environment(\.colorScheme) private var colorScheme

    // Email verification state
    @State private var showEmailVerification = false
    @State private var verificationCode = ""
    @State private var isSendingCode = false
    @State private var isVerifyingCode = false
    @State private var codeSent = false
    @State private var emailError: String?

    private var isDarkMode: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            if showEmailVerification {
                emailVerificationView
            } else {
                biometricView
            }
        }
        .onAppear {
            // Automatically trigger authentication when view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !biometricAuth.isUnlocked && !showEmailVerification {
                    biometricAuth.authenticate()
                }
            }
        }
    }

    // MARK: - Biometric View

    private var biometricView: some View {
        VStack(spacing: 32) {
            Spacer()

            // App logo
            Image(isDarkMode ? "hoidma.dark" : "hoidma")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 60)

            // Lock icon
            Image(systemName: biometricAuth.biometricType == .faceID ? "faceid" : "touchid")
                .font(.system(size: 64))
                .foregroundColor(Color.primary.opacity(0.6))
                .padding(.top, 20)

            // Status text
            VStack(spacing: 8) {
                Text("Unlock with \(biometricAuth.biometricTypeName)")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.primary)

                if let error = biometricAuth.authError {
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }

            Spacer()

            VStack(spacing: 16) {
                // Unlock button
                Button {
                    biometricAuth.authenticate()
                } label: {
                    HStack(spacing: 12) {
                        if biometricAuth.isAuthenticating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: biometricAuth.biometricType == .faceID ? "faceid" : "touchid")
                        }
                        Text(biometricAuth.isAuthenticating ? "Authenticating..." : "Tap to Unlock")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        Image("GradientBackground")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    )
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(biometricAuth.isAuthenticating)

                // Email verification fallback - show after failed attempts
                if biometricAuth.hasAttemptedAuth && biometricAuth.authError != nil {
                    Button {
                        showEmailVerification = true
                        codeSent = false
                        verificationCode = ""
                        emailError = nil
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "envelope")
                            Text("Use Email Instead")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.primary.opacity(0.7))
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }

    // MARK: - Email Verification View

    private var emailVerificationView: some View {
        VStack(spacing: 24) {
            // Back button
            HStack {
                Button {
                    showEmailVerification = false
                    codeSent = false
                    verificationCode = ""
                    emailError = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.system(size: 16))
                    .foregroundColor(Color.primary.opacity(0.7))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Spacer()

            // Email icon
            Image(systemName: "envelope.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(Color.primary.opacity(0.6))

            Text("Unlock with Email")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Color.primary)

            if let email = authManager.email {
                Text("We'll send a verification code to\n\(email)")
                    .font(.system(size: 14))
                    .foregroundColor(Color.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Verify your identity to unlock")
                    .font(.system(size: 14))
                    .foregroundColor(Color.secondary)
                    .multilineTextAlignment(.center)
            }

            if codeSent {
                // Code input
                VStack(spacing: 16) {
                    TextField("Enter 8-digit code", text: $verificationCode)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 24, weight: .medium, design: .monospaced))
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal, 40)
                        .onChange(of: verificationCode) { _, newValue in
                            // Limit to 8 digits
                            if newValue.count > 8 {
                                verificationCode = String(newValue.prefix(8))
                            }
                        }

                    if let error = emailError {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }

                    Button {
                        verifyEmailCode()
                    } label: {
                        HStack {
                            if isVerifyingCode {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Verify Code")
                            }
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(verificationCode.count == 8 ? Color.primary : Color.gray)
                        .cornerRadius(12)
                    }
                    .disabled(verificationCode.count != 8 || isVerifyingCode)
                    .padding(.horizontal, 40)

                    // Resend option
                    Button {
                        sendEmailCode()
                    } label: {
                        Text("Resend Code")
                            .font(.system(size: 14))
                            .foregroundColor(Color.primary.opacity(0.7))
                    }
                    .disabled(isSendingCode)
                }
            } else {
                // Send code button
                VStack(spacing: 16) {
                    if let error = emailError {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }

                    Button {
                        sendEmailCode()
                    } label: {
                        HStack {
                            if isSendingCode {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "paperplane.fill")
                                Text("Send Code")
                            }
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.primary)
                        .cornerRadius(12)
                    }
                    .disabled(isSendingCode || authManager.email == nil)
                    .padding(.horizontal, 40)
                }
            }

            Spacer()
            Spacer()
        }
    }

    // MARK: - Actions

    private func sendEmailCode() {
        guard let email = authManager.email else {
            emailError = "No email found. Please sign out and sign in again."
            return
        }

        isSendingCode = true
        emailError = nil

        Task {
            do {
                try await authManager.sendVerificationCode(to: email)
                await MainActor.run {
                    isSendingCode = false
                    codeSent = true
                }
            } catch {
                await MainActor.run {
                    isSendingCode = false
                    emailError = "Failed to send code. Please try again."
                }
            }
        }
    }

    private func verifyEmailCode() {
        isVerifyingCode = true
        emailError = nil

        Task {
            do {
                try await authManager.verifyCode(verificationCode)
                // Verification successful - unlock the app
                await MainActor.run {
                    isVerifyingCode = false
                    biometricAuth.isUnlocked = true
                    showEmailVerification = false
                }
            } catch {
                await MainActor.run {
                    isVerifyingCode = false
                    if let rateLimitMsg = authManager.rateLimitMessage {
                        emailError = rateLimitMsg
                    } else {
                        emailError = authManager.errorMessage ?? "Invalid code. Please try again."
                    }
                }
            }
        }
    }
}

#Preview {
    LockScreenView(biometricAuth: BiometricAuthManager())
        .environmentObject(SupabaseAuthManager())
}
