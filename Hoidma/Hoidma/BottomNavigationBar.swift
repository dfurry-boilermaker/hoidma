import SwiftUI

struct BottomNavigationBar: View {
    @Binding var selectedTab: Int
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    var onTabSelected: ((Int) -> Void)?
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...4, id: \.self) { tabNumber in
                Button {
                    selectedTab = tabNumber
                    onTabSelected?(tabNumber)
                } label: {
                    Text("\(tabNumber)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(selectedTab == tabNumber ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                
                if tabNumber < 4 {
                    Divider()
                        .frame(height: 24)
                }
            }
        }
        .background(Color(UIColor.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.gray.opacity(0.3)),
            alignment: .top
        )
    }
}

