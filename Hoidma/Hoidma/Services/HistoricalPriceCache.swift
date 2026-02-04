import Foundation

/// Caches historical price data to minimize API calls
/// Stores in memory with optional Supabase persistence
actor HistoricalPriceCache {
    static let shared = HistoricalPriceCache()

    // MARK: - Cache Storage

    /// In-memory cache: ticker -> (date -> close price)
    private var priceCache: [String: [Date: Double]] = [:]

    /// Track when each ticker was last fetched
    private var lastFetchDate: [String: Date] = [:]

    /// Track the date range we have cached for each ticker
    private var cachedDateRange: [String: (from: Date, to: Date)] = [:]

    /// Cache duration before considering data stale (4 hours for intraday freshness)
    private let cacheDuration: TimeInterval = 4 * 60 * 60

    // MARK: - Public API

    /// Get historical prices for a ticker, fetching from API if needed
    /// - Parameters:
    ///   - ticker: Stock symbol
    ///   - from: Start date
    ///   - to: End date
    /// - Returns: Dictionary mapping dates to closing prices
    func getPrices(
        for ticker: String,
        from: Date,
        to: Date
    ) async -> [Date: Double] {
        let cacheKey = ticker.uppercased()
        let requestedFrom = Calendar.current.startOfDay(for: from)
        let requestedTo = Calendar.current.startOfDay(for: to)

        // Check if we have valid cached data covering the requested range
        if let lastFetch = lastFetchDate[cacheKey],
           Date().timeIntervalSince(lastFetch) < cacheDuration,
           let range = cachedDateRange[cacheKey],
           range.from <= requestedFrom && range.to >= requestedTo,
           let cached = priceCache[cacheKey] {
            AppLogger.debug("Cache hit for \(ticker)")
            return filterPrices(cached, from: requestedFrom, to: requestedTo)
        }

        // Need to fetch from API
        AppLogger.debug("Cache miss for \(ticker), fetching from Polygon")

        do {
            let bars = try await PolygonService.shared.fetchDailyBars(
                ticker: ticker,
                from: from,
                to: to
            )

            // Convert to [Date: Double] using close prices
            var prices: [Date: Double] = [:]
            for bar in bars {
                prices[bar.dayStart] = bar.c
            }

            // Merge with existing cache (if any) to preserve older data
            if var existing = priceCache[cacheKey] {
                existing.merge(prices) { _, new in new }
                priceCache[cacheKey] = existing
            } else {
                priceCache[cacheKey] = prices
            }

            // Update metadata
            lastFetchDate[cacheKey] = Date()

            // Update cached date range
            if let existingRange = cachedDateRange[cacheKey] {
                cachedDateRange[cacheKey] = (
                    from: min(existingRange.from, requestedFrom),
                    to: max(existingRange.to, requestedTo)
                )
            } else {
                cachedDateRange[cacheKey] = (from: requestedFrom, to: requestedTo)
            }

            return filterPrices(priceCache[cacheKey] ?? [:], from: requestedFrom, to: requestedTo)

        } catch {
            AppLogger.error("Failed to fetch prices for \(ticker): \(error.localizedDescription)")
            // Return whatever we have cached, even if stale
            return filterPrices(priceCache[cacheKey] ?? [:], from: requestedFrom, to: requestedTo)
        }
    }

    /// Get portfolio value history by calculating total value at each date
    /// - Parameters:
    ///   - holdings: Dictionary of ticker -> shares held
    ///   - from: Start date
    ///   - to: End date
    /// - Returns: Array of (date, totalValue) tuples sorted by date
    func getPortfolioHistory(
        holdings: [String: Double],
        from: Date,
        to: Date
    ) async -> [(date: Date, value: Double)] {
        guard !holdings.isEmpty else { return [] }

        // Fetch all tickers in parallel
        var allPrices: [String: [Date: Double]] = [:]

        await withTaskGroup(of: (String, [Date: Double]).self) { group in
            for ticker in holdings.keys {
                group.addTask {
                    let prices = await self.getPrices(for: ticker, from: from, to: to)
                    return (ticker, prices)
                }
            }

            for await (ticker, prices) in group {
                allPrices[ticker] = prices
            }
        }

        // Get all unique trading dates across all tickers
        let allDates = Set(allPrices.values.flatMap { $0.keys }).sorted()

        guard !allDates.isEmpty else {
            AppLogger.warning("No historical data available for portfolio")
            return []
        }

        // Calculate portfolio value for each date
        var portfolioHistory: [(date: Date, value: Double)] = []
        var lastKnownPrices: [String: Double] = [:]

        for date in allDates {
            var totalValue: Double = 0
            var hasAnyPrice = false

            for (ticker, shares) in holdings {
                // Use current date's price or carry forward last known price
                if let price = allPrices[ticker]?[date] {
                    lastKnownPrices[ticker] = price
                    totalValue += price * shares
                    hasAnyPrice = true
                } else if let lastPrice = lastKnownPrices[ticker] {
                    // Carry forward last known price (for weekends/holidays)
                    totalValue += lastPrice * shares
                    hasAnyPrice = true
                }
            }

            // Only add dates where we have at least some price data
            if hasAnyPrice && totalValue > 0 {
                portfolioHistory.append((date, totalValue))
            }
        }

        AppLogger.debug("Built portfolio history with \(portfolioHistory.count) data points")
        return portfolioHistory
    }

    /// Get normalized performance data for comparing multiple tickers
    /// All values normalized to 100 at the start date
    /// - Parameters:
    ///   - tickers: Array of stock symbols
    ///   - from: Start date
    ///   - to: End date
    /// - Returns: Dictionary mapping ticker to array of (date, normalizedValue)
    func getNormalizedPerformance(
        tickers: [String],
        from: Date,
        to: Date
    ) async -> [String: [(date: Date, value: Double)]] {
        var results: [String: [(date: Date, value: Double)]] = [:]

        for ticker in tickers {
            let prices = await getPrices(for: ticker, from: from, to: to)
            let sortedPrices = prices.sorted { $0.key < $1.key }

            guard let firstPrice = sortedPrices.first?.value, firstPrice > 0 else {
                continue
            }

            // Normalize to 100 at start
            let normalized = sortedPrices.map { (date, price) in
                (date: date, value: (price / firstPrice) * 100)
            }

            results[ticker] = normalized
        }

        return results
    }

    // MARK: - Cache Management

    /// Clear cache for a specific ticker
    func clearCache(for ticker: String) {
        let cacheKey = ticker.uppercased()
        priceCache.removeValue(forKey: cacheKey)
        lastFetchDate.removeValue(forKey: cacheKey)
        cachedDateRange.removeValue(forKey: cacheKey)
    }

    /// Clear all cached data
    func clearAllCache() {
        priceCache.removeAll()
        lastFetchDate.removeAll()
        cachedDateRange.removeAll()
        AppLogger.debug("Cleared all historical price cache")
    }

    /// Get cache statistics for debugging
    func getCacheStats() -> (tickerCount: Int, totalDataPoints: Int) {
        let tickerCount = priceCache.count
        let totalDataPoints = priceCache.values.reduce(0) { $0 + $1.count }
        return (tickerCount, totalDataPoints)
    }

    // MARK: - Private Helpers

    private func filterPrices(_ prices: [Date: Double], from: Date, to: Date) -> [Date: Double] {
        prices.filter { $0.key >= from && $0.key <= to }
    }
}
