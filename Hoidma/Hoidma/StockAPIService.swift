import Foundation

// MARK: - Stock API Service

/// Service to fetch real stock data from Yahoo Finance API
/// 
/// Uses Yahoo Finance's public API endpoint (no API key required):
/// - Endpoint: https://query1.finance.yahoo.com/v8/finance/chart/{SYMBOL}
/// - Returns: Current market price, historical data, and metadata
/// - Rate Limits: No official limits, but be respectful (30+ second intervals recommended)
/// 
/// Note: This is an unofficial API endpoint. For production apps, consider:
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
    
    /// Fetches the current stock price and company name for a given ticker symbol
    /// - Parameter ticker: Stock ticker symbol (e.g., "AAPL")
    /// - Returns: StockData with price and company name, or nil if fetch fails
    func fetchStockData(for ticker: String) async -> StockData? {
        let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(ticker.uppercased())"
        
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL for ticker: \(ticker)")
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("❌ Invalid HTTP response for \(ticker)")
                return nil
            }
            
            // Parse JSON response
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let chart = json["chart"] as? [String: Any],
               let result = chart["result"] as? [[String: Any]],
               let firstResult = result.first,
               let meta = firstResult["meta"] as? [String: Any],
               let regularMarketPrice = meta["regularMarketPrice"] as? Double {
                
                // Extract company name from meta data - prioritize longName, then shortName
                // Skip symbol as it's just the ticker
                var companyName: String
                if let longName = meta["longName"] as? String, !longName.isEmpty {
                    companyName = longName
                } else if let shortName = meta["shortName"] as? String, !shortName.isEmpty, shortName != ticker.uppercased() {
                    companyName = shortName
                } else {
                    // Fallback: use ticker if no proper name found
                    companyName = ticker.uppercased()
                }
                
                // Extract percentage changes from meta data
                var periodChanges: [String: Double] = [:]
                
                // Yahoo Finance provides these fields in meta:
                // - regularMarketChangePercent (latest trading day change as percentage, e.g., 2.5 for 2.5%)
                // - chartPreviousClose (previous trading day's close price)
                // We can calculate other periods from historical data
                
                // Get previous close price (latest trading day's close)
                let previousClose = meta["chartPreviousClose"] as? Double
                
                if let dayChange = meta["regularMarketChangePercent"] as? Double {
                    // regularMarketChangePercent is already in percentage format (2.5 = 2.5%)
                    // This represents the change from the previous trading day's close
                    periodChanges["1d"] = dayChange
                    print("📊 Daily change for \(ticker): \(dayChange)% (from previous close: \(previousClose ?? 0))")
                }
                
                // Fetch percentage changes for other periods (1W, 1M, 3M, YTD)
                let historicalChanges = await fetchPeriodChanges(for: ticker, currentPrice: regularMarketPrice)
                periodChanges.merge(historicalChanges) { (_, new) in new }
                print("📊 Period changes for \(ticker): \(periodChanges)")
                
                print("✅ Fetched data for \(ticker): $\(regularMarketPrice) - \(companyName)")
                return StockData(price: regularMarketPrice, companyName: companyName, periodChanges: periodChanges.isEmpty ? nil : periodChanges, previousClose: previousClose)
            } else {
                print("❌ Failed to parse price data for \(ticker)")
                return nil
            }
        } catch {
            print("❌ Error fetching data for \(ticker): \(error.localizedDescription)")
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
        
        // Fetch data for different periods to calculate percentage changes
        let periods: [(String, String)] = [
            ("1w", "5d"),  // 1 week - use 5 day range (trading days)
            ("1m", "1mo"), // 1 month
            ("3m", "3mo"), // 3 months
            ("ytd", "ytd") // Year to date
        ]
        
        print("🔄 Fetching period changes for \(ticker): \(periods.map { $0.0 })")
        
        await withTaskGroup(of: (String, Double?).self) { group in
            for (periodKey, apiRange) in periods {
                group.addTask {
                    let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(ticker.uppercased())?interval=1d&range=\(apiRange)"
                    
                    guard let url = URL(string: urlString) else {
                        return (periodKey, nil)
                    }
                    
                    do {
                        let (data, response) = try await URLSession.shared.data(from: url)
                        
                        guard let httpResponse = response as? HTTPURLResponse,
                              httpResponse.statusCode == 200 else {
                            return (periodKey, nil)
                        }
                        
                        // Parse to get the first (oldest) price in the range
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let chart = json["chart"] as? [String: Any],
                           let result = chart["result"] as? [[String: Any]],
                           let firstResult = result.first,
                           let indicators = firstResult["indicators"] as? [String: Any],
                           let quote = indicators["quote"] as? [[String: Any]],
                           let firstQuote = quote.first,
                           let close = firstQuote["close"] as? [Double?],
                           let startPrice = close.compactMap({ $0 }).first,
                           startPrice > 0 {
                            // Calculate percentage change
                            let change = ((currentPrice - startPrice) / startPrice) * 100
                            return (periodKey, change)
                        }
                    } catch {
                        print("❌ Error fetching period change for \(periodKey): \(error.localizedDescription)")
                    }
                    
                    return (periodKey, nil)
                }
            }
            
            for await (period, change) in group {
                if let change = change {
                    periodChanges[period] = change
                    print("✅ Fetched \(period) change for \(ticker): \(change)%")
                } else {
                    print("⚠️ Failed to fetch \(period) change for \(ticker)")
                }
            }
        }
        
        print("📊 Final period changes for \(ticker): \(periodChanges)")
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
                group.addTask {
                    let data = await self.fetchStockData(for: ticker)
                    return (ticker, data)
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
    ///   - period: Time period (1d, 5d, 1mo, 3mo, 1y)
    /// - Returns: Price as Double (closing price from the start of the period), or nil if fetch fails
    func fetchHistoricalPrice(for ticker: String, period: String) async -> Double? {
        let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(ticker.uppercased())?interval=1d&range=\(period)"
        
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL for historical price: \(ticker)")
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("❌ Invalid HTTP response for historical \(ticker)")
                return nil
            }
            
            // Parse JSON response to get historical prices
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let chart = json["chart"] as? [String: Any],
               let result = chart["result"] as? [[String: Any]],
               let firstResult = result.first,
               let indicators = firstResult["indicators"] as? [String: Any],
               let quote = indicators["quote"] as? [[String: Any]],
               let firstQuote = quote.first,
               let close = firstQuote["close"] as? [Double?],
               let firstValidPrice = close.compactMap({ $0 }).first {
                // Get the first (oldest) price from the period
                return firstValidPrice
            }
            
            return nil
        } catch {
            print("❌ Error fetching historical price for \(ticker): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Fetches historical prices for all time periods
    /// - Parameter ticker: Stock ticker symbol
    /// - Returns: Dictionary mapping period to price, or nil if fetch fails
    func fetchHistoricalPrices(for ticker: String) async -> [String: Double]? {
        var historicalPrices: [String: Double] = [:]
        
        // Fetch prices for different periods concurrently
        await withTaskGroup(of: (String, Double?).self) { group in
            // 1 day ago
            group.addTask {
                let price = await self.fetchHistoricalPrice(for: ticker, period: "5d")
                return ("1d", price)
            }
            
            // 1 week ago
            group.addTask {
                let price = await self.fetchHistoricalPrice(for: ticker, period: "1mo")
                return ("1w", price)
            }
            
            // 1 month ago
            group.addTask {
                let price = await self.fetchHistoricalPrice(for: ticker, period: "3mo")
                return ("1m", price)
            }
            
            // 3 months ago
            group.addTask {
                let price = await self.fetchHistoricalPrice(for: ticker, period: "6mo")
                return ("3m", price)
            }
            
            // Year to date (start of current year)
            group.addTask {
                let calendar = Calendar.current
                let now = Date()
                if let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now)) {
                    let period1 = Int(startOfYear.timeIntervalSince1970)
                    let period2 = Int(now.timeIntervalSince1970)
                    let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(ticker.uppercased())?interval=1d&period1=\(period1)&period2=\(period2)"
                    
                    if let url = URL(string: urlString),
                       let (data, _) = try? await URLSession.shared.data(from: url),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let chart = json["chart"] as? [String: Any],
                       let result = chart["result"] as? [[String: Any]],
                       let firstResult = result.first,
                       let indicators = firstResult["indicators"] as? [String: Any],
                       let quote = indicators["quote"] as? [[String: Any]],
                       let firstQuote = quote.first,
                       let close = firstQuote["close"] as? [Double?],
                       let firstValidPrice = close.compactMap({ $0 }).first {
                        return ("ytd", firstValidPrice)
                    }
                }
                return ("ytd", nil)
            }
            
            for await (period, price) in group {
                if let price = price {
                    historicalPrices[period] = price
                }
            }
        }
        
        return historicalPrices.isEmpty ? nil : historicalPrices
    }
}

