import Foundation
import SwiftYFinance
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

// MARK: - Stock API Service

/// Service to fetch real stock data from Yahoo Finance API
/// 
/// Uses SwiftYFinance library (maintained Swift wrapper for Yahoo Finance API):
/// - Library: SwiftYFinance by AlexRoar (https://github.com/AlexRoar/SwiftYFinance)
/// - Provides: Current market price, historical data, company info, and metadata
/// - Rate Limits: No official limits, but be respectful (30+ second intervals recommended)
/// - Benefits: Maintained library, better error handling, async/await support
/// 
/// Note: Yahoo Finance API is unofficial. SwiftYFinance provides a stable interface
/// that handles endpoint changes and provides better error handling.
/// 
/// For production apps with higher reliability needs, consider:
/// - Alpha Vantage (free tier: 5 calls/min, 500 calls/day)
/// - IEX Cloud (free tier available)
/// - Polygon.io (free tier available)
class StockAPIService {
    static let shared = StockAPIService()

    private init() {}
    
    /// Structure to hold stock data from API
    struct StockData {
        let price: Double
        let companyName: String
        let periodChanges: [String: Double]? // Percentage changes for different periods
        let previousClose: Double? // Previous trading day's close price
    }
    
    /// Structure to hold company information from Polygon.io
    struct CompanyInfo {
        let ticker: String
        let name: String
        let description: String?
        let homepage: String?
        let market: String?
        let locale: String?
        let primaryExchange: String?
        let type: String?
        let active: Bool?
        let currency: String?
        let marketCap: Double?
        let employees: Int?
        let shareClassSharesOutstanding: Int?
        let weightedSharesOutstanding: Int?
        let sicCode: String?
        let sicDescription: String?
        let totalEmployees: Int?
        let tags: [String]?
        let similar: [String]?
        let updated: String?
        let listDate: String?
    }
    
    /// Fetches the current stock price and company name for a given ticker symbol
    /// - Parameter ticker: Stock ticker symbol (e.g., "AAPL")
    /// - Returns: StockData with price and company name, or nil if fetch fails
    /// - Note: Uses direct Yahoo Finance API to avoid SwiftYFinance crashes
    func fetchStockData(for ticker: String) async -> StockData? {
        let trimmedTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmedTicker.isEmpty else { return nil }

        // Skip API calls during UI testing
        guard !AppEnvironment.isUITesting else {
            AppEnvironment.testingLog(" Skipping API call for \(ticker), returning mock data")
            return StockData(
                price: 150.0,
                companyName: ticker.uppercased(),
                periodChanges: nil,
                previousClose: 150.0
            )
        }

        // Use direct Yahoo Finance API instead of SwiftYFinance to avoid crashes
        return await fetchStockDataDirect(for: trimmedTicker)
    }

