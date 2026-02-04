import Foundation

// MARK: - Data Models

/// Defines a single lot of stock in a specific account
struct StockLot: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var accountName: String
    var shares: Double // Changed to Double to support fractional shares
    var purchasePrice: Double // Changed to var to allow updating when adding shares

    init(accountName: String, shares: Double, purchasePrice: Double) {
        self.id = UUID()
        self.accountName = accountName
        self.shares = shares
        self.purchasePrice = purchasePrice
    }

    var totalCost: Double {
        return purchasePrice * shares
    }

    static func == (lhs: StockLot, rhs: StockLot) -> Bool {
        return lhs.id == rhs.id &&
               lhs.accountName == rhs.accountName &&
               lhs.shares == rhs.shares &&
               lhs.purchasePrice == rhs.purchasePrice
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Defines the data structure for a committed stock.
struct Stock: Codable, Equatable, Hashable {
    let ticker: String
    var companyName: String
    let purchasePrice: Double
    let shares: Int
    var isMaritalStatus: Bool = false
    var lots: [StockLot] = [] // Multiple lots in different accounts

    static func == (lhs: Stock, rhs: Stock) -> Bool {
        return lhs.ticker == rhs.ticker &&
               lhs.companyName == rhs.companyName &&
               lhs.purchasePrice == rhs.purchasePrice &&
               lhs.shares == rhs.shares &&
               lhs.isMaritalStatus == rhs.isMaritalStatus &&
               lhs.lots == rhs.lots
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ticker)
    }
    
    // Custom decoder to handle migration from old data without companyName
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ticker = try container.decode(String.self, forKey: .ticker)
        purchasePrice = try container.decode(Double.self, forKey: .purchasePrice)
        shares = try container.decode(Int.self, forKey: .shares)
        isMaritalStatus = try container.decodeIfPresent(Bool.self, forKey: .isMaritalStatus) ?? false
        lots = try container.decodeIfPresent([StockLot].self, forKey: .lots) ?? []
        // If companyName is missing, use ticker as fallback (will be updated from API)
        companyName = try container.decodeIfPresent(String.self, forKey: .companyName) ?? ticker.uppercased()
    }
    
    enum CodingKeys: String, CodingKey {
        case ticker
        case companyName
        case purchasePrice
        case shares
        case isMaritalStatus
        case lots
    }
    
    // Regular initializer
    init(ticker: String, companyName: String, purchasePrice: Double, shares: Int, isMaritalStatus: Bool = false, lots: [StockLot] = []) {
        self.ticker = ticker
        self.companyName = companyName
        self.purchasePrice = purchasePrice
        self.shares = shares
        self.isMaritalStatus = isMaritalStatus
        self.lots = lots
    }
    
    // MARK: Financial Calculations
    
    var totalCost: Double {
        return purchasePrice * Double(shares)
    }
    
    // DEPRECATED: DO NOT USE - Generates random fake prices that violate data integrity
    // This property was removed from production code to prevent showing fabricated financial data
    // Only kept for backward compatibility with preview/test code
    @available(*, deprecated, message: "Never use mock prices in production - shows fake data to users")
    var mockCurrentPrice: Double {
        AppLogger.error("⚠️ DEPRECATED: mockCurrentPrice called - this generates fake data!")
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

    // Beta (volatility relative to market, 1.0 = market average)
    var beta: Double?

    // Whether this is an ETF (vs individual stock)
    var isETF: Bool?

    // Data source - "polygon" (preferred) or "yahoo" (fallback)
    var dataSource: String?

    var isGreen: Bool {
        return profitLoss >= 0
    }

    // Data quality indicator - true if we have valid previousClose for accurate daily %
    var hasValidDailyData: Bool {
        guard let prevClose = previousClose, prevClose > 0 else { return false }
        let ratio = currentPrice / prevClose
        return ratio >= 0.5 && ratio <= 2.0  // Sanity check
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

// MARK: - Stock Sector

/// Represents the 11 GICS sectors for stock classification
enum StockSector: String, CaseIterable, Codable {
    case technology = "Technology"
    case healthcare = "Healthcare"
    case financials = "Financials"
    case consumerDiscretionary = "Consumer Discretionary"
    case communicationServices = "Communication Services"
    case industrials = "Industrials"
    case consumerStaples = "Consumer Staples"
    case energy = "Energy"
    case utilities = "Utilities"
    case realEstate = "Real Estate"
    case materials = "Materials"
    case etf = "ETFs"
    case other = "Other"

    /// Returns a unique color for each sector
    var color: (red: Double, green: Double, blue: Double) {
        switch self {
        case .technology:
            return (0.0, 0.48, 1.0)        // Blue
        case .healthcare:
            return (0.0, 0.78, 0.55)       // Teal
        case .financials:
            return (0.4, 0.27, 0.68)       // Purple
        case .consumerDiscretionary:
            return (1.0, 0.58, 0.0)        // Orange
        case .communicationServices:
            return (0.98, 0.36, 0.36)      // Coral Red
        case .industrials:
            return (0.55, 0.55, 0.55)      // Gray
        case .consumerStaples:
            return (0.2, 0.6, 0.33)        // Green
        case .energy:
            return (0.85, 0.65, 0.13)      // Golden
        case .utilities:
            return (0.58, 0.44, 0.86)      // Lavender
        case .realEstate:
            return (0.6, 0.4, 0.2)         // Brown
        case .materials:
            return (0.35, 0.75, 0.85)      // Cyan
        case .etf:
            return (0.95, 0.75, 0.0)       // Gold/Amber - represents diversified funds
        case .other:
            return (0.5, 0.5, 0.5)         // Medium Gray
        }
    }

    /// Maps Yahoo Finance sector strings to StockSector enum
    static func from(yahooSector: String?) -> StockSector {
        guard let sector = yahooSector?.lowercased() else { return .other }

        switch sector {
        case let s where s.contains("technology"):
            return .technology
        case let s where s.contains("healthcare") || s.contains("health care"):
            return .healthcare
        case let s where s.contains("financial"):
            return .financials
        case let s where s.contains("consumer discretionary") || s.contains("consumer cyclical"):
            return .consumerDiscretionary
        case let s where s.contains("communication") || s.contains("telecom"):
            return .communicationServices
        case let s where s.contains("industrial"):
            return .industrials
        case let s where s.contains("consumer staples") || s.contains("consumer defensive"):
            return .consumerStaples
        case let s where s.contains("energy"):
            return .energy
        case let s where s.contains("utilities"):
            return .utilities
        case let s where s.contains("real estate"):
            return .realEstate
        case let s where s.contains("materials") || s.contains("basic materials"):
            return .materials
        default:
            return .other
        }
    }
}

// MARK: - Database Models (Supabase)

/// Represents a stock price record from the Supabase stock_prices table
/// Used for server-side cached stock data
struct DBStockPrice: Codable {
    let ticker: String
    let price: Double
    let previousClose: Double?
    let dayChangePercent: Double?
    let companyName: String?
    let beta: Double?
    let isETF: Bool?
    let updatedAt: Date?
    let change1w: Double?
    let change1m: Double?
    let change3m: Double?
    let changeYtd: Double?

    enum CodingKeys: String, CodingKey {
        case ticker
        case price
        case previousClose = "previous_close"
        case dayChangePercent = "day_change_percent"
        case companyName = "company_name"
        case beta
        case isETF = "is_etf"
        case updatedAt = "updated_at"
        case change1w = "change_1w"
        case change1m = "change_1m"
        case change3m = "change_3m"
        case changeYtd = "change_ytd"
    }

    /// Convert to StockAPIService.StockData for compatibility with existing code
    func toStockData() -> StockAPIService.StockData {
        var periodChanges: [String: Double] = [:]
        if let dayChange = dayChangePercent {
            periodChanges["1d"] = dayChange
        }
        if let weekChange = change1w {
            periodChanges["1w"] = weekChange
        }
        if let monthChange = change1m {
            periodChanges["1m"] = monthChange
        }
        if let threeMonthChange = change3m {
            periodChanges["3m"] = threeMonthChange
        }
        if let ytdChange = changeYtd {
            periodChanges["ytd"] = ytdChange
        }

        return StockAPIService.StockData(
            price: price,
            companyName: companyName ?? ticker,
            periodChanges: periodChanges.isEmpty ? nil : periodChanges,
            previousClose: previousClose,
            beta: beta,
            isETF: isETF ?? false,
            dataSource: "supabase"
        )
    }
}

// MARK: - Polygon.io API Models

/// Polygon.io last trade response
/// Reference: https://polygon.io/docs/stocks/get_v2_last_trade__stocksticker
struct PolygonLastTrade: Codable {
    let status: String
    let results: TradeResult?
    let error: String?  // Error message if status != "OK"

    struct TradeResult: Codable {
        let T: String   // Ticker
        let p: Double   // Price
        let s: Int      // Size
        let t: Int64    // Timestamp (Unix milliseconds)
        let x: Int?     // Exchange ID
        let c: [Int]?   // Conditions
    }
}

/// Polygon.io aggregates (bars) response
/// Reference: https://polygon.io/docs/stocks/get_v2_aggs_ticker__stocksticker__range__multiplier___timespan___from___to
struct PolygonAggregates: Codable {
    let ticker: String
    let queryCount: Int?
    let resultsCount: Int?
    let adjusted: Bool?
    let results: [AggregateBar]?
    let status: String?
    let nextUrl: String?

    struct AggregateBar: Codable {
        let v: Int64    // Volume
        let vw: Double? // VWAP (Volume Weighted Average Price)
        let o: Double   // Open
        let c: Double   // Close
        let h: Double   // High
        let l: Double   // Low
        let t: Int64    // Timestamp (Unix milliseconds)
        let n: Int?     // Number of transactions
    }

    enum CodingKeys: String, CodingKey {
        case ticker
        case queryCount
        case resultsCount
        case adjusted
        case results
        case status
        case nextUrl = "next_url"
    }
}

/// Polygon.io ticker details response
/// Reference: https://polygon.io/docs/stocks/get_v3_reference_tickers__ticker
struct PolygonTickerDetails: Codable {
    let status: String?
    let results: TickerResult?

    struct TickerResult: Codable {
        let ticker: String
        let name: String
        let market: String?
        let locale: String?
        let primaryExchange: String?
        let type: String?
        let active: Bool?
        let currencyName: String?
        let cik: String?
        let compositeFigi: String?
        let shareClassFigi: String?
        let marketCap: Double?
        let phoneNumber: String?
        let address: Address?
        let description: String?
        let sicCode: String?
        let sicDescription: String?
        let tickerRoot: String?
        let homepageUrl: String?
        let totalEmployees: Int?
        let listDate: String?
        let branding: Branding?
        let shareClassSharesOutstanding: Int64?
        let weightedSharesOutstanding: Int64?
        let roundLot: Int?

        struct Address: Codable {
            let address1: String?
            let city: String?
            let state: String?
            let postalCode: String?
        }

        struct Branding: Codable {
            let logoUrl: String?
            let iconUrl: String?
        }

        enum CodingKeys: String, CodingKey {
            case ticker, name, market, locale, type, active, description
            case primaryExchange = "primary_exchange"
            case currencyName = "currency_name"
            case cik
            case compositeFigi = "composite_figi"
            case shareClassFigi = "share_class_figi"
            case marketCap = "market_cap"
            case phoneNumber = "phone_number"
            case address
            case sicCode = "sic_code"
            case sicDescription = "sic_description"
            case tickerRoot = "ticker_root"
            case homepageUrl = "homepage_url"
            case totalEmployees = "total_employees"
            case listDate = "list_date"
            case branding
            case shareClassSharesOutstanding = "share_class_shares_outstanding"
            case weightedSharesOutstanding = "weighted_shares_outstanding"
            case roundLot = "round_lot"
        }
    }
}

/// Polygon.io previous close response
/// Reference: https://polygon.io/docs/stocks/get_v2_aggs_ticker__stocksticker__prev
struct PolygonPreviousClose: Codable {
    let ticker: String
    let queryCount: Int?
    let resultsCount: Int?
    let adjusted: Bool?
    let results: [PreviousCloseBar]?
    let status: String?
    let error: String?  // Error message if status != "OK"

    struct PreviousCloseBar: Codable {
        let T: String?  // Ticker
        let v: Int64    // Volume
        let vw: Double? // VWAP
        let o: Double   // Open
        let c: Double   // Close
        let h: Double   // High
        let l: Double   // Low
        let t: Int64    // Timestamp
        let n: Int?     // Number of transactions
    }

    enum CodingKeys: String, CodingKey {
        case ticker
        case queryCount
        case resultsCount
        case adjusted
        case results
        case status
        case error
    }
}

/// Enhanced stock data with OHLCV information
struct EnhancedStockData {
    let price: Double
    let companyName: String
    let previousClose: Double?
    let beta: Double?
    let isETF: Bool

    // OHLCV data
    let open: Double?
    let high: Double?
    let low: Double?
    let volume: Int64?
    let vwap: Double?

    // Metadata
    let dataSource: String
    let marketStatus: String?
    let timestamp: Date?

    // Period changes
    let periodChanges: [String: Double]?

    /// Convert to legacy StockData format for backward compatibility
    func toStockData() -> StockAPIService.StockData {
        return StockAPIService.StockData(
            price: price,
            companyName: companyName,
            periodChanges: periodChanges,
            previousClose: previousClose,
            beta: beta,
            isETF: isETF,
            dataSource: dataSource
        )
    }
}

// MARK: - Waterfall Chart Data

/// Represents a segment in the waterfall chart
struct WaterfallSegment: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let isTotal: Bool
    let isPositive: Bool

    /// The starting Y position for the bar (for floating bars)
    var startValue: Double = 0

    init(label: String, value: Double, isTotal: Bool = false, isPositive: Bool = true, startValue: Double = 0) {
        self.label = label
        self.value = value
        self.isTotal = isTotal
        self.isPositive = isPositive
        self.startValue = startValue
    }
}

