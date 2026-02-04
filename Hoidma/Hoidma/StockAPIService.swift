import Foundation
import SwiftYFinance
import Supabase
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

// MARK: - Ticker Validation Result

/// Result of ticker validation check
enum TickerValidationResult {
    case valid(StockAPIService.StockData)
    case invalid
    case networkError(Error)
    case cached  // Found in Supabase cache (another user validated it)
}

// MARK: - API Error Types

/// Specific API error types for proper error handling
enum APIError: Error, LocalizedError {
    case invalidURL
    case networkError(underlying: Error)
    case httpError(statusCode: Int, message: String?)
    case rateLimited(retryAfter: TimeInterval?)
    case unauthorized
    case forbidden
    case notFound
    case serverError(statusCode: Int)
    case parseError
    case notConfigured
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError:
            return "Network error"
        case .httpError(let code, _):
            return "HTTP error \(code)"
        case .rateLimited:
            return "Rate limited - please wait"
        case .unauthorized:
            return "Invalid API key"
        case .forbidden:
            return "Access forbidden"
        case .notFound:
            return "Resource not found"
        case .serverError(let code):
            return "Server error \(code)"
        case .parseError:
            return "Failed to parse response"
        case .notConfigured:
            return "API not configured"
        case .timeout:
            return "Request timed out"
        }
    }

    /// Whether this error is transient and should be retried
    var isRetryable: Bool {
        switch self {
        case .networkError, .timeout, .serverError, .rateLimited:
            return true
        default:
            return false
        }
    }
}

// MARK: - Stock API Service

