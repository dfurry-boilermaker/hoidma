import SwiftUI

struct StockDetailView: View {
    let stock: Stock
    let priceData: StockPriceData?
    @ObservedObject var viewModel: StockViewModel
    @Binding var navigationPath: NavigationPath
    @Environment(\.dismiss) var dismiss
    @State private var selectedPeriod: TimePeriod = .allTime
    @State private var showingAddLotForm: Bool = false
    @State private var selectedLotForSell: StockLot? = nil
    @State private var selectedLotForAdd: StockLot? = nil
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @AppStorage("selectedTab") private var selectedTab: Int = 1
    
    // Get the current stock from view model to reflect updates - cached to avoid repeated lookups
    @State private var cachedStock: Stock?

    private var currentStock: Stock {
        if let cached = cachedStock {
            return cached
        }
        let found = viewModel.stocks.first(where: { $0.ticker == stock.ticker }) ?? stock
        cachedStock = found
        return found
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 4) {
                        // Header with back button
                        HStack {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color.primary)
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 2)
                        .padding(.bottom, 20)
                        
                        // Company name and ticker
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(currentStock.companyName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color.primary)
                                    .multilineTextAlignment(.leading)
                                
                                HStack(spacing: 8) {
                                    if let priceData = priceData {
                                        Text(priceData.currentPrice, format: .currency(code: "USD"))
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(Color.primary)
                                    }
                                    
                                    Text(currentStock.ticker)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(Color.secondary)
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 0)
                        
