import SwiftUI

struct AccountDetailView: View {
    let account: AccountSummary
    let totalAllAccounts: Double
    @ObservedObject var viewModel: StockViewModel
    @Binding var navigationPath: NavigationPath
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("selectedTab") private var selectedTab: Int = 1
    @AppStorage("appearanceMode") private var appearanceMode: Int = AppearanceMode.auto.rawValue

    // Rename account state
    @State private var isEditingName = false
    @State private var editedName = ""

    // Add position state
    @State private var showingAddStockForm = false

    private var isDarkMode: Bool {
        let mode = AppearanceMode(rawValue: appearanceMode) ?? .auto
        switch mode {
        case .light: return false
        case .dark: return true
        case .auto: return systemColorScheme == .dark
        }
    }

    private var accountPercentage: Double {
        totalAllAccounts > 0 ? (account.totalValue / totalAllAccounts) * 100 : 0
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 4) {
                        // Standard header matching main page
                        ZStack(alignment: .center) {
                            // Back button on left
                            HStack {
                                Button {
                                    dismiss()
                                } label: {
                                    Image(isDarkMode ? "back.button.dark" : "back.button")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 12, height: 12)
                                }
                                .padding(.leading, 20)

                                Spacer()
                            }

                            // Dave folly logo centered
                            Button {
                                withAnimation {
                                    // Toggle between light and dark only (auto is set in profile)
                                    if isDarkMode {
                                        appearanceMode = AppearanceMode.light.rawValue
                                    } else {
                                        appearanceMode = AppearanceMode.dark.rawValue
                                    }
                                }
                            } label: {
                                Image(isDarkMode ? "dave.folly.logo.dark" : "dave.folly.logo")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 50)
                            }

