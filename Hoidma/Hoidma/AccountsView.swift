import SwiftUI

/// Data structure representing an account summary
struct AccountSummary: Identifiable {
    let id = UUID()
    let accountName: String
    var totalValue: Double
    var totalCost: Double
    var positions: [(ticker: String, companyName: String, shares: Double, value: Double, cost: Double, color: Color)]

    var profitLoss: Double {
        totalValue - totalCost
    }

    var profitLossPercent: Double {
        totalCost > 0 ? (profitLoss / totalCost) * 100 : 0
    }
}

struct AccountsView: View {
    @ObservedObject var viewModel: StockViewModel
    @Binding var selectedTab: Int
    @Binding var navigationPath: NavigationPath
    @Binding var selectedAccountName: String?
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false

    /// Calculate account summaries from all stocks and their lots
    private var accountSummaries: [AccountSummary] {
        var accountsDict: [String: AccountSummary] = [:]

        for stock in viewModel.stocks where stock.isMaritalStatus {
            let currentPrice = viewModel.stockPrices[stock.ticker]?.currentPrice ?? stock.purchasePrice

            for lot in stock.lots {
                let lotValue = currentPrice * lot.shares
                let lotCost = lot.totalCost
                let position = (
                    ticker: stock.ticker,
                    companyName: stock.companyName,
                    shares: lot.shares,
                    value: lotValue,
                    cost: lotCost,
                    color: colorForTicker(stock.ticker)
                )

                if var existing = accountsDict[lot.accountName] {
                    existing.totalValue += lotValue
                    existing.totalCost += lotCost
                    existing.positions.append(position)
                    accountsDict[lot.accountName] = existing
                } else {
                    accountsDict[lot.accountName] = AccountSummary(
                        accountName: lot.accountName,
                        totalValue: lotValue,
                        totalCost: lotCost,
                        positions: [position]
                    )
                }
            }
        }

        // Sort accounts by total value (descending)
        return accountsDict.values.sorted { $0.totalValue > $1.totalValue }
    }

    /// Total value across all accounts
    private var totalAllAccounts: Double {
        accountSummaries.reduce(0) { $0 + $1.totalValue }
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        // Header - standardized across all pages
                        ZStack {
                            // Hoidma logo on the left
                            HStack {
                                Image(isDarkMode ? "hoidma.dark" : "hoidma")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 100, height: 50)
                                    .cornerRadius(8)
                                Spacer()
                            }

                            // Dave folly logo in center (dark mode toggle)
                            Button {
                                withAnimation {
                                    isDarkMode.toggle()
                                }
                            } label: {
                                Image(isDarkMode ? "dave.folly.logo.dark" : "dave.folly.logo")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 50)
                            }
                        }
                        .padding(.top, 16)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                        .background(Color(UIColor.systemBackground))

                        if accountSummaries.isEmpty {
                            // Empty state
                            VStack(spacing: 16) {
                                Text("No accounts to display")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(Color.secondary)

                                Text("Add stock positions to see your accounts summary")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(Color.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(40)
                        } else {
                            // Account cards
                            VStack(spacing: 12) {
                                ForEach(accountSummaries) { account in
                                    AccountCard(
                                        account: account,
                                        totalAllAccounts: totalAllAccounts,
                                        viewModel: viewModel,
                                        navigationPath: $navigationPath,
                                        selectedAccountName: $selectedAccountName
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
        }
        .gesture(
            DragGesture()
                .onEnded { gesture in
                    // Swipe right to go to visualizations page (tab 2)
                    if gesture.translation.width > 100 {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedTab = 2
                        }
                    }
                }
        )
    }
}

/// Individual account card view
struct AccountCard: View {
    let account: AccountSummary
    let totalAllAccounts: Double
    @ObservedObject var viewModel: StockViewModel
    @Binding var navigationPath: NavigationPath
    @Binding var selectedAccountName: String?
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @State private var isExpanded: Bool = false

    private var accountPercentage: Double {
        totalAllAccounts > 0 ? (account.totalValue / totalAllAccounts) * 100 : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Account header (always visible)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                VStack(spacing: 6) {
                    HStack {
                        // Account name
                        Text(account.accountName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.primary)

                        Spacer()

                        // Account value
                        Text(account.totalValue, format: .currency(code: "USD"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.primary)
                    }

                    HStack {
                        // Profit/Loss
                        HStack(spacing: 2) {
                            Text(account.profitLoss >= 0 ? "+" : "")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppColors.forValue(account.profitLoss))

                            Text(account.profitLoss, format: .currency(code: "USD"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppColors.forValue(account.profitLoss))

                            Text("(\(account.profitLossPercent >= 0 ? "+" : "")\(String(format: "%.2f", account.profitLossPercent))%)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppColors.forValue(account.profitLoss))
                        }

                        Spacer()

                        // Percentage of total portfolio
                        Text("\(String(format: "%.1f", accountPercentage))% of portfolio")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(Color.secondary)

                        // Expand/collapse indicator
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.secondary)
                            .padding(.leading, 4)
                    }
                }
                .padding(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())

            // Expanded positions list
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(account.positions.sorted { $0.value > $1.value }.enumerated()), id: \.element.ticker) { index, position in
                        VStack(spacing: 0) {
                            Button {
                                // Find the stock and navigate to detail
                                if let stock = viewModel.stocks.first(where: { $0.ticker == position.ticker }) {
                                    navigationPath.append(NavigationDestination.stockDetail(stock))
                                }
                            } label: {
                                HStack {
                                    // Ticker color indicator
                                    Circle()
                                        .fill(position.color)
                                        .frame(width: 6, height: 6)

                                    // Ticker and company name
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(position.ticker)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(Color.primary)

                                        Text("\(String(format: "%.2f", position.shares)) shares")
                                            .font(.system(size: 10, weight: .regular))
                                            .foregroundColor(Color.secondary)
                                    }

                                    Spacer()

                                    // Position value and P/L
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(position.value, format: .currency(code: "USD"))
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(Color.primary)

                                        let positionPL = position.value - position.cost
                                        let positionPLPercent = position.cost > 0 ? (positionPL / position.cost) * 100 : 0

                                        Text("\(positionPL >= 0 ? "+" : "")\(String(format: "%.2f", positionPLPercent))%")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(AppColors.forValue(positionPL))
                                    }

                                    // Chevron indicator
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Color.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())

                            // Divider between positions
                            if index < account.positions.count - 1 {
                                Divider()
                                    .padding(.leading, 40)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .onAppear {
            // Auto-expand if this account was selected from visualizations page
            if selectedAccountName == account.accountName {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded = true
                }
                // Clear the selection after expanding
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    selectedAccountName = nil
                }
            }
        }
    }
}

#Preview("Accounts View") {
    struct PreviewWrapper: View {
        @State private var selectedTab = 3
        @State private var navigationPath = NavigationPath()
        @State private var selectedAccountName: String? = nil

        var body: some View {
            NavigationStack(path: $navigationPath) {
                AccountsView(viewModel: MockStockViewModel(), selectedTab: $selectedTab, navigationPath: $navigationPath, selectedAccountName: $selectedAccountName)
            }
        }
    }
    return PreviewWrapper()
}
