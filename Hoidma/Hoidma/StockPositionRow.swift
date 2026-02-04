import SwiftUI

struct StockPositionRow: View {
    let stock: Stock
    let priceData: StockPriceData?
    let totalPortfolioValue: Double
    let selectedPeriod: TimePeriod
    let onRemove: () -> Void
    var forAccountName: String? = nil // Optional filter for specific account

    // Get shares for this context (filtered by account if specified)
    private var relevantShares: Double {
        if let accountName = forAccountName {
            // Only count shares from lots in this specific account
            return stock.lots.filter { $0.accountName == accountName }.reduce(0.0) { $0 + $1.shares }
        } else {
            // All shares across all accounts
            return stock.lots.isEmpty ? Double(stock.shares) : stock.lots.reduce(0.0) { $0 + $1.shares }
        }
    }

    // Get cost basis for this context (filtered by account if specified)
    private var relevantCostBasis: Double {
        if let accountName = forAccountName {
            return stock.lots.filter { $0.accountName == accountName }.reduce(0.0) { $0 + $1.totalCost }
        } else {
            return stock.lots.isEmpty ? stock.totalCost : stock.lots.reduce(0.0) { $0 + $1.totalCost }
        }
    }

    // Calculate the stock value in dollars
    var stockValue: Double {
        guard let priceData = priceData else { return 0 }
        return priceData.currentPrice * relevantShares
    }

    // Calculate the percentage of portfolio this stock represents
    var portfolioPercentage: Double {
        guard totalPortfolioValue > 0 else { return 0 }
        return (stockValue / totalPortfolioValue) * 100
    }

    // Calculate daily return
    var dailyReturn: (value: Double, percent: Double) {
        guard let priceData = priceData else { return (0, 0) }
        let returnData = priceData.returnForPeriod(.daily)
        // Calculate dollar value based on shares
        let dollarValue = returnData.value * relevantShares
        return (dollarValue, returnData.percent)
    }

    // Calculate all-time return based on cost basis
    var allTimeReturn: (value: Double, percent: Double) {
        guard let priceData = priceData else { return (0, 0) }
        let currentValue = priceData.currentPrice * relevantShares
        let costBasis = relevantCostBasis
        let dollarValue = currentValue - costBasis
        let percent = costBasis > 0 ? (dollarValue / costBasis) * 100 : 0
        return (dollarValue, percent)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: Company name and price aligned
            HStack(alignment: .firstTextBaseline) {
                Text(stock.companyName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.primary)
                    .lineLimit(1)
                
                Spacer()
                
                // Stock price - aligned with company name
                if let priceData = priceData {
                    Text(priceData.currentPrice, format: .currency(code: "USD"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.primary)
                }
            }
            
            // Row 2: Ticker + Shares | Daily change
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Text(stock.ticker)
                        .font(.hoidmaMono(size: 10))
                        .foregroundColor(Color.secondary)

                    let sharesText = relevantShares.truncatingRemainder(dividingBy: 1) == 0
                        ? "\(Int(relevantShares)) shares"
                        : "\(String(format: "%.4f", relevantShares)) shares"
                    Text(sharesText)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(Color.secondary)
                }
                
                Spacer()
                
                // Daily change - aligned with ticker/shares
                if priceData != nil {
                    HStack(spacing: 2) {
                        Text(dailyReturn.value >= 0 ? "+" : "")
                            .font(.system(size: 10, weight: .medium))
                        Text(dailyReturn.value, format: .currency(code: "USD"))
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("(\(dailyReturn.percent >= 0 ? "+" : "")\(String(format: "%.2f", dailyReturn.percent))%)")
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("1D")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(Color.secondary)
                    }
                    .foregroundColor(AppColors.forValue(dailyReturn.value))
                }
            }
            
            // Row 3: Portfolio percentage with dollar value | All-time change
            HStack(alignment: .firstTextBaseline) {
                if portfolioPercentage > 0 {
                    HStack(spacing: 4) {
                        Text(stockValue, format: .currency(code: "USD"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.secondary)
                        Text("(\(portfolioPercentage, specifier: "%.1f")%)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.secondary)
                    }
                } else {
                    Spacer()
                        .frame(width: 0)
                }
                
                Spacer()
                
                // All-time change - aligned with portfolio percentage
                if priceData != nil {
                    HStack(spacing: 2) {
                        Text(allTimeReturn.value >= 0 ? "+" : "")
                            .font(.system(size: 10, weight: .medium))
                        Text(allTimeReturn.value, format: .currency(code: "USD"))
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("(\(allTimeReturn.percent >= 0 ? "+" : "")\(String(format: "%.2f", allTimeReturn.percent))%)")
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("All")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(Color.secondary)
                    }
                    .foregroundColor(AppColors.forValue(allTimeReturn.value))
                } else {
                    Text("Loading...")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
    }
}