    /// Direct Yahoo Finance API call without SwiftYFinance library
    private func fetchStockDataDirect(for ticker: String) async -> StockData? {
        let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(ticker)?interval=1d&range=5d"

        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL for ticker: \(ticker)")
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("❌ HTTP error fetching \(ticker)")
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let chart = json["chart"] as? [String: Any],
                  let result = (chart["result"] as? [[String: Any]])?.first,
                  let meta = result["meta"] as? [String: Any] else {
                print("❌ Failed to parse response for \(ticker)")
                return nil
            }

            // Extract price data
            let price = meta["regularMarketPrice"] as? Double ?? 0.0
            let previousClose = meta["previousClose"] as? Double
            let companyName = (meta["longName"] as? String) ?? (meta["shortName"] as? String) ?? ticker

            // Calculate daily change
            var periodChanges: [String: Double] = [:]
            if let prevClose = previousClose, prevClose > 0 {
                let dayChange = ((price - prevClose) / prevClose) * 100
                periodChanges["1d"] = dayChange
                print("📊 \(ticker) daily change: \(String(format: "%.2f", dayChange))% (price: $\(String(format: "%.2f", price)), prevClose: $\(String(format: "%.2f", prevClose)))")
            } else {
                print("⚠️ \(ticker) no previousClose available in API response")
            }

            print("✅ Fetched data for \(ticker): $\(price) - \(companyName)")

            return StockData(
                price: price,
                companyName: companyName,
                periodChanges: periodChanges.isEmpty ? nil : periodChanges,
                previousClose: previousClose
            )
        } catch {
            print("❌ Error fetching stock data for \(ticker): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Fetches percentage changes for different time periods from the API
    /// - Parameters:
    ///   - ticker: Stock ticker symbol
    ///   - currentPrice: Current price of the stock
    /// - Returns: Dictionary mapping period to percentage change
    private func fetchPeriodChanges(for ticker: String, currentPrice: Double) async -> [String: Double] {
        var periodChanges: [String: Double] = [:]

        // Skip API calls in UI tests
        if AppEnvironment.isUITesting {
            return ["1w": 2.5, "1m": 5.0, "3m": 10.0, "ytd": 15.0]
        }

        // Define periods with Yahoo Finance range parameters
        let periods: [(String, String)] = [
            ("1w", "5d"),
            ("1m", "1mo"),
            ("3m", "3mo"),
            ("ytd", "ytd")
        ]

        print("🔄 Fetching period changes for \(ticker)")

        await withTaskGroup(of: (String, Double?).self) { group in
            for (periodKey, range) in periods {
                group.addTask {
                    let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(ticker.uppercased())?interval=1d&range=\(range)"

                    guard let url = URL(string: urlString) else {
                        return (periodKey, nil)
                    }

                    do {
                        var request = URLRequest(url: url)
                        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

                        let (data, _) = try await URLSession.shared.data(for: request)

                        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let chart = json["chart"] as? [String: Any],
                              let result = (chart["result"] as? [[String: Any]])?.first,
                              let indicators = result["indicators"] as? [String: Any],
                              let quote = (indicators["quote"] as? [[String: Any]])?.first,
                              let closes = quote["close"] as? [Double?],
                              let firstClose = closes.first(where: { $0 != nil }) as? Double else {
                            return (periodKey, nil)
                        }

                        if firstClose > 0 {
                            let change = ((currentPrice - firstClose) / firstClose) * 100
                            return (periodKey, change)
                        }
                    } catch {
                        print("❌ Error fetching \(periodKey) for \(ticker): \(error.localizedDescription)")
                    }

                    return (periodKey, nil)
                }
            }

            for await (period, change) in group {
                if let change = change {
                    periodChanges[period] = change
                    print("✅ Fetched \(period) change for \(ticker): \(String(format: "%.2f", change))%")
                }
            }
        }

        return periodChanges
    }
    
    /// Fetches the current stock price for a given ticker symbol (legacy method for compatibility)
    /// - Parameter ticker: Stock ticker symbol (e.g., "AAPL")
    /// - Returns: Current price as Double, or nil if fetch fails
    func fetchCurrentPrice(for ticker: String) async -> Double? {
        if let stockData = await fetchStockData(for: ticker) {
            return stockData.price
        }
        return nil
    }
    
    /// Fetches current prices for multiple tickers
    /// - Parameter tickers: Array of ticker symbols
    /// - Returns: Dictionary mapping ticker to price
    func fetchPrices(for tickers: [String]) async -> [String: Double] {
        var prices: [String: Double] = [:]
        
        // Fetch prices concurrently
        await withTaskGroup(of: (String, Double?).self) { group in
            for ticker in tickers {
                group.addTask {
                    let price = await self.fetchCurrentPrice(for: ticker)
                    return (ticker, price)
                }
            }
            
            for await (ticker, price) in group {
                if let price = price {
                    prices[ticker] = price
                }
            }
        }
        
        return prices
    }
    
    /// Fetches stock data (price and company name) for multiple tickers
    /// - Parameter tickers: Array of ticker symbols
    /// - Returns: Dictionary mapping ticker to StockData
    func fetchStockData(for tickers: [String]) async -> [String: StockData] {
        var stockDataDict: [String: StockData] = [:]
        
        // Fetch data concurrently
        await withTaskGroup(of: (String, StockData?).self) { group in
            for ticker in tickers {
                let trimmedTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedTicker.isEmpty { continue }
                group.addTask {
                    let data = await self.fetchStockData(for: trimmedTicker)
                    return (trimmedTicker, data)
                }
            }
            
            for await (ticker, data) in group {
                if let data = data {
                    stockDataDict[ticker] = data
                }
            }
        }
        
        return stockDataDict
    }
    
    /// Fetches historical price for a specific time period
    /// - Parameters:
    ///   - ticker: Stock ticker symbol
    ///   - period: Time period string (1d, 5d, 1mo, 3mo, 1y)
    /// - Returns: Price as Double (closing price from the start of the period), or nil if fetch fails
    func fetchHistoricalPrice(for ticker: String, period: String) async -> Double? {
        let trimmedTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmedTicker.isEmpty else { return nil }

        // Skip API calls during UI testing
        if AppEnvironment.isUITesting {
            return 150.0
        }

        // Map period to Yahoo Finance range
        let range: String
        switch period.lowercased() {
        case "1d", "5d":
            range = "5d"
        case "1mo":
            range = "1mo"
        case "3mo":
            range = "3mo"
        case "1y":
            range = "1y"
        default:
            range = "5d"
        }

        let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(trimmedTicker)?interval=1d&range=\(range)"

        guard let url = URL(string: urlString) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

            let (data, _) = try await URLSession.shared.data(for: request)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let chart = json["chart"] as? [String: Any],
                  let result = (chart["result"] as? [[String: Any]])?.first,
                  let indicators = result["indicators"] as? [String: Any],
                  let quote = (indicators["quote"] as? [[String: Any]])?.first,
                  let closes = quote["close"] as? [Double?],
                  let firstClose = closes.first(where: { $0 != nil }) as? Double else {
                return nil
            }

            return firstClose
        } catch {
            print("❌ Error fetching historical price for \(ticker): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Fetches historical prices for all time periods
    /// - Parameter ticker: Stock ticker symbol
    /// - Returns: Dictionary mapping period to price, or nil if fetch fails
    func fetchHistoricalPrices(for ticker: String) async -> [String: Double]? {
        let trimmedTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmedTicker.isEmpty else { return nil }

        // Skip API calls during UI testing
        if AppEnvironment.isUITesting {
            return ["1d": 150.0, "1w": 148.0, "1m": 145.0, "3m": 140.0, "ytd": 135.0]
        }

        var historicalPrices: [String: Double] = [:]

        // Define periods with Yahoo Finance ranges
        let periods: [(String, String)] = [
            ("1d", "5d"),
            ("1w", "5d"),
            ("1m", "1mo"),
            ("3m", "3mo"),
            ("ytd", "ytd")
        ]

        await withTaskGroup(of: (String, Double?).self) { group in
            for (periodKey, range) in periods {
                group.addTask {
                    return await self.fetchHistoricalPriceForRange(ticker: trimmedTicker, range: range, periodKey: periodKey)
                }
            }

            for await (period, price) in group {
                if let price = price {
                    historicalPrices[period] = price
                }
            }
        }

        return historicalPrices.isEmpty ? nil : historicalPrices
    }

    /// Helper function to fetch historical price using Yahoo Finance API directly
    private func fetchHistoricalPriceForRange(ticker: String, range: String, periodKey: String) async -> (String, Double?) {
        // Skip API calls in UI tests
        if AppEnvironment.isUITesting {
            return (periodKey, 150.0)
        }

        let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(ticker)?interval=1d&range=\(range)"

        guard let url = URL(string: urlString) else {
            return (periodKey, nil)
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

            let (data, _) = try await URLSession.shared.data(for: request)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let chart = json["chart"] as? [String: Any],
                  let result = (chart["result"] as? [[String: Any]])?.first,
                  let indicators = result["indicators"] as? [String: Any],
                  let quote = (indicators["quote"] as? [[String: Any]])?.first,
                  let closes = quote["close"] as? [Double?],
                  let firstClose = closes.first(where: { $0 != nil }) as? Double else {
                return (periodKey, nil)
            }

            return (periodKey, firstClose)
        } catch {
            print("❌ Error fetching \(periodKey) price for \(ticker): \(error.localizedDescription)")
            return (periodKey, nil)
        }
    }
    // MARK: - Polygon.io Integration
    
    /// Fetches company information from Polygon.io
    /// - Parameter ticker: Stock ticker symbol (e.g., "AAPL")
    /// - Returns: CompanyInfo with company details, or nil if fetch fails
    /// - Note: Free tier limit: 5 API calls per minute
    func fetchCompanyInfo(fromPolygon ticker: String) async -> CompanyInfo? {
        // Check if API key is set
        guard APIConfig.polygonAPIKey != "YOUR_POLYGON_API_KEY_HERE" else {
            print("⚠️ Polygon.io API key not configured. Get your free API key from https://polygon.io/")
            return nil
        }
        
        let urlString = "https://api.polygon.io/v3/reference/tickers/\(ticker.uppercased())?apiKey=\(APIConfig.polygonAPIKey)"
        
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL for Polygon.io ticker: \(ticker)")
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid HTTP response from Polygon.io for \(ticker)")
                return nil
            }
            
            // Check for rate limiting (429) or other errors
            if httpResponse.statusCode == 429 {
                print("⚠️ Polygon.io rate limit exceeded for \(ticker). Free tier: 5 calls/minute")
                return nil
            }
            
            guard httpResponse.statusCode == 200 else {
                print("❌ Polygon.io API error for \(ticker): Status \(httpResponse.statusCode)")
                if let errorData = String(data: data, encoding: .utf8) {
                    print("Error details: \(errorData.prefix(500))") // Limit output
                }
                return nil
            }
            
            // Debug: Print raw response for troubleshooting (first 500 chars)
            if let responseString = String(data: data, encoding: .utf8) {
                print("🔍 Polygon.io response for \(ticker) (first 500 chars): \(responseString.prefix(500))")
            }
            
            // Parse JSON response
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [String: Any] {
                
                let tickerSymbol = results["ticker"] as? String ?? ticker.uppercased()
                let name = results["name"] as? String ?? ""
                let description = results["description"] as? String
                let homepage = results["homepage_url"] as? String
                
                let market = results["market"] as? String
                let locale = results["locale"] as? String
                let primaryExchange = results["primary_exchange"] as? String
                let type = results["type"] as? String
                let active = results["active"] as? Bool
                let currency = results["currency_name"] as? String
                
                // Market cap and shares
                let marketCap = results["market_cap"] as? Double
                let employees = results["total_employees"] as? Int
                let shareClassSharesOutstanding = results["share_class_shares_outstanding"] as? Int
                let weightedSharesOutstanding = results["weighted_shares_outstanding"] as? Int
                
                // SIC code information
                let sicCode = results["sic_code"] as? String
                let sicDescription = results["sic_description"] as? String
                
                // Additional info
                let totalEmployees = results["total_employees"] as? Int
                let tags = results["tags"] as? [String]
                let similar = results["similar"] as? [String]
                let updated = results["updated_utc"] as? String
                let listDate = results["list_date"] as? String
                
                print("✅ Fetched company info from Polygon.io for \(ticker): \(name)")
                
                return CompanyInfo(
                    ticker: tickerSymbol,
                    name: name,
                    description: description,
                    homepage: homepage,
                    market: market,
                    locale: locale,
                    primaryExchange: primaryExchange,
                    type: type,
                    active: active,
                    currency: currency,
                    marketCap: marketCap,
                    employees: employees,
                    shareClassSharesOutstanding: shareClassSharesOutstanding,
                    weightedSharesOutstanding: weightedSharesOutstanding,
                    sicCode: sicCode,
                    sicDescription: sicDescription,
                    totalEmployees: totalEmployees,
                    tags: tags,
                    similar: similar,
                    updated: updated,
                    listDate: listDate
                )
            } else {
                print("❌ Failed to parse Polygon.io response for \(ticker)")
                return nil
            }
        } catch {
            print("❌ Error fetching company info from Polygon.io for \(ticker): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Fetches company information for multiple tickers from Polygon.io
    /// - Parameter tickers: Array of stock ticker symbols
    /// - Returns: Dictionary mapping ticker to CompanyInfo
    /// - Note: Respects rate limits (5 calls/minute on free tier)
    func fetchCompanyInfo(fromPolygon tickers: [String]) async -> [String: CompanyInfo] {
        var companyInfoDict: [String: CompanyInfo] = [:]
        
        // Process in batches to respect rate limits (5 calls/minute)
        let batchSize = 5
        for i in stride(from: 0, to: tickers.count, by: batchSize) {
            let batch = Array(tickers[i..<min(i + batchSize, tickers.count)])
            
            await withTaskGroup(of: (String, CompanyInfo?).self) { group in
                for ticker in batch {
                    group.addTask {
                        let info = await self.fetchCompanyInfo(fromPolygon: ticker)
                        return (ticker, info)
                    }
                }
                
                for await (ticker, info) in group {
                    if let info = info {
                        companyInfoDict[ticker] = info
                    }
                }
            }
            
            // Wait 60 seconds between batches to respect rate limits (5 calls/minute)
            if i + batchSize < tickers.count {
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
            }
        }
        
        return companyInfoDict
    }
}


