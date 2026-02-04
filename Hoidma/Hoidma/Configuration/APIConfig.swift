import Foundation

// MARK: - API Configuration

/// Centralized API key management
///
/// SECURITY CRITICAL: API keys must NEVER be hardcoded in source code.
///
/// Configuration Method (xcconfig files - RECOMMENDED):
/// 1. Edit Configuration/Debug.xcconfig with your API keys
/// 2. Edit Configuration/Release.xcconfig for production keys
/// 3. In Xcode: Project > Info > Configurations
///    - Set Debug to use Debug.xcconfig
///    - Set Release to use Release.xcconfig
/// 4. Keys are automatically injected into Info.plist at build time
///
/// Note: Debug.xcconfig and Release.xcconfig are gitignored.
/// Use the .template files as reference.
///
/// For CI/CD: Override at build time with:
///   xcodebuild POLYGON_API_KEY=xxx FMP_API_KEY=xxx
///
/// Key lookup order:
/// 1. Environment variables (for CI/CD override)
/// 2. Info.plist (injected via xcconfig at build time)
enum APIConfig: Sendable {

    // MARK: - Configuration Keys

    /// Placeholder value used when no API key is configured
    /// This is intentionally obvious to prevent accidental use
    nonisolated private static let notConfiguredPlaceholder = "API_KEY_NOT_CONFIGURED"

    // MARK: - Polygon.io Subscription Tiers

    /// Polygon.io subscription tier configuration
    enum PolygonSubscription {
        case free       // 5 calls/min
        case starter    // Unlimited calls, 5 years historical data

        nonisolated var callsPerMinute: Int {
            switch self {
            case .free:
                return 5
            case .starter:
                return Int.max  // Unlimited
            }
        }

        var description: String {
            switch self {
            case .free:
                return "Free (5 calls/min)"
            case .starter:
                return "Starter (Unlimited calls)"
            }
        }
    }

    /// Current Polygon.io subscription tier
    /// Set to .starter when using paid subscription ($29/month)
    /// IMPORTANT: Update this when upgrading subscription
    nonisolated static let polygonTier: PolygonSubscription = .starter

    // MARK: - Polygon.io

    /// Polygon.io API key for stock data and company information
    /// Free tier: 5 API calls per minute
    /// Starter tier: Unlimited API calls, 5 years historical data
    /// Get your key at: https://polygon.io/
    nonisolated static var polygonAPIKey: String {
        // Check environment variable first (required for production)
        if let envKey = ProcessInfo.processInfo.environment["POLYGON_API_KEY"],
           !envKey.isEmpty,
           envKey != notConfiguredPlaceholder {
            return envKey
        }

        // Check Info.plist for build-time injection
        if let plistKey = Bundle.main.object(forInfoDictionaryKey: "POLYGON_API_KEY") as? String,
           !plistKey.isEmpty,
           plistKey != "$(POLYGON_API_KEY)",
           plistKey != notConfiguredPlaceholder {
            return plistKey
        }

        // SECURITY: No hardcoded fallback - return placeholder
        // This ensures the app fails safely if keys aren't configured
        AppLogger.warning("Polygon.io API key not configured - API features will be limited")
        return notConfiguredPlaceholder
    }

    /// Check if Polygon API is configured
    nonisolated static var isPolygonConfigured: Bool {
        let key = polygonAPIKey
        return !key.isEmpty && key != notConfiguredPlaceholder
    }

    // MARK: - Financial Modeling Prep

    /// Financial Modeling Prep API key for company logos and profiles
    /// Free tier: 250 calls per day
    /// Get your key at: https://financialmodelingprep.com/
    nonisolated static var fmpAPIKey: String {
        // Check environment variable first (required for production)
        if let envKey = ProcessInfo.processInfo.environment["FMP_API_KEY"],
           !envKey.isEmpty,
           envKey != notConfiguredPlaceholder {
            return envKey
        }

        // Check Info.plist for build-time injection
        if let plistKey = Bundle.main.object(forInfoDictionaryKey: "FMP_API_KEY") as? String,
           !plistKey.isEmpty,
           plistKey != "$(FMP_API_KEY)",
           plistKey != notConfiguredPlaceholder {
            return plistKey
        }

        // SECURITY: No hardcoded fallback - return placeholder
        AppLogger.warning("FMP API key not configured - API features will be limited")
        return notConfiguredPlaceholder
    }

