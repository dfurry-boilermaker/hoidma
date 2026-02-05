import Foundation

/// Polygon.io API service for historical stock data
/// Pricing: Starter $29/mo = unlimited API calls, 5 years history
/// Free tier: 5 calls/minute - sufficient with caching
actor PolygonService {
    static let shared = PolygonService()

    private let baseURL = "https://api.polygon.io"
    private var apiKey: String { APIConfig.polygonAPIKey }

    /// Rate limiter for Polygon API
    private let rateLimiter = APIRateLimiter()

    // MARK: - Data Structures

    /// A single OHLCV bar from the aggregates endpoint
    struct AggregateBar: Codable, Sendable {
        let o: Double   // open
        let h: Double   // high
        let l: Double   // low
        let c: Double   // close
        let v: Double   // volume
        let t: Int64    // timestamp (milliseconds)
        let n: Int?     // number of trades
        let vw: Double? // volume weighted average price

        var date: Date {
            Date(timeIntervalSince1970: TimeInterval(t) / 1000)
        }

        /// Start of day for this bar (for keying purposes)
        var dayStart: Date {
            Calendar.current.startOfDay(for: date)
        }
    }

    /// Response from the aggregates endpoint
    struct AggregatesResponse: Codable {
        let ticker: String?
        let status: String
        let resultsCount: Int?
        let results: [AggregateBar]?
        let requestId: String?
        let count: Int?
        let adjusted: Bool?

        enum CodingKeys: String, CodingKey {
            case ticker, status, results, adjusted, count
            case resultsCount = "resultsCount"
            case requestId = "request_id"
        }
    }

    /// Error types specific to Polygon API
    enum PolygonError: Error, LocalizedError {
        case notConfigured
        case rateLimited
        case invalidResponse
        case noData
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Polygon API key not configured"
            case .rateLimited:
                return "Rate limited - please wait"
            case .invalidResponse:
                return "Invalid response from Polygon"
            case .noData:
                return "No data available for this ticker"
            case .apiError(let message):
                return "Polygon API error: \(message)"
            }
        }
    }

    // MARK: - Historical Data

    /// Fetch historical intraday bars for a ticker (15-minute intervals)
    /// - Parameters:
    ///   - ticker: Stock symbol (e.g., "AAPL")
    ///   - from: Start date/time
    ///   - to: End date/time
    /// - Returns: Array of 15-minute price bars sorted by date ascending
    func fetchIntradayBars(
        ticker: String,
        from: Date,
        to: Date
    ) async throws -> [AggregateBar] {
        // Check if API is configured
        guard APIConfig.isPolygonConfigured else {
            AppLogger.warning("Polygon API key not configured")
            throw PolygonError.notConfigured
        }

        // Check rate limit
        let config = APIRateLimiter.EndpointConfig.polygon
        guard await rateLimiter.canMakeRequest(endpoint: "polygon", config: config) else {
            let waitTime = await rateLimiter.timeUntilNextRequest(endpoint: "polygon", config: config)
            AppLogger.warning("Polygon rate limited, wait \(Int(waitTime))s")
            throw PolygonError.rateLimited
        }

        // Record the request
        await rateLimiter.recordRequest(endpoint: "polygon")

        // Format dates for intraday (need milliseconds timestamp)
        let fromMs = Int64(from.timeIntervalSince1970 * 1000)
        let toMs = Int64(to.timeIntervalSince1970 * 1000)

        // Build URL for 15-minute bars
        let path = "/v2/aggs/ticker/\(ticker.uppercased())/range/15/minute/\(fromMs)/\(toMs)"
        guard var components = URLComponents(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "adjusted", value: "true"),
            URLQueryItem(name: "sort", value: "asc"),
            URLQueryItem(name: "limit", value: "5000"),
            URLQueryItem(name: "apiKey", value: apiKey)
        ]

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        AppLogger.debug("Fetching Polygon 15min data for \(ticker)")

        // Make request
        var request = URLRequest(url: url)
        request.timeoutInterval = 15.0

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PolygonError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(AggregatesResponse.self, from: data)

            guard let results = decoded.results, !results.isEmpty else {
                AppLogger.debug("No Polygon intraday data for \(ticker)")
                throw PolygonError.noData
            }

            AppLogger.debug("Fetched \(results.count) 15min bars for \(ticker)")
            return results

        case 429:
            AppLogger.warning("Polygon rate limit hit for \(ticker)")
            throw PolygonError.rateLimited

        case 401, 403:
            AppLogger.error("Polygon auth error: \(httpResponse.statusCode)")
            throw APIError.unauthorized

        case 404:
            AppLogger.debug("Ticker not found: \(ticker)")
            throw PolygonError.noData

        case 400:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            AppLogger.error("Polygon HTTP 400 for \(ticker): \(errorMessage)")
            AppLogger.error("Request URL: \(url.absoluteString)")
            throw PolygonError.apiError("HTTP 400: Bad request")

        default:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            AppLogger.error("Polygon error \(httpResponse.statusCode): \(errorMessage)")
            throw PolygonError.apiError("HTTP \(httpResponse.statusCode)")
        }
    }

    /// Fetch historical daily bars for a ticker
    /// - Parameters:
    ///   - ticker: Stock symbol (e.g., "AAPL")
    ///   - from: Start date
    ///   - to: End date
    /// - Returns: Array of daily price bars sorted by date ascending
    func fetchDailyBars(
        ticker: String,
        from: Date,
        to: Date
    ) async throws -> [AggregateBar] {
        // Check if API is configured
        guard APIConfig.isPolygonConfigured else {
            AppLogger.warning("Polygon API key not configured")
            throw PolygonError.notConfigured
        }

        // Check rate limit
        let config = APIRateLimiter.EndpointConfig.polygon
        guard await rateLimiter.canMakeRequest(endpoint: "polygon", config: config) else {
            let waitTime = await rateLimiter.timeUntilNextRequest(endpoint: "polygon", config: config)
            AppLogger.warning("Polygon rate limited, wait \(Int(waitTime))s")
            throw PolygonError.rateLimited
        }

        // Record the request
        await rateLimiter.recordRequest(endpoint: "polygon")

        // Format dates (use UTC to avoid timezone issues)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0) // UTC
        let fromStr = dateFormatter.string(from: from)
        let toStr = dateFormatter.string(from: to)

        // Build URL
        let path = "/v2/aggs/ticker/\(ticker.uppercased())/range/1/day/\(fromStr)/\(toStr)"
        guard var components = URLComponents(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "adjusted", value: "true"),
            URLQueryItem(name: "sort", value: "asc"),
            URLQueryItem(name: "limit", value: "5000"),
            URLQueryItem(name: "apiKey", value: apiKey)
        ]

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        AppLogger.debug("Fetching Polygon data for \(ticker) from \(fromStr) to \(toStr)")

        // Make request
        var request = URLRequest(url: url)
        request.timeoutInterval = 15.0

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PolygonError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(AggregatesResponse.self, from: data)

            guard let results = decoded.results, !results.isEmpty else {
                AppLogger.debug("No Polygon data for \(ticker)")
                throw PolygonError.noData
            }

            AppLogger.debug("Fetched \(results.count) bars for \(ticker)")
            return results

        case 429:
            AppLogger.warning("Polygon rate limit hit for \(ticker)")
            throw PolygonError.rateLimited

        case 401, 403:
            AppLogger.error("Polygon auth error: \(httpResponse.statusCode)")
            throw APIError.unauthorized

        case 404:
            AppLogger.debug("Ticker not found: \(ticker)")
            throw PolygonError.noData

        case 400:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            AppLogger.error("Polygon HTTP 400 for \(ticker): \(errorMessage)")
            AppLogger.error("Request URL: \(url.absoluteString)")
            throw PolygonError.apiError("HTTP 400: Bad request")

        default:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            AppLogger.error("Polygon error \(httpResponse.statusCode): \(errorMessage)")
            throw PolygonError.apiError("HTTP \(httpResponse.statusCode)")
        }
    }

    /// Fetch historical data for multiple tickers in parallel
    /// Uses TaskGroup with concurrency limiting to respect rate limits
    /// - Parameters:
    ///   - tickers: Array of stock symbols
    ///   - from: Start date
    ///   - to: End date
    /// - Returns: Dictionary mapping ticker to array of bars
    func fetchDailyBarsForPortfolio(
        tickers: [String],
        from: Date,
        to: Date
    ) async -> [String: [AggregateBar]] {
        var results: [String: [AggregateBar]] = [:]

        // Process in batches of 3 to respect rate limits (5/min free tier)
        let batchSize = 3
        let batches = stride(from: 0, to: tickers.count, by: batchSize).map {
            Array(tickers[$0..<min($0 + batchSize, tickers.count)])
        }

        for (batchIndex, batch) in batches.enumerated() {
            // Add delay between batches (except first)
            if batchIndex > 0 {
                try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds between batches
            }

            await withTaskGroup(of: (String, [AggregateBar]).self) { group in
                for ticker in batch {
                    group.addTask {
                        do {
                            let bars = try await self.fetchDailyBars(ticker: ticker, from: from, to: to)
                            return (ticker, bars)
                        } catch {
                            AppLogger.warning("Failed to fetch \(ticker): \(error.localizedDescription)")
                            return (ticker, [])
                        }
                    }
                }

                for await (ticker, bars) in group {
                    results[ticker] = bars
                }
            }
        }

        return results
    }

    /// Get a single day's closing price for a ticker
    /// Useful for filling gaps in data
    func fetchClosingPrice(ticker: String, date: Date) async -> Double? {
        do {
            let bars = try await fetchDailyBars(ticker: ticker, from: date, to: date)
            return bars.first?.c
        } catch {
            return nil
        }
    }
}
