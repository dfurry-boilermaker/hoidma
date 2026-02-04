import SwiftUI

// MARK: - Treemap Visualization

struct TreemapView: View {
    let accounts: [String]
    let sharedData: [(ticker: String, accounts: [String], totalValue: Double, accountValues: [String: Double], color: Color)]
    let accountValues: [String: Double]
    let showDollarAmounts: Bool
    var onAccountTap: ((String) -> Void)? = nil

    /// Get stocks for a specific account with their actual values in that account
    private func stocksForAccount(_ account: String) -> [(ticker: String, value: Double, color: Color)] {
        sharedData
            .filter { $0.accounts.contains(account) }
            .compactMap { item -> (ticker: String, value: Double, color: Color)? in
                // Use the actual value for this account from accountValues
                guard let valueInAccount = item.accountValues[account], valueInAccount > 0 else { return nil }
                return (ticker: item.ticker, value: valueInAccount, color: item.color)
            }
            .sorted { $0.value > $1.value }
    }

    /// Total value across all accounts
    private var totalValue: Double {
        accountValues.values.reduce(0, +)
    }

    var body: some View {
        VStack(spacing: 16) {
            ForEach(Array(accounts.sorted { (accountValues[$0] ?? 0) > (accountValues[$1] ?? 0) }.enumerated()), id: \.element) { index, account in
                let accountValue = accountValues[account] ?? 0
                let accountPercentage = totalValue > 0 ? (accountValue / totalValue) * 100 : 0
                let stocks = stocksForAccount(account)

                Button {
                    onAccountTap?(account)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        // Account header
                        HStack {
                            Text(account)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color.primary)

                            Spacer()

                            if showDollarAmounts {
                                Text(accountValue, format: .currency(code: "USD"))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color.secondary)
                            }

                            Text("\(String(format: "%.1f", accountPercentage))%")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color.primary)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color.secondary.opacity(0.5))
                        }

                        // Stock treemap for this account
                        if !stocks.isEmpty {
                            AccountTreemapRow(
                                stocks: stocks,
                                accountValue: accountValue,
                                showDollarAmounts: showDollarAmounts
                            )
                        }
                    }
                    .padding(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

// MARK: - Account Treemap Row

struct AccountTreemapRow: View {
    let stocks: [(ticker: String, value: Double, color: Color)]
    let accountValue: Double
    let showDollarAmounts: Bool

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let height: CGFloat = 50

            HStack(spacing: 2) {
                ForEach(stocks, id: \.ticker) { stock in
                    let percentage = accountValue > 0 ? stock.value / accountValue : 0
                    let width = max(totalWidth * percentage - 2, 0)

                    if width > 20 {
                        VStack(spacing: 2) {
                            Text(stock.ticker)
                                .font(.system(size: width > 50 ? 10 : 8, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                                .lineLimit(1)

                            if showDollarAmounts && width > 60 {
                                Text("$\(Int(stock.value))")
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .frame(width: width, height: height)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(stock.color)
                        )
                    } else if width > 4 {
                        // Very small segment - just show color
                        RoundedRectangle(cornerRadius: 4)
                            .fill(stock.color)
                            .frame(width: width, height: height)
                    }
                }
            }
        }
        .frame(height: 50)
    }
}

// MARK: - Preview

#Preview("Treemap View") {
    let mockAccounts = ["401k", "Roth IRA", "Indv"]
    let mockData: [(ticker: String, accounts: [String], totalValue: Double, accountValues: [String: Double], color: Color)] = [
        ("AAPL", ["401k", "Indv"], 15000, ["401k": 9000, "Indv": 6000], .blue),
        ("GOOGL", ["Roth IRA"], 12000, ["Roth IRA": 12000], .green),
        ("MSFT", ["401k", "Roth IRA"], 18000, ["401k": 10000, "Roth IRA": 8000], .purple),
        ("AMZN", ["Indv"], 8000, ["Indv": 8000], .orange),
        ("TSLA", ["401k"], 6000, ["401k": 6000], .red),
        ("NVDA", ["Roth IRA", "Indv"], 20000, ["Roth IRA": 10000, "Indv": 10000], .cyan),
    ]
    let mockAccountValues: [String: Double] = [
        "401k": 25000,
        "Roth IRA": 30000,
        "Indv": 24000
    ]

    return ScrollView {
        TreemapView(
            accounts: mockAccounts,
            sharedData: mockData,
            accountValues: mockAccountValues,
            showDollarAmounts: true
        )
        .padding()
    }
}
