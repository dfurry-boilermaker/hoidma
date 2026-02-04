import SwiftUI

struct BottomNavigationBar: View {
    @Binding var selectedTab: Int
    @Environment(\.colorScheme) private var colorScheme
    var onTabSelected: ((Int) -> Void)?

    private var isDarkMode: Bool { colorScheme == .dark }

    // Tab order: Portfolio (1), Visuals (2), Charts (3), Accounts (4), Profile (5)
    private let tabs: [(id: Int, lightIcon: String, darkIcon: String, isSystemImage: Bool)] = [
        (1, "dog.house", "dog.house.dark", false),
        (2, "visuals", "visuals.dark", false),
        (3, "chart", "chart.dark", false),
        (4, "accounts", "accounts.dark", false),
        (5, "profile", "profile.dark", false)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Top border
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 0.5)

            // Tab bar content
            HStack(spacing: 0) {
                ForEach(tabs, id: \.id) { tab in
                    TabBarButton(
                        isSelected: selectedTab == tab.id,
                        iconName: isDarkMode ? tab.darkIcon : tab.lightIcon,
                        isSystemImage: tab.isSystemImage
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab.id
                        }
                        onTabSelected?(tab.id)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 4)
        }
        .background(.ultraThinMaterial)
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: -4)
        .ignoresSafeArea(edges: .bottom)
    }
}

/// Individual tab bar button
private struct TabBarButton: View {
    let isSelected: Bool
    let iconName: String
    let isSystemImage: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isSystemImage {
                    Image(systemName: iconName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 24)
                        .foregroundColor(.primary)
                } else {
                    Image(iconName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 26)
                }
            }
            .opacity(isSelected ? 1.0 : 0.4)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
