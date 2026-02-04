import SwiftUI
import PhotosUI
import Combine
import UIKit

// MARK: - Profile Image Manager
class ProfileImageManager: ObservableObject {
    @Published var profileImage: UIImage?

    private let fileName = "profile_image.jpg"

    init() {
        loadImage()
    }

    private var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName)
    }

    func saveImage(_ image: UIImage) {
        guard let fileURL = fileURL,
              let data = image.jpegData(compressionQuality: 0.8) else { return }

        do {
            try data.write(to: fileURL)
            DispatchQueue.main.async {
                self.profileImage = image
            }
            AppLogger.debug("Profile image saved")
        } catch {
            AppLogger.error("Error saving profile image: \(error.localizedDescription)")
        }
    }

    func loadImage() {
        guard let fileURL = fileURL,
              FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return
        }
        self.profileImage = image
        AppLogger.debug("Profile image loaded")
    }

    func deleteImage() {
        guard let fileURL = fileURL else { return }

        do {
            try FileManager.default.removeItem(at: fileURL)
            DispatchQueue.main.async {
                self.profileImage = nil
            }
            AppLogger.debug("Profile image deleted")
        } catch {
            AppLogger.error("Error deleting profile image: \(error.localizedDescription)")
        }
    }
}

// Appearance mode enum for light/dark/auto setting
enum AppearanceMode: Int {
    case light = 0
    case dark = 1
    case auto = 2

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .auto: return "Auto"
        }
    }

    var icon: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .auto: return "circle.lefthalf.filled"
        }
    }
}

struct ProfileView: View {
    @Binding var selectedTab: Int
    @AppStorage("appearanceMode") private var appearanceMode: Int = AppearanceMode.auto.rawValue
    @EnvironmentObject var authManager: SupabaseAuthManager
    @EnvironmentObject var biometricAuth: BiometricAuthManager
    // TODO: Profile photo upload - commented out for now
    // @StateObject private var imageManager = ProfileImageManager()
    // @State private var selectedPhotoItem: PhotosPickerItem?
    // @State private var showingImageOptions = false

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        // Spacer for fixed header
                        Spacer()
                            .frame(height: 90)

