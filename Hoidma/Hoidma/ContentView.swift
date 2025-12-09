import SwiftUI
import UIKit

struct ContentView: View {
    // The main view model manages the state and logic
    @StateObject private var viewModel = StockViewModel()
    @State private var showingCommitForm = false
    @State private var showingModal = false
    @State private var selectedTicker: String? = nil
    
    var body: some View {
        NavigationStack {
            ZStack {
                // White background
                Color.white
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Minimal header
                        HStack(spacing: 6) {
                            // Dog logo - use system image as fallback for preview
                            if UIImage(named: "dave.folly") != nil {
                                Image("dave.folly")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                            } else {
                                Image(systemName: "photo")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                            }
                            
                            // Hoidma text logo - use text as fallback for preview
                            if UIImage(named: "HOiDMA") != nil {
                                Image("HOiDMA")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 40)
                            } else {
                                Text("HOiDMA")
                                    .font(.system(size: 24, weight: .bold))
                                    .frame(height: 40)
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 20)
                        
                        if showingCommitForm {
                            AddStockFormView(viewModel: viewModel, isPresented: $showingCommitForm)
                        } else if !viewModel.stocks.isEmpty {
                            PortfolioView(viewModel: viewModel, showingModal: $showingModal, showingCommitForm: $showingCommitForm, selectedTicker: $selectedTicker)
                        } else {
                            InitialView(showingCommitForm: $showingCommitForm)
                        }
                    }
                }

                // Remove Stock Modal
                if showingModal, let ticker = selectedTicker {
                    RemoveStockModal(viewModel: viewModel, showingModal: $showingModal, ticker: ticker)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .onAppear {
            // Prevent preview from making network calls
            UserDefaults.standard.removeObject(forKey: "committedStocks")
        }
}
