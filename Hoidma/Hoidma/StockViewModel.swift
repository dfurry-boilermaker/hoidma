import Foundation
import Combine
import SwiftUI

class StockViewModel: ObservableObject {
    @Published var stocks: [Stock] = []
    @Published var stockPrices: [String: StockPriceData] = [:]
    @Published var stockSectors: [String: String] = [:]
    @Published var isDataReady: Bool = false

    // Used to update prices every 30 seconds (reduced frequency to respect API limits)
    private var timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private let localStorageKey = "localStocks"

    // Use centralized environment configuration
    private var useLocalStorage: Bool { AppEnvironment.useLocalStorage }
    private var isUITesting: Bool { AppEnvironment.isUITesting }

    // Supabase Manager for cloud storage (only used if not using local storage)
    let manager = SupabaseManager()

    // API service for fetching real stock data
    private let apiService = StockAPIService.shared

    private var cancellables = Set<AnyCancellable>()

    /// SECURITY FIX: Store task references for proper cancellation
    /// This prevents memory leaks from orphaned tasks
    private var activeTasks: [Task<Void, Never>] = []
    private let taskLock = NSLock()
    
    init() {
        if useLocalStorage {
            // Load from local storage
            loadLocalStocks()
        } else {
            // Use Supabase - listener starts automatically when user authenticates
            // Monitor stocks from the Supabase Manager
            manager.$stocks
                .sink { [weak self] newStocks in
                    guard let self = self else { return }
                    self.stocks = newStocks
                    // Initialize prices for new stocks using API (skip in UI tests)
                    if !self.isUITesting {
                        self.trackTask(Task { [weak self] in
                            await self?.updateAllPrices()
                        })
                    }
                }
                .store(in: &cancellables)
        }

        // Start the price update timer (fetches real data from API) - SKIP IN UI TESTS
        if !isUITesting {
            timer
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    self.trackTask(Task { [weak self] in
                        await self?.updateAllPrices()
                    })
                }
                .store(in: &cancellables)
        } else {
            AppEnvironment.testingLog(" Price update timer disabled")
        }
    }

    deinit {
        // SECURITY FIX: Cancel all active tasks to prevent memory leaks
        cancelAllTasks()
        cancellables.removeAll()
    }

    // MARK: - Task Management

    /// Track a task for later cancellation
    private func trackTask(_ task: Task<Void, Never>) {
        taskLock.lock()
        defer { taskLock.unlock() }

        // Clean up completed tasks
        activeTasks.removeAll { $0.isCancelled }
        activeTasks.append(task)
    }

    /// Cancel all active tasks
    private func cancelAllTasks() {
        taskLock.lock()
        defer { taskLock.unlock() }

        for task in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()
    }
    
    // Load stocks from local storage
    private func loadLocalStocks() {
        if let data = UserDefaults.standard.data(forKey: localStorageKey),
           let decoded = try? JSONDecoder().decode([Stock].self, from: data) {
            let sanitizedStocks = decoded.compactMap { stock -> Stock? in
                let trimmedTicker = stock.ticker.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedTicker.isEmpty else { return nil }
                let normalizedTicker = trimmedTicker.uppercased()
                if normalizedTicker == stock.ticker {
                    return stock
                }
                return Stock(
                    ticker: normalizedTicker,
                    companyName: stock.companyName,
                    purchasePrice: stock.purchasePrice,
                    shares: stock.shares,
                    isMaritalStatus: stock.isMaritalStatus,
                    lots: stock.lots
                )
            }
            self.stocks = sanitizedStocks.filter { $0.isMaritalStatus }
            AppLogger.info("Loaded \(self.stocks.count) stocks from local storage")
            
            // Initialize prices for loaded stocks (SKIP IN UI TESTS to prevent crashes)
            if !isUITesting {
                // Defer price updates to avoid blocking initialization
                trackTask(Task { @MainActor [weak self] in
                    await self?.updateAllPrices()
                })
            } else {
                // In UI tests, just set placeholder prices to avoid API calls
                // Do this synchronously on main thread to avoid async issues
                AppEnvironment.testingLog(" Setting placeholder prices for \(self.stocks.count) stocks")
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    for stock in self.stocks {
                        let placeholderPrice = stock.purchasePrice * 1.1 // 10% gain
                        self.updatePriceData(for: stock, newPrice: placeholderPrice, beta: self.stockPrices[stock.ticker]?.beta, isETF: self.stockPrices[stock.ticker]?.isETF)
                    }
                    self.updateColorAssignments()
                }
            }
        } else {
            AppLogger.debug("No local stocks found, starting with empty portfolio")
        }
    }
    
    /// Updates color assignments based on current stock values (largest to smallest)
    @MainActor
    func updateColorAssignments() {
        let sortedTickers = stocks
            .filter { $0.isMaritalStatus }
            .sorted { stock1, stock2 in
                let shares1 = stock1.lots.isEmpty ? Double(stock1.shares) : stock1.lots.reduce(0.0) { $0 + $1.shares }
                let shares2 = stock2.lots.isEmpty ? Double(stock2.shares) : stock2.lots.reduce(0.0) { $0 + $1.shares }
                let price1 = stockPrices[stock1.ticker]?.currentPrice ?? stock1.purchasePrice
                let price2 = stockPrices[stock2.ticker]?.currentPrice ?? stock2.purchasePrice
                return (price1 * shares1) > (price2 * shares2)
            }
            .map { $0.ticker }

        StockColorManager.shared.updateColorAssignments(sortedTickers: sortedTickers)
    }

    // Save stocks to local storage
    private func saveLocalStocks() {
        // UserDefaults is fast for small datasets, so synchronous is fine
        if let encoded = try? JSONEncoder().encode(stocks) {
            UserDefaults.standard.set(encoded, forKey: localStorageKey)
            AppLogger.debug("Saved \(stocks.count) stocks to local storage")
        } else {
            AppLogger.error("Failed to save stocks to local storage")
        }
    }
    
    /// Updates prices for all stocks using the API
    /// Uses Supabase server-side cache when available, falls back to direct Yahoo API
    @MainActor
    func updateAllPrices() async {
        // SKIP API CALLS IN UI TESTS to prevent crashes
        if isUITesting {
            AppEnvironment.testingLog(" Skipping updateAllPrices()")
            isDataReady = true
            return
        }

        let activeStocks = stocks.filter { stock in
            stock.isMaritalStatus && !stock.ticker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !activeStocks.isEmpty else {
            // No stocks to load, mark as ready
            isDataReady = true
            return
        }

        let tickers = activeStocks.map { $0.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }

        // Fetch prices using Supabase with Yahoo fallback
        // This reduces direct API calls and supports multiple users
        let stockDataDict = await apiService.fetchStockDataWithFallback(for: tickers)

        for stock in activeStocks {
            if let stockData = stockDataDict[stock.ticker] {
                // Check if this is a new stock (no existing price data)
                let isNewStock = stockPrices[stock.ticker] == nil

                // For new stocks, fetch historical prices to initialize period start prices
                var historicalPrices: [String: Double]? = nil
                if isNewStock {
                    historicalPrices = await apiService.fetchHistoricalPrices(for: stock.ticker)
                    AppLogger.debug("Fetched historical prices for \(stock.ticker)")
                }

                // Update price with historical data and API period changes if available
                updatePriceData(for: stock, newPrice: stockData.price, historicalPrices: historicalPrices, apiPeriodChanges: stockData.periodChanges, previousClose: stockData.previousClose, beta: stockData.beta, isETF: stockData.isETF)

                // Update company name if API returns a real name (not just the ticker)
                // Also update if current name is just the ticker placeholder
                let apiHasRealName = !stockData.companyName.isEmpty && stockData.companyName != stock.ticker.uppercased()
                let currentNameIsPlaceholder = stock.companyName == stock.ticker.uppercased() || stock.companyName == stock.ticker
                if apiHasRealName && (stock.companyName != stockData.companyName || currentNameIsPlaceholder) {
                    updateCompanyName(for: stock.ticker, newName: stockData.companyName)
                }
            } else {
                // DATA INTEGRITY: Do NOT update price with fake data when API fails
                // Keep last known good price instead of showing fabricated numbers
                AppLogger.error("❌ API failed for \(stock.ticker) - keeping last known price (no fake data)")
                // Price remains unchanged - better to show stale real data than fake data
            }
        }

        // Update color assignments based on new values
        updateColorAssignments()

        // Mark data as ready after first successful load
        if !isDataReady {
            isDataReady = true
            AppLogger.info("Stock data ready - all prices loaded")
        }
    }

    /// Manually refresh stock prices by triggering the Edge Function
    /// Use this for pull-to-refresh or refresh button
    @MainActor
    func manualRefresh() async {
        // SKIP API CALLS IN UI TESTS
        if isUITesting {
            AppEnvironment.testingLog(" Skipping manualRefresh()")
            return
        }

        let tickers = stocks
            .filter { $0.isMaritalStatus && !$0.ticker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { $0.ticker.uppercased() }

        guard !tickers.isEmpty else { return }

        AppLogger.info("Manual refresh triggered for \(tickers.count) stocks")

        // Trigger the Edge Function to fetch fresh prices from Yahoo
        let success = await apiService.refreshPricesNow()

        if success {
            // Wait briefly for the server to update
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

            // Fetch the updated prices from Supabase
            await updateAllPrices()
        } else {
            // Edge Function failed, fall back to direct API calls
            AppLogger.warning("Edge Function failed, falling back to direct API")
            apiService.useServerSidePrices = false
            await updateAllPrices()
            apiService.useServerSidePrices = true
        }
    }

    /// Updates the company name for a stock
    @MainActor
    private func updateCompanyName(for ticker: String, newName: String) {
        // Find and update the stock in the local stocks array
        if let index = stocks.firstIndex(where: { $0.ticker == ticker }) {
            var updatedStock = stocks[index]
            updatedStock.companyName = newName
            stocks[index] = updatedStock  // Replace entire object to trigger UI update

            if useLocalStorage {
                saveLocalStocks()
            } else {
                // Also update in manager's stocks array for Supabase mode
                if let managerIndex = manager.stocks.firstIndex(where: { $0.ticker == ticker }) {
                    manager.stocks[managerIndex] = updatedStock
                }
            }

            AppLogger.debug("Updated company name for \(ticker)")
        }
    }
    
    /// Updates price for a single stock (async version for API calls)
    func updatePrice(for stock: Stock) {
        let trimmedTicker = stock.ticker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard stock.isMaritalStatus, !trimmedTicker.isEmpty else { return }
        
        // SKIP API CALLS IN UI TESTS
        if isUITesting {
            AppEnvironment.testingLog(" Skipping updatePrice for \(stock.ticker)")
            // Set placeholder price
            let placeholderPrice = stock.purchasePrice * 1.1
            updatePriceData(for: stock, newPrice: placeholderPrice, beta: stockPrices[stock.ticker]?.beta, isETF: stockPrices[stock.ticker]?.isETF)
            return
        }
        
        trackTask(Task { [weak self] in
            guard let self = self else { return }

            let isNewStock = await MainActor.run { self.stockPrices[stock.ticker] == nil }

            // For new stocks, fetch historical prices
            var historicalPrices: [String: Double]? = nil
            if isNewStock {
                historicalPrices = await self.apiService.fetchHistoricalPrices(for: stock.ticker)
                AppLogger.debug("Fetched historical prices for \(stock.ticker)")
            }

            if let stockData = await self.apiService.fetchStockData(for: stock.ticker) {
                await MainActor.run { [weak self] in
                    self?.updatePriceData(for: stock, newPrice: stockData.price, historicalPrices: historicalPrices, apiPeriodChanges: stockData.periodChanges, previousClose: stockData.previousClose, beta: stockData.beta, isETF: stockData.isETF, dataSource: stockData.dataSource)
                }
            } else {
                // DATA INTEGRITY: Do NOT update price with fake data when API fails
                // Keep last known good price instead of showing fabricated numbers
                AppLogger.error("❌ API failed for \(stock.ticker) - keeping last known price (no fake data)")
                // Price remains unchanged - better to show stale real data than fake data
            }
        })
    }

    /// Updates the price data structure with a new price
    @MainActor
    private func updatePriceData(for stock: Stock, newPrice: Double, historicalPrices: [String: Double]? = nil, apiPeriodChanges: [String: Double]? = nil, previousClose: Double? = nil, beta: Double? = nil, isETF: Bool? = nil, dataSource: String? = nil) {
        let newProfitLoss = (newPrice * Double(stock.shares)) - stock.totalCost
        let newChangePercent = (newProfitLoss / stock.totalCost) * 100
        
        let now = Date()
        let existingData = stockPrices[stock.ticker]
        
        let calendar = Calendar.current
        
        // Initialize or update period start prices
        let isNewStock = existingData == nil

        // For daily, ONLY use previousClose from API (most reliable source)
        // Do NOT use historicalPrices["1d"] as primary source - it can be stale
        var dailyStartPrice: Double

        if let prevClose = previousClose, prevClose > 0 {
            // CRITICAL FIX: Validate against existing previousClose to detect Yahoo's inconsistent data
            // If we already have a good previousClose from today, and the new one differs significantly,
            // reject the new one (likely stale data from Yahoo)
            if let existingDaily = existingData?.dailyStartPrice,
               let existingStartTime = existingData?.dailyStartTime,
               calendar.isDate(existingStartTime, inSameDayAs: now),
               existingDaily > 0 {
                let difference = abs((prevClose - existingDaily) / existingDaily * 100)
                let existingSource = existingData?.dataSource

                // CRITICAL: Only reject if Yahoo is trying to replace Polygon data with very different value
                // For Yahoo-to-Yahoo or other updates, accept the new value (it's fresher data)
                if existingSource == "polygon" && dataSource == "yahoo" && difference > 0.5 {
                    // Polygon data exists, Yahoo differs significantly - keep Polygon (more reliable)
                    AppLogger.warning("\(stock.ticker) Rejecting Yahoo previousClose (\(prevClose)) - differs \(String(format: "%.2f", difference))% from Polygon (\(existingDaily)). Keeping Polygon data.")
                    dailyStartPrice = existingDaily
                } else if difference > 5.0 {
                    // Same source or no source info, but difference is huge (>5%) - likely error
                    AppLogger.error("⚠️ \(stock.ticker) previousClose changed drastically (\(String(format: "%.2f", difference))%): \(existingDaily) → \(prevClose). Rejecting.")
                    dailyStartPrice = existingDaily
                } else {
                    // Accept new previousClose (fresher data or reasonable change)
                    dailyStartPrice = prevClose
                    AppLogger.debug("\(stock.ticker) dailyStartPrice from previousClose: \(prevClose) (source: \(dataSource ?? "unknown"), diff: \(String(format: "%.2f", difference))%)")
                }
            } else {
                // No existing data from today, validate against current price
                let ratio = newPrice / prevClose
                if ratio >= 0.5 && ratio <= 2.0 {
                    dailyStartPrice = prevClose
                    AppLogger.debug("\(stock.ticker) dailyStartPrice from previousClose: \(prevClose)")
                } else {
                    // DATA QUALITY WARNING: Invalid previousClose
                    // Setting dailyStartPrice = newPrice will show 0% change, which is misleading
                    // Better to show no data than fake 0% change, but keeping for backward compat
                    dailyStartPrice = newPrice
                    AppLogger.error("⚠️ DATA QUALITY: \(stock.ticker) previousClose \(prevClose) invalid (ratio: \(String(format: "%.2f", ratio))) - daily % will show 0% (misleading!)")
                }
            }
        } else if let existingDaily = existingData?.dailyStartPrice, existingDaily > 0 {
            // Keep existing if we don't have new data
            let ratio = newPrice / existingDaily
            if ratio >= 0.5 && ratio <= 2.0 {
                dailyStartPrice = existingDaily
            } else {
                // DATA QUALITY WARNING: Existing dailyStartPrice invalid
                dailyStartPrice = newPrice
                AppLogger.error("⚠️ DATA QUALITY: \(stock.ticker) existing dailyStartPrice invalid - daily % will show 0% (misleading!)")
            }
        } else if let historicalDaily = historicalPrices?["1d"], historicalDaily > 0 {
            // Last resort: use historical data
            dailyStartPrice = historicalDaily
        } else {
            // DATA QUALITY WARNING: No previousClose data available
            // Setting dailyStartPrice = newPrice will make daily % show 0%, which is misleading
            // Users will think stock didn't move when reality is we don't have yesterday's data
            dailyStartPrice = newPrice
            AppLogger.error("⚠️ DATA QUALITY: \(stock.ticker) has NO previousClose data - daily % will incorrectly show 0%")
        }

        var weeklyStartPrice = existingData?.weeklyStartPrice ?? (historicalPrices?["1w"] ?? newPrice)
        var monthlyStartPrice = existingData?.monthlyStartPrice ?? (historicalPrices?["1m"] ?? newPrice)
        var threeMonthsStartPrice = existingData?.threeMonthsStartPrice ?? (historicalPrices?["3m"] ?? newPrice)
        var ytdStartPrice = existingData?.ytdStartPrice ?? (historicalPrices?["ytd"] ?? newPrice)
        // For all-time, use purchase price if new stock, otherwise keep existing
        // All time never resets, so use let instead of var
        let allTimeStartPrice = existingData?.allTimeStartPrice ?? stock.purchasePrice
        
        var dailyStartTime = existingData?.dailyStartTime ?? now
        var weeklyStartTime = existingData?.weeklyStartTime ?? now
        var monthlyStartTime = existingData?.monthlyStartTime ?? now
        var threeMonthsStartTime = existingData?.threeMonthsStartTime ?? now
        var ytdStartTime = existingData?.ytdStartTime ?? now
        var allTimeStartTime = existingData?.allTimeStartTime ?? now
        
        // For new stocks, initialize start times based on historical data or now
        if isNewStock {
            // Set start times based on when historical prices were from
            if historicalPrices != nil {
                // Use approximate dates for historical prices
                dailyStartTime = calendar.date(byAdding: .day, value: -1, to: now) ?? now
                weeklyStartTime = calendar.date(byAdding: .day, value: -7, to: now) ?? now
                monthlyStartTime = calendar.date(byAdding: .month, value: -1, to: now) ?? now
                threeMonthsStartTime = calendar.date(byAdding: .month, value: -3, to: now) ?? now
                if let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now)) {
                    ytdStartTime = startOfYear
                } else {
                    ytdStartTime = now
                }
            } else {
                // No historical data, use current time
                dailyStartTime = now
                weeklyStartTime = now
                monthlyStartTime = now
                threeMonthsStartTime = now
                ytdStartTime = now
            }
            allTimeStartTime = now
        }
        
        // Reset daily price if it's a new day
        // CRITICAL: ONLY reset if we have valid previousClose from API
        // Do NOT update dailyStartTime unless we also update dailyStartPrice
        if !calendar.isDate(dailyStartTime, inSameDayAs: now) {
            if let prevClose = previousClose, prevClose > 0 {
                let ratio = newPrice / prevClose
                if ratio >= 0.5 && ratio <= 2.0 {
                    dailyStartPrice = prevClose
                    dailyStartTime = now  // Update time only when we update price
                    AppLogger.debug("\(stock.ticker) daily reset with previousClose: \(prevClose)")
                } else {
                    AppLogger.warning("\(stock.ticker) previousClose \(prevClose) invalid ratio \(ratio), keeping old dailyStartPrice")
                }
            } else {
                AppLogger.warning("\(stock.ticker) new day detected but no valid previousClose - keeping old dailyStartPrice to avoid stale data")
                // Do NOT update dailyStartTime - this way it will retry on next update
            }
        }
        
        // Reset weekly price if it's been 7 days
        if let daysSinceWeekly = calendar.dateComponents([.day], from: weeklyStartTime, to: now).day, daysSinceWeekly >= 7 {
            weeklyStartPrice = newPrice
            weeklyStartTime = now
        }
        
        // Reset monthly price if it's been 30 days
        if let daysSinceMonthly = calendar.dateComponents([.day], from: monthlyStartTime, to: now).day, daysSinceMonthly >= 30 {
            monthlyStartPrice = newPrice
            monthlyStartTime = now
        }
        
        // Reset 3 months price if it's been 90 days
        if let daysSinceThreeMonths = calendar.dateComponents([.day], from: threeMonthsStartTime, to: now).day, daysSinceThreeMonths >= 90 {
            threeMonthsStartPrice = newPrice
            threeMonthsStartTime = now
        }
        
        // Reset YTD price if it's a new year
        if !calendar.isDate(ytdStartTime, equalTo: now, toGranularity: .year) {
            ytdStartPrice = newPrice
            ytdStartTime = now
        }
        
        // All time never resets - keep the original purchase price or first tracked price
        
        // Merge API period changes with existing ones (API values take precedence)
        var updatedApiPeriodChanges = existingData?.apiPeriodChanges ?? [:]

        // CRITICAL FIX: If we rejected the API's previousClose (detected above), also reject its daily %
        // Check if dailyStartPrice differs from the API's previousClose
        var rejectedInconsistentPreviousClose = false
        if let prevClose = previousClose, prevClose > 0, dailyStartPrice != prevClose {
            let difference = abs((prevClose - dailyStartPrice) / dailyStartPrice * 100)
            if difference > 0.1 {  // They differ - we rejected the API's previousClose
                rejectedInconsistentPreviousClose = true
                AppLogger.warning("\(stock.ticker) Rejected API's previousClose (\(prevClose)), so also rejecting its daily % calculation")
            }
        }

        if let apiChanges = apiPeriodChanges {
            if apiChanges.isEmpty {
                // CRITICAL FIX: Empty dictionary means API failed - clear all API percentages
                // to force recalculation from previousClose/dailyStartPrice
                AppLogger.warning("\(stock.ticker) API returned empty periodChanges (likely API failure) - clearing all cached API percentages")
                updatedApiPeriodChanges = [:]
            } else if rejectedInconsistentPreviousClose {
                // Don't merge API's daily % since we rejected its previousClose
                // But keep other period changes (weekly, monthly, etc.) if valid
                var filteredChanges = apiChanges
                filteredChanges.removeValue(forKey: "1d")
                updatedApiPeriodChanges.merge(filteredChanges) { (_, new) in new }
                updatedApiPeriodChanges.removeValue(forKey: "1d")  // Also clear any existing stale daily %
            } else {
                updatedApiPeriodChanges.merge(apiChanges) { (_, new) in new }
            }
        } else {
            // DEFENSIVE FIX: If API returns nil periodChanges on a new day, clear the daily cache
            // to force recalculation from previousClose
            if let existingDaily = updatedApiPeriodChanges["1d"],
               let existingStartTime = existingData?.dailyStartTime,
               !calendar.isDate(existingStartTime, inSameDayAs: now) {
                AppLogger.warning("\(stock.ticker) API returned nil periodChanges on new day - clearing stale daily value (was: \(String(format: "%.2f", existingDaily))%)")
                updatedApiPeriodChanges.removeValue(forKey: "1d")
            }
        }

        // Validate API daily % against calculated daily % to catch stale values
        if let apiDaily = updatedApiPeriodChanges["1d"], dailyStartPrice > 0, dailyStartPrice != newPrice {
            let calculatedDaily = ((newPrice - dailyStartPrice) / dailyStartPrice) * 100
            let difference = abs(apiDaily - calculatedDaily)

            if difference > 5.0 {  // >5% difference suggests stale API value
                AppLogger.warning("\(stock.ticker) API daily change (\(String(format: "%.2f", apiDaily))%) differs significantly from calculated (\(String(format: "%.2f", calculatedDaily))%) - using calculated")
                updatedApiPeriodChanges["1d"] = calculatedDaily
            }
        }

        // Update previous close - use the VALIDATED dailyStartPrice (not the raw API value)
        // This ensures previousClose matches what we're actually using for calculations
        // Prevents storing rejected/invalid previousClose values
        let updatedPreviousClose = dailyStartPrice

        // Update beta if provided (use existing if not provided)
        let updatedBeta = beta ?? existingData?.beta

        // Update isETF if provided (use existing if not provided)
        let updatedIsETF = isETF ?? existingData?.isETF

        // Update data source if provided (keep existing if new source is nil or unknown)
        let updatedDataSource = dataSource ?? existingData?.dataSource

        withAnimation {
            stockPrices[stock.ticker] = StockPriceData(
                ticker: stock.ticker,
                currentPrice: newPrice,
                changePercent: newChangePercent,
                profitLoss: newProfitLoss,
                dailyStartPrice: dailyStartPrice,
                weeklyStartPrice: weeklyStartPrice,
                monthlyStartPrice: monthlyStartPrice,
                threeMonthsStartPrice: threeMonthsStartPrice,
                ytdStartPrice: ytdStartPrice,
                allTimeStartPrice: allTimeStartPrice,
                dailyStartTime: dailyStartTime,
                weeklyStartTime: weeklyStartTime,
                monthlyStartTime: monthlyStartTime,
                threeMonthsStartTime: threeMonthsStartTime,
                ytdStartTime: ytdStartTime,
                allTimeStartTime: allTimeStartTime,
                apiPeriodChanges: updatedApiPeriodChanges,
                previousClose: updatedPreviousClose,
                beta: updatedBeta,
                isETF: updatedIsETF,
                dataSource: updatedDataSource
            )
        }
    }
    
    // MARK: - Ticker Validation

    /// Status result for ticker validation
    enum TickerValidationStatus {
        case valid
        case alreadyInPortfolio
        case invalid(message: String)
        case networkError(message: String)
    }

    /// Validates a ticker symbol before adding to portfolio
    /// Uses tiered approach: local portfolio check, Supabase cache, Yahoo Finance API
    /// - Parameter ticker: Stock ticker symbol to validate
    /// - Returns: TickerValidationStatus indicating result
    @MainActor
    func validateTicker(_ ticker: String) async -> TickerValidationStatus {
        let trimmedTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        // Empty ticker check
        guard !trimmedTicker.isEmpty else {
            return .invalid(message: "Please enter a ticker symbol.")
        }

        // Step 1: Check if already in portfolio (instant, skip API)
        if stocks.contains(where: { $0.ticker.uppercased() == trimmedTicker }) {
            AppLogger.debug("Ticker \(trimmedTicker) already in portfolio, skipping validation")
            return .alreadyInPortfolio
        }

        // Step 2: Validate via API service (checks Supabase cache, then Yahoo)
        let result = await apiService.validateTicker(trimmedTicker)

        switch result {
        case .valid:
            return .valid
        case .cached:
            // Found in Supabase cache - another user has validated this ticker
            return .valid
        case .invalid:
            return .invalid(message: "Symbol '\(trimmedTicker)' not found. Please check the ticker symbol.")
        case .networkError:
            return .networkError(message: "Unable to verify symbol. Check your connection and try again.")
        }
    }

    func commitStock(ticker: String, price: Double, shares: Double, accountName: String = "Main") {
        // IMMEDIATELY add stock with placeholder name (don't wait for API)
        // This prevents UI freezing
        let placeholderCompanyName = ticker.uppercased()
        
        // Check if stock already exists
        if let existingIndex = stocks.firstIndex(where: { $0.ticker == ticker }) {
            // Add the new lot to existing stock
            let existingStock = stocks[existingIndex]
            let newLot = StockLot(accountName: accountName, shares: shares, purchasePrice: price)
            var updatedLots = existingStock.lots
            updatedLots.append(newLot)
            
            // Calculate aggregated values from all lots
            let totalShares = updatedLots.reduce(0.0) { $0 + $1.shares }
            let totalCost = updatedLots.reduce(0.0) { $0 + $1.totalCost }
            let averagePurchasePrice = totalShares > 0 ? totalCost / totalShares : price
            
            // Create updated stock with all lots and aggregated values
            // Use existing company name if available, otherwise placeholder
            let companyName = existingStock.companyName.isEmpty || existingStock.companyName == existingStock.ticker.uppercased() ? placeholderCompanyName : existingStock.companyName
            let updatedStock = Stock(
                ticker: ticker,
                companyName: companyName,
                purchasePrice: averagePurchasePrice,
                shares: Int(totalShares),
                isMaritalStatus: true, // Mark as committed
                lots: updatedLots
            )
            stocks[existingIndex] = updatedStock
            
            // FOR TESTING: Save locally immediately (synchronous, fast)
            if useLocalStorage {
                saveLocalStocks()
            } else {
                Task { await manager.commit(newStock: updatedStock) }
            }

            // Trigger price update to recalculate profit/loss with new aggregated values
            if let priceData = stockPrices[ticker] {
                updatePriceData(for: updatedStock, newPrice: priceData.currentPrice, apiPeriodChanges: priceData.apiPeriodChanges, previousClose: priceData.previousClose, beta: priceData.beta, isETF: priceData.isETF)
            } else {
            // Fetch price in background (don't block)
            Task { @MainActor [weak self] in
                await self?.updatePriceFast(for: updatedStock)
            }
            }
        } else {
            // Create new stock with the lot
            let lot = StockLot(accountName: accountName, shares: shares, purchasePrice: price)
            let newStock = Stock(ticker: ticker, companyName: placeholderCompanyName, purchasePrice: price, shares: Int(shares), isMaritalStatus: true, lots: [lot])
            stocks.append(newStock)

            // FOR TESTING: Save locally immediately (synchronous, fast)
            if useLocalStorage {
                saveLocalStocks()
            } else {
                Task { await manager.commit(newStock: newStock) }
            }
            
            // Show placeholder price immediately, then fetch real price in background
            // This prevents UI freeze
            let placeholderPrice = price // Use purchase price as placeholder
            updatePriceData(for: newStock, newPrice: placeholderPrice)
            
            // Fetch real price and company name in background (non-blocking)
            Task { @MainActor [weak self] in
                await self?.updatePriceFast(for: newStock)
                await self?.updateCompanyNameAsync(for: ticker)
            }
        }
    }
    
    // Fast price update without historical data (for immediate UI updates)
    @MainActor
    private func updatePriceFast(for stock: Stock) async {
        let trimmedTicker = stock.ticker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard stock.isMaritalStatus, !trimmedTicker.isEmpty else { return }
        
        // SKIP API CALLS IN UI TESTS
        if isUITesting {
            AppEnvironment.testingLog(" Skipping updatePriceFast for \(stock.ticker)")
            // Set placeholder price
            let placeholderPrice = stock.purchasePrice * 1.1
            updatePriceData(for: stock, newPrice: placeholderPrice, beta: stockPrices[stock.ticker]?.beta, isETF: stockPrices[stock.ticker]?.isETF)
            return
        }
        
        // Just fetch current price, skip historical data for now
        if let stockData = await apiService.fetchStockData(for: stock.ticker) {
            updatePriceData(for: stock, newPrice: stockData.price, apiPeriodChanges: stockData.periodChanges, previousClose: stockData.previousClose, beta: stockData.beta, isETF: stockData.isETF)
            
            // Fetch historical prices in background after showing current price
            Task { @MainActor [weak self] in
                let historicalPrices = await self?.apiService.fetchHistoricalPrices(for: stock.ticker)
                if let historicalPrices = historicalPrices, let self = self {
                    // Update with historical data if we have it
                    if let existingData = self.stockPrices[stock.ticker] {
                        self.updatePriceData(
                            for: stock,
                            newPrice: existingData.currentPrice,
                            historicalPrices: historicalPrices,
                            apiPeriodChanges: existingData.apiPeriodChanges,
                            previousClose: existingData.previousClose,
                            beta: existingData.beta,
                            isETF: existingData.isETF
                        )
                    }
                }
            }
        } else {
            // DATA INTEGRITY: Do NOT update price with fake data when API fails
            // For new stocks, we have no last known price, so show error state
            AppLogger.error("❌ API failed for new stock \(stock.ticker) - no price data available")
            // Don't call updatePriceData - let UI show loading/error state
        }
    }

    // Update company name in background
    @MainActor
    private func updateCompanyNameAsync(for ticker: String) async {
        let trimmedTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTicker.isEmpty else { return }
        // SKIP API CALLS IN UI TESTS
        if isUITesting {
            AppEnvironment.testingLog(" Skipping updateCompanyNameAsync for \(ticker)")
            return
        }

        if let stockData = await apiService.fetchStockData(for: trimmedTicker),
           let index = stocks.firstIndex(where: { $0.ticker == ticker }),
           stockData.companyName != trimmedTicker.uppercased() && !stockData.companyName.isEmpty {
            // Update company name if we got a real one from API
            // Replace entire object to trigger SwiftUI update
            var updatedStock = stocks[index]
            updatedStock.companyName = stockData.companyName
            stocks[index] = updatedStock
            AppLogger.debug("Updated company name for \(ticker)")
            if useLocalStorage {
                saveLocalStocks()
            }
        }
    }
    
    func removeStock(ticker: String) {
        // Remove from local array
        stocks.removeAll { $0.ticker == ticker }
        stockPrices.removeValue(forKey: ticker)

        // FOR TESTING: Save locally instead of Supabase
        if useLocalStorage {
            saveLocalStocks()
        } else {
            Task { await manager.removeStock(ticker: ticker) }
        }
    }
    
    func updateStockLots(ticker: String, lots: [StockLot]) {
        if let index = stocks.firstIndex(where: { $0.ticker == ticker }) {
            let existingStock = stocks[index]

            // Calculate aggregated values from all lots
            let totalShares = lots.reduce(0.0) { $0 + $1.shares }
            let totalCost = lots.reduce(0.0) { $0 + $1.totalCost }
            let averagePurchasePrice = totalShares > 0 ? totalCost / totalShares : existingStock.purchasePrice

            // Create a new Stock with updated lots and aggregated values
            let newStock = Stock(
                ticker: existingStock.ticker,
                companyName: existingStock.companyName,
                purchasePrice: averagePurchasePrice,
                shares: Int(totalShares),
                isMaritalStatus: existingStock.isMaritalStatus,
                lots: lots
            )
            stocks[index] = newStock

            // FOR TESTING: Save locally instead of Supabase
            if useLocalStorage {
                saveLocalStocks()
            } else {
                Task { await manager.commit(newStock: newStock) }
            }

            // Trigger price update to recalculate profit/loss with new aggregated values
            if let priceData = stockPrices[ticker] {
                updatePriceData(for: newStock, newPrice: priceData.currentPrice, apiPeriodChanges: priceData.apiPeriodChanges, previousClose: priceData.previousClose, beta: priceData.beta, isETF: priceData.isETF)
            } else {
                updatePrice(for: newStock)
            }
        }
    }

    func sellLot(ticker: String, lotId: UUID, sharesToSell: Double) {
        if let index = stocks.firstIndex(where: { $0.ticker == ticker }) {
            let existingStock = stocks[index]
            
            // Find the lot to sell
            guard let lotIndex = existingStock.lots.firstIndex(where: { $0.id == lotId }) else {
                AppLogger.warning("Lot not found for ID: \(lotId)")
                return
            }
            
            var updatedLots = existingStock.lots
            let lot = updatedLots[lotIndex]
            
            // Validate shares to sell
            guard sharesToSell > 0 && sharesToSell <= lot.shares else {
                AppLogger.warning("Invalid shares to sell: \(sharesToSell), available: \(lot.shares)")
                return
            }
            
            // Update or remove the lot
            if sharesToSell >= lot.shares {
                // Sell all shares - remove the lot
                updatedLots.remove(at: lotIndex)
            } else {
                // Sell partial shares - create a new lot with reduced shares
                var updatedLot = lot
                updatedLot.shares = lot.shares - sharesToSell
                updatedLots[lotIndex] = updatedLot
            }
            
            // Calculate aggregated values from remaining lots
            let totalShares = updatedLots.reduce(0.0) { $0 + $1.shares }
            let totalCost = updatedLots.reduce(0.0) { $0 + $1.totalCost }
            let averagePurchasePrice = totalShares > 0 ? totalCost / totalShares : existingStock.purchasePrice
            
            // Create updated stock
            let updatedStock = Stock(
                ticker: existingStock.ticker,
                companyName: existingStock.companyName,
                purchasePrice: averagePurchasePrice,
                shares: Int(totalShares),
                isMaritalStatus: existingStock.isMaritalStatus,
                lots: updatedLots
            )
            
            stocks[index] = updatedStock

            // FOR TESTING: Save locally instead of Supabase
            if useLocalStorage {
                saveLocalStocks()
            } else {
                Task { await manager.commit(newStock: updatedStock) }
            }

            // Trigger price update to recalculate profit/loss
            if let priceData = stockPrices[ticker] {
                updatePriceData(for: updatedStock, newPrice: priceData.currentPrice, apiPeriodChanges: priceData.apiPeriodChanges, previousClose: priceData.previousClose, beta: priceData.beta, isETF: priceData.isETF)
            } else {
                updatePrice(for: updatedStock)
            }
        }
    }

    func addSharesToLot(ticker: String, lotId: UUID, sharesToAdd: Double, newPurchasePrice: Double) {
        if let index = stocks.firstIndex(where: { $0.ticker == ticker }) {
            let existingStock = stocks[index]
            
            // Find the lot to update
            guard let lotIndex = existingStock.lots.firstIndex(where: { $0.id == lotId }) else {
                AppLogger.warning("Lot not found for ID: \(lotId)")
                return
            }
            
            var updatedLots = existingStock.lots
            let lot = updatedLots[lotIndex]
            
            // Calculate weighted average purchase price
            let existingCost = lot.totalCost
            let newCost = newPurchasePrice * sharesToAdd
            let totalNewShares = lot.shares + sharesToAdd
            let weightedAveragePrice = (existingCost + newCost) / totalNewShares
            
            // Update the lot with new shares and weighted average price
            var updatedLot = lot
            updatedLot.shares = totalNewShares
            updatedLot.purchasePrice = weightedAveragePrice
            updatedLots[lotIndex] = updatedLot
            
            // Calculate aggregated values from all lots
            let totalShares = updatedLots.reduce(0.0) { $0 + $1.shares }
            let totalCost = updatedLots.reduce(0.0) { $0 + $1.totalCost }
            let averagePurchasePrice = totalShares > 0 ? totalCost / totalShares : existingStock.purchasePrice
            
            // Create updated stock
            let updatedStock = Stock(
                ticker: existingStock.ticker,
                companyName: existingStock.companyName,
                purchasePrice: averagePurchasePrice,
                shares: Int(totalShares),
                isMaritalStatus: existingStock.isMaritalStatus,
                lots: updatedLots
            )
            
            stocks[index] = updatedStock

            // FOR TESTING: Save locally instead of Supabase
            if useLocalStorage {
                saveLocalStocks()
            } else {
                Task { await manager.commit(newStock: updatedStock) }
            }

            // Trigger price update to recalculate profit/loss
            if let priceData = stockPrices[ticker] {
                updatePriceData(for: updatedStock, newPrice: priceData.currentPrice, apiPeriodChanges: priceData.apiPeriodChanges, previousClose: priceData.previousClose, beta: priceData.beta, isETF: priceData.isETF)
            } else {
                updatePrice(for: updatedStock)
            }
        }
    }

    var totalPortfolioValue: Double {
        stocks.reduce(0) { total, stock in
            guard stock.isMaritalStatus,
                  let priceData = stockPrices[stock.ticker] else { return total }
            return total + (priceData.currentPrice * Double(stock.shares))
        }
    }
    
    var totalProfitLoss: Double {
        stockPrices.values.reduce(0) { $0 + $1.profitLoss }
    }
    
    func totalReturnForPeriod(_ period: TimePeriod) -> (value: Double, percent: Double) {
        var totalValue: Double = 0
        var totalDailyGain: Double = 0
        var totalStartValue: Double = 0
        var useDailyApiData = period == .daily

        for stock in stocks where stock.isMaritalStatus {
            guard let priceData = stockPrices[stock.ticker] else { continue }
            let totalShares = stock.lots.isEmpty ? Double(stock.shares) : stock.lots.reduce(0.0) { $0 + $1.shares }
            let currentValue = priceData.currentPrice * totalShares
            totalValue += currentValue

            if period == .daily {
                // For daily, prioritize API data which uses previous trading day's close
                if let apiDailyPercent = priceData.apiPeriodChanges["1d"] {
                    // Calculate daily gain: currentValue * (percent / (100 + percent))
                    let dailyGain = currentValue * (apiDailyPercent / (100 + apiDailyPercent))
                    totalDailyGain += dailyGain
                    AppLogger.debug("\(stock.ticker): API daily data used (\(apiDailyPercent)%) = $\(dailyGain)")
                } else if let prevClose = priceData.previousClose, prevClose > 0 {
                    // Fallback to previousClose
                    let startValue = prevClose * totalShares
                    totalStartValue += startValue
                    useDailyApiData = false
                    AppLogger.debug("\(stock.ticker): Using previousClose fallback = $\(prevClose)")
                } else {
                    // Last resort: use dailyStartPrice
                    totalStartValue += priceData.dailyStartPrice * totalShares
                    useDailyApiData = false
                    AppLogger.debug("\(stock.ticker): Using dailyStartPrice fallback = $\(priceData.dailyStartPrice)")
                }
            } else {
                let startPrice: Double
                switch period {
                case .daily:
                    startPrice = priceData.dailyStartPrice // Won't reach here
                case .weekly:
                    startPrice = priceData.weeklyStartPrice
                case .monthly:
                    startPrice = priceData.monthlyStartPrice
                case .threeMonths:
                    startPrice = priceData.threeMonthsStartPrice
                case .ytd:
                    startPrice = priceData.ytdStartPrice
                case .allTime:
                    startPrice = priceData.allTimeStartPrice
                }
                totalStartValue += startPrice * totalShares
            }
        }

        if period == .daily && useDailyApiData && totalValue > 0 {
            // Use API-based calculation for daily
            let percent = totalValue > 0 ? (totalDailyGain / (totalValue - totalDailyGain)) * 100 : 0

            #if DEBUG
            // Validate: sum of individual stock daily returns should match portfolio total
            let sumCheck = stocks.filter { $0.isMaritalStatus }.compactMap { stock -> Double? in
                guard let priceData = stockPrices[stock.ticker] else { return nil }
                let totalShares = stock.lots.isEmpty ? Double(stock.shares) : stock.lots.reduce(0.0) { $0 + $1.shares }
                let returnData = priceData.returnForPeriod(.daily)
                return returnData.value * totalShares
            }.reduce(0, +)

            let difference = abs(sumCheck - totalDailyGain)
            if difference > 0.01 {
                AppLogger.warning("Daily return calculation mismatch: sum=\(sumCheck), portfolio=\(totalDailyGain), diff=\(difference)")
            } else {
                AppLogger.debug("Daily return validated: \(sumCheck) ≈ \(totalDailyGain)")
            }
            #endif

            return (totalDailyGain, percent)
        }

        let change = totalValue - totalStartValue
        let percent = totalStartValue > 0 ? (change / totalStartValue) * 100 : 0
        return (change, percent)
    }

    // MARK: - Sector Information

    /// Updates sector information for all stocks
    @MainActor
    func updateSectorInfo() async {
        // SKIP API CALLS IN UI TESTS
        if isUITesting {
            AppEnvironment.testingLog(" Skipping updateSectorInfo()")
            return
        }

        let activeStocks = stocks.filter { stock in
            stock.isMaritalStatus && !stock.ticker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !activeStocks.isEmpty else { return }

        let tickers = activeStocks.map { $0.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        let sectorDict = await apiService.fetchSectorInfo(for: tickers)

        for (ticker, sector) in sectorDict {
            stockSectors[ticker] = sector
        }

        AppLogger.debug("Updated sectors for \(sectorDict.count) stocks")
    }

    /// Returns sector breakdown for the portfolio
    /// - Returns: Array of (sector, value, percentage, color) tuples sorted by value
    var sectorBreakdown: [(sector: StockSector, value: Double, percentage: Double, color: (red: Double, green: Double, blue: Double))] {
        var sectorValues: [StockSector: Double] = [:]

        for stock in stocks where stock.isMaritalStatus {
            guard let priceData = stockPrices[stock.ticker] else { continue }

            let totalShares = stock.lots.isEmpty ? Double(stock.shares) : stock.lots.reduce(0.0) { $0 + $1.shares }
            let stockValue = priceData.currentPrice * totalShares

            // Check if this is an ETF - if so, categorize as ETF sector
            let sector: StockSector
            if priceData.isETF == true {
                sector = .etf
            } else {
                // Get sector from stockSectors dictionary
                let sectorString = stockSectors[stock.ticker]
                sector = StockSector.from(yahooSector: sectorString)
            }

            sectorValues[sector, default: 0] += stockValue
        }

        let totalValue = sectorValues.values.reduce(0, +)

        return sectorValues
            .map { sector, value in
                let percentage = totalValue > 0 ? (value / totalValue) * 100 : 0
                return (sector, value, percentage, sector.color)
            }
            .sorted { $0.value > $1.value }
    }

    /// Total cost basis of the portfolio (sum of all purchase costs)
    var totalCostBasis: Double {
        stocks.filter { $0.isMaritalStatus }.reduce(0) { total, stock in
            if stock.lots.isEmpty {
                return total + stock.totalCost
            } else {
                return total + stock.lots.reduce(0.0) { $0 + $1.totalCost }
            }
        }
    }

    /// Total unrealized gain/loss (current value minus cost basis)
    var totalUnrealizedGainLoss: Double {
        totalPortfolioValue - totalCostBasis
    }

    /// Total daily gain/loss in dollars
    var totalDailyGainLoss: Double {
        var dailyGainLoss: Double = 0

        for stock in stocks where stock.isMaritalStatus {
            guard let priceData = stockPrices[stock.ticker] else { continue }

            let totalShares = stock.lots.isEmpty ? Double(stock.shares) : stock.lots.reduce(0.0) { $0 + $1.shares }
            let currentValue = priceData.currentPrice * totalShares

            // Get daily change percent
            let dailyChangePercent: Double
            if let apiDaily = priceData.apiPeriodChanges["1d"] {
                dailyChangePercent = apiDaily
            } else if let prevClose = priceData.previousClose, prevClose > 0 {
                dailyChangePercent = ((priceData.currentPrice - prevClose) / prevClose) * 100
            } else {
                let startPrice = priceData.dailyStartPrice
                dailyChangePercent = startPrice > 0 ? ((priceData.currentPrice - startPrice) / startPrice) * 100 : 0
            }

            // Calculate daily gain in dollars: currentValue * (dailyChange% / (100 + dailyChange%))
            let dailyGain = currentValue * (dailyChangePercent / (100 + dailyChangePercent))
            dailyGainLoss += dailyGain
        }

        return dailyGainLoss
    }

    /// Daily gain/loss percentage
    var totalDailyGainLossPercent: Double {
        let previousValue = totalPortfolioValue - totalDailyGainLoss
        return previousValue > 0 ? (totalDailyGainLoss / previousValue) * 100 : 0
    }

    // MARK: - Account Renaming

    /// Renames all lots with the matching account name to a new name
    func renameAccount(from oldName: String, to newName: String) {
        let trimmedNewName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNewName.isEmpty, trimmedNewName != oldName else { return }

        for i in stocks.indices {
            for j in stocks[i].lots.indices {
                if stocks[i].lots[j].accountName == oldName {
                    stocks[i].lots[j].accountName = trimmedNewName
                }
            }
        }

        if useLocalStorage {
            saveLocalStocks()
        } else {
            // Sync all affected stocks to cloud
            for stock in stocks where stock.lots.contains(where: { $0.accountName == trimmedNewName }) {
                Task { await manager.commit(newStock: stock) }
            }
        }
    }
}

