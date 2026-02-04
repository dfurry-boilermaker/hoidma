import SwiftUI

struct EmailAuthView: View {
    @EnvironmentObject var authManager: SupabaseAuthManager
    @State private var email: String = ""
    @State private var verificationCode: String = ""
    @State private var isVerificationStep = false
    @State private var showError = false
    @FocusState private var isEmailFocused: Bool
    @FocusState private var isCodeFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            // Background
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Logo
                Image(isDarkMode ? "hoidma.dark" : "hoidma")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 80)
                    .padding(.bottom, 20)

                if !isVerificationStep {
                    // Email entry
                    emailEntryView
                } else {
                    // Verification code entry
                    verificationCodeView
                }

                Spacer()
            }
            .padding(.horizontal, 32)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(authManager.errorMessage ?? "An unknown error occurred")
        }
        .onChange(of: authManager.errorMessage) { oldValue, newValue in
            showError = newValue != nil
        }
    }

    private var emailEntryView: some View {
        VStack(spacing: 20) {
            Text("Welcome to Hoidma")
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)

            Text("Sign in or create an account\nWe'll send you a verification code")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Text("Email Address")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("you@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .focused($isEmailFocused)
                    .font(.system(size: 18))
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
            }

            Button {
                Task {
                    await sendCode()
                }
            } label: {
                HStack {
                    Spacer()
                    if authManager.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Send Code")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    Spacer()
                }
                .frame(height: 56)
                .background(
                    Group {
                        if isValidEmail {
                            Image("GradientBackground")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Color.gray
                        }
                    }
                )
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(!isValidEmail || authManager.isLoading)
        }
    }

    private var verificationCodeView: some View {
        VStack(spacing: 20) {
            Text("Enter verification code")
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)

            Text("We sent a code to \(email)")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Text("Verification Code")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("12345678", text: $verificationCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($isCodeFocused)
                    .font(.system(size: 18))
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    .onChange(of: verificationCode) { _, newValue in
                        // Limit to 8 digits
                        if newValue.count > 8 {
                            verificationCode = String(newValue.prefix(8))
                        }
                    }
            }

            Button {
                Task {
                    await verifyCode()
                }
            } label: {
                HStack {
                    Spacer()
                    if authManager.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Verify")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    Spacer()
                }
                .frame(height: 56)
                .background(
                    Group {
                        if verificationCode.isEmpty {
                            Color.gray
                        } else {
                            Image("GradientBackground")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                    }
                )
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(verificationCode.isEmpty || authManager.isLoading)

            HStack(spacing: 24) {
                Button {
                    Task {
                        await sendCode()
                    }
                } label: {
                    Text("Resend Code")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(authManager.isLoading)

                Button {
                    isVerificationStep = false
                    verificationCode = ""
                } label: {
                    Text("Change Email")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)

            // Rate limit message
            if let rateLimitMsg = authManager.rateLimitMessage {
                Text(rateLimitMsg)
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Email Validation

    /// SECURITY FIX: Improved email validation
    /// - RFC 5322 compliant pattern
    /// - Length validation (max 254 characters per RFC 5321)
    /// - Local part max 64 characters
    private var isValidEmail: Bool {
        let normalizedEmail = normalizeEmail(email)

        // Check length limits per RFC 5321
        guard normalizedEmail.count <= 254 else { return false }

        // Check local part length (before @)
        if let atIndex = normalizedEmail.firstIndex(of: "@") {
            let localPart = normalizedEmail[..<atIndex]
            guard localPart.count <= 64 else { return false }
        }

        // RFC 5322 compliant regex pattern (simplified but robust)
        // Allows: letters, numbers, dots, hyphens, underscores, plus signs in local part
        // Domain must have at least one dot, TLD must be 2-63 characters
        let emailRegex = #"^[A-Za-z0-9]([A-Za-z0-9._%+\-]*[A-Za-z0-9])?@[A-Za-z0-9]([A-Za-z0-9\-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9\-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,63}$"#

        guard normalizedEmail.range(of: emailRegex, options: .regularExpression) != nil else {
            return false
        }

        // Additional checks for edge cases
        // No consecutive dots
        guard !normalizedEmail.contains("..") else { return false }

        // No dot at start of local part or right after @
        guard !normalizedEmail.hasPrefix(".") else { return false }
        if let atIndex = normalizedEmail.firstIndex(of: "@") {
            let afterAt = normalizedEmail.index(after: atIndex)
            if afterAt < normalizedEmail.endIndex && normalizedEmail[afterAt] == "." {
                return false
            }
        }

        return true
    }

    /// Normalize email address
    /// - Trims whitespace
    /// - Converts to lowercase
    private func normalizeEmail(_ email: String) -> String {
        return email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func sendCode() async {
        isEmailFocused = false
        do {
            // SECURITY: Use normalized email
            let normalizedEmail = normalizeEmail(email)
            try await authManager.sendVerificationCode(to: normalizedEmail)
            withAnimation {
                isVerificationStep = true
            }
        } catch {
            // Error is handled by authManager and shown in alert
        }
    }

    private func verifyCode() async {
        isCodeFocused = false
        do {
            try await authManager.verifyCode(verificationCode)
            // Authentication successful - app will automatically navigate
        } catch {
            // Error is handled by authManager and shown in alert
        }
    }
}

#Preview("Email Entry") {
    EmailAuthView()
        .environmentObject(SupabaseAuthManager())
}

#Preview("Verification Code Entry") {
    struct VerificationPreview: View {
        @StateObject private var authManager = SupabaseAuthManager()
        @State private var email = "test@example.com"
        @State private var verificationCode = ""
        @State private var isVerificationStep = true

        var body: some View {
            ZStack {
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    Image("hoidma")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 80)
                        .padding(.bottom, 20)

                    VStack(spacing: 20) {
                        Text("Enter verification code")
                            .font(.system(size: 24, weight: .bold))
                            .multilineTextAlignment(.center)

                        Text("We sent a code to \(email)")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Verification Code")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)

                            TextField("12345678", text: $verificationCode)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .font(.system(size: 18))
                                .padding()
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(12)
                        }

                        Button {
                            // Preview action
                        } label: {
                            HStack {
                                Spacer()
                                Text("Verify")
                                    .font(.system(size: 18, weight: .semibold))
                                Spacer()
                            }
                            .frame(height: 56)
                            .background(
                                Group {
                                    if verificationCode.isEmpty {
                                        Color.gray
                                    } else {
                                        Image("GradientBackground")
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    }
                                }
                            )
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .disabled(verificationCode.isEmpty)

                        Button {
                            // Preview action
                        } label: {
                            Text("Change email address")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }

                    Spacer()
                }
                .padding(.horizontal, 32)
            }
        }
    }

    return VerificationPreview()
}
