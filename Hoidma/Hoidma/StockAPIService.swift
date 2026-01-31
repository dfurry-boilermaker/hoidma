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
        let logoURL: String? // Company logo URL
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
    
    /// Structure to hold extracted brand colors from a logo
    struct BrandColors {
        let primary: Color? // Dominant color
        let secondary: Color? // Second most common color
        let accent: Color? // Accent color
    }
    
    /// Fetches the current stock price and company name for a given ticker symbol
    /// - Parameter ticker: Stock ticker symbol (e.g., "AAPL")
    /// - Returns: StockData with price and company name, or nil if fetch fails
    /// - Note: Uses SwiftYFinance library for reliable Yahoo Finance API access
    func fetchStockData(for ticker: String) async -> StockData? {
        let trimmedTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTicker.isEmpty else { return nil }
        // CRITICAL: Check BEFORE creating continuation to prevent SwiftYFinance from initializing
        // This prevents crashes during UI testing
        guard !AppEnvironment.isUITesting else {
            AppEnvironment.testingLog(" Skipping API call for \(ticker), returning mock data")
            return StockData(
                price: 150.0, // Mock price
                companyName: ticker.uppercased(),
                periodChanges: nil,
                previousClose: 150.0,
                logoURL: nil
            )
        }
        
        return await withCheckedContinuation { continuation in
            // Fetch recent data using SwiftYFinance
            SwiftYFinance.recentDataBy(identifier: trimmedTicker.uppercased()) { data, error in
                if let error = error {
                    print("❌ Error fetching recent data for \(ticker): \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let stock = data else {
                    print("❌ No data returned for \(ticker)")
                    continuation.resume(returning: nil)
                    return
                }
                
                // Extract price and previous close (SwiftYFinance may return Float, convert to Double)
                let price = Double(stock.regularMarketPrice ?? 0.0)
                let previousClose: Double? = stock.previousClose.map { Double($0) }
                
                // Get company name from summary data
                SwiftYFinance.summaryDataBy(identifier: trimmedTicker.uppercased(), selection: [.price, .summaryProfile]) { summaryData, summaryError in
                    var companyName = trimmedTicker.uppercased()
                    
                    if let summary = summaryData {
                        // Try price module first for company name
                        if let priceModule = summary.price {
                            if let longName = priceModule.longName, !longName.isEmpty {
                                companyName = longName
                            } else if let shortName = priceModule.shortName, !shortName.isEmpty, shortName != ticker.uppercased() {
                                companyName = shortName
                            }
                        }
                        
                        // If still using ticker, try summary profile (though it doesn't have name directly)
                        // The price module should have the name we need
                    }
                    
                    // Fetch percentage changes for different periods
                    Task {
                        var periodChanges: [String: Double] = [:]
                        
                        // Get daily change from recent data
                        if let previousClose = previousClose, previousClose > 0 {
                            let dayChange = ((price - previousClose) / previousClose) * 100
                            periodChanges["1d"] = dayChange
                            print("📊 Daily change for \(ticker): \(dayChange)% (from previous close: \(previousClose))")
                        }
                        
                        // Fetch historical changes for other periods
                        let historicalChanges = await self.fetchPeriodChanges(for: ticker, currentPrice: price)
                        periodChanges.merge(historicalChanges) { (_, new) in new }
                        
                        // Fetch company logo
                        let logoURL = await self.fetchCompanyLogo(for: ticker)
                        
                        print("✅ Fetched data for \(ticker): $\(price) - \(companyName)")
                        let stockData = StockData(
                            price: price,
                            companyName: companyName,
                            periodChanges: periodChanges.isEmpty ? nil : periodChanges,
                            previousClose: previousClose,
                            logoURL: logoURL
                        )
                        continuation.resume(returning: stockData)
                    }
                }
            }
        }
    }
    
    /// Fetches percentage changes for different time periods from the API
    /// - Parameters:
    ///   - ticker: Stock ticker symbol
    ///   - currentPrice: Current price of the stock
    /// - Returns: Dictionary mapping period to percentage change
    private func fetchPeriodChanges(for ticker: String, currentPrice: Double) async -> [String: Double] {
        var periodChanges: [String: Double] = [:]
        
        // Define periods with their date ranges
        let now = Date()
        let calendar = Calendar.current
        let periods: [(String, Date)] = [
            ("1w", calendar.date(byAdding: .day, value: -7, to: now) ?? now),
            ("1m", calendar.date(byAdding: .month, value: -1, to: now) ?? now),
            ("3m", calendar.date(byAdding: .month, value: -3, to: now) ?? now),
            ("ytd", calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now)
        ]
        
        print("🔄 Fetching period changes for \(ticker): \(periods.map { $0.0 })")
        
        await withTaskGroup(of: (String, Double?).self) { group in
            for (periodKey, startDate) in periods {
                group.addTask {
                    // Skip API calls in UI tests
                    if AppEnvironment.isUITesting {
                        return (periodKey, 150.0) // Mock price
                    }
                    
                    return await withCheckedContinuation { continuation in
                        // Use SwiftYFinance to fetch chart data
                        SwiftYFinance.chartDataBy(
                            identifier: ticker.uppercased(),
                            start: startDate,
                            end: now,
                            interval: .oneday
                        ) { chartData, error in
                            if let error = error {
                                print("❌ Error fetching period change for \(periodKey): \(error.localizedDescription)")
                                continuation.resume(returning: (periodKey, nil))
                                return
                            }
                            
                            // Get the first (oldest) price from the chart data
                            if let chart = chartData,
                               let first = chart.first,
                               let closePrice = first.close {
                                let startPrice = Double(closePrice)
                                if startPrice > 0 {
                                    // Calculate percentage change
                                    let change = ((currentPrice - startPrice) / startPrice) * 100
                                    continuation.resume(returning: (periodKey, change))
                                    return
                                }
                            }
                            continuation.resume(returning: (periodKey, nil))
                        }
                    }
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
    ///   - period: Time period string (1d, 5d, 1mo, 3mo, 1y) - converted to Date range
    /// - Returns: Price as Double (closing price from the start of the period), or nil if fetch fails
    /// - Note: Uses SwiftYFinance library for reliable Yahoo Finance API access
    func fetchHistoricalPrice(for ticker: String, period: String) async -> Double? {
        let trimmedTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTicker.isEmpty else { return nil }
        // Skip API calls during UI testing
        if AppEnvironment.isUITesting {
            return 150.0 // Mock historical price
        }
        let calendar = Calendar.current
        let now = Date()
        let startDate: Date
        
        // Convert period string to Date
        switch period.lowercased() {
        case "1d", "5d":
            startDate = calendar.date(byAdding: .day, value: -5, to: now) ?? now
        case "1mo":
            startDate = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case "3mo":
            startDate = calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case "1y":
            startDate = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        default:
            startDate = calendar.date(byAdding: .day, value: -5, to: now) ?? now
        }
        
        // Skip API calls in UI tests
        guard !AppEnvironment.isUITesting else {
            return 150.0 // Mock price
        }
        
        return await withCheckedContinuation { continuation in
            SwiftYFinance.chartDataBy(
                identifier: trimmedTicker.uppercased(),
                start: startDate,
                end: now,
                interval: .oneday
            ) { chartData, error in
                if let error = error {
                    print("❌ Error fetching historical price for \(ticker): \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                
                // Get the first (oldest) price from the chart data (convert Float to Double)
                if let chart = chartData,
                   let first = chart.first,
                   let closePrice = first.close {
                    let price = Double(closePrice)
                    continuation.resume(returning: price)
                    return
                }
                continuation.resume(returning: nil)
            }
        }
    }
    
    /// Fetches historical prices for all time periods
    /// - Parameter ticker: Stock ticker symbol
    /// - Returns: Dictionary mapping period to price, or nil if fetch fails
    /// - Note: Uses SwiftYFinance library for reliable Yahoo Finance API access
    func fetchHistoricalPrices(for ticker: String) async -> [String: Double]? {
        let trimmedTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTicker.isEmpty else { return nil }
        // Skip API calls during UI testing
        if AppEnvironment.isUITesting {
            return ["1d": 150.0, "1w": 148.0, "1m": 145.0, "3m": 140.0, "ytd": 135.0] // Mock historical prices
        }
        var historicalPrices: [String: Double] = [:]
        let calendar = Calendar.current
        let now = Date()
        
        // Fetch prices for different periods concurrently
        await withTaskGroup(of: (String, Double?).self) { group in
            // 1 day ago (use 5 day range to ensure we get data)
            group.addTask {
                let startDate = calendar.date(byAdding: .day, value: -5, to: now) ?? now
                return await self.fetchHistoricalPriceForDateRange(ticker: ticker, start: startDate, end: now, periodKey: "1d")
            }
            
            // 1 week ago
            group.addTask {
                let startDate = calendar.date(byAdding: .day, value: -7, to: now) ?? now
                return await self.fetchHistoricalPriceForDateRange(ticker: ticker, start: startDate, end: now, periodKey: "1w")
            }
            
            // 1 month ago
            group.addTask {
                let startDate = calendar.date(byAdding: .month, value: -1, to: now) ?? now
                return await self.fetchHistoricalPriceForDateRange(ticker: ticker, start: startDate, end: now, periodKey: "1m")
            }
            
            // 3 months ago
            group.addTask {
                let startDate = calendar.date(byAdding: .month, value: -3, to: now) ?? now
                return await self.fetchHistoricalPriceForDateRange(ticker: ticker, start: startDate, end: now, periodKey: "3m")
            }
            
            // Year to date (start of current year)
            group.addTask {
                if let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now)) {
                    return await self.fetchHistoricalPriceForDateRange(ticker: ticker, start: startOfYear, end: now, periodKey: "ytd")
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
    
    /// Helper function to fetch historical price for a date range using SwiftYFinance
    private func fetchHistoricalPriceForDateRange(ticker: String, start: Date, end: Date, periodKey: String) async -> (String, Double?) {
        let trimmedTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTicker.isEmpty else { return (periodKey, nil) }
        // Skip API calls in UI tests
        if AppEnvironment.isUITesting {
            return (periodKey, 150.0) // Mock price
        }
        
        return await withCheckedContinuation { continuation in
            SwiftYFinance.chartDataBy(
                identifier: trimmedTicker.uppercased(),
                start: start,
                end: end,
                interval: .oneday
            ) { chartData, error in
                if let error = error {
                    print("❌ Error fetching \(periodKey) price for \(ticker): \(error.localizedDescription)")
                    continuation.resume(returning: (periodKey, nil))
                    return
                }
                
                if let chart = chartData,
                   let first = chart.first,
                   let closePrice = first.close {
                    let price = Double(closePrice)
                    continuation.resume(returning: (periodKey, price))
                    return
                }
                continuation.resume(returning: (periodKey, nil))
            }
        }
    }
    
    /// Fetches company logo URL using fallback services
    /// - Parameter ticker: Stock ticker symbol
    /// - Returns: Logo URL as String, or nil if fetch fails
    func fetchCompanyLogo(for ticker: String) async -> String? {
        let trimmedTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTicker.isEmpty else { return nil }
        // Skip API calls in UI tests
        if AppEnvironment.isUITesting {
            return nil // No logo in test mode
        }
        
        // Try Financial Modeling Prep API (legacy)
        if let logo = await fetchLogoFromFMP(for: trimmedTicker) {
            print("✅ Using FMP logo for \(ticker): \(logo)")
            return logo
        }
        
        // Final fallback: Try using a pattern-based approach for major companies
        let alternativeLogo = await fetchLogoFromAlternative(for: ticker)
        print("🔄 Using alternative logo URL for \(ticker): \(alternativeLogo ?? "nil")")
        return alternativeLogo
    }
    
    /// Fetches image data from logo URL (for authenticated image loading)
    /// - Parameter ticker: Stock ticker symbol
    /// - Returns: Image data as Data, or nil if fetch fails
    func fetchAuthenticatedLogoImage(for ticker: String) async -> Data? {
        // Get logo URL from Polygon.io
        if let logoURL = await fetchCompanyLogo(for: ticker),
           let url = URL(string: logoURL) {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    return nil
                }
                
                return data
            } catch {
                print("❌ Error fetching logo image for \(ticker): \(error.localizedDescription)")
                return nil
            }
        }
        
        return nil
    }
    
    /// Fetches logo from Financial Modeling Prep (legacy endpoint - may not work for new users)
    private func fetchLogoFromFMP(for ticker: String) async -> String? {
        let urlString = APIConfig.Endpoints.fmpProfile(ticker: ticker)
        
        guard let url = URL(string: urlString) else {
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            
            // Parse JSON response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  !json.isEmpty,
                  let firstResult = json.first else {
                return nil
            }
            
            // Try multiple possible field names for logo
            let possibleLogoFields = ["image", "logo", "logoUrl", "logo_url", "companyLogo", "company_logo"]
            
            for fieldName in possibleLogoFields {
                if let logo = firstResult[fieldName] as? String, !logo.isEmpty, logo != "null" {
                    if logo.hasPrefix("http://") || logo.hasPrefix("https://") {
                        print("✅ Fetched logo for \(ticker) from FMP: \(logo)")
                        return logo
                    }
                }
            }
        } catch {
            // Silently fail and try alternative
        }
        
        return nil
    }
    
    /// Fetches logo using alternative free services or pattern-based URLs
    /// Fallback method when Polygon.io doesn't have a logo
    private func fetchLogoFromAlternative(for ticker: String) async -> String? {
        // Use free logo CDN services as last resort
        // Format: https://companieslogo.com/img/orig/{ticker}.png
        let companiesLogoURL = "https://companieslogo.com/img/orig/\(ticker.lowercased()).png"
        
        // Return the URL - AsyncImage will handle 404s gracefully
        // This is faster than checking each URL first
        print("🔄 Using alternative logo URL for \(ticker): \(companiesLogoURL)")
        return companiesLogoURL
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
    
    // MARK: - Brand Color Extraction
    
    /// Extracts dominant colors from a company logo image
    /// - Parameter logoURL: URL of the company logo
    /// - Returns: BrandColors with primary, secondary, and accent colors, or nil if extraction fails
    func extractBrandColors(fromLogoURL logoURL: String) async -> BrandColors? {
        guard let url = URL(string: logoURL) else {
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else {
                return nil
            }
            
            return extractColors(from: image)
        } catch {
            print("❌ Error fetching logo for color extraction: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Extracts dominant colors from a UIImage
    /// - Parameter image: The image to analyze
    /// - Returns: BrandColors with primary, secondary, and accent colors
    private func extractColors(from image: UIImage) -> BrandColors? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // Create a bitmap context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Sample pixels (every 10th pixel for performance)
        var colorCounts: [UInt32: Int] = [:]
        let sampleStep = 10
        
        for y in stride(from: 0, to: height, by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                let pixelIndex = (y * width + x) * bytesPerPixel
                
                if pixelIndex + 3 < pixelData.count {
                    let r = pixelData[pixelIndex]
                    let g = pixelData[pixelIndex + 1]
                    let b = pixelData[pixelIndex + 2]
                    let a = pixelData[pixelIndex + 3]
                    
                    // Skip transparent or very light pixels
                    if a > 50 {
                        // Skip white/very light colors (likely background)
                        let brightness = (Double(r) + Double(g) + Double(b)) / 3.0
                        if brightness < 240 {
                            let colorKey = (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
                            colorCounts[colorKey, default: 0] += 1
                        }
                    }
                }
            }
        }
        
        // Get top 3 most common colors
        let sortedColors = colorCounts.sorted { $0.value > $1.value }.prefix(3)
        
        var primary: Color?
        var secondary: Color?
        var accent: Color?
        
        for (index, (colorKey, _)) in sortedColors.enumerated() {
            let r = Double((colorKey >> 16) & 0xFF) / 255.0
            let g = Double((colorKey >> 8) & 0xFF) / 255.0
            let b = Double(colorKey & 0xFF) / 255.0
            
            let color = Color(red: r, green: g, blue: b)
            
            switch index {
            case 0:
                primary = color
            case 1:
                secondary = color
            case 2:
                accent = color
            default:
                break
            }
        }
        
        return BrandColors(primary: primary, secondary: secondary, accent: accent)
    }
}