    /// Check if FMP API is configured
    nonisolated static var isFMPConfigured: Bool {
        let key = fmpAPIKey
        return !key.isEmpty && key != notConfiguredPlaceholder
    }

    // MARK: - API Endpoints

    /// URL builder for API endpoints
    /// SECURITY: Uses URLComponents to properly encode parameters
    enum Endpoints: Sendable {

        /// Build Polygon.io ticker info URL
        /// - Parameter ticker: Stock ticker symbol
        /// - Returns: URL if API is configured, nil otherwise
        nonisolated static func polygonTickerInfo(ticker: String) -> URL? {
            guard isPolygonConfigured else { return nil }

            var components = URLComponents()
            components.scheme = "https"
            components.host = "api.polygon.io"
            components.path = "/v3/reference/tickers/\(ticker.uppercased())"
            components.queryItems = [
                URLQueryItem(name: "apiKey", value: polygonAPIKey)
            ]

            return components.url
        }

        /// Build Polygon.io last trade URL
        /// - Parameter ticker: Stock ticker symbol
        /// - Returns: URL if API is configured, nil otherwise
        nonisolated static func polygonLastTrade(ticker: String) -> URL? {
            guard isPolygonConfigured else { return nil }

            var components = URLComponents()
            components.scheme = "https"
            components.host = "api.polygon.io"
            components.path = "/v2/last/trade/\(ticker.uppercased())"
            components.queryItems = [
                URLQueryItem(name: "apiKey", value: polygonAPIKey)
            ]

            return components.url
        }

        /// Build Polygon.io previous close URL
        /// - Parameter ticker: Stock ticker symbol
        /// - Returns: URL if API is configured, nil otherwise
        nonisolated static func polygonPreviousClose(ticker: String) -> URL? {
            guard isPolygonConfigured else { return nil }

            var components = URLComponents()
            components.scheme = "https"
            components.host = "api.polygon.io"
            components.path = "/v2/aggs/ticker/\(ticker.uppercased())/prev"
            components.queryItems = [
                URLQueryItem(name: "adjusted", value: "true"),
                URLQueryItem(name: "apiKey", value: polygonAPIKey)
            ]

            return components.url
        }

        /// Build Polygon.io aggregates URL
        /// - Parameters:
        ///   - ticker: Stock ticker symbol
        ///   - multiplier: Size of timespan (e.g., 1 for 1 day)
        ///   - timespan: Size of time window (day, week, month, etc.)
        ///   - from: Start date (YYYY-MM-DD)
        ///   - to: End date (YYYY-MM-DD)
        /// - Returns: URL if API is configured, nil otherwise
        nonisolated static func polygonAggregates(
            ticker: String,
            multiplier: Int = 1,
            timespan: String = "day",
            from: String,
            to: String,
            limit: Int = 50000
        ) -> URL? {
            guard isPolygonConfigured else { return nil }

            var components = URLComponents()
            components.scheme = "https"
            components.host = "api.polygon.io"
            components.path = "/v2/aggs/ticker/\(ticker.uppercased())/range/\(multiplier)/\(timespan)/\(from)/\(to)"
            components.queryItems = [
                URLQueryItem(name: "adjusted", value: "true"),
                URLQueryItem(name: "sort", value: "asc"),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "apiKey", value: polygonAPIKey)
            ]

            return components.url
        }

        /// Build FMP profile URL
        /// - Parameter ticker: Stock ticker symbol
        /// - Returns: URL if API is configured, nil otherwise
        nonisolated static func fmpProfile(ticker: String) -> URL? {
            guard isFMPConfigured else { return nil }

            var components = URLComponents()
            components.scheme = "https"
            components.host = "financialmodelingprep.com"
            components.path = "/api/v3/profile/\(ticker.uppercased())"
            components.queryItems = [
                URLQueryItem(name: "apikey", value: fmpAPIKey)
            ]

            return components.url
        }
    }

    // MARK: - Validation

    /// Validate API configuration on app startup
    /// Logs warnings for missing keys but doesn't prevent app from running
    static func validateConfiguration() {
        var warnings: [String] = []

        if !isPolygonConfigured {
            warnings.append("Polygon.io API key not configured")
        }

        if !isFMPConfigured {
            warnings.append("Financial Modeling Prep API key not configured")
        }

        if !warnings.isEmpty {
            AppLogger.warning("API Configuration: \(warnings.joined(separator: ", "))")
            AppLogger.info("Set API keys via environment variables or Info.plist")
        }
    }
}
