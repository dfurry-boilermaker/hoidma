import SwiftUI

struct StockPositionRow: View {
    let stock: Stock
    let priceData: StockPriceData?
    let totalPortfolioValue: Double
    let selectedPeriod: TimePeriod
    let onRemove: () -> Void
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    
    // Calculate the stock value in dollars
    var stockValue: Double {
        guard let priceData = priceData else { return 0 }
        let totalShares = stock.lots.isEmpty ? Double(stock.shares) : stock.lots.reduce(0.0) { $0 + $1.shares }
        return priceData.currentPrice * totalShares
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
        let totalShares = stock.lots.isEmpty ? Double(stock.shares) : stock.lots.reduce(0.0) { $0 + $1.shares }
        let dollarValue = returnData.value * totalShares
        return (dollarValue, returnData.percent)
    }
    
    // Calculate all-time return
    var allTimeReturn: (value: Double, percent: Double) {
        guard let priceData = priceData else { return (0, 0) }
        let returnData = priceData.returnForPeriod(.allTime)
        // Calculate dollar value based on shares
        let totalShares = stock.lots.isEmpty ? Double(stock.shares) : stock.lots.reduce(0.0) { $0 + $1.shares }
        let dollarValue = returnData.value * totalShares
        return (dollarValue, returnData.percent)
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
                    
                    Text("\(stock.shares) shares")
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