                        // Position details card
                        VStack(spacing: 4) {

                            
                            VStack(spacing: 4) {
                                // Calculate aggregated values from all lots
                                let totalShares = currentStock.lots.isEmpty ? Double(currentStock.shares) : currentStock.lots.reduce(0.0) { $0 + $1.shares }
                                let totalCostFromLots = currentStock.lots.isEmpty ? currentStock.totalCost : currentStock.lots.reduce(0.0) { $0 + $1.totalCost }
                                let averagePurchasePrice = totalShares > 0 ? (currentStock.lots.isEmpty ? currentStock.purchasePrice : totalCostFromLots / Double(totalShares)) : currentStock.purchasePrice
                                
                                DetailRow(label: "Shares", value: formatShares(totalShares))
                                
                                if let priceData = priceData {
                                    DetailRow(label: "Purchase Price", value: averagePurchasePrice.formatted(.currency(code: "USD")))
                                    
                                    DetailRow(label: "Total Cost", value: totalCostFromLots.formatted(.currency(code: "USD")))

                                    let totalValue = priceData.currentPrice * Double(totalShares)
                                    DetailRow(label: "Total Value", value: totalValue.formatted(.currency(code: "USD")))
                                    
                                    let totalProfitLoss = totalValue - totalCostFromLots
                                    let profitLossPercent = totalCostFromLots > 0 ? (totalProfitLoss / totalCostFromLots) * 100 : 0
                                    let profitLossString = "\(totalProfitLoss >= 0 ? "+" : "")\(totalProfitLoss.formatted(.currency(code: "USD"))) (\(profitLossPercent >= 0 ? "+" : "")\(String(format: "%.2f", profitLossPercent))%)"
                                    DetailRow(label: "Profit/Loss", value: profitLossString, isProfitLoss: true)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                        
                        // Portfolio allocation section
                        if let priceData = priceData, viewModel.totalPortfolioValue > 0 {
                            let totalShares = currentStock.lots.isEmpty ? Double(currentStock.shares) : currentStock.lots.reduce(0.0) { $0 + $1.shares }
                            let stockValue = priceData.currentPrice * Double(totalShares)
                            let portfolioPercentage = (stockValue / viewModel.totalPortfolioValue) * 100
                            
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    // Background bar with neutral outline
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.clear)
                                        .frame(height: 3)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                    
                                    // Filled bar - more prominent (using same color as visualization page)
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(colorForTicker(currentStock.ticker))
                                        .frame(width: geometry.size.width * min(portfolioPercentage / 100, 1.0), height: 3)
                                    
                                    // Percentage text centered on the bar with background
                                    HStack {
                                        Spacer()
                                        Text("\(String(format: "%.1f", portfolioPercentage))%")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(Color.primary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color(UIColor.systemBackground).opacity(0.9))
                                            )
                                        Spacer()
                                    }
                                    .frame(height: 3)
                                }
                            }
                            .frame(height: 3)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 20)
                        }
                        
                        // Lots/Accounts section
                        VStack(spacing: 4) {
                            HStack {
                                Text("Lots by Account")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color.primary)
                                
                                Spacer()
                                
                                Button {
                                    showingAddLotForm = true
                                } label: {
                                    Image(isDarkMode ? "add.button.dark" : "add.button")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 60, height: 60)
                                }
                            } //.padding(.top, -8)
                            
                            if currentStock.lots.isEmpty {
                                VStack(spacing: 4) {
                                    Text("No lots defined. Add lots to track shares across different accounts (e.g., Indv, 401k, Roth IRA).")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(Color.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.vertical, 2)
                                }
                            } else {
                                VStack(spacing: 4) {
                                    ForEach(currentStock.lots) { lot in
                                        LotRow(
                                            lot: lot,
                                            currentPrice: priceData?.currentPrice ?? 0,
                                            onSell: { lotToSell in
                                                selectedLotForSell = lotToSell
                                            },
                                            onAddShares: { lotToAdd in
                                                selectedLotForAdd = lotToAdd
                                            }
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                        .sheet(isPresented: $showingAddLotForm) {
                            AddLotFormView(
                                stock: currentStock,
                                viewModel: viewModel,
                                isPresented: $showingAddLotForm
                            )
                        }
                        .sheet(item: $selectedLotForSell) { lot in
                            SellLotFormView(
                                lot: lot,
                                stock: currentStock,
                                viewModel: viewModel,
                                selectedLot: $selectedLotForSell
                            )
                            .presentationDetents([.large])
                            .presentationDragIndicator(.visible)
                        }
                        .sheet(item: $selectedLotForAdd) { lot in
                            AddSharesToLotFormView(
                                lot: lot,
                                stock: currentStock,
                                viewModel: viewModel,
                                selectedLot: $selectedLotForAdd
                            )
                            .presentationDetents([.large])
                            .presentationDragIndicator(.visible)
                        }
                    }
                }
                
                // Bottom navigation bar
                BottomNavigationBar(selectedTab: $selectedTab) { tabNumber in
                    // Navigation logic
                    if tabNumber == 1 {
                        // Navigate back to main page
                        dismiss()
                    } else if tabNumber == 2 {
                        // Navigate to portfolio visualizations view
                        navigationPath.append(NavigationDestination.portfolioVisualizations)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Refresh cached stock
            cachedStock = viewModel.stocks.first(where: { $0.ticker == stock.ticker }) ?? stock
            
            // Ensure price is initialized
            if viewModel.stockPrices[currentStock.ticker] == nil {
                viewModel.updatePrice(for: currentStock)
            }
        }
        .onChange(of: viewModel.stocks) {
            // Refresh cached stock when stocks change
            cachedStock = viewModel.stocks.first(where: { $0.ticker == stock.ticker }) ?? stock
        }
    }
}

// Helper function to format shares with commas
private func formatShares(_ shares: Double) -> String {
    let numberFormatter = NumberFormatter()
    numberFormatter.numberStyle = .decimal
    numberFormatter.groupingSeparator = ","
    numberFormatter.usesGroupingSeparator = true
    
    if shares.truncatingRemainder(dividingBy: 1) == 0 {
        // Whole number
        if let formatted = numberFormatter.string(from: NSNumber(value: Int(shares))) {
            return formatted
        }
        return "\(Int(shares))"
    } else {
        // Fractional shares - format whole part with commas, keep decimal
        let wholePart = Int(shares)
        let decimalPart = shares - Double(wholePart)
        if let formattedWhole = numberFormatter.string(from: NSNumber(value: wholePart)) {
            return "\(formattedWhole)\(String(format: "%.4f", decimalPart).dropFirst())"
        }
        return String(format: "%.4f", shares)
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var isProfitLoss: Bool = false
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.secondary)
            
            Spacer()
            
            if isProfitLoss {
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(value.hasPrefix("+") || !value.hasPrefix("-") ? AppColors.positive : Color.red)
            } else {
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.primary)
            }
        }
    }
}

