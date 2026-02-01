import SwiftUI

struct EmailAuthView: View {
    @EnvironmentObject var authManager: SupabaseAuthManager
    @State private var email: String = ""
    @State private var verificationCode: String = ""
    @State private var isVerificationStep = false
    @State private var showError = false
    @FocusState private var isEmailFocused: Bool
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        ZStack {
            // Background
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Logo
                Image("hoidma")
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
            Text("Sign in with your email")
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)

            Text("We'll send you a verification code")
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
                .background(isValidEmail ? AppColors.positive : Color.gray)
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

                TextField("123456", text: $verificationCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($isCodeFocused)
                    .font(.system(size: 18))
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
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
                .background(verificationCode.isEmpty ? Color.gray : AppColors.positive)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(verificationCode.isEmpty || authManager.isLoading)

            Button {
                isVerificationStep = false
                verificationCode = ""
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
    }

    // MARK: - Helpers

    private var isValidEmail: Bool {
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: emailRegex, options: .regularExpression) != nil
    }

    private func sendCode() async {
        isEmailFocused = false
        do {
            try await authManager.sendVerificationCode(to: email)
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

                            TextField("123456", text: $verificationCode)
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
                            .background(verificationCode.isEmpty ? Color.gray : AppColors.positive)
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
