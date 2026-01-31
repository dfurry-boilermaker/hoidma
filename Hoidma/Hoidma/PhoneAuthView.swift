import SwiftUI

struct PhoneAuthView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var phoneNumber: String = ""
    @State private var verificationCode: String = ""
    @State private var isVerificationStep = false
    @State private var showError = false
    @FocusState private var isPhoneFocused: Bool
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
                    // Phone number entry
                    phoneNumberView
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
    
    private var phoneNumberView: some View {
        VStack(spacing: 20) {
            Text("Sign in with your phone number")
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
            
            Text("We'll send you a verification code")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Phone Number")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("+")
                        .foregroundColor(.secondary)
                    
                    TextField("1234567890", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($isPhoneFocused)
                        .font(.system(size: 18))
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
            }
            
            Button {
                Task {
                    await sendCode()
                }
            } label: {
                if authManager.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Send Code")
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(phoneNumber.isEmpty ? Color.gray : AppColors.positive)
            .foregroundColor(.white)
            .cornerRadius(12)
            .disabled(phoneNumber.isEmpty || authManager.isLoading)
            
            // Show warning if testing on simulator
            #if targetEnvironment(simulator)
            Text("⚠️ Phone Auth requires a real device. APNs doesn't work on simulator.")
                .font(.system(size: 12))
                .foregroundColor(.orange)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            #endif
        }
    }
    
    private var verificationCodeView: some View {
        VStack(spacing: 20) {
            Text("Enter verification code")
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
            
            Text("We sent a code to \(phoneNumber)")
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
                if authManager.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Verify")
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(verificationCode.isEmpty ? Color.gray : AppColors.positive)
            .foregroundColor(.white)
            .cornerRadius(12)
            .disabled(verificationCode.isEmpty || authManager.isLoading)
            
            Button {
                isVerificationStep = false
                verificationCode = ""
            } label: {
                Text("Change phone number")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        }
    }
    
    private func sendCode() async {
        isPhoneFocused = false
        do {
            try await authManager.sendVerificationCode(to: phoneNumber)
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

#Preview("Phone Number Entry") {
    PhoneAuthView()
        .environmentObject(AuthManager())
}

#Preview("Verification Code Entry") {
    struct VerificationPreview: View {
        @StateObject private var authManager = AuthManager()
        @State private var phoneNumber = "+1234567890"
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
                        
                        Text("We sent a code to \(phoneNumber)")
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
                            Text("Verify")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(verificationCode.isEmpty ? Color.gray : AppColors.positive)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .disabled(verificationCode.isEmpty)
                        
                        Button {
                            // Preview action
                        } label: {
                            Text("Change phone number")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                        }
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