struct LotRow: View {
    let lot: StockLot
    let currentPrice: Double
    let onSell: (StockLot) -> Void
    let onAddShares: (StockLot) -> Void
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(lot.accountName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.primary)
                Spacer()
                Text("\(formatShares(lot.shares)) shares")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.secondary)
            }
            
            HStack {
                Text("Purchase Price")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.secondary)
                Spacer()
                Text(lot.purchasePrice.formatted(.currency(code: "USD")))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.primary)
            }
            
            if currentPrice > 0 {
                let lotValue = currentPrice * lot.shares
                let lotCost = lot.totalCost
                let lotProfitLoss = lotValue - lotCost
                
                HStack {
                    Text("Current Value")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.secondary)
                    Spacer()
                    Text(lotValue.formatted(.currency(code: "USD")))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.primary)
                }
                
                HStack {
                    Text("Profit/Loss")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.secondary)
                    Spacer()
                    let profitLossPercent = lotCost > 0 ? (lotProfitLoss / lotCost) * 100 : 0
                    let profitLossString = "\((lotProfitLoss >= 0 ? "+" : ""))\(lotProfitLoss.formatted(.currency(code: "USD"))) (\(profitLossPercent >= 0 ? "+" : "")\(String(format: "%.2f", profitLossPercent))%)"
                    Text(profitLossString)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(lotProfitLoss >= 0 ? AppColors.positive : Color.red)
                }
            }
            
            // Action buttons
            HStack(spacing: 6) {
                Button {
                    onAddShares(lot)
                } label: {
                    Image(isDarkMode ? "buy.dark" : "buy")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: 10)
                        .padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AppColors.positive, lineWidth: 1)
                        )
                }
                
                Button {
                    onSell(lot)
                } label: {
                    Image(isDarkMode ? "sell.dark" : "sell")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: 10)
                        .padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.red, lineWidth: 1)
                        )
                }
            }
            .padding(.top, 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}


struct PeriodReturnRow: View {
    let period: TimePeriod
    let value: Double
    let percent: Double
    
    var body: some View {
        HStack {
            Text(period.rawValue)
                .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.secondary)
            
            Spacer()
            
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(value >= 0 ? "+" : "")
                    Text(value, format: .currency(code: "USD"))
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(value >= 0 ? AppColors.positive : Color.red)
                
                Text("(\(percent >= 0 ? "+" : "")\(String(format: "%.2f", percent))%)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(percent >= 0 ? AppColors.positive : Color.red)
            }
        }
    }
}

struct AddLotFormView: View {
    let stock: Stock
    @ObservedObject var viewModel: StockViewModel
    @Binding var isPresented: Bool
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    
    @State private var accountNameInput: String = ""
    @State private var priceInput: String = ""
    @State private var sharesInput: String = ""
    @State private var commitError: String? = nil
    @FocusState private var focusedField: Field?
    
    enum Field {
        case accountName, price, shares
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            ZStack {
                HStack {
                    Button {
                        isPresented = false
                    } label: {
                        Image("cancel")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                    }
                    
                    Spacer()
                }
                
                Text("Add Lot")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.primary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            // Form fields
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Account Name")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.secondary)
                    
                    TextField("Indv, 401k, Roth IRA, etc.", text: $accountNameInput)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.primary)
                        .focused($focusedField, equals: .accountName)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Purchase Price")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.secondary)
                    
                    HStack {
                        Text("$")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.secondary)
                        TextField("22.00", text: $priceInput)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.primary)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .price)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shares")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.secondary)
                    
                    TextField("9.0000", text: $sharesInput)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.primary)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .shares)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
                
                // Buy button below shares
                Button {
                    attemptCommit()
                } label: {
                    Image(isDarkMode ? "buy.dark" : "buy")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: 15)
                        .padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AppColors.positive, lineWidth: 1)
                        )
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            
            if let commitError = commitError {
                Text(commitError)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.red)
                    .padding(.top, 12)
            }
            
            Spacer()
        }
    }
    
    private func attemptCommit() {
        guard let priceValue = Double(priceInput), priceValue > 0,
              let sharesValue = Double(sharesInput), sharesValue > 0,
              !accountNameInput.isEmpty else {
            commitError = "Please enter valid numbers and an account name."
            return
        }
        
        let price = priceValue
        let shares = sharesValue
        
        let accountName = accountNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Add the lot using commitStock which will merge it with existing lots
        viewModel.commitStock(ticker: stock.ticker, price: price, shares: shares, accountName: accountName)
        isPresented = false
    }
}

