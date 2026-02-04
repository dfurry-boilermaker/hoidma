import SwiftUI

/// Position data within an account
struct AccountPosition: Hashable {
    let ticker: String
    let companyName: String
    let shares: Double
    let value: Double
    let cost: Double
    let dailyChange: Double
    let color: Color

    func hash(into hasher: inout Hasher) {
        hasher.combine(ticker)
        hasher.combine(shares)
        hasher.combine(value)
    }

    static func == (lhs: AccountPosition, rhs: AccountPosition) -> Bool {
        lhs.ticker == rhs.ticker && lhs.shares == rhs.shares && lhs.value == rhs.value
    }
}

/// Data structure representing an account summary
struct AccountSummary: Identifiable, Hashable {
    let id = UUID()
    let accountName: String
    var totalValue: Double
    var totalCost: Double
    var dailyGain: Double // Daily dollar gain/loss
    var dailyGainPercent: Double // Daily percentage gain/loss
    var positions: [AccountPosition]

    var profitLoss: Double {
        totalValue - totalCost
    }

    var profitLossPercent: Double {
        totalCost > 0 ? (profitLoss / totalCost) * 100 : 0
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AccountSummary, rhs: AccountSummary) -> Bool {
        lhs.id == rhs.id
    }
}

struct AccountsView: View {
    @ObservedObject var viewModel: StockViewModel
    @Binding var selectedTab: Int
    @Binding var navigationPath: NavigationPath
    @Binding var selectedAccountName: String?

    /// Calculate account summaries from all stocks and their lots
    private var accountSummaries: [AccountSummary] {
        var accountsDict: [String: AccountSummary] = [:]

        for stock in viewModel.stocks where stock.isMaritalStatus {
            let priceData = viewModel.stockPrices[stock.ticker]
            let currentPrice = priceData?.currentPrice ?? stock.purchasePrice

            // Get daily change percent from API data
            let dailyChangePercent = priceData?.apiPeriodChanges["1d"] ?? 0

            for lot in stock.lots {
                let lotValue = currentPrice * lot.shares
                let lotCost = lot.totalCost

                // Calculate daily gain for this lot
                let lotDailyGain = lotValue * (dailyChangePercent / (100 + dailyChangePercent))

                let position = AccountPosition(
                    ticker: stock.ticker,
                    companyName: stock.companyName,
                    shares: lot.shares,
                    value: lotValue,
                    cost: lotCost,
                    dailyChange: dailyChangePercent,
                    color: colorForTicker(stock.ticker)
                )

                if var existing = accountsDict[lot.accountName] {
                    existing.totalValue += lotValue
                    existing.totalCost += lotCost
                    existing.dailyGain += lotDailyGain
                    existing.positions.append(position)
                    accountsDict[lot.accountName] = existing
                } else {
                    accountsDict[lot.accountName] = AccountSummary(
                        accountName: lot.accountName,
                        totalValue: lotValue,
                        totalCost: lotCost,
                        dailyGain: lotDailyGain,
                        dailyGainPercent: 0, // Will be calculated after
                        positions: [position]
                    )
                }
            }
        }

        // Calculate daily gain percent for each account
        for (key, var account) in accountsDict {
            let previousValue = account.totalValue - account.dailyGain
            account.dailyGainPercent = previousValue > 0 ? (account.dailyGain / previousValue) * 100 : 0
            accountsDict[key] = account
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
                        // Spacer for fixed header
                        Spacer()
                            .frame(height: 78)

                        // Accounts header
                        HStack {
                            Text("Accounts")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(Color.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                        // Account distribution bar
                        if !accountSummaries.isEmpty && totalAllAccounts > 0 {
                            AccountDistributionBar(accounts: accountSummaries, totalValue: totalAllAccounts)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 16)
                        }

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
                            VStack(spacing: 0) {
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
                    // Swipe right to go to charts page (tab 3)
                    if gesture.translation.width > 100 {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedTab = 3
                        }
                    }
                    // Swipe left to go to profile page (tab 5)
                    else if gesture.translation.width < -100 {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedTab = 5
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

    // Rename account state
    @State private var isEditingName = false
    @State private var editedName = ""

    private var accountPercentage: Double {
        totalAllAccounts > 0 ? (account.totalValue / totalAllAccounts) * 100 : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                navigationPath.append(NavigationDestination.accountDetail(account))
            } label: {
                HStack(alignment: .top, spacing: 0) {
                    // Left side: Account name, position count and percentage
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.accountName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.primary)

                        // Position count
                        Text("\(account.positions.count) position\(account.positions.count == 1 ? "" : "s")")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(Color.secondary)

                        // Percentage of portfolio
                        Text("\(String(format: "%.1f", accountPercentage))% of portfolio")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(Color.secondary)
                    }

                    Spacer()

                    // Right side: Total value and gains (right-aligned)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(account.totalValue, format: .currency(code: "USD"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.primary)

                        // 1D gain/loss
                        HStack(spacing: 4) {
                            Text(account.dailyGain >= 0 ? "+" : "")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppColors.forValue(account.dailyGain))
                            Text(account.dailyGain, format: .currency(code: "USD"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppColors.forValue(account.dailyGain))
                            Text("(\(account.dailyGainPercent >= 0 ? "+" : "")\(String(format: "%.2f", account.dailyGainPercent))%)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppColors.forValue(account.dailyGain))
                            Text("1D")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(Color.secondary)
                        }

                        // All time gain/loss
                        HStack(spacing: 4) {
                            Text(account.profitLoss >= 0 ? "+" : "")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppColors.forValue(account.profitLoss))
                            Text(account.profitLoss, format: .currency(code: "USD"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppColors.forValue(account.profitLoss))
                            Text("(\(account.profitLossPercent >= 0 ? "+" : "")\(String(format: "%.2f", account.profitLossPercent))%)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppColors.forValue(account.profitLoss))
                            Text("All")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(Color.secondary)
                        }
                    }
                }
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .contextMenu {
                Button {
                    editedName = account.accountName
                    isEditingName = true
                } label: {
                    Label("Rename Account", systemImage: "pencil")
                }
            }

            Divider()
        }
        .onAppear {
            // Navigate to account detail if selected from visualizations page
            if selectedAccountName == account.accountName {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    navigationPath.append(NavigationDestination.accountDetail(account))
                    selectedAccountName = nil
                }
            }
        }
        .sheet(isPresented: $isEditingName) {
            RenameAccountSheet(
                accountName: account.accountName,
                editedName: $editedName,
                isPresented: $isEditingName,
                onSave: { newName in
                    viewModel.renameAccount(from: account.accountName, to: newName)
                }
            )
            .presentationDetents([.height(200)])
        }
    }
}

// MARK: - Account Distribution Bar

/// A colorful bar showing the distribution of accounts by value
struct AccountDistributionBar: View {
    let accounts: [AccountSummary]
    let totalValue: Double

    // Predefined colors for accounts
    private let accountColors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .cyan, .indigo, .mint, .teal, .yellow
    ]

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                    let percentage = account.totalValue / totalValue

                    RoundedRectangle(cornerRadius: 6)
                        .fill(accountColors[index % accountColors.count])
                        .frame(width: max(geometry.size.width * percentage, 0), height: 3)
                }
            }
            .frame(maxWidth: geometry.size.width, alignment: .leading)
            .clipped()
        }
        .frame(height: 3)
    }
}

#Preview("Accounts View") {
    struct PreviewWrapper: View {
        @State private var selectedTab = 4
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
