import SwiftUI

struct RemoveStockModal: View {
    @ObservedObject var viewModel: StockViewModel
    @Binding var showingModal: Bool
    let ticker: String
    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool { colorScheme == .dark }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    showingModal = false
                }
            
            VStack(spacing: 0) {
                Text("Remove Stock")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color.primary)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                
                Text("Are you sure you want to remove \(ticker) from your portfolio?")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                
                VStack(spacing: 12) {
                    Button {
                        viewModel.removeStock(ticker: ticker)
                        showingModal = false
                    } label: {
                        Text("Remove")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.red)
                            .cornerRadius(12)
                    }
                    
                    Button {
                        showingModal = false
                    } label: {
                        Image("cancel")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.gray.opacity(isDarkMode ? 0.3 : 0.2))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Color(UIColor.systemBackground))
            .cornerRadius(16)
            .padding(.horizontal, 20)
        }
    }
}

