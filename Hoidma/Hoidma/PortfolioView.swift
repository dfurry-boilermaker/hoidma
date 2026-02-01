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
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    
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
                        VStack(spacing: 12) {
                            HStack {
                                Text(viewModel.totalPortfolioValue, format: .currency(code: "USD"))
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(Color.primary)
                                Spacer()
                            }
                            
                            // Gains section with add button on the right
                            HStack(alignment: .top, spacing: 0) {
                                // Returns section - grouped together with consistent spacing
                                VStack(spacing: 0) {
                                    // Day gain display
                                    HStack(spacing: 4) {
                                        Text(dayReturn.value >= 0 ? "+" : "")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(AppColors.forValue(dayReturn.value))
                                        Text(dayReturn.value, format: .currency(code: "USD"))
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(AppColors.forValue(dayReturn.value))

                                        Text("(\(dayReturn.percent >= 0 ? "+" : "")\(String(format: "%.2f", dayReturn.percent))%)")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(AppColors.forValue(dayReturn.value))

                                        Text("1D")
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(Color.secondary)

                                        Spacer()
                                    }

                                    // Total gain display
                                    HStack(spacing: 4) {
                                        Text(totalReturn.value >= 0 ? "+" : "")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(AppColors.forValue(totalReturn.value))
                                        Text(totalReturn.value, format: .currency(code: "USD"))
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(AppColors.forValue(totalReturn.value))

                                        Text("(\(totalReturn.percent >= 0 ? "+" : "")\(String(format: "%.2f", totalReturn.percent))%)")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(AppColors.forValue(totalReturn.value))
                                        
                                        Text("All")
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(Color.secondary)
                                        
                                        Spacer()
                                    }
                                    .padding(.top, 2)
                                }
                                
                                Spacer()
                                
                                // Add button - same height as both return lines combined
                                if sortedStocks.count > 0 {
                                    Button {
                                        showingCommitForm = true
                                    } label: {
                                        Image(isDarkMode ? "add.button.dark" : "add.button")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 65, height: 40)
                                    }
                                }
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
                                                        RoundedRectangle(cornerRadius: 6)
                                                            .fill(colorForTicker(stock.ticker))
                                                            .frame(width: max(geometry.size.width * portfolioPercentage, 0), height: 3)
                                                    }
                                                }
                                            }
                                        }
                                        .frame(maxWidth: geometry.size.width, alignment: .leading)
                                        .clipped()
                                    }
                                }
                            }
                            .frame(height: 3)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)

                        // Add stock button and message - only show if there are no positions with shares
                        if sortedStocks.count == 0 {
                            VStack() {
                                Text("Add positions below")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(Color.secondary)
                                
                                Button {
                                    showingCommitForm = true
                                } label: {
                                    Image(isDarkMode ? "add.button.dark" : "add.button")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 90, height: 90)
                                }
                            }
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

