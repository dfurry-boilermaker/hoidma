import SwiftUI
import LocalAuthentication

/// Lock screen that requires biometric authentication
struct LockScreenView: View {
    @ObservedObject var biometricAuth: BiometricAuthManager
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

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
                    .background(Color.primary)
                    .cornerRadius(12)
                }
                .disabled(biometricAuth.isAuthenticating)
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            // Automatically trigger authentication when view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !biometricAuth.isUnlocked {
                    biometricAuth.authenticate()
                }
            }
        }
    }
}

#Preview {
    LockScreenView(biometricAuth: BiometricAuthManager())
}