struct SellLotFormView: View {
    let lot: StockLot
    let stock: Stock
    @ObservedObject var viewModel: StockViewModel
    @Binding var selectedLot: StockLot?
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    
    @State private var sharesToSellInput: String = ""
    @State private var commitError: String? = nil
    @FocusState private var focusedField: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            ZStack {
                HStack {
                    Button {
                        selectedLot = nil
                    } label: {
                        Image("cancel")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                    }
                    
                    Spacer()
                }
                
                Text("Sell Lot")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.primary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            // Lot info
            VStack(spacing: 12) {
                // Read-only fields - simple HStack format like portfolio view
                VStack(spacing: 8) {
                    HStack {
                        Text("Account")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.secondary)
                        
                        Spacer()
                        
                        Text(lot.accountName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.primary)
                    }
                    
                    HStack {
                        Text("Current Shares")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.secondary)
                        
                        Spacer()
                        
                        Text(lot.shares.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(lot.shares))" : "\(String(format: "%.4f", lot.shares))")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.primary)
                    }
                    
                    HStack {
                        Text("Current Purchase Price")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.secondary)
                        
                        Spacer()
                        
                        Text(lot.purchasePrice.formatted(.currency(code: "USD")))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.primary)
                    }
                }
                
                // Input field with border
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shares to Sell")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.secondary)
                    
                    TextField("0.0000", text: $sharesToSellInput)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.primary)
                        .keyboardType(.decimalPad)
                        .focused($focusedField)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
                
                // Sell button below input
                Button {
                    attemptSell()
                } label: {
                    Image(isDarkMode ? "sell.dark" : "sell")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                        .padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.red, lineWidth: 1)
                        )
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            
            if let commitError = commitError {
                Text(commitError)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.red)
                    .padding(.top, 12)
            }
            
            Spacer()
        }
    }
    
    private func attemptSell() {
        guard let sharesToSell = Double(sharesToSellInput), sharesToSell > 0 else {
            commitError = "Please enter a valid number of shares to sell."
            return
        }
        
        guard sharesToSell <= lot.shares else {
            commitError = "Cannot sell more shares than available (\(String(format: "%.4f", lot.shares)))."
            return
        }
        
        viewModel.sellLot(ticker: stock.ticker, lotId: lot.id, sharesToSell: sharesToSell)
        selectedLot = nil
    }
}

struct AddSharesToLotFormView: View {
    let lot: StockLot
    let stock: Stock
    @ObservedObject var viewModel: StockViewModel
    @Binding var selectedLot: StockLot?
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    
    @State private var sharesToAddInput: String = ""
    @State private var purchasePriceInput: String = ""
    @State private var commitError: String? = nil
    @FocusState private var focusedField: Field?
    
    enum Field {
        case shares, price
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            ZStack {
                HStack {
                    Button {
                        selectedLot = nil
                    } label: {
                        Image("cancel")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                    }
                    
                    Spacer()
                }
                
                Text("Add Shares")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.primary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            // Lot info
            VStack(spacing: 12) {
                // Read-only fields - simple HStack format like portfolio view
                VStack(spacing: 8) {
                    HStack {
                        Text("Account")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.secondary)
                        
                        Spacer()
                        
                        Text(lot.accountName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.primary)
                    }
                    
                    HStack {
                        Text("Current Shares")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.secondary)
                        
                        Spacer()
                        
                        Text(lot.shares.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(lot.shares))" : "\(String(format: "%.4f", lot.shares))")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.primary)
                    }
                    
                    HStack {
                        Text("Current Purchase Price")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.secondary)
                        
                        Spacer()
                        
                        Text(lot.purchasePrice.formatted(.currency(code: "USD")))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.primary)
                    }
                }
                
                // Input fields with borders
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shares to Add")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.secondary)
                    
                    TextField("0.0000", text: $sharesToAddInput)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.primary)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .shares)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Purchase Price")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.secondary)
                    
                    HStack {
                        Text("$")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.secondary)
                        TextField("0.00", text: $purchasePriceInput)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.primary)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .price)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
                
                // Buy button below purchase price
                Button {
                    attemptAdd()
                } label: {
                    Image(isDarkMode ? "buy.dark" : "buy")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                        .padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AppColors.positive, lineWidth: 1)
                        )
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            
            if let commitError = commitError {
                Text(commitError)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.red)
                    .padding(.top, 12)
            }
            
            Spacer()
        }
    }
    
    private func attemptAdd() {
        guard let sharesToAdd = Double(sharesToAddInput), sharesToAdd > 0 else {
            commitError = "Please enter a valid number of shares to add."
            return
        }
        
        guard let newPurchasePrice = Double(purchasePriceInput), newPurchasePrice > 0 else {
            commitError = "Please enter a valid purchase price."
            return
        }
        
        viewModel.addSharesToLot(ticker: stock.ticker, lotId: lot.id, sharesToAdd: sharesToAdd, newPurchasePrice: newPurchasePrice)
        selectedLot = nil
    }
}

