import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

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
    
    // Polygon.io API Key 
    private let polygonAPIKey = "Ds3t3cHooEShvcG3nqYXmBTDBrLauU68" 
    
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
                
                // Fetch company logo from Financial Modeling Prep (free tier)
                let logoURL = await fetchCompanyLogo(for: ticker)
                
                print("✅ Fetched data for \(ticker): $\(regularMarketPrice) - \(companyName)")
                return StockData(price: regularMarketPrice, companyName: companyName, periodChanges: periodChanges.isEmpty ? nil : periodChanges, previousClose: previousClose, logoURL: logoURL)
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
    
    /// Fetches company logo URL using fallback services
    /// - Parameter ticker: Stock ticker symbol
    /// - Returns: Logo URL as String, or nil if fetch fails
    func fetchCompanyLogo(for ticker: String) async -> String? {
        // Try Financial Modeling Prep API (legacy)
        if let logo = await fetchLogoFromFMP(for: ticker) {
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
        let urlString = "https://financialmodelingprep.com/api/v3/profile/\(ticker.uppercased())?apikey=Qadn9INnY2R9FEuFi5PwYRm7cwPp7Zwt"
        
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
        guard polygonAPIKey != "YOUR_POLYGON_API_KEY_HERE" else {
            print("⚠️ Polygon.io API key not configured. Get your free API key from https://polygon.io/")
            return nil
        }
        
        let urlString = "https://api.polygon.io/v3/reference/tickers/\(ticker.uppercased())?apiKey=\(polygonAPIKey)"
        
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