                        // Profile content
                        VStack(spacing: 24) {
                            // User info section
                            VStack(spacing: 12) {
                                // TODO: Profile photo upload - commented out for now
                                /*
                                Button {
                                    showingImageOptions = true
                                } label: {
                                    if let profileImage = imageManager.profileImage {
                                        Image(uiImage: profileImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 100, height: 100)
                                            .clipShape(Circle())
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                                            )
                                    } else {
                                        Image(systemName: "person.circle.fill")
                                            .font(.system(size: 80))
                                            .foregroundColor(Color.gray.opacity(0.5))
                                    }
                                }
                                .confirmationDialog("Profile Photo", isPresented: $showingImageOptions, titleVisibility: .visible) {
                                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                        Text("Choose Photo")
                                    }
                                    if imageManager.profileImage != nil {
                                        Button("Remove Photo", role: .destructive) {
                                            imageManager.deleteImage()
                                        }
                                    }
                                    Button("Cancel", role: .cancel) { }
                                }
                                */

                                // Email
                                if let email = authManager.email {
                                    Text(email)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(Color.primary)
                                }

                                // TODO: Uncomment when photo upload is working
                                // Text("Tap photo to change")
                                //     .font(.system(size: 11, weight: .regular))
                                //     .foregroundColor(Color.secondary)
                            }
                            .padding(.top, 20)
                            .padding(.bottom, 30)
                            // TODO: Profile photo upload - commented out for now
                            /*
                            .onChange(of: selectedPhotoItem) { _, newItem in
                                Task {
                                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                                       let image = UIImage(data: data) {
                                        imageManager.saveImage(image)
                                    }
                                    selectedPhotoItem = nil
                                }
                            }
                            */

                            // Settings section
                            VStack(spacing: 0) {
                                // Appearance mode picker
                                AppearancePickerRow(selectedMode: $appearanceMode)

                                // Hint about dog toggle
                                Text("Tip: Tap the dog in the header to cycle through appearance modes")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(Color.secondary)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 12)

                                Divider()
                                    .padding(.leading, 50)

                                // Biometric toggle (if available)
                                if biometricAuth.canUseBiometrics {
                                    SettingsRow(
                                        icon: biometricAuth.biometricTypeName == "Face ID" ? "faceid" : "touchid",
                                        title: biometricAuth.biometricTypeName,
                                        showToggle: true,
                                        isOn: Binding(
                                            get: { biometricAuth.biometricAuthEnabled },
                                            set: { biometricAuth.biometricAuthEnabled = $0 }
                                        )
                                    )

                                    Divider()
                                        .padding(.leading, 50)
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                            .padding(.horizontal, 20)

                            // Feedback section
                            VStack(spacing: 0) {
                                Button {
                                    openFeatureSuggestionEmail()
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: "lightbulb")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(Color.primary)
                                            .frame(width: 24)

                                        Text("Suggest a Feature")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(Color.primary)

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(Color.secondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                            .padding(.horizontal, 20)
                            .padding(.top, 10)

                            // About Hoidma section
                            VStack(spacing: 8) {
                                HStack(spacing: 14) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(Color.primary)
                                        .frame(width: 24)

                                    Text("About Hoidma")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(Color.primary)

                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 14)

                                Text("\"Hoidma\" (Estonian) To hold, to take care of - reflecting our mission to hold investments and develop conviction through deep due diligence.")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(Color.secondary)
                                    .multilineTextAlignment(.leading)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 14)
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                            .padding(.horizontal, 20)
                            .padding(.top, 10)

                            // Sign Out button
                            Button {
                                Task {
                                    do {
                                        try await authManager.signOut()
                                    } catch {
                                        AppLogger.error("Error signing out: \(error.localizedDescription)")
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.system(size: 16, weight: .medium))
                                    Text("Sign Out")
                                        .font(.system(size: 16, weight: .medium))
                                }
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.gray.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 10)

                            Spacer()
                        }
                    }
                }
            }
        }
        .gesture(
            DragGesture()
                .onEnded { gesture in
                    // Swipe right to go to accounts page (tab 4)
                    if gesture.translation.width > 100 {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedTab = 4
                        }
                    }
                }
        )
    }

    private func openFeatureSuggestionEmail() {
        let email = "danielfurry22@gmail.com"
        let subject = "Hoidma Feature Suggestion"
        let body = "Hi,\n\nI have a feature suggestion for Hoidma:\n\n"

        let subjectEncoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let bodyEncoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        if let url = URL(string: "mailto:\(email)?subject=\(subjectEncoded)&body=\(bodyEncoded)") {
            UIApplication.shared.open(url)
        }
    }
}

// Settings row component
struct SettingsRow: View {
    let icon: String
    let title: String
    var showToggle: Bool = false
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(Color.primary)
                .frame(width: 24)

            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color.primary)

            Spacer()

            if showToggle {
                Toggle("", isOn: $isOn)
                    .labelsHidden()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// Appearance picker row component
struct AppearancePickerRow: View {
    @Binding var selectedMode: Int

    private var currentMode: AppearanceMode {
        AppearanceMode(rawValue: selectedMode) ?? .auto
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: currentMode.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Color.primary)
                    .frame(width: 24)

                Text("Appearance")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.primary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            // Segmented picker
            HStack(spacing: 8) {
                ForEach([AppearanceMode.light, AppearanceMode.dark, AppearanceMode.auto], id: \.rawValue) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedMode = mode.rawValue
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 14, weight: .medium))
                            Text(mode.displayName)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(selectedMode == mode.rawValue ? Color.white : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedMode == mode.rawValue ? Color.blue : Color.clear)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }
}

#Preview("Profile View") {
    struct PreviewWrapper: View {
        @State private var selectedTab = 5

        var body: some View {
            ProfileView(selectedTab: $selectedTab)
                .environmentObject(SupabaseAuthManager())
                .environmentObject(BiometricAuthManager())
        }
    }
    return PreviewWrapper()
}