                            // Add button at top-right
                            HStack {
                                Spacer()
                                Button {
                                    showingAddStockForm = true
                                } label: {
                                    Image(isDarkMode ? "add.button.dark" : "add.button")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 70, height: 43)
                                }
                                .padding(.trailing, 16)
                            }
                        }
                        .padding(.bottom, 8)

                        // Account name and position count
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(account.accountName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color.primary)

                                Button {
                                    editedName = account.accountName
                                    isEditingName = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Color.secondary)
                                }
                            }

                            Text("\(account.positions.count) position\(account.positions.count == 1 ? "" : "s")")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 0)

                        // Details rows
                        VStack(spacing: 4) {
                            // Total Value row
                            HStack {
                                Text("Total Value")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color.secondary)
                                Spacer()
                                Text(account.totalValue, format: .currency(code: "USD"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color.primary)
                            }

                            // 1D Gain/Loss row
                            HStack {
                                Text("1D Gain/Loss")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color.secondary)
                                Spacer()
                                Text("\(account.dailyGain >= 0 ? "+" : "")\(account.dailyGain.formatted(.currency(code: "USD"))) (\(account.dailyGainPercent >= 0 ? "+" : "")\(String(format: "%.2f", account.dailyGainPercent))%)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AppColors.forValue(account.dailyGain))
                            }

                            // All Time Gain/Loss row
                            HStack {
                                Text("All Time Gain/Loss")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color.secondary)
                                Spacer()
                                Text("\(account.profitLoss >= 0 ? "+" : "")\(account.profitLoss.formatted(.currency(code: "USD"))) (\(account.profitLossPercent >= 0 ? "+" : "")\(String(format: "%.2f", account.profitLossPercent))%)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AppColors.forValue(account.profitLoss))
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)

                        // Portfolio allocation section
                        VStack(spacing: 4) {
                            // Percentage text centered above the bar
                            Text("\(String(format: "%.1f", accountPercentage))% of portfolio")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color.primary)

                            // Progress bar
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

                                    // Filled bar using account's primary color (first position color)
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(account.positions.first?.color ?? Color.blue)
                                        .frame(width: max(geometry.size.width * min(accountPercentage / 100, 1.0), 0), height: 3)
                                }
                            }
                            .frame(height: 3)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)

                        // Account Positions label
                        HStack {
                            Text("Account Positions")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                        // Positions section
                        VStack(spacing: 0) {
                            // Position rows using StockPositionRow - sorted by current value
                            VStack(spacing: 0) {
                                let sortedPositions = account.positions.sorted { pos1, pos2 in
                                    let price1 = viewModel.stockPrices[pos1.ticker]?.currentPrice ?? pos1.value / pos1.shares
                                    let price2 = viewModel.stockPrices[pos2.ticker]?.currentPrice ?? pos2.value / pos2.shares
                                    let value1 = price1 * pos1.shares
                                    let value2 = price2 * pos2.shares
                                    return value1 > value2
                                }
                                ForEach(Array(sortedPositions.enumerated()), id: \.element.ticker) { index, position in
                                    if let stock = viewModel.stocks.first(where: { $0.ticker == position.ticker }) {
                                        VStack(spacing: 0) {
                                            Button {
                                                navigationPath.append(NavigationDestination.stockDetail(stock))
                                            } label: {
                                                StockPositionRow(
                                                    stock: stock,
                                                    priceData: viewModel.stockPrices[stock.ticker],
                                                    totalPortfolioValue: account.totalValue,
                                                    selectedPeriod: .daily,
                                                    onRemove: {},
                                                    forAccountName: account.accountName
                                                )
                                            }
                                            .buttonStyle(PlainButtonStyle())

                                            if index < sortedPositions.count - 1 {
                                                Divider()
                                                    .padding(.leading, 20)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }

                // Bottom navigation bar
                BottomNavigationBar(selectedTab: $selectedTab) { tabNumber in
                    selectedTab = tabNumber
                    dismiss()
                }
            }
        }
        .gesture(
            DragGesture()
                .onEnded { gesture in
                    // Swipe right to go back
                    if gesture.translation.width > 100 {
                        dismiss()
                    }
                }
        )
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $isEditingName) {
            RenameAccountSheet(
                accountName: account.accountName,
                editedName: $editedName,
                isPresented: $isEditingName,
                onSave: { newName in
                    viewModel.renameAccount(from: account.accountName, to: newName)
                    dismiss() // Dismiss to refresh the account list
                }
            )
            .presentationDetents([.height(200)])
        }
        .sheet(isPresented: $showingAddStockForm) {
            AddStockFormView(
                viewModel: viewModel,
                isPresented: $showingAddStockForm,
                initialAccountName: account.accountName
            )
        }
    }
}

// MARK: - Rename Account Sheet

struct RenameAccountSheet: View {
    let accountName: String
    @Binding var editedName: String
    @Binding var isPresented: Bool
    let onSave: (String) -> Void
    @FocusState private var isTextFieldFocused: Bool

    private var isValidName: Bool {
        !editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .foregroundColor(Color.primary)

                Spacer()

                Text("Rename Account")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.primary)

                Spacer()

                Button("Save") {
                    let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedName.isEmpty {
                        onSave(trimmedName)
                        isPresented = false
                    }
                }
                .foregroundColor(isValidName ? AppColors.positive : Color.secondary)
                .disabled(!isValidName)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            // Text field
            TextField("Account Name", text: $editedName)
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(Color.primary)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)
                .padding(.horizontal, 20)
                .focused($isTextFieldFocused)
                .onSubmit {
                    let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedName.isEmpty {
                        onSave(trimmedName)
                        isPresented = false
                    }
                }

            Spacer()
        }
        .background(Color(UIColor.systemBackground))
        .onAppear {
            isTextFieldFocused = true
        }
    }
}

// MARK: - Account Detail Row

struct AccountDetailRow: View {
    let label: String
    let value: String
    var valueColor: Color = Color.primary

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(valueColor)
        }
    }
}

#Preview("Account Detail View") {
    struct PreviewWrapper: View {
        @State private var navigationPath = NavigationPath()

        var body: some View {
            NavigationStack(path: $navigationPath) {
                AccountDetailView(
                    account: AccountSummary(
                        accountName: "401k",
                        totalValue: 50000,
                        totalCost: 45000,
                        dailyGain: 250,
                        dailyGainPercent: 0.5,
                        positions: [
                            AccountPosition(ticker: "AAPL", companyName: "Apple Inc.", shares: 10, value: 20000, cost: 18000, dailyChange: 1.5, color: .blue),
                            AccountPosition(ticker: "GOOGL", companyName: "Alphabet Inc.", shares: 5, value: 15000, cost: 14000, dailyChange: -0.5, color: .orange),
                            AccountPosition(ticker: "MSFT", companyName: "Microsoft Corp.", shares: 8, value: 15000, cost: 13000, dailyChange: 2.0, color: .green)
                        ]
                    ),
                    totalAllAccounts: 100000,
                    viewModel: MockStockViewModel(),
                    navigationPath: $navigationPath
                )
            }
        }
    }
    return PreviewWrapper()
}
