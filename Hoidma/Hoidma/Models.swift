import Foundation

// MARK: - Data Models

/// Defines the data structure for a committed stock.
struct Stock: Codable {
    let ticker: String
    var companyName: String
    let purchasePrice: Double
    let shares: Int
    var isMaritalStatus: Bool = false
    
    // Custom decoder to handle migration from old data without companyName
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ticker = try container.decode(String.self, forKey: .ticker)
        purchasePrice = try container.decode(Double.self, forKey: .purchasePrice)
        shares = try container.decode(Int.self, forKey: .shares)
        isMaritalStatus = try container.decodeIfPresent(Bool.self, forKey: .isMaritalStatus) ?? false
        // If companyName is missing, use ticker as fallback (will be updated from API)
        companyName = try container.decodeIfPresent(String.self, forKey: .companyName) ?? ticker.uppercased()
    }
    
    enum CodingKeys: String, CodingKey {
        case ticker
        case companyName
        case purchasePrice
        case shares
        case isMaritalStatus
    }
    
    // Regular initializer
    init(ticker: String, companyName: String, purchasePrice: Double, shares: Int, isMaritalStatus: Bool = false) {
        self.ticker = ticker
        self.companyName = companyName
        self.purchasePrice = purchasePrice
        self.shares = shares
        self.isMaritalStatus = isMaritalStatus
    }
    
    // MARK: Financial Calculations
    
    var totalCost: Double {
        return purchasePrice * Double(shares)
    }
    
    // NOTE: This property is a placeholder for the live price in a real app.
    // In this simulation, we generate a mock price based on the purchase price.
    var mockCurrentPrice: Double {
        let initialSeedPrice = purchasePrice * 1.05
        let fluctuation = (Double.random(in: 0...1) - 0.5) * 0.4 // +/- 20% fluctuation
        return initialSeedPrice * (1 + fluctuation)
    }
}

// Model to track individual stock price data
struct StockPriceData {
    let ticker: String
    var currentPrice: Double
    var changePercent: Double
    var profitLoss: Double
    var dailyStartPrice: Double
    var weeklyStartPrice: Double
    var monthlyStartPrice: Double
    var threeMonthsStartPrice: Double
    var ytdStartPrice: Double
    var allTimeStartPrice: Double
    var dailyStartTime: Date
    var weeklyStartTime: Date
    var monthlyStartTime: Date
    var threeMonthsStartTime: Date
    var ytdStartTime: Date
    var allTimeStartTime: Date
    
    // API-provided percentage changes for each period
    var apiPeriodChanges: [String: Double] = [:]
    
    // Previous trading day's close price (for accurate daily return calculation)
    var previousClose: Double?
    
    var isGreen: Bool {
        return profitLoss >= 0
    }
    
    func returnForPeriod(_ period: TimePeriod) -> (value: Double, percent: Double) {
        // Map TimePeriod to API period keys
        let apiPeriodKey: String
        switch period {
        case .daily:
            apiPeriodKey = "1d"
        case .weekly:
            apiPeriodKey = "1w"
        case .monthly:
            apiPeriodKey = "1m"
        case .threeMonths:
            apiPeriodKey = "3m"
        case .ytd:
            apiPeriodKey = "ytd"
        case .allTime:
            // For all-time, calculate from purchase price (not from API)
            let change = currentPrice - allTimeStartPrice
            let percent = allTimeStartPrice > 0 ? (change / allTimeStartPrice) * 100 : 0
            return (change, percent)
        }
        
        // For daily period, prioritize API data which represents latest trading day
        if period == .daily {
            // Use API-provided percentage change if available (this is the latest trading day's change)
            if let apiPercent = apiPeriodChanges[apiPeriodKey] {
                // For daily, use previous close if available (latest trading day's close)
                // Otherwise calculate from current price and percentage
                let startPrice: Double
                if let prevClose = previousClose, prevClose > 0 {
                    startPrice = prevClose
                } else {
                    // Calculate previous close from current price and percentage change
                    // If current = prevClose * (1 + percent/100), then prevClose = current / (1 + percent/100)
                    startPrice = currentPrice / (1 + apiPercent / 100)
                }
                let value = currentPrice - startPrice
                return (value, apiPercent)
            }
        }
        
        // Use API-provided percentage change if available for other periods
        if let apiPercent = apiPeriodChanges[apiPeriodKey] {
            // Calculate value from percentage
            let startPrice: Double
            switch period {
            case .daily:
                // Should not reach here for daily (handled above), but keep for safety
                if let prevClose = previousClose, prevClose > 0 {
                    startPrice = prevClose
                } else {
                    startPrice = dailyStartPrice
                }
            case .weekly:
                startPrice = weeklyStartPrice
            case .monthly:
                startPrice = monthlyStartPrice
            case .threeMonths:
                startPrice = threeMonthsStartPrice
            case .ytd:
                startPrice = ytdStartPrice
            case .allTime:
                startPrice = allTimeStartPrice
            }
            let value = (apiPercent / 100) * startPrice
            return (value, apiPercent)
        }
        
        // Fallback to calculated value if API data not available
        let startPrice: Double
        switch period {
        case .daily:
            startPrice = dailyStartPrice
        case .weekly:
            startPrice = weeklyStartPrice
        case .monthly:
            startPrice = monthlyStartPrice
        case .threeMonths:
            startPrice = threeMonthsStartPrice
        case .ytd:
            startPrice = ytdStartPrice
        case .allTime:
            startPrice = allTimeStartPrice
        }
        
        let change = currentPrice - startPrice
        let percent = startPrice > 0 ? (change / startPrice) * 100 : 0
        return (change, percent)
    }
}

enum TimePeriod: String, CaseIterable {
    case daily = "1D"
    case weekly = "1W"
    case monthly = "1M"
    case threeMonths = "3M"
    case ytd = "YTD"
    case allTime = "All"
}

