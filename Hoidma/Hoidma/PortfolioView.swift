import SwiftUI

struct PortfolioView: View {
    @ObservedObject var viewModel: StockViewModel
    @Binding var showingModal: Bool
    @Binding var showingCommitForm: Bool
    @Binding var selectedTicker: String?
    @Binding var navigationPath: NavigationPath
    @State private var selectedPeriod: TimePeriod = .daily
    @State private var stockToDelete: Stock? = nil
    @State private var showDeleteConfirmation: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool { colorScheme == .dark }
    
    var periodReturn: (value: Double, percent: Double) {
        viewModel.totalReturnForPeriod(selectedPeriod)
    }
    
    var dayReturn: (value: Double, percent: Double) {
        viewModel.totalReturnForPeriod(.daily)
    }
    
    var totalReturn: (value: Double, percent: Double) {
        viewModel.totalReturnForPeriod(.allTime)
    }
    
    // Computed property to get stocks sorted by total value (descending)
    var sortedStocks: [Stock] {
        viewModel.stocks
            .filter { $0.isMaritalStatus }
            .filter { stock in
                let totalShares = stock.lots.isEmpty ? Double(stock.shares) : stock.lots.reduce(0.0) { $0 + $1.shares }
                return totalShares > 0
            }
            .sorted { stock1, stock2 in
                let totalShares1 = stock1.lots.isEmpty ? Double(stock1.shares) : stock1.lots.reduce(0.0) { $0 + $1.shares }
                let totalShares2 = stock2.lots.isEmpty ? Double(stock2.shares) : stock2.lots.reduce(0.0) { $0 + $1.shares }
                
                let price1 = viewModel.stockPrices[stock1.ticker]?.currentPrice ?? 0.0
                let price2 = viewModel.stockPrices[stock2.ticker]?.currentPrice ?? 0.0
                
                let totalValue1 = price1 * totalShares1
                let totalValue2 = price2 * totalShares2
                
                return totalValue1 > totalValue2
            }
    }
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        // Portfolio summary card
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .lastTextBaseline, spacing: 8) {
                                Text(viewModel.totalPortfolioValue, format: .currency(code: "USD"))
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(Color.primary)
                                Text("Total")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(Color.secondary)
                                Spacer()
                            }

                            // Day gain display
                            HStack(spacing: 4) {
                                Text("\(dayReturn.value >= 0 ? "+" : "")\(dayReturn.value.formatted(.currency(code: "USD"))) (\(dayReturn.percent >= 0 ? "+" : "")\(String(format: "%.2f", dayReturn.percent))%)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AppColors.forValue(dayReturn.value))

                                Text("1D")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(Color.secondary)
                            }

                            // Total gain display
                            HStack(spacing: 4) {
                                Text("\(totalReturn.value >= 0 ? "+" : "")\(totalReturn.value.formatted(.currency(code: "USD"))) (\(totalReturn.percent >= 0 ? "+" : "")\(String(format: "%.2f", totalReturn.percent))%)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AppColors.forValue(totalReturn.value))

                                Text("All")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(Color.secondary)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                        
                        // Portfolio Diversity section - replaces divider
                        VStack(spacing: 12) {
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    // Background bar - only show when there are no positions
                                    if viewModel.totalPortfolioValue == 0 {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.gray.opacity(isDarkMode ? 0.3 : 0.15))
                                            .frame(height: 3)
                                    }

                                    // Multi-segment progress bar (only show if there are positions)
                                    if viewModel.totalPortfolioValue > 0 {
                                        HStack(spacing: 0) {
                                            ForEach(sortedStocks, id: \.ticker) { stock in
                                                if let priceData = viewModel.stockPrices[stock.ticker] {
                                                    let totalShares = stock.lots.isEmpty ? Double(stock.shares) : stock.lots.reduce(0.0) { $0 + $1.shares }
                                                    let stockValue = priceData.currentPrice * totalShares
                                                    let portfolioPercentage = min((stockValue / viewModel.totalPortfolioValue), 1.0)

                                                    if portfolioPercentage > 0 {
                                                        Rectangle()
                                                            .fill(colorForTicker(stock.ticker))
                                                            .frame(width: max(geometry.size.width * portfolioPercentage, 0), height: 3)
                                                    }
                                                }
                                            }
                                        }
                                        .frame(maxWidth: geometry.size.width, alignment: .leading)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                            }
                            .frame(height: 3)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)

                        // Empty state message - only show if there are no positions with shares
                        if sortedStocks.count == 0 {
                            Text("Tap add in the top right to add positions")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(Color.secondary)
                                .frame(maxWidth: .infinity)
                        }
                        
                        // Stock positions list
                        VStack(spacing: 0) {
                            ForEach(Array(sortedStocks.enumerated()), id: \.element.ticker) { index, stock in
                                VStack(spacing: 0) {
                                    NavigationLink(destination: StockDetailView(
                                        stock: stock,
                                        priceData: viewModel.stockPrices[stock.ticker],
                                        viewModel: viewModel,
                                        navigationPath: $navigationPath
                                    )) {
                                        StockPositionRow(
                                            stock: stock,
                                            priceData: viewModel.stockPrices[stock.ticker],
                                            totalPortfolioValue: viewModel.totalPortfolioValue,
                                            selectedPeriod: selectedPeriod,
                                            onRemove: {
                                                selectedTicker = stock.ticker
                                                showingModal = true
                                            }
                                        )
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            stockToDelete = stock
                                            showDeleteConfirmation = true
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .onAppear {
                                        // Ensure price is initialized
                                        if viewModel.stockPrices[stock.ticker] == nil {
                                            viewModel.updatePrice(for: stock)
                                        }
                                    }
                                    
                                    // Divider line between positions (except after last one)
                                    if index < sortedStocks.count - 1 {
                                        Divider()
                                            .padding(.leading, 20)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .alert("Delete Position", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                stockToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let stock = stockToDelete {
                    viewModel.removeStock(ticker: stock.ticker)
                }
                stockToDelete = nil
            }
        } message: {
            if let stock = stockToDelete {
                Text("Are you sure you want to delete \(stock.ticker) from all accounts? This cannot be undone.")
            }
        }
    }
}

