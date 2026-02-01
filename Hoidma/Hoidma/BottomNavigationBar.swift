import SwiftUI

struct BottomNavigationBar: View {
    @Binding var selectedTab: Int
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    var onTabSelected: ((Int) -> Void)?

    private let tabs: [(id: Int, lightIcon: String, darkIcon: String)] = [
        (1, "dog.house", "dog.house.dark"),
        (2, "visuals", "visuals.dark"),
        (3, "accounts", "accounts.dark")
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
                        iconName: isDarkMode ? tab.darkIcon : tab.lightIcon
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab.id
                        }
                        onTabSelected?(tab.id)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
        .background(
            Color(UIColor.systemBackground)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

/// Individual tab bar button
private struct TabBarButton: View {
    let isSelected: Bool
    let iconName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 20)
                    .opacity(isSelected ? 1.0 : 0.4)

                // Selection indicator
                Circle()
                    .fill(isSelected ? Color.primary : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
