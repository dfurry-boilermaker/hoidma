import Foundation

// MARK: - API Configuration
/// Centralized API key management
///
/// SECURITY NOTE: In production, these keys should be:
/// 1. Stored in environment variables or a secure keychain
/// 2. Retrieved from a secure configuration service
/// 3. Never committed to version control
///
/// For development, you can set these as environment variables:
/// - POLYGON_API_KEY
/// - FMP_API_KEY
enum APIConfig {
    // MARK: - Polygon.io

    /// Polygon.io API key for stock data and company information
    /// Free tier: 5 API calls per minute
    /// Get your key at: https://polygon.io/
    static var polygonAPIKey: String {
        // Check environment variable first (preferred for security)
        if let envKey = ProcessInfo.processInfo.environment["POLYGON_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        // Fallback to hardcoded key (for development only)
        // TODO: Move to secure storage before production
        return "Ds3t3cHooEShvcG3nqYXmBTDBrLauU68"
    }

    // MARK: - Financial Modeling Prep

    /// Financial Modeling Prep API key for company logos and profiles
    /// Get your key at: https://financialmodelingprep.com/
    static var fmpAPIKey: String {
        // Check environment variable first (preferred for security)
        if let envKey = ProcessInfo.processInfo.environment["FMP_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        // Fallback to hardcoded key (for development only)
        // TODO: Move to secure storage before production
        return "Qadn9INnY2R9FEuFi5PwYRm7cwPp7Zwt"
    }

    // MARK: - API Endpoints

    enum Endpoints {
        static func polygonTickerInfo(ticker: String) -> String {
            "https://api.polygon.io/v3/reference/tickers/\(ticker.uppercased())?apiKey=\(polygonAPIKey)"
        }

        static func fmpProfile(ticker: String) -> String {
            "https://financialmodelingprep.com/api/v3/profile/\(ticker.uppercased())?apikey=\(fmpAPIKey)"
        }
    }
}