/// Service to fetch real stock data from Yahoo Finance API
///
/// SECURITY FEATURES:
/// - API rate limiting to respect provider limits
/// - Exponential backoff for 429 responses
/// - Proper error categorization and handling
/// - No API keys in URLs for logging
/// - Thread-safe beta cache using actor isolation
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

    /// Rate limiter for API calls
    private let apiRateLimiter = APIRateLimiter()

    /// Default request timeout in seconds
    private let requestTimeout: TimeInterval = 10.0

    /// Maximum retry attempts for transient errors
    private let maxRetryAttempts = 3

    /// Whether to use server-side (Supabase) stock prices instead of direct Yahoo API calls
    /// When true, reads cached prices from Supabase and falls back to Yahoo if needed
    var useServerSidePrices: Bool = true

    private init() {}

    // MARK: - Thread-Safe Beta Cache

    /// Actor for thread-safe beta cache access
    private actor BetaCacheActor {
        private var cache: [String: (beta: Double, timestamp: Date)] = [:]
        private let cacheDuration: TimeInterval = 24 * 60 * 60 // 24 hours

        func get(for ticker: String) -> Double? {
            let key = ticker.uppercased()
            guard let cached = cache[key] else { return nil }

            if Date().timeIntervalSince(cached.timestamp) < cacheDuration {
                return cached.beta
            }

            cache.removeValue(forKey: key)
            return nil
        }

        func set(_ beta: Double, for ticker: String) {
            cache[ticker.uppercased()] = (beta, Date())
        }
    }

    private let betaCacheActor = BetaCacheActor()

    /// Returns cached beta if available and not expired
    private func getCachedBeta(for ticker: String) async -> Double? {
        if let beta = await betaCacheActor.get(for: ticker) {
            AppLogger.debug("\(ticker) beta (cached): \(String(format: "%.2f", beta))")
            return beta
        }
        return nil
    }

    /// Caches a beta value for later use
    private func cacheBeta(_ beta: Double, for ticker: String) async {
        await betaCacheActor.set(beta, for: ticker)
    }

    // MARK: - Data Structures

    /// Structure to hold stock data from API
    struct StockData {
        let price: Double
        let companyName: String
        let periodChanges: [String: Double]? // Percentage changes for different periods
        let previousClose: Double? // Previous trading day's close price
        let beta: Double? // Stock beta (volatility relative to market)
        let isETF: Bool // Whether this is an ETF vs individual stock
        let dataSource: String? // "polygon" (preferred) or "yahoo" (fallback)
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

    // MARK: - HTTP Helpers

    /// Create a URLRequest with proper configuration
    private nonisolated func createRequest(url: URL, timeout: TimeInterval? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout ?? requestTimeout
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Handle HTTP response and convert to appropriate error if needed
    private func handleHTTPResponse(_ response: URLResponse, for endpoint: String) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(underlying: NSError(domain: "Invalid response", code: -1))
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return // Success
        case 401:
            AppLogger.warning("API unauthorized for \(endpoint)")
            throw APIError.unauthorized
        case 403:
            AppLogger.warning("API forbidden for \(endpoint)")
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap { Double($0) }
            AppLogger.warning("API rate limited for \(endpoint)")
            throw APIError.rateLimited(retryAfter: retryAfter)
        case 500..<600:
            AppLogger.warning("API server error \(httpResponse.statusCode) for \(endpoint)")
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        default:
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: nil)
        }
    }

    /// Perform a request with retry logic for transient errors
    private func performRequestWithRetry(
        url: URL,
        endpoint: String,
        attempt: Int = 1
    ) async throws -> Data {
        do {
            let request = createRequest(url: url)
            let (data, response) = try await URLSession.shared.data(for: request)
            try handleHTTPResponse(response, for: endpoint)
            return data
        } catch let error as APIError where error.isRetryable && attempt < maxRetryAttempts {
            // Exponential backoff: 1s, 2s, 4s
            let delay = pow(2.0, Double(attempt - 1))
            AppLogger.debug("Retrying \(endpoint) after \(delay)s (attempt \(attempt + 1)/\(maxRetryAttempts))")
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            return try await performRequestWithRetry(url: url, endpoint: endpoint, attempt: attempt + 1)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw APIError.timeout
        } catch let apiError as APIError {
            throw apiError
        } catch {
            throw APIError.networkError(underlying: error)
        }
    }

    // MARK: - URL Builders (SECURITY: Use URLComponents, never string concatenation with keys)

    /// Build Yahoo Finance chart URL
    private nonisolated func buildYahooChartURL(ticker: String, interval: String = "1d", range: String = "5d") -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "query1.finance.yahoo.com"
        components.path = "/v8/finance/chart/\(ticker.uppercased())"
        components.queryItems = [
            URLQueryItem(name: "interval", value: interval),
            URLQueryItem(name: "range", value: range)
        ]
        return components.url
    }

    /// Build Yahoo Finance quote summary URL
    private func buildYahooQuoteSummaryURL(ticker: String, modules: [String]) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "query1.finance.yahoo.com"
        components.path = "/v10/finance/quoteSummary/\(ticker.uppercased())"
        components.queryItems = [
            URLQueryItem(name: "modules", value: modules.joined(separator: ","))
        ]
        return components.url
    }

    /// Build FMP profile URL (SECURITY: Uses APIConfig.Endpoints which handles key safely)
    private func buildFMPProfileURL(ticker: String) -> URL? {
        return APIConfig.Endpoints.fmpProfile(ticker: ticker)
    }

    /// Build Polygon ticker info URL (SECURITY: Uses APIConfig.Endpoints which handles key safely)
    private func buildPolygonTickerURL(ticker: String) -> URL? {
        return APIConfig.Endpoints.polygonTickerInfo(ticker: ticker)
    }

    // MARK: - Public API

    /// Fetches the current stock price and company name for a given ticker symbol
    /// - Parameter ticker: Stock ticker symbol (e.g., "AAPL")
    /// - Returns: StockData with price and company name, or nil if fetch fails
    /// - Note: Uses Polygon.io as primary source with Yahoo Finance fallback
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
                previousClose: 150.0,
                beta: 1.0,
                isETF: false,
                dataSource: "mock"
            )
        }

        // PRIORITY 1: Try Polygon.io (primary source)
        if APIConfig.isPolygonConfigured {
            if let polygonData = await fetchPriceFromPolygon(for: trimmedTicker) {
                AppLogger.info("✅ Fetched \(trimmedTicker) from Polygon.io (primary)")
                return polygonData.toStockData()
            }
            AppLogger.warning("⚠️ Polygon.io failed for \(trimmedTicker), falling back to Yahoo Finance")
        } else {
            AppLogger.debug("Polygon.io not configured, using Yahoo Finance")
        }

        // FALLBACK: Yahoo Finance (emergency only)
        if let yahooData = await fetchStockDataDirect(for: trimmedTicker) {
            AppLogger.info("📊 Fetched \(trimmedTicker) from Yahoo Finance (fallback)")
            return yahooData
        }

        AppLogger.error("❌ All data sources failed for \(trimmedTicker)")
        return nil
    }

    /// Direct Yahoo Finance API call without SwiftYFinance library
    private func fetchStockDataDirect(for ticker: String) async -> StockData? {
        guard let url = buildYahooChartURL(ticker: ticker) else {
            AppLogger.error("Invalid URL for ticker: \(ticker)")
            return nil
        }

        do {
            let data = try await performRequestWithRetry(url: url, endpoint: "yahoo-chart-\(ticker)")

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let chart = json["chart"] as? [String: Any],
                  let result = (chart["result"] as? [[String: Any]])?.first,
                  let meta = result["meta"] as? [String: Any] else {
                AppLogger.warning("Failed to parse response for \(ticker)")
                return nil
            }

            // Extract price data
            let price = meta["regularMarketPrice"] as? Double ?? 0.0
            let companyName = (meta["longName"] as? String) ?? (meta["shortName"] as? String) ?? ticker

            // PRIORITY 1: meta.previousClose (official previous trading day close)
            var previousClose: Double? = nil

            // Helper to extract Double from various formats Yahoo might return
            func extractDouble(from value: Any?) -> Double? {
                if let d = value as? Double, d > 0 { return d }
                if let n = value as? NSNumber { return n.doubleValue > 0 ? n.doubleValue : nil }
                if let i = value as? Int, i > 0 { return Double(i) }
                // Handle nested dict format: {"raw": 196.38, "fmt": "196.38"}
                if let dict = value as? [String: Any], let raw = dict["raw"] as? Double, raw > 0 { return raw }
                return nil
            }

            // Log what's in meta for debugging
            let prevCloseValue = meta["previousClose"]
            let regMarketPrevClose = meta["regularMarketPreviousClose"]
            let chartPrevClose = meta["chartPreviousClose"]
            AppLogger.debug("\(ticker) META DEBUG - previousClose: \(String(describing: prevCloseValue)) (type: \(type(of: prevCloseValue)))")
            AppLogger.debug("\(ticker) META DEBUG - regularMarketPreviousClose: \(String(describing: regMarketPrevClose))")
            AppLogger.debug("\(ticker) META DEBUG - chartPreviousClose: \(String(describing: chartPrevClose))")
            AppLogger.debug("\(ticker) META DEBUG - regularMarketPrice: \(String(describing: meta["regularMarketPrice"]))")
            AppLogger.debug("\(ticker) META DEBUG - all keys: \(meta.keys.sorted())")

            if let pc = extractDouble(from: prevCloseValue) {
                previousClose = pc
                AppLogger.debug("\(ticker): Using meta.previousClose = \(pc)")
            }
            // PRIORITY 2: meta.regularMarketPreviousClose
            else if let pc = extractDouble(from: regMarketPrevClose) {
                previousClose = pc
                AppLogger.debug("\(ticker): Using meta.regularMarketPreviousClose = \(pc)")
            }
            // NOTE: chartPreviousClose is NOT used - it represents the close from the START
            // of the chart range (e.g., 5 days ago), not yesterday's close
            // PRIORITY 3: Use closes array - ALWAYS use second-to-last for previousClose
            // With daily interval, the array structure is: [..., yesterday, today]
            // count-1 = today's close, count-2 = yesterday's close (what we need)
            else if let indicators = result["indicators"] as? [String: Any],
                    let quote = (indicators["quote"] as? [[String: Any]])?.first,
                    let closes = quote["close"] as? [Double?] {

                let validCloses = closes.compactMap { $0 }
                AppLogger.debug("\(ticker) CLOSES DEBUG - count: \(validCloses.count), ALL values: \(validCloses)")

                // With range=5d on Feb 3rd: [Jan 29, Jan 30, Jan 31, Feb 2, Feb 3]
                // count-1 = Feb 3 (today's close)
                // count-2 = Feb 2 (yesterday's close) <-- THIS IS WHAT WE NEED
                if validCloses.count >= 2 {
                    previousClose = validCloses[validCloses.count - 2]
                    AppLogger.debug("\(ticker): Using closes[count-2] as previousClose = \(previousClose!) (yesterday)")
                } else if let lastClose = validCloses.last, lastClose > 0 {
                    previousClose = lastClose
                    AppLogger.debug("\(ticker): Only \(validCloses.count) close(s), using last = \(lastClose)")
                }
            }

            // Validation: reject if implies >100% daily change (very rare, likely data error)
            if let pc = previousClose, price > 0 {
                let ratio = price / pc
                if ratio < 0.5 || ratio > 2.0 {
                    AppLogger.warning("\(ticker): previousClose \(pc) invalid relative to price \(price), discarding")
                    previousClose = nil
                }
            }

            // Calculate daily change
            var periodChanges: [String: Double] = [:]
            if let prevClose = previousClose, prevClose > 0 {
                let dayChange = ((price - prevClose) / prevClose) * 100
                periodChanges["1d"] = dayChange
                AppLogger.debug("\(ticker) daily change: \(String(format: "%.2f", dayChange))% (prevClose: \(prevClose), price: \(price))")
            }

            AppLogger.info("Fetched data for \(ticker): $\(String(format: "%.2f", price))")

            // Fetch beta and quote type from quoteSummary endpoint
            let (beta, isETF) = await fetchBetaAndQuoteType(for: ticker)

            return StockData(
                price: price,
                companyName: companyName,
                periodChanges: periodChanges.isEmpty ? nil : periodChanges,
                previousClose: previousClose,
                beta: beta,
                isETF: isETF,
                dataSource: "yahoo"
            )
        } catch {
            // SECURITY: Don't log URLs with API keys
            AppLogger.error("Error fetching stock data for \(ticker): \(error.localizedDescription)")
            return nil
        }
    }

    /// Fetches beta from Financial Modeling Prep API (more reliable than Yahoo)
    /// Uses 24-hour cache to minimize API calls (250/day limit)
    /// - Parameter ticker: Stock ticker symbol
    /// - Returns: Beta value or nil if unavailable
    private func fetchBetaFromFMP(for ticker: String) async -> Double? {
        // Check cache first (beta changes slowly, so 24-hour cache is fine)
        if let cachedBeta = await getCachedBeta(for: ticker) {
            return cachedBeta
        }

        // Check if API key is configured
        guard APIConfig.isFMPConfigured else {
            AppLogger.warning("FMP API key not configured - beta fetch will use Yahoo fallback")
            return nil
        }

        // Check rate limit
        let canRequest = await apiRateLimiter.canMakeRequest(endpoint: "fmp", config: .fmp)
        guard canRequest else {
            AppLogger.warning("FMP rate limit reached for \(ticker) - beta fetch will use Yahoo fallback")
            return nil
        }

        guard let url = buildFMPProfileURL(ticker: ticker) else {
            AppLogger.error("Invalid FMP URL for ticker: \(ticker)")
            return nil
        }

        // Record the request
        await apiRateLimiter.recordRequest(endpoint: "fmp")

        do {
            let data = try await performRequestWithRetry(url: url, endpoint: "fmp-profile-\(ticker)")

            // FMP returns an array with one profile object
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let profile = jsonArray.first else {
                // Log first 500 chars of response to debug format issues
                let responsePreview = String(data: data.prefix(500), encoding: .utf8) ?? "unable to decode"
                AppLogger.warning("FMP response for \(ticker) unexpected format: \(responsePreview)")
                return nil
            }

            // Extract beta from profile
            if let beta = profile["beta"] as? Double {
                AppLogger.info("BETA DEBUG: \(ticker) beta found from FMP: \(String(format: "%.2f", beta))")
                // Cache the beta value to reduce future API calls
                await cacheBeta(beta, for: ticker)
                return beta
            } else {
                // Log available keys to help debug
                let availableKeys = profile.keys.joined(separator: ", ")
                AppLogger.warning("\(ticker) beta not found in FMP profile. Available keys: \(availableKeys)")
                return nil
            }
        } catch {
            AppLogger.warning("Error fetching beta from FMP for \(ticker): \(error.localizedDescription)")
            return nil
        }
    }

    /// Fetches beta and quote type using static fallback map (primary) or cache
    /// Note: FMP and Yahoo quoteSummary APIs are now restricted (403/401 errors as of late 2025)
    /// - Parameter ticker: Stock ticker symbol
    /// - Returns: Tuple of (beta, isETF) - beta may be nil, isETF defaults to false
    private func fetchBetaAndQuoteType(for ticker: String) async -> (beta: Double?, isETF: Bool) {
        let upperTicker = ticker.uppercased()

        // 1. Check static fallback map FIRST (most reliable, avoids broken API calls)
        if let staticBeta = StockAPIService.betaFallbackMap[upperTicker] {
            AppLogger.info("BETA DEBUG: \(upperTicker) beta from static map: \(String(format: "%.2f", staticBeta))")
            // Check ETF status from static set
            let isETF = StockAPIService.etfTickers.contains(upperTicker)
            return (staticBeta, isETF)
        }

        // 2. Check cache (from any previous successful API calls)
        if let cachedBeta = await getCachedBeta(for: upperTicker) {
            let isETF = StockAPIService.etfTickers.contains(upperTicker)
            AppLogger.info("BETA DEBUG: \(upperTicker) beta from cache: \(String(format: "%.2f", cachedBeta))")
            return (cachedBeta, isETF)
        }

        // 3. Stock not in static map - API calls are unreliable (FMP: 403, Yahoo: 401)
        //    Log at debug level and return nil gracefully
        AppLogger.debug("BETA DEBUG: \(upperTicker) not in static map or cache, beta unavailable")
        let isETF = StockAPIService.etfTickers.contains(upperTicker)
        return (nil, isETF)
    }

    /// Fetches beta and quote type from Yahoo Finance quoteSummary API
    /// - Parameter ticker: Stock ticker symbol
    /// - Returns: Tuple of (beta, isETF) - beta may be nil, isETF defaults to false
    private func fetchBetaAndQuoteTypeFromYahoo(for ticker: String) async -> (beta: Double?, isETF: Bool) {
        guard let url = buildYahooQuoteSummaryURL(ticker: ticker, modules: ["defaultKeyStatistics", "quoteType"]) else {
            return (nil, false)
        }

        do {
            let data = try await performRequestWithRetry(url: url, endpoint: "yahoo-summary-\(ticker)")

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let quoteSummary = json["quoteSummary"] as? [String: Any],
                  let result = (quoteSummary["result"] as? [[String: Any]])?.first else {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let quoteSummary = json["quoteSummary"] as? [String: Any],
                   let error = quoteSummary["error"] as? [String: Any] {
                    AppLogger.warning("Yahoo API error for \(ticker) beta fetch: \(error)")
                } else {
                    // Log response preview for debugging
                    let responsePreview = String(data: data.prefix(500), encoding: .utf8) ?? "unable to decode"
                    AppLogger.warning("Yahoo quoteSummary parse failed for \(ticker): \(responsePreview)")
                }
                return (nil, false)
            }

            // Extract beta - handle multiple possible formats from Yahoo Finance
            var beta: Double? = nil
            if let keyStatistics = result["defaultKeyStatistics"] as? [String: Any] {
                let betaValue = keyStatistics["beta"]

                // Format 1: {"raw": 1.23, "fmt": "1.23"} - nested dict with raw value
                if let betaDict = betaValue as? [String: Any],
                   let rawBeta = betaDict["raw"] as? Double {
                    beta = rawBeta
                    AppLogger.info("BETA DEBUG: \(ticker) beta from Yahoo (nested format): \(String(format: "%.2f", rawBeta))")
                }
                // Format 2: Direct Double value
                else if let directBeta = betaValue as? Double {
                    beta = directBeta
                    AppLogger.info("BETA DEBUG: \(ticker) beta from Yahoo (direct format): \(String(format: "%.2f", directBeta))")
                }
                // Format 3: NSNumber (can happen with JSON parsing)
                else if let numberBeta = betaValue as? NSNumber {
                    beta = numberBeta.doubleValue
                    AppLogger.info("BETA DEBUG: \(ticker) beta from Yahoo (NSNumber format): \(String(format: "%.2f", numberBeta.doubleValue))")
                }
                // Format 4: String that can be converted to Double
                else if let stringBeta = betaValue as? String,
                        let parsedBeta = Double(stringBeta) {
                    beta = parsedBeta
                    AppLogger.info("BETA DEBUG: \(ticker) beta from Yahoo (string format): \(String(format: "%.2f", parsedBeta))")
                }
                // Log if beta field exists but in unexpected format
                else if betaValue != nil && !(betaValue is NSNull) {
                    AppLogger.warning("BETA DEBUG: \(ticker) Yahoo beta exists but unexpected type: \(type(of: betaValue))")
                }
                // Beta is null or missing
                else {
                    AppLogger.debug("BETA DEBUG: \(ticker) Yahoo defaultKeyStatistics has no beta field")
                }
            } else {
                AppLogger.debug("BETA DEBUG: \(ticker) Yahoo response missing defaultKeyStatistics module")
            }

            // Extract quote type to detect ETFs
            var isETF = false
            if let quoteType = result["quoteType"] as? [String: Any],
               let quoteTypeStr = quoteType["quoteType"] as? String {
                isETF = quoteTypeStr == "ETF"
                if isETF {
                    AppLogger.debug("\(ticker) is an ETF")
                }
            }

            return (beta, isETF)
        } catch {
            AppLogger.warning("Could not fetch beta/quoteType from Yahoo for \(ticker): \(error.localizedDescription)")
            return (nil, false)
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

        AppLogger.debug("Fetching period changes for \(ticker)")

        await withTaskGroup(of: (String, Double?).self) { group in
            for (periodKey, range) in periods {
                group.addTask {
                    guard let url = self.buildYahooChartURL(ticker: ticker, range: range) else {
                        return (periodKey, nil)
                    }

                    do {
                        let request = self.createRequest(url: url)
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
                        AppLogger.debug("Error fetching \(periodKey) for \(ticker)")
                    }

                    return (periodKey, nil)
                }
            }

            for await (period, change) in group {
                if let change = change {
                    periodChanges[period] = change
                    AppLogger.debug("Fetched \(period) change for \(ticker): \(String(format: "%.2f", change))%")
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

        guard let url = buildYahooChartURL(ticker: trimmedTicker, range: range) else { return nil }

        do {
            let data = try await performRequestWithRetry(url: url, endpoint: "yahoo-historical-\(trimmedTicker)")

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
            AppLogger.debug("Error fetching historical price for \(ticker)")
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

        guard let url = buildYahooChartURL(ticker: ticker, range: range) else {
            return (periodKey, nil)
        }

        do {
            let request = createRequest(url: url)
            let (data, _) = try await URLSession.shared.data(for: request)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let chart = json["chart"] as? [String: Any],
                  let result = (chart["result"] as? [[String: Any]])?.first else {
                return (periodKey, nil)
            }

            // For "1d", get meta.previousClose directly (more reliable than array indexing)
            if periodKey == "1d" {
                if let meta = result["meta"] as? [String: Any] {
                    // Helper to extract Double from various formats Yahoo might return
                    func extractDouble(from value: Any?) -> Double? {
                        if let d = value as? Double, d > 0 { return d }
                        if let n = value as? NSNumber { return n.doubleValue > 0 ? n.doubleValue : nil }
                        if let i = value as? Int, i > 0 { return Double(i) }
                        // Handle nested dict format: {"raw": 196.38, "fmt": "196.38"}
                        if let dict = value as? [String: Any], let raw = dict["raw"] as? Double, raw > 0 { return raw }
                        return nil
                    }

                    if let pc = extractDouble(from: meta["previousClose"]) {
                        AppLogger.debug("Historical 1d for \(ticker): meta.previousClose = \(pc)")
                        return (periodKey, pc)
                    }
                    if let pc = extractDouble(from: meta["regularMarketPreviousClose"]) {
                        AppLogger.debug("Historical 1d for \(ticker): meta.regularMarketPreviousClose = \(pc)")
                        return (periodKey, pc)
                    }
                    // NOTE: chartPreviousClose is NOT used - it's the close from the START of
                    // the chart range (e.g., 5 days ago), not yesterday's close
                }

                // Fallback: use closes array - ALWAYS use second-to-last for yesterday
                // With daily interval: [..., yesterday, today]
                // count-2 = yesterday's close (what we need for 1D)
                if let indicators = result["indicators"] as? [String: Any],
                   let quote = (indicators["quote"] as? [[String: Any]])?.first,
                   let closes = quote["close"] as? [Double?] {

                    let validCloses = closes.compactMap { $0 }

                    if validCloses.count >= 2 {
                        let prevClose = validCloses[validCloses.count - 2]
                        AppLogger.debug("Historical 1d for \(ticker): closes[count-2] = \(prevClose)")
                        return (periodKey, prevClose)
                    } else if let lastClose = validCloses.last, lastClose > 0 {
                        AppLogger.debug("Historical 1d for \(ticker): using only available close = \(lastClose)")
                        return (periodKey, lastClose)
                    }
                }
                return (periodKey, nil)
            }

            // For other periods (1w, 1m, 3m, ytd), use first valid close
            guard let indicators = result["indicators"] as? [String: Any],
                  let quote = (indicators["quote"] as? [[String: Any]])?.first,
                  let closes = quote["close"] as? [Double?] else {
                return (periodKey, nil)
            }

            let validCloses = closes.compactMap { $0 }
            guard !validCloses.isEmpty else {
                return (periodKey, nil)
            }

            return (periodKey, validCloses[0])
        } catch {
            AppLogger.debug("Error fetching \(periodKey) price for \(ticker)")
            return (periodKey, nil)
        }
    }

    // MARK: - Sector Information

    /// Comprehensive sector mapping for S&P 500 and popular stocks
    /// Using GICS sector classification
    private static let sectorFallbackMap: [String: String] = [
        // Technology (Information Technology)
        "AAPL": "Technology", "MSFT": "Technology", "GOOGL": "Technology", "GOOG": "Technology",
        "NVDA": "Technology", "META": "Technology", "AVGO": "Technology", "ORCL": "Technology",
        "CRM": "Technology", "ADBE": "Technology", "AMD": "Technology", "INTC": "Technology",
        "CSCO": "Technology", "IBM": "Technology", "QCOM": "Technology", "TXN": "Technology",
        "NOW": "Technology", "AMAT": "Technology", "MU": "Technology", "LRCX": "Technology",
        "INTU": "Technology", "SNPS": "Technology", "CDNS": "Technology", "KLAC": "Technology",
        "ADI": "Technology", "PANW": "Technology", "MCHP": "Technology", "FTNT": "Technology",
        "NXPI": "Technology", "ON": "Technology", "MPWR": "Technology",
        "CRWD": "Technology", "DDOG": "Technology", "ZS": "Technology", "TEAM": "Technology",
        "WDAY": "Technology", "SNOW": "Technology", "NET": "Technology", "MDB": "Technology",
        "PLTR": "Technology", "U": "Technology", "PATH": "Technology", "DOCN": "Technology",
        "HPQ": "Technology", "HPE": "Technology", "DELL": "Technology", "WDC": "Technology",
        "STX": "Technology", "KEYS": "Technology", "TEL": "Technology", "GLW": "Technology",
        "APH": "Technology", "IT": "Technology", "EPAM": "Technology", "AKAM": "Technology",
        "CTSH": "Technology", "ACN": "Technology", "FFIV": "Technology", "JNPR": "Technology",
        "GEN": "Technology", "NTAP": "Technology", "ZBRA": "Technology", "TYL": "Technology",
        "PAYC": "Technology", "ADSK": "Technology", "ANSS": "Technology",
        "PTC": "Technology", "SPLK": "Technology", "OKTA": "Technology", "VEEV": "Technology",
        "HUBS": "Technology", "TWLO": "Technology", "SQ": "Technology", "SHOP": "Technology",
        "ROP": "Technology", "CDW": "Technology", "GDDY": "Technology",
        "FICO": "Technology", "TDY": "Technology", "VRSN": "Technology", "SWKS": "Technology",
        "TER": "Technology", "TRMB": "Technology", "SMCI": "Technology", "APP": "Technology",
        "QRVO": "Technology", "ANET": "Technology",

        // Healthcare
        "UNH": "Healthcare", "JNJ": "Healthcare", "LLY": "Healthcare", "PFE": "Healthcare",
        "ABBV": "Healthcare", "MRK": "Healthcare", "TMO": "Healthcare", "ABT": "Healthcare",
        "DHR": "Healthcare", "BMY": "Healthcare", "AMGN": "Healthcare", "MDT": "Healthcare",
        "GILD": "Healthcare", "VRTX": "Healthcare", "ISRG": "Healthcare", "REGN": "Healthcare",
        "SYK": "Healthcare", "BSX": "Healthcare", "ZTS": "Healthcare", "BDX": "Healthcare",
        "CVS": "Healthcare", "CI": "Healthcare", "ELV": "Healthcare", "HUM": "Healthcare",
        "CNC": "Healthcare", "MCK": "Healthcare", "CAH": "Healthcare", "ABC": "Healthcare",
        "BIIB": "Healthcare", "MRNA": "Healthcare", "ILMN": "Healthcare", "DXCM": "Healthcare",
        "IQV": "Healthcare", "MTD": "Healthcare", "A": "Healthcare", "WAT": "Healthcare",
        "IDXX": "Healthcare", "EW": "Healthcare", "ALGN": "Healthcare", "HOLX": "Healthcare",
        "COO": "Healthcare", "RMD": "Healthcare", "BAX": "Healthcare", "ZBH": "Healthcare",
        "TECH": "Healthcare", "HCA": "Healthcare", "GEHC": "Healthcare", "MOH": "Healthcare",
        "CRL": "Healthcare", "DGX": "Healthcare", "LH": "Healthcare", "INCY": "Healthcare",
        "SGEN": "Healthcare", "BMRN": "Healthcare", "EXAS": "Healthcare", "PODD": "Healthcare",
        "KVUE": "Healthcare", "COR": "Healthcare", "WST": "Healthcare", "STE": "Healthcare",
        "RVTY": "Healthcare", "VTRS": "Healthcare", "HSIC": "Healthcare", "UHS": "Healthcare",
        "SOLV": "Healthcare", "DVA": "Healthcare",

        // Financials
        "BRK.A": "Financials", "BRK.B": "Financials", "JPM": "Financials", "V": "Financials",
        "MA": "Financials", "BAC": "Financials", "WFC": "Financials", "GS": "Financials",
        "MS": "Financials", "BLK": "Financials", "C": "Financials", "AXP": "Financials",
        "SCHW": "Financials", "SPGI": "Financials", "CB": "Financials", "MMC": "Financials",
        "PGR": "Financials", "AON": "Financials", "CME": "Financials", "ICE": "Financials",
        "USB": "Financials", "PNC": "Financials", "TFC": "Financials", "AIG": "Financials",
        "MET": "Financials", "PRU": "Financials", "AFL": "Financials", "TRV": "Financials",
        "ALL": "Financials", "AMP": "Financials", "BK": "Financials", "STT": "Financials",
        "NTRS": "Financials", "COF": "Financials", "DFS": "Financials", "SYF": "Financials",
        "FIS": "Financials", "FISV": "Financials", "GPN": "Financials", "PYPL": "Financials",
        "MCO": "Financials", "MSCI": "Financials", "NDAQ": "Financials", "CBOE": "Financials",
        "FRC": "Financials", "SIVB": "Financials", "FITB": "Financials", "RF": "Financials",
        "CFG": "Financials", "KEY": "Financials", "HBAN": "Financials", "MTB": "Financials",
        "ALLY": "Financials", "COIN": "Financials", "HOOD": "Financials", "SOFI": "Financials",
        "ACGL": "Financials", "TROW": "Financials", "WTW": "Financials", "RJF": "Financials",
        "FLT": "Financials", "IBKR": "Financials", "BRO": "Financials", "PFG": "Financials",
        "FDS": "Financials", "CINF": "Financials", "EG": "Financials", "WRB": "Financials",
        "L": "Financials", "JKHY": "Financials", "APO": "Financials", "GL": "Financials",
        "ERIE": "Financials", "KKR": "Financials", "BEN": "Financials", "AIZ": "Financials",
        "IVZ": "Financials", "BX": "Financials", "MKTX": "Financials", "HIG": "Financials",
        "EWBC": "Financials", "CMA": "Financials", "ZION": "Financials", "FCNCA": "Financials",

        // Consumer Discretionary
        "AMZN": "Consumer Discretionary", "TSLA": "Consumer Discretionary", "HD": "Consumer Discretionary",
        "MCD": "Consumer Discretionary", "NKE": "Consumer Discretionary", "SBUX": "Consumer Discretionary",
        "LOW": "Consumer Discretionary", "TJX": "Consumer Discretionary", "BKNG": "Consumer Discretionary",
        "CMG": "Consumer Discretionary", "MAR": "Consumer Discretionary", "HLT": "Consumer Discretionary",
        "ORLY": "Consumer Discretionary", "AZO": "Consumer Discretionary", "ROST": "Consumer Discretionary",
        "DHI": "Consumer Discretionary", "LEN": "Consumer Discretionary", "PHM": "Consumer Discretionary",
        "NVR": "Consumer Discretionary", "GM": "Consumer Discretionary", "F": "Consumer Discretionary",
        "RIVN": "Consumer Discretionary", "LCID": "Consumer Discretionary", "YUM": "Consumer Discretionary",
        "DPZ": "Consumer Discretionary", "WYNN": "Consumer Discretionary", "LVS": "Consumer Discretionary",
        "MGM": "Consumer Discretionary", "RCL": "Consumer Discretionary", "CCL": "Consumer Discretionary",
        "NCLH": "Consumer Discretionary", "EXPE": "Consumer Discretionary", "ABNB": "Consumer Discretionary",
        "EBAY": "Consumer Discretionary", "ETSY": "Consumer Discretionary", "W": "Consumer Discretionary",
        "CHWY": "Consumer Discretionary", "BBY": "Consumer Discretionary", "ULTA": "Consumer Discretionary",
        "LULU": "Consumer Discretionary", "GPS": "Consumer Discretionary", "KSS": "Consumer Discretionary",
        "M": "Consumer Discretionary", "JWN": "Consumer Discretionary", "DECK": "Consumer Discretionary",
        "GRMN": "Consumer Discretionary", "POOL": "Consumer Discretionary", "DRI": "Consumer Discretionary",
        "APTV": "Consumer Discretionary", "TSCO": "Consumer Discretionary", "GPC": "Consumer Discretionary",
        "HAS": "Consumer Discretionary", "BBWI": "Consumer Discretionary", "TPR": "Consumer Discretionary",
        "RL": "Consumer Discretionary", "WSM": "Consumer Discretionary", "CVNA": "Consumer Discretionary",
        "BWA": "Consumer Discretionary", "LEG": "Consumer Discretionary", "MHK": "Consumer Discretionary",
        "WHR": "Consumer Discretionary", "PVH": "Consumer Discretionary", "VFC": "Consumer Discretionary",
        "PENN": "Consumer Discretionary", "CZR": "Consumer Discretionary", "LKQ": "Consumer Discretionary",
        "AAP": "Consumer Discretionary",

        // Communication Services
        "NFLX": "Communication Services", "DIS": "Communication Services", "CMCSA": "Communication Services",
        "VZ": "Communication Services", "T": "Communication Services", "TMUS": "Communication Services",
        "CHTR": "Communication Services", "WBD": "Communication Services", "PARA": "Communication Services",
        "FOX": "Communication Services", "FOXA": "Communication Services", "NWSA": "Communication Services",
        "NWS": "Communication Services", "OMC": "Communication Services", "IPG": "Communication Services",
        "EA": "Communication Services", "TTWO": "Communication Services", "ATVI": "Communication Services",
        "MTCH": "Communication Services", "ZG": "Communication Services", "Z": "Communication Services",
        "PINS": "Communication Services", "SNAP": "Communication Services", "SPOT": "Communication Services",
        "ROKU": "Communication Services", "RBLX": "Communication Services", "LYFT": "Communication Services",
        "UBER": "Communication Services", "DASH": "Communication Services", "TTD": "Communication Services",
        "LYV": "Communication Services", "LIVE": "Communication Services", "SIRI": "Communication Services",
        "TKO": "Communication Services", "WMG": "Communication Services",

        // Industrials
        "UNP": "Industrials", "HON": "Industrials", "UPS": "Industrials", "BA": "Industrials",
        "CAT": "Industrials", "RTX": "Industrials", "DE": "Industrials", "LMT": "Industrials",
        "GE": "Industrials", "MMM": "Industrials", "GD": "Industrials", "NOC": "Industrials",
        "FDX": "Industrials", "NSC": "Industrials", "CSX": "Industrials", "EMR": "Industrials",
        "ETN": "Industrials", "ITW": "Industrials", "PH": "Industrials", "ROK": "Industrials",
        "CMI": "Industrials", "PCAR": "Industrials", "CARR": "Industrials", "OTIS": "Industrials",
        "WM": "Industrials", "RSG": "Industrials", "LUV": "Industrials", "DAL": "Industrials",
        "UAL": "Industrials", "AAL": "Industrials", "JBHT": "Industrials", "XPO": "Industrials",
        "EXPD": "Industrials", "CHRW": "Industrials", "FAST": "Industrials", "CPRT": "Industrials",
        "VRSK": "Industrials", "PWR": "Industrials", "AME": "Industrials", "IR": "Industrials",
        "DOV": "Industrials", "TT": "Industrials", "SWK": "Industrials", "NDSN": "Industrials",
        "IEX": "Industrials", "GWW": "Industrials", "ODFL": "Industrials", "URI": "Industrials",
        "TDG": "Industrials", "HWM": "Industrials", "WAB": "Industrials", "LDOS": "Industrials",
        "J": "Industrials", "CTAS": "Industrials", "PAYX": "Industrials", "RHI": "Industrials",
        "EFX": "Industrials", "BR": "Industrials", "EME": "Industrials", "TXT": "Industrials",
        "SNA": "Industrials", "AXON": "Industrials", "MAS": "Industrials", "CDAY": "Industrials",
        "PNR": "Industrials", "ALLE": "Industrials", "ROL": "Industrials", "BLDR": "Industrials",
        "AOS": "Industrials", "HII": "Industrials", "LII": "Industrials", "GNRC": "Industrials",
        "FIX": "Industrials", "VLTO": "Industrials", "HUBB": "Industrials",
        "GGG": "Industrials", "RRX": "Industrials", "TTC": "Industrials",
        "LECO": "Industrials", "NWL": "Industrials",
        "FERG": "Industrials", "XYL": "Industrials", "JCI": "Industrials", "APG": "Industrials",
        "CGNX": "Industrials", "AIT": "Industrials", "KEX": "Industrials",
        "SPXC": "Industrials", "ACM": "Industrials", "ARMK": "Industrials", "DAY": "Industrials",

        // Consumer Staples
        "PG": "Consumer Staples", "KO": "Consumer Staples", "PEP": "Consumer Staples",
        "COST": "Consumer Staples", "WMT": "Consumer Staples", "PM": "Consumer Staples",
        "MDLZ": "Consumer Staples", "CL": "Consumer Staples", "KHC": "Consumer Staples",
        "MO": "Consumer Staples", "GIS": "Consumer Staples", "K": "Consumer Staples",
        "KMB": "Consumer Staples", "HSY": "Consumer Staples", "SYY": "Consumer Staples",
        "STZ": "Consumer Staples", "ADM": "Consumer Staples", "MKC": "Consumer Staples",
        "CAG": "Consumer Staples", "CPB": "Consumer Staples", "SJM": "Consumer Staples",
        "HRL": "Consumer Staples", "TSN": "Consumer Staples", "KDP": "Consumer Staples",
        "MNST": "Consumer Staples", "CHD": "Consumer Staples", "CLX": "Consumer Staples",
        "EL": "Consumer Staples", "TGT": "Consumer Staples", "DG": "Consumer Staples",
        "DLTR": "Consumer Staples", "KR": "Consumer Staples", "WBA": "Consumer Staples",
        "BJ": "Consumer Staples", "GO": "Consumer Staples", "USFD": "Consumer Staples",
        "BG": "Consumer Staples", "LW": "Consumer Staples", "BFB": "Consumer Staples",
        "TAP": "Consumer Staples", "CASY": "Consumer Staples", "INGR": "Consumer Staples",
        "FLO": "Consumer Staples", "POST": "Consumer Staples", "SFM": "Consumer Staples",
        "FRPT": "Consumer Staples", "CHEF": "Consumer Staples", "PPC": "Consumer Staples",
        "LANC": "Consumer Staples", "JJSF": "Consumer Staples", "LNTH": "Consumer Staples",

        // Energy
        "XOM": "Energy", "CVX": "Energy", "COP": "Energy", "SLB": "Energy",
        "EOG": "Energy", "MPC": "Energy", "PSX": "Energy", "VLO": "Energy",
        "OXY": "Energy", "PXD": "Energy", "DVN": "Energy", "HES": "Energy",
        "HAL": "Energy", "BKR": "Energy", "FANG": "Energy", "APA": "Energy",
        "MRO": "Energy", "CTRA": "Energy", "OKE": "Energy", "WMB": "Energy",
        "KMI": "Energy", "ET": "Energy", "EPD": "Energy", "TRGP": "Energy",
        "LNG": "Energy", "ENPH": "Energy", "SEDG": "Energy", "FSLR": "Energy",
        "RUN": "Energy", "NOVA": "Energy", "ARRY": "Energy", "BE": "Energy",
        "TPL": "Energy", "EQT": "Energy", "GEV": "Energy", "EXE": "Energy",
        "DINO": "Energy", "PR": "Energy", "SM": "Energy", "MTDR": "Energy",
        "CHRD": "Energy", "GPOR": "Energy", "RRC": "Energy", "AR": "Energy",

        // Utilities
        "NEE": "Utilities", "DUK": "Utilities", "SO": "Utilities", "D": "Utilities",
        "AEP": "Utilities", "EXC": "Utilities", "SRE": "Utilities", "XEL": "Utilities",
        "PCG": "Utilities", "ED": "Utilities", "WEC": "Utilities", "ES": "Utilities",
        "AWK": "Utilities", "EIX": "Utilities", "DTE": "Utilities", "ETR": "Utilities",
        "FE": "Utilities", "PPL": "Utilities", "AEE": "Utilities", "CMS": "Utilities",
        "CNP": "Utilities", "EVRG": "Utilities", "NI": "Utilities", "ATO": "Utilities",
        "NRG": "Utilities", "VST": "Utilities", "PNW": "Utilities", "LNT": "Utilities",
        "CEG": "Utilities", "AES": "Utilities",

        // Real Estate
        "PLD": "Real Estate", "AMT": "Real Estate", "CCI": "Real Estate", "EQIX": "Real Estate",
        "PSA": "Real Estate", "O": "Real Estate", "SPG": "Real Estate", "WELL": "Real Estate",
        "DLR": "Real Estate", "AVB": "Real Estate", "EQR": "Real Estate", "VTR": "Real Estate",
        "ARE": "Real Estate", "MAA": "Real Estate", "UDR": "Real Estate", "ESS": "Real Estate",
        "INVH": "Real Estate", "SUI": "Real Estate", "ELS": "Real Estate", "REG": "Real Estate",
        "KIM": "Real Estate", "BXP": "Real Estate", "VNO": "Real Estate", "SLG": "Real Estate",
        "HST": "Real Estate", "PEAK": "Real Estate", "CPT": "Real Estate", "IRM": "Real Estate",
        "SBAC": "Real Estate", "WY": "Real Estate", "CBRE": "Real Estate", "JLL": "Real Estate",
        "CSGP": "Real Estate", "VICI": "Real Estate", "EXR": "Real Estate", "FRT": "Real Estate",

        // Materials
        "LIN": "Materials", "APD": "Materials", "SHW": "Materials", "FCX": "Materials",
        "NEM": "Materials", "NUE": "Materials", "ECL": "Materials", "DD": "Materials",
        "DOW": "Materials", "PPG": "Materials", "VMC": "Materials", "MLM": "Materials",
        "CTVA": "Materials", "ALB": "Materials", "IFF": "Materials", "FMC": "Materials",
        "CF": "Materials", "MOS": "Materials", "NTR": "Materials", "CE": "Materials",
        "EMN": "Materials", "PKG": "Materials", "IP": "Materials", "WRK": "Materials",
        "BALL": "Materials", "AVY": "Materials", "SEE": "Materials", "AMCR": "Materials",
        "STLD": "Materials", "CLF": "Materials", "X": "Materials", "AA": "Materials",
        "CRH": "Materials", "LYB": "Materials", "RS": "Materials", "RGLD": "Materials",
        "CMC": "Materials", "CC": "Materials", "HUN": "Materials", "OLN": "Materials",
        "SMG": "Materials", "CBT": "Materials", "UFPI": "Materials", "SLVM": "Materials",

        // ETFs - map to their primary sector exposure
        "SPY": "Financials", "QQQ": "Technology", "IWM": "Financials", "DIA": "Industrials",
        "VOO": "Financials", "VTI": "Financials", "VGT": "Technology", "XLK": "Technology",
        "XLF": "Financials", "XLV": "Healthcare", "XLE": "Energy", "XLI": "Industrials",
        "XLP": "Consumer Staples", "XLY": "Consumer Discretionary", "XLU": "Utilities",
        "XLRE": "Real Estate", "XLB": "Materials", "XLC": "Communication Services",
        "ARKK": "Technology", "ARKG": "Healthcare", "ARKF": "Financials", "ARKW": "Technology",
        "VNQ": "Real Estate", "SCHD": "Financials", "VYM": "Financials", "VIG": "Financials",

        // International ADRs
        "BABA": "Consumer Discretionary", "TSM": "Technology", "NVO": "Healthcare",
        "ASML": "Technology", "TM": "Consumer Discretionary", "SAP": "Technology",
        "SNY": "Healthcare", "UL": "Consumer Staples", "BHP": "Materials",
        "RIO": "Materials", "BP": "Energy", "SHEL": "Energy", "TTE": "Energy",
        "NVS": "Healthcare", "AZN": "Healthcare", "GSK": "Healthcare", "DEO": "Consumer Staples",
        "BTI": "Consumer Staples", "SONY": "Consumer Discretionary", "HMC": "Consumer Discretionary",
        "LYG": "Financials", "BCS": "Financials", "CS": "Financials", "UBS": "Financials",
        "HSBC": "Financials", "DB": "Financials", "ING": "Financials", "SAN": "Financials",
        "TCEHY": "Communication Services", "BIDU": "Communication Services", "JD": "Consumer Discretionary",
        "PDD": "Consumer Discretionary", "NIO": "Consumer Discretionary", "LI": "Consumer Discretionary",
        "XPEV": "Consumer Discretionary", "BILI": "Communication Services", "SE": "Consumer Discretionary",

        // Crypto & Bitcoin ETFs
        "IBIT": "Financials",

        // Additional stocks (user portfolio)
        "IREN": "Technology", "NBIS": "Technology", "GRNY": "Consumer Staples", "AIS": "Healthcare"
    ]

    // MARK: - Static Beta Fallback Map

    /// Static beta values for common stocks (updated Q1 2026)
    /// Used as primary source since FMP and Yahoo quoteSummary APIs are now restricted
    /// Beta values are relatively stable and typically update quarterly
    private static let betaFallbackMap: [String: Double] = [
        // Major Technology
        "AAPL": 1.24, "MSFT": 0.89, "GOOGL": 1.05, "GOOG": 1.05,
        "NVDA": 1.67, "META": 1.23, "AMZN": 1.16, "TSLA": 2.31,
        "AVGO": 1.08, "ORCL": 1.02, "CRM": 1.21, "ADBE": 1.18,
        "AMD": 1.72, "INTC": 0.97, "CSCO": 0.88, "IBM": 0.75,
        "QCOM": 1.28, "TXN": 1.05, "NOW": 1.15, "AMAT": 1.45,
        "MU": 1.38, "LRCX": 1.42, "INTU": 1.12, "SNPS": 1.08,
        "CDNS": 1.05, "KLAC": 1.35, "ADI": 1.12, "PANW": 1.18,
        "MCHP": 1.15, "FTNT": 1.08, "NXPI": 1.32, "ON": 1.45,
        "MPWR": 1.28, "CRWD": 1.35, "DDOG": 1.42, "ZS": 1.38,
        "TEAM": 1.25, "WDAY": 1.18, "SNOW": 1.52, "NET": 1.48,
        "MDB": 1.55, "PLTR": 1.85, "U": 1.72, "PATH": 1.45,
        "DOCN": 1.38, "HPQ": 0.92, "HPE": 0.85, "DELL": 1.02,
        "WDC": 1.28, "STX": 1.22, "KEYS": 1.05, "TEL": 1.08,
        "GLW": 0.95, "APH": 1.02, "IT": 1.12, "EPAM": 1.35,
        "AKAM": 0.88, "CTSH": 0.95, "ACN": 1.02, "FFIV": 0.92,
        "JNPR": 0.85, "GEN": 0.78, "NTAP": 0.95, "ZBRA": 1.18,
        "TYL": 1.05, "PAYC": 1.15, "ADSK": 1.08, "ANSS": 1.02,
        "PTC": 1.08, "VEEV": 0.95, "HUBS": 1.35, "SQ": 2.12,
        "SHOP": 1.85, "ROP": 0.92, "CDW": 1.05, "GDDY": 1.12,
        "FICO": 1.18, "TDY": 0.88, "VRSN": 0.82, "SWKS": 1.25,
        "TER": 1.32, "TRMB": 1.15, "SMCI": 1.92, "APP": 1.78,
        "QRVO": 1.28, "ANET": 1.35,

        // Healthcare
        "UNH": 0.72, "JNJ": 0.52, "LLY": 0.43, "PFE": 0.65,
        "ABBV": 0.58, "MRK": 0.42, "TMO": 0.82, "ABT": 0.78,
        "DHR": 0.85, "BMY": 0.48, "AMGN": 0.55, "MDT": 0.72,
        "GILD": 0.62, "VRTX": 0.48, "ISRG": 0.92, "REGN": 0.45,
        "SYK": 0.85, "BSX": 0.88, "ZTS": 0.75, "BDX": 0.72,
        "CVS": 0.85, "CI": 0.78, "ELV": 0.75, "HUM": 0.68,
        "CNC": 0.82, "MCK": 0.72, "CAH": 0.68, "ABC": 0.65,
        "BIIB": 0.55, "MRNA": 1.85, "ILMN": 1.12, "DXCM": 1.08,
        "IQV": 0.92, "MTD": 0.85, "A": 0.88, "WAT": 0.78,
        "IDXX": 0.82, "EW": 0.88, "ALGN": 1.15, "HOLX": 0.72,
        "COO": 0.75, "RMD": 0.82, "BAX": 0.68, "ZBH": 0.72,
        "TECH": 0.88, "HCA": 1.12, "GEHC": 0.92, "MOH": 0.78,
        "CRL": 0.95, "DGX": 0.65, "LH": 0.62, "INCY": 0.72,
        "BMRN": 0.68, "EXAS": 1.05, "PODD": 0.92, "KVUE": 0.58,
        "COR": 0.72, "WST": 0.85, "STE": 0.78, "RVTY": 0.88,
        "VTRS": 0.62, "HSIC": 0.68, "UHS": 0.92, "SOLV": 0.75,
        "DVA": 0.85,

        // Financials
        "BRK.A": 0.88, "BRK.B": 0.88, "JPM": 1.12, "V": 0.94,
        "MA": 1.08, "BAC": 1.42, "WFC": 1.25, "GS": 1.35,
        "MS": 1.32, "BLK": 1.18, "C": 1.45, "AXP": 1.22,
        "SCHW": 1.28, "SPGI": 1.05, "CB": 0.72, "MMC": 0.85,
        "PGR": 0.68, "AON": 0.82, "CME": 0.95, "ICE": 0.98,
        "USB": 1.08, "PNC": 1.12, "TFC": 1.18, "AIG": 1.05,
        "MET": 1.15, "PRU": 1.22, "AFL": 0.92, "TRV": 0.78,
        "ALL": 0.82, "AMP": 1.18, "BK": 1.08, "STT": 1.15,
        "NTRS": 1.02, "COF": 1.35, "DFS": 1.28, "SYF": 1.42,
        "FIS": 1.05, "FISV": 0.92, "GPN": 0.88, "PYPL": 1.52,
        "MCO": 1.08, "MSCI": 1.12, "NDAQ": 0.95, "CBOE": 0.88,
        "FITB": 1.15, "RF": 1.22, "CFG": 1.28, "KEY": 1.32,
        "HBAN": 1.18, "MTB": 1.05, "ALLY": 1.45, "COIN": 2.85,
        "HOOD": 2.12, "SOFI": 1.92, "ACGL": 0.72, "TROW": 1.25,
        "WTW": 0.82, "RJF": 1.02, "IBKR": 1.08, "BRO": 0.75,
        "PFG": 1.12, "FDS": 0.95, "CINF": 0.68, "WRB": 0.72,
        "L": 0.82, "JKHY": 0.78, "APO": 1.45, "GL": 0.68,
        "ERIE": 0.55, "KKR": 1.52, "BEN": 1.28, "AIZ": 0.75,
        "IVZ": 1.35, "BX": 1.48, "MKTX": 0.82, "HIG": 0.92,
        "EWBC": 1.18, "CMA": 1.25, "ZION": 1.22,

        // Consumer Discretionary
        "HD": 0.98, "MCD": 0.62, "NKE": 0.88, "SBUX": 0.82,
        "LOW": 1.02, "TJX": 0.85, "BKNG": 1.32, "CMG": 1.15,
        "MAR": 1.28, "HLT": 1.22, "ORLY": 0.92, "AZO": 0.78,
        "ROST": 0.88, "DHI": 1.45, "LEN": 1.38, "PHM": 1.42,
        "NVR": 1.25, "GM": 1.18, "F": 1.25, "RIVN": 2.15,
        "LCID": 2.28, "YUM": 0.75, "DPZ": 0.85, "WYNN": 1.72,
        "LVS": 1.58, "MGM": 1.65, "RCL": 2.08, "CCL": 2.15,
        "NCLH": 2.22, "EXPE": 1.48, "ABNB": 1.65, "EBAY": 1.15,
        "ETSY": 1.52, "W": 1.85, "CHWY": 1.42, "BBY": 1.25,
        "ULTA": 1.02, "LULU": 1.18, "GPS": 1.35, "DECK": 1.12,
        "GRMN": 0.88, "POOL": 1.15, "DRI": 0.92, "APTV": 1.28,
        "TSCO": 0.85, "GPC": 0.72, "HAS": 0.95, "BBWI": 1.18,
        "TPR": 1.22, "RL": 1.08, "WSM": 1.15, "CVNA": 2.45,
        "BWA": 1.12, "MHK": 1.35, "WHR": 1.28, "PVH": 1.32,
        "VFC": 1.18, "PENN": 1.85, "CZR": 1.92, "LKQ": 0.95,

        // Communication Services
        "NFLX": 1.42, "DIS": 1.08, "CMCSA": 0.95, "VZ": 0.42,
        "T": 0.48, "TMUS": 0.72, "CHTR": 0.85, "WBD": 1.52,
        "PARA": 1.45, "FOX": 1.02, "FOXA": 1.05, "NWSA": 0.95,
        "NWS": 0.92, "OMC": 0.82, "IPG": 0.88, "EA": 0.75,
        "TTWO": 0.82, "MTCH": 1.25, "PINS": 1.38, "SNAP": 1.72,
        "SPOT": 1.55, "ROKU": 1.85, "RBLX": 1.68, "LYFT": 1.72,
        "UBER": 1.42, "DASH": 1.58, "TTD": 1.52, "LYV": 1.18,

        // Industrials
        "UNP": 0.92, "HON": 0.98, "UPS": 0.95, "BA": 1.42,
        "CAT": 1.05, "RTX": 0.78, "DE": 0.92, "LMT": 0.62,
        "GE": 1.12, "MMM": 0.85, "GD": 0.68, "NOC": 0.58,
        "FDX": 1.22, "NSC": 0.88, "CSX": 0.92, "EMR": 0.95,
        "ETN": 1.08, "ITW": 0.88, "PH": 1.02, "ROK": 1.12,
        "CMI": 1.08, "PCAR": 0.95, "CARR": 1.15, "OTIS": 0.92,
        "WM": 0.68, "RSG": 0.62, "LUV": 1.25, "DAL": 1.32,
        "UAL": 1.45, "AAL": 1.52, "JBHT": 0.98, "XPO": 1.28,
        "EXPD": 0.85, "CHRW": 0.78, "FAST": 0.88, "CPRT": 0.92,
        "VRSK": 0.82, "PWR": 1.05, "AME": 0.95, "IR": 1.08,
        "DOV": 0.98, "TT": 1.12, "SWK": 1.02, "NDSN": 0.92,
        "IEX": 0.88, "GWW": 0.85, "ODFL": 0.95, "URI": 1.22,
        "TDG": 0.88, "HWM": 1.05, "WAB": 0.92, "LDOS": 0.72,
        "J": 0.82, "CTAS": 0.78, "PAYX": 0.85, "EFX": 1.08,
        "BR": 0.75, "EME": 1.12, "TXT": 1.02, "SNA": 0.88,
        "AXON": 1.35, "MAS": 1.18, "BLDR": 1.45, "AOS": 0.95,
        "HII": 0.72, "LII": 1.08, "GNRC": 1.22, "HUBB": 1.05,
        "FERG": 1.02, "XYL": 0.95, "JCI": 1.08,

        // Consumer Staples
        "PG": 0.42, "KO": 0.55, "PEP": 0.52, "COST": 0.78,
        "WMT": 0.48, "PM": 0.62, "MDLZ": 0.52, "CL": 0.45,
        "KHC": 0.48, "MO": 0.58, "GIS": 0.42, "K": 0.48,
        "KMB": 0.45, "HSY": 0.38, "SYY": 0.82, "STZ": 0.88,
        "ADM": 0.75, "MKC": 0.48, "CAG": 0.42, "CPB": 0.38,
        "SJM": 0.42, "HRL": 0.35, "TSN": 0.72, "KDP": 0.55,
        "MNST": 0.82, "CHD": 0.48, "CLX": 0.42, "EL": 0.78,
        "TGT": 0.92, "DG": 0.68, "DLTR": 0.75, "KR": 0.48,
        "WBA": 0.85, "BJ": 0.72, "USFD": 0.78,

        // Energy
        "XOM": 0.92, "CVX": 0.95, "COP": 1.15, "SLB": 1.38,
        "EOG": 1.22, "MPC": 1.28, "PSX": 1.18, "VLO": 1.32,
        "OXY": 1.45, "DVN": 1.52, "HES": 1.35, "HAL": 1.42,
        "BKR": 1.28, "FANG": 1.38, "APA": 1.55, "MRO": 1.48,
        "CTRA": 1.35, "OKE": 1.02, "WMB": 0.95, "KMI": 0.88,
        "ET": 1.08, "EPD": 0.85, "TRGP": 1.12, "LNG": 1.22,
        "ENPH": 1.85, "SEDG": 1.92, "FSLR": 1.72, "RUN": 1.88,
        "EQT": 1.28, "GEV": 1.35,

        // Utilities
        "NEE": 0.52, "DUK": 0.42, "SO": 0.38, "D": 0.48,
        "AEP": 0.45, "EXC": 0.52, "SRE": 0.55, "XEL": 0.42,
        "PCG": 0.72, "ED": 0.35, "WEC": 0.38, "ES": 0.42,
        "AWK": 0.48, "EIX": 0.58, "DTE": 0.52, "ETR": 0.55,
        "FE": 0.48, "PPL": 0.45, "AEE": 0.42, "CMS": 0.38,
        "CNP": 0.52, "EVRG": 0.45, "NI": 0.42, "ATO": 0.48,
        "NRG": 0.82, "VST": 0.88, "PNW": 0.45, "LNT": 0.42,
        "CEG": 0.68, "AES": 0.92,

        // Real Estate
        "PLD": 0.88, "AMT": 0.62, "CCI": 0.58, "EQIX": 0.75,
        "PSA": 0.52, "O": 0.55, "SPG": 1.35, "WELL": 0.82,
        "DLR": 0.72, "AVB": 0.85, "EQR": 0.78, "VTR": 0.92,
        "ARE": 0.88, "MAA": 0.72, "UDR": 0.75, "ESS": 0.82,
        "INVH": 0.88, "SUI": 0.72, "ELS": 0.68, "REG": 0.85,
        "KIM": 0.92, "BXP": 1.08, "HST": 1.22, "CPT": 0.78,
        "IRM": 0.72, "SBAC": 0.55, "CBRE": 1.18, "JLL": 1.22,
        "CSGP": 1.08, "VICI": 0.82, "EXR": 0.68, "FRT": 0.88,

        // Materials
        "LIN": 0.82, "APD": 0.85, "SHW": 0.88, "FCX": 1.68,
        "NEM": 0.42, "NUE": 1.35, "ECL": 0.82, "DD": 0.92,
        "DOW": 1.18, "PPG": 0.95, "VMC": 0.88, "MLM": 0.85,
        "CTVA": 0.78, "ALB": 1.45, "IFF": 0.82, "FMC": 0.88,
        "CF": 1.12, "MOS": 1.18, "NTR": 0.95, "CE": 1.05,
        "EMN": 1.02, "PKG": 0.85, "IP": 0.92, "WRK": 0.98,
        "BALL": 0.88, "AVY": 0.82, "SEE": 0.78, "AMCR": 0.72,
        "STLD": 1.28, "CLF": 1.55, "X": 1.72, "AA": 1.65,
        "CRH": 0.92, "LYB": 1.08, "RS": 1.05,

        // ETFs (beta relative to S&P 500)
        "SPY": 1.00, "QQQ": 1.18, "IWM": 1.24, "DIA": 0.98,
        "VOO": 1.00, "VTI": 1.02, "VGT": 1.15, "XLK": 1.12,
        "XLF": 1.08, "XLV": 0.72, "XLE": 1.15, "XLI": 1.02,
        "XLP": 0.58, "XLY": 1.08, "XLU": 0.52, "XLRE": 0.82,
        "XLB": 0.95, "XLC": 0.92, "ARKK": 1.85, "ARKG": 1.42,
        "ARKF": 1.52, "ARKW": 1.72, "VNQ": 0.88, "SCHD": 0.78,
        "VYM": 0.82, "VIG": 0.88, "IBIT": 1.45,

        // International ADRs
        "BABA": 0.85, "TSM": 1.15, "NVO": 0.48, "ASML": 1.12,
        "TM": 0.72, "SAP": 0.92, "SNY": 0.58, "UL": 0.52,
        "BHP": 1.08, "RIO": 1.12, "BP": 0.88, "SHEL": 0.82,
        "TTE": 0.85, "NVS": 0.48, "AZN": 0.55, "GSK": 0.52,
        "DEO": 0.62, "BTI": 0.48, "SONY": 1.02, "HMC": 0.88,
        "LYG": 1.25, "BCS": 1.18, "UBS": 1.08, "HSBC": 0.92,
        "DB": 1.35, "ING": 1.22, "SAN": 1.28, "TCEHY": 0.78,
        "BIDU": 1.05, "JD": 0.95, "PDD": 1.12, "NIO": 1.85,
        "LI": 1.72, "XPEV": 1.82, "BILI": 1.28, "SE": 1.65,

        // User portfolio and other popular stocks
        "NBIS": 2.10, "IREN": 2.25, "GRNY": 0.85, "AIS": 0.78
    ]

    /// Set of known ETF tickers for quick lookup
    private static let etfTickers: Set<String> = [
        "SPY", "QQQ", "IWM", "DIA", "VOO", "VTI", "VGT", "XLK",
        "XLF", "XLV", "XLE", "XLI", "XLP", "XLY", "XLU", "XLRE",
        "XLB", "XLC", "ARKK", "ARKG", "ARKF", "ARKW", "VNQ",
        "SCHD", "VYM", "VIG", "IBIT", "SOXL", "TQQQ", "SQQQ",
        "SPXL", "SPXS", "TLT", "IEF", "SHY", "GLD", "SLV",
        "USO", "UNG", "EEM", "EFA", "VWO", "VXUS", "BND",
        "AGG", "LQD", "HYG", "JNK", "TIP", "GOVT"
    ]

    /// Fetches sector information for a given ticker symbol
    /// - Parameter ticker: Stock ticker symbol (e.g., "AAPL")
    /// - Returns: Sector string, or nil if fetch fails
    func fetchSectorInfo(for ticker: String) async -> String? {
        let trimmedTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmedTicker.isEmpty else { return nil }

        // Check fallback map first - this is fast and reliable
        if let fallbackSector = StockAPIService.sectorFallbackMap[trimmedTicker] {
            AppLogger.debug("Using fallback sector for \(trimmedTicker): \(fallbackSector)")
            return fallbackSector
        }

        // Skip API calls during UI testing
        guard !AppEnvironment.isUITesting else {
            return "Technology" // Default for unknown in tests
        }

        // Try Yahoo Finance quoteSummary endpoint for stocks not in fallback map
        guard let url = buildYahooQuoteSummaryURL(ticker: trimmedTicker, modules: ["assetProfile"]) else {
            AppLogger.error("Invalid URL for sector info: \(ticker)")
            return nil
        }

        do {
            let data = try await performRequestWithRetry(url: url, endpoint: "yahoo-sector-\(trimmedTicker)")

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let quoteSummary = json["quoteSummary"] as? [String: Any],
                  let result = (quoteSummary["result"] as? [[String: Any]])?.first,
                  let assetProfile = result["assetProfile"] as? [String: Any],
                  let sector = assetProfile["sector"] as? String else {
                return nil
            }

            AppLogger.debug("Fetched sector from API for \(ticker): \(sector)")
            return sector
        } catch {
            AppLogger.debug("Error fetching sector for \(ticker)")
            return nil
        }
    }

    /// Fetches sector information for multiple tickers
    /// - Parameter tickers: Array of stock ticker symbols
    /// - Returns: Dictionary mapping ticker to sector string
    func fetchSectorInfo(for tickers: [String]) async -> [String: String] {
        var sectorDict: [String: String] = [:]

        await withTaskGroup(of: (String, String?).self) { group in
            for ticker in tickers {
                let trimmedTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if trimmedTicker.isEmpty { continue }

                group.addTask {
                    let sector = await self.fetchSectorInfo(for: trimmedTicker)
                    return (trimmedTicker, sector)
                }
            }

            for await (ticker, sector) in group {
                if let sector = sector {
                    sectorDict[ticker] = sector
                }
            }
        }

        return sectorDict
    }

    // MARK: - Polygon.io Integration

    /// Fetches company information from Polygon.io
    /// - Parameter ticker: Stock ticker symbol (e.g., "AAPL")
    /// - Returns: CompanyInfo with company details, or nil if fetch fails
    /// - Note: Free tier limit: 5 API calls per minute
    func fetchCompanyInfo(fromPolygon ticker: String) async -> CompanyInfo? {
        // Check if API key is configured
        guard APIConfig.isPolygonConfigured else {
            AppLogger.debug("Polygon.io API key not configured")
            return nil
        }

        // Check rate limit
        let canRequest = await apiRateLimiter.canMakeRequest(endpoint: "polygon", config: .polygon)
        guard canRequest else {
            AppLogger.debug("Polygon rate limit reached, skipping company info fetch for \(ticker)")
            return nil
        }

        guard let url = buildPolygonTickerURL(ticker: ticker) else {
            AppLogger.error("Invalid Polygon.io URL for ticker: \(ticker)")
            return nil
        }

        // Record the request
        await apiRateLimiter.recordRequest(endpoint: "polygon")

        do {
            let data = try await performRequestWithRetry(url: url, endpoint: "polygon-ticker-\(ticker)")

            // Parse JSON response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [String: Any] else {
                AppLogger.debug("Failed to parse Polygon.io response for \(ticker)")
                return nil
            }

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

            AppLogger.debug("Fetched company info from Polygon.io for \(ticker): \(name)")

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
        } catch {
            AppLogger.debug("Error fetching company info from Polygon.io for \(ticker)")
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

    // MARK: - Polygon.io Price Data

    /// Fetches current price from Polygon.io last trade endpoint
    /// - Parameter ticker: Stock ticker symbol (e.g., "AAPL")
    /// - Returns: EnhancedStockData with price and metadata, or nil if fetch fails
    /// - Note: Uses Polygon.io /v2/last/trade endpoint
    func fetchPriceFromPolygon(for ticker: String) async -> EnhancedStockData? {
        guard APIConfig.isPolygonConfigured else {
            AppLogger.debug("Polygon.io API key not configured")
            return nil
        }

        // Check rate limit (unlimited on Starter tier, but check anyway)
        let canRequest = await apiRateLimiter.canMakeRequest(endpoint: "polygon", config: .polygon)
        guard canRequest else {
            AppLogger.debug("Polygon rate limit reached for \(ticker)")
            return nil
        }

        // Strategy: Use last trade endpoint (realtime with daily % calculation)
        // Note: Previous close endpoint removed from hybrid strategy as it returns stale data
        // (yesterday's close as current price). It's only used by fetchPreviousCloseFromPolygon() helper.

        AppLogger.debug("Attempting Polygon.io fetch for \(ticker)")

        // Try last trade endpoint
        if let lastTradeData = await fetchFromLastTradeEndpoint(ticker: ticker) {
            return lastTradeData
        }

        // Polygon endpoint failed - caller will fall back to Yahoo Finance
        AppLogger.warning("⚠️ Polygon.io last trade endpoint failed for \(ticker)")
        return nil
    }

    /// Attempts to fetch data from Polygon.io /v2/last/trade endpoint
    private func fetchFromLastTradeEndpoint(ticker: String) async -> EnhancedStockData? {
        guard let url = APIConfig.Endpoints.polygonLastTrade(ticker: ticker) else {
            AppLogger.error("Invalid Polygon.io last trade URL for ticker: \(ticker)")
            return nil
        }

        await apiRateLimiter.recordRequest(endpoint: "polygon")

        do {
            let data = try await performRequestWithRetry(url: url, endpoint: "polygon-last-trade-\(ticker)")

            #if DEBUG
            AppLogger.debug("Polygon last trade response for \(ticker): \(String(data: data, encoding: .utf8) ?? "Invalid UTF-8")")
            #endif

            let decoder = JSONDecoder()
            let response = try decoder.decode(PolygonLastTrade.self, from: data)

            guard response.status == "OK", let tradeResult = response.results else {
                AppLogger.warning("Polygon.io /v2/last/trade failed for \(ticker): status='\(response.status)', results=\(response.results != nil ? "present" : "nil")")
                if let error = response.error {
                    AppLogger.warning("Polygon.io error message: \(error)")
                }
                return nil
            }

            // Fetch company details for name and type (ETF detection)
            let companyInfo = await fetchCompanyInfo(fromPolygon: ticker)
            let companyName = companyInfo?.name ?? ticker.uppercased()
            let isETF = companyInfo?.type?.lowercased().contains("etf") ?? false

            // Fetch previous close for daily return calculation
            let previousClose = await fetchPreviousCloseFromPolygon(for: ticker)

            // CRITICAL FIX: Calculate daily percentage change (like Yahoo does)
            var periodChanges: [String: Double]? = nil
            if let prevClose = previousClose, prevClose > 0 {
                let dayChange = ((tradeResult.p - prevClose) / prevClose) * 100
                periodChanges = ["1d": dayChange]
                AppLogger.debug("\(ticker) Polygon daily change: \(String(format: "%.2f", dayChange))% (prevClose: \(prevClose), price: \(tradeResult.p))")
            }

            AppLogger.debug("✅ Fetched \(ticker) from Polygon.io (last trade endpoint): $\(tradeResult.p)")

            return EnhancedStockData(
                price: tradeResult.p,
                companyName: companyName,
                previousClose: previousClose,
                beta: nil, // Beta will be added in Phase 2
                isETF: isETF,
                open: nil,
                high: nil,
                low: nil,
                volume: Int64(tradeResult.s),
                vwap: nil,
                dataSource: "polygon",
                marketStatus: nil,
                timestamp: Date(timeIntervalSince1970: TimeInterval(tradeResult.t) / 1000.0),
                periodChanges: periodChanges
            )
        } catch {
            AppLogger.warning("Error fetching from Polygon.io last trade endpoint for \(ticker): \(error.localizedDescription)")
            return nil
        }
    }

    /// Attempts to fetch data from Polygon.io /v2/aggs/ticker/{ticker}/prev endpoint
    /// NOTE: This endpoint returns yesterday's CLOSE price, NOT today's realtime price
    /// It should only be used to get previousClose for daily calculations
    private func fetchFromPreviousCloseEndpoint(ticker: String) async -> EnhancedStockData? {
        guard let url = APIConfig.Endpoints.polygonPreviousClose(ticker: ticker) else {
            AppLogger.error("Invalid Polygon.io previous close URL for ticker: \(ticker)")
            return nil
        }

        await apiRateLimiter.recordRequest(endpoint: "polygon")

        do {
            let data = try await performRequestWithRetry(url: url, endpoint: "polygon-prev-close-\(ticker)")

            #if DEBUG
            AppLogger.debug("Polygon previous close response for \(ticker): \(String(data: data, encoding: .utf8) ?? "Invalid UTF-8")")
            #endif

            let decoder = JSONDecoder()
            let response = try decoder.decode(PolygonPreviousClose.self, from: data)

            guard response.status == "OK", let results = response.results, !results.isEmpty else {
                AppLogger.warning("Polygon.io /v2/aggs failed for \(ticker): status='\(response.status ?? "nil")', results=\(response.results != nil ? "present" : "nil")")
                return nil
            }

            let bar = results[0]

            // Fetch company details for name and type (ETF detection)
            let companyInfo = await fetchCompanyInfo(fromPolygon: ticker)
            let companyName = companyInfo?.name ?? ticker.uppercased()
            let isETF = companyInfo?.type?.lowercased().contains("etf") ?? false

            // IMPORTANT: bar.c is yesterday's close, not today's price
            // Use it as both current price AND previous close since we don't have today's realtime data
            // This will show 0% daily change, which is acceptable for the fallback scenario
            AppLogger.warning("⚠️ Using previous close as current price for \(ticker) (realtime data unavailable): $\(bar.c)")

            return EnhancedStockData(
                price: bar.c,  // Yesterday's close (best available data)
                companyName: companyName,
                previousClose: bar.c,  // Same as price - will show 0% daily change
                beta: nil,
                isETF: isETF,
                open: bar.o,
                high: bar.h,
                low: bar.l,
                volume: bar.v,
                vwap: bar.vw,
                dataSource: "polygon-stale",  // Mark as stale data
                marketStatus: nil,
                timestamp: Date(timeIntervalSince1970: TimeInterval(bar.t) / 1000.0),  // Use bar timestamp
                periodChanges: nil  // No daily change since we don't have today's price
            )
        } catch {
            AppLogger.warning("Error fetching from Polygon.io previous close endpoint for \(ticker): \(error.localizedDescription)")
            return nil
        }
    }

    /// Fetches previous close price from Polygon.io
    /// - Parameter ticker: Stock ticker symbol
    /// - Returns: Previous close price, or nil if fetch fails
    private func fetchPreviousCloseFromPolygon(for ticker: String) async -> Double? {
        guard let url = APIConfig.Endpoints.polygonPreviousClose(ticker: ticker) else {
            return nil
        }

        // Rate limit already checked by parent call
        await apiRateLimiter.recordRequest(endpoint: "polygon")

        do {
            let data = try await performRequestWithRetry(url: url, endpoint: "polygon-prev-close-\(ticker)")
            let decoder = JSONDecoder()
            let response = try decoder.decode(PolygonPreviousClose.self, from: data)

            guard response.status == "OK", let results = response.results, !results.isEmpty else {
                return nil
            }

            return results[0].c
        } catch {
            AppLogger.debug("Error fetching previous close from Polygon.io for \(ticker)")
            return nil
        }
    }

    /// Fetches company details from Polygon.io (optimized version)
    /// - Parameter ticker: Stock ticker symbol
    /// - Returns: Company name and type (for ETF detection)
    func fetchCompanyDetailsFromPolygon(for ticker: String) async -> (name: String, isETF: Bool)? {
        guard let companyInfo = await fetchCompanyInfo(fromPolygon: ticker) else {
            return nil
        }

        let isETF = companyInfo.type?.lowercased().contains("etf") ?? false
        return (companyInfo.name, isETF)
    }

    /// Fetches historical bars (OHLCV data) from Polygon.io
    /// - Parameters:
    ///   - ticker: Stock ticker symbol
    ///   - from: Start date
    ///   - to: End date
    ///   - timespan: Bar timespan (day, week, month, etc.)
    /// - Returns: Array of aggregate bars with OHLCV data
    func fetchHistoricalBarsFromPolygon(
        for ticker: String,
        from: Date,
        to: Date,
        timespan: String = "day"
    ) async -> [PolygonAggregates.AggregateBar]? {
        guard APIConfig.isPolygonConfigured else {
            return nil
        }

        // Format dates as YYYY-MM-DD
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fromString = formatter.string(from: from)
        let toString = formatter.string(from: to)

        guard let url = APIConfig.Endpoints.polygonAggregates(
            ticker: ticker,
            multiplier: 1,
            timespan: timespan,
            from: fromString,
            to: toString
        ) else {
            AppLogger.error("Invalid Polygon.io aggregates URL for ticker: \(ticker)")
            return nil
        }

        // Check rate limit
        let canRequest = await apiRateLimiter.canMakeRequest(endpoint: "polygon", config: .polygon)
        guard canRequest else {
            AppLogger.debug("Polygon rate limit reached for historical data: \(ticker)")
            return nil
        }

        await apiRateLimiter.recordRequest(endpoint: "polygon")

        do {
            let data = try await performRequestWithRetry(url: url, endpoint: "polygon-aggs-\(ticker)")
            let decoder = JSONDecoder()
            let response = try decoder.decode(PolygonAggregates.self, from: data)

            guard response.status == "OK", let results = response.results else {
                AppLogger.warning("Polygon.io returned no historical data for \(ticker)")
                return nil
            }

            AppLogger.debug("Fetched \(results.count) historical bars for \(ticker) from Polygon.io")
            return results
        } catch {
            AppLogger.warning("Error fetching historical data from Polygon.io for \(ticker): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Supabase Server-Side Prices

    /// Fetches stock prices from Supabase (server-side cached data)
    /// This is the preferred method when supporting multiple users to avoid API rate limits
    /// - Parameter tickers: Array of stock ticker symbols
    /// - Returns: Dictionary mapping ticker to StockData
    func fetchStockPricesFromSupabase(for tickers: [String]) async -> [String: StockData] {
        var result: [String: StockData] = [:]

        // Skip if no tickers
        guard !tickers.isEmpty else { return result }

        do {
            let response: [DBStockPrice] = try await SupabaseConfig.client
                .from("stock_prices")
                .select()
                .in("ticker", values: tickers.map { $0.uppercased() })
                .execute()
                .value

            for dbPrice in response {
                result[dbPrice.ticker] = dbPrice.toStockData()
            }

            AppLogger.debug("Fetched \(response.count) prices from Supabase")
        } catch {
            AppLogger.error("Failed to fetch prices from Supabase: \(error.localizedDescription)")
        }

        return result
    }

    /// Triggers the Edge Function to refresh stock prices immediately
    /// Use this for on-demand refresh (e.g., pull-to-refresh)
    /// - Parameter tickers: Optional array of specific tickers to refresh. If nil, refreshes all tracked stocks.
    /// - Returns: True if the refresh was triggered successfully
    @discardableResult
    func refreshPricesNow(for tickers: [String]? = nil) async -> Bool {
        // Build the Edge Function URL
        var urlString = "\(SupabaseConfig.projectURL.absoluteString)/functions/v1/fetch-prices?force=true"

        // If specific ticker is requested, add it to the query
        if let tickers = tickers, tickers.count == 1 {
            urlString += "&ticker=\(tickers[0].uppercased())"
        }

        guard let url = URL(string: urlString) else {
            AppLogger.error("Invalid Edge Function URL")
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    // Parse response to log what was updated
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let updated = json["updated"] as? Int {
                        AppLogger.info("Price refresh triggered: \(updated) stocks updated")
                    } else {
                        AppLogger.info("Price refresh triggered successfully")
                    }
                    return true
                } else {
                    AppLogger.warning("Price refresh returned status \(httpResponse.statusCode)")
                    return false
                }
            }
            return false
        } catch {
            AppLogger.error("Failed to trigger price refresh: \(error.localizedDescription)")
            return false
        }
    }

    /// Fetches stock data with server-side fallback
    /// Tries Supabase first (if enabled), then falls back to direct Yahoo API
    /// - Parameter tickers: Array of stock ticker symbols
    /// - Returns: Dictionary mapping ticker to StockData
    func fetchStockDataWithFallback(for tickers: [String]) async -> [String: StockData] {
        // Skip if empty
        guard !tickers.isEmpty else { return [:] }

        // If server-side prices are enabled, try Supabase first
        if useServerSidePrices {
            let supabaseResult = await fetchStockPricesFromSupabase(for: tickers)

            // Check if we got all tickers from Supabase
            let missingTickers = tickers.filter { supabaseResult[$0.uppercased()] == nil }

            if missingTickers.isEmpty {
                // All tickers found in Supabase
                return supabaseResult
            }

            // Fetch missing tickers from Yahoo directly
            if !missingTickers.isEmpty {
                AppLogger.debug("Fetching \(missingTickers.count) missing tickers from Yahoo directly")
                let yahooResult = await fetchStockData(for: missingTickers)

                // Merge results
                var merged = supabaseResult
                for (ticker, data) in yahooResult {
                    merged[ticker] = data
                }
                return merged
            }
        }

        // Fall back to direct Yahoo API calls
        return await fetchStockData(for: tickers)
    }

    // MARK: - Ticker Validation

    /// Validates a ticker symbol by checking if it exists
    /// Uses tiered approach: Supabase cache first, then Yahoo Finance API
    /// - Parameter ticker: Stock ticker symbol to validate
    /// - Returns: TickerValidationResult indicating validity and any stock data
    func validateTicker(_ ticker: String) async -> TickerValidationResult {
        let trimmedTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmedTicker.isEmpty else {
            return .invalid
        }

        // Skip API calls during UI testing
        if AppEnvironment.isUITesting {
            AppEnvironment.testingLog("Validating ticker \(trimmedTicker), returning mock valid")
            return .valid(StockData(
                price: 150.0,
                companyName: trimmedTicker,
                periodChanges: nil,
                previousClose: 150.0,
                beta: 1.0,
                isETF: false,
                dataSource: "mock"
            ))
        }

        // Step 1: Check Supabase cache (fast, ~100-300ms)
        // If another user has this ticker, it's already validated
        if useServerSidePrices {
            let cachedData = await fetchStockPricesFromSupabase(for: [trimmedTicker])
            if cachedData[trimmedTicker] != nil {
                AppLogger.debug("Ticker \(trimmedTicker) found in Supabase cache")
                return .cached
            }
        }

        // Step 2: Validate via Yahoo Finance API (slower, ~500-2000ms)
        do {
            guard let url = buildYahooChartURL(ticker: trimmedTicker) else {
                AppLogger.error("Invalid URL for ticker validation: \(trimmedTicker)")
                return .invalid
            }

            let data = try await performRequestWithRetry(url: url, endpoint: "yahoo-validate-\(trimmedTicker)")

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let chart = json["chart"] as? [String: Any],
                  let result = (chart["result"] as? [[String: Any]])?.first,
                  let meta = result["meta"] as? [String: Any] else {
                // Check for specific error indicating invalid ticker
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let chart = json["chart"] as? [String: Any],
                   let error = chart["error"] as? [String: Any] {
                    let code = error["code"] as? String ?? ""
                    if code == "Not Found" || code.contains("not found") {
                        AppLogger.debug("Ticker \(trimmedTicker) not found via Yahoo API")
                        return .invalid
                    }
                }
                AppLogger.warning("Failed to parse validation response for \(trimmedTicker)")
                return .invalid
            }

            // Extract price data to confirm it's a valid tradeable security
            let price = meta["regularMarketPrice"] as? Double ?? 0.0
            guard price > 0 else {
                AppLogger.debug("Ticker \(trimmedTicker) has no price data - likely invalid")
                return .invalid
            }

            let companyName = (meta["longName"] as? String) ?? (meta["shortName"] as? String) ?? trimmedTicker
            let previousClose = meta["previousClose"] as? Double ?? meta["regularMarketPreviousClose"] as? Double

            AppLogger.info("Ticker \(trimmedTicker) validated: \(companyName) @ $\(String(format: "%.2f", price))")

            return .valid(StockData(
                price: price,
                companyName: companyName,
                periodChanges: nil,
                previousClose: previousClose,
                beta: nil,
                isETF: false,
                dataSource: nil
            ))
        } catch let error as APIError {
            switch error {
            case .notFound:
                AppLogger.debug("Ticker \(trimmedTicker) returned 404 - invalid")
                return .invalid
            case .networkError, .timeout:
                AppLogger.warning("Network error validating \(trimmedTicker): \(error.localizedDescription)")
                return .networkError(error)
            default:
                AppLogger.warning("API error validating \(trimmedTicker): \(error.localizedDescription)")
                return .networkError(error)
            }
        } catch {
            AppLogger.warning("Error validating ticker \(trimmedTicker): \(error.localizedDescription)")
            return .networkError(error)
        }
    }
}
