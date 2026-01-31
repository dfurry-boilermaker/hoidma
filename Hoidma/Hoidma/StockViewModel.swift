import Foundation
import Combine
import SwiftUI

class StockViewModel: ObservableObject {
    @Published var stocks: [Stock] = []
    @Published var stockPrices: [String: StockPriceData] = [:]

    // Used to update prices every 30 seconds (reduced frequency to respect API limits)
    private var timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private let localStorageKey = "localStocks"

    // Use centralized environment configuration
    private var useLocalStorage: Bool { AppEnvironment.useLocalStorage }
    private var isUITesting: Bool { AppEnvironment.isUITesting }

    // The placeholder Firebase Manager (only used if not using local storage)
    let manager = FirebaseManager()
    
    // API service for fetching real stock data
    private let apiService = StockAPIService.shared
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        if useLocalStorage {
            // Load from local storage
            loadLocalStocks()
        } else {
            // Use Firebase
            manager.startDataListener()
            
            // Monitor stocks from the Firebase Manager
            manager.$stocks
                .sink { [weak self] newStocks in
                    guard let self = self else { return }
                    self.stocks = newStocks
                    // Initialize prices for new stocks using API (skip in UI tests)
                    if !self.isUITesting {
                        Task {
                            await self.updateAllPrices()
                        }
                    }
                }
                .store(in: &cancellables)
        }
        
        // Start the price update timer (fetches real data from API) - SKIP IN UI TESTS
        if !isUITesting {
            timer
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    Task {
                        await self.updateAllPrices()
                    }
                }
                .store(in: &cancellables)
        } else {
            AppEnvironment.testingLog(" Price update timer disabled")
        }
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
            print("✅ Loaded \(self.stocks.count) stocks from local storage")
            
            // Initialize prices for loaded stocks (SKIP IN UI TESTS to prevent crashes)
            if !isUITesting {
                // Defer price updates to avoid blocking initialization
                Task { @MainActor in
                    await self.updateAllPrices()
                }
            } else {
                // In UI tests, just set placeholder prices to avoid API calls
                // Do this synchronously on main thread to avoid async issues
                AppEnvironment.testingLog(" Setting placeholder prices for \(self.stocks.count) stocks")
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    for stock in self.stocks {
                        let placeholderPrice = stock.purchasePrice * 1.1 // 10% gain
                        self.updatePriceData(for: stock, newPrice: placeholderPrice)
                    }
                }
            }
        } else {
            print("📭 No local stocks found, starting with empty portfolio")
        }
    }
    
    // Save stocks to local storage
    private func saveLocalStocks() {
        // UserDefaults is fast for small datasets, so synchronous is fine
        if let encoded = try? JSONEncoder().encode(stocks) {
            UserDefaults.standard.set(encoded, forKey: localStorageKey)
            print("✅ Saved \(stocks.count) stocks to local storage")
        } else {
            print("❌ Failed to save stocks to local storage")
        }
    }
    
    /// Updates prices for all stocks using the API
    @MainActor
    func updateAllPrices() async {
        // SKIP API CALLS IN UI TESTS to prevent crashes
        if isUITesting {
            AppEnvironment.testingLog(" Skipping updateAllPrices()")
            return
        }
        
        let activeStocks = stocks.filter { stock in
            stock.isMaritalStatus && !stock.ticker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !activeStocks.isEmpty else { return }
        
        let tickers = activeStocks.map { $0.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        
        // Fetch both prices and company names
        let stockDataDict = await apiService.fetchStockData(for: tickers)
        
        for stock in activeStocks {
            if let stockData = stockDataDict[stock.ticker] {
                // Check if this is a new stock (no existing price data)
                let isNewStock = stockPrices[stock.ticker] == nil
                
                // For new stocks, fetch historical prices to initialize period start prices
                var historicalPrices: [String: Double]? = nil
                if isNewStock {
                    historicalPrices = await apiService.fetchHistoricalPrices(for: stock.ticker)
                    print("📊 Fetched historical prices for \(stock.ticker): \(historicalPrices ?? [:])")
                }
                
                // Update price with historical data and API period changes if available
                updatePriceData(for: stock, newPrice: stockData.price, historicalPrices: historicalPrices, apiPeriodChanges: stockData.periodChanges, previousClose: stockData.previousClose, logoURL: stockData.logoURL)
                
                // Update company name if it's different (and not just the ticker)
                if stock.companyName != stockData.companyName && stockData.companyName != stock.ticker.uppercased() {
                    updateCompanyName(for: stock.ticker, newName: stockData.companyName)
                }
            } else {
                // Fallback to mock price if API fails
                print("⚠️ API failed for \(stock.ticker), using fallback price")
                let fallbackPrice = stock.mockCurrentPrice
                updatePriceData(for: stock, newPrice: fallbackPrice)
            }
        }
    }
    
    /// Updates the company name for a stock
    @MainActor
    private func updateCompanyName(for ticker: String, newName: String) {
        // Find and update the stock in the manager's stocks array
        if let index = manager.stocks.firstIndex(where: { $0.ticker == ticker }) {
            var updatedStock = manager.stocks[index]
            updatedStock.companyName = newName
            manager.stocks[index] = updatedStock
            
            // Update in our local stocks array too
            if let localIndex = stocks.firstIndex(where: { $0.ticker == ticker }) {
                stocks[localIndex] = updatedStock
            }
            
            // Stock is already saved to Firestore via manager.commit in FirebaseManager
            print("✅ Updated company name for \(ticker) to \(newName)")
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
            updatePriceData(for: stock, newPrice: placeholderPrice)
            return
        }
        
        Task {
            let isNewStock = await MainActor.run { stockPrices[stock.ticker] == nil }
            
            // For new stocks, fetch historical prices
            var historicalPrices: [String: Double]? = nil
            if isNewStock {
                historicalPrices = await apiService.fetchHistoricalPrices(for: stock.ticker)
                print("📊 Fetched historical prices for \(stock.ticker): \(historicalPrices ?? [:])")
            }
            
            if let stockData = await apiService.fetchStockData(for: stock.ticker) {
                await MainActor.run {
                    updatePriceData(for: stock, newPrice: stockData.price, historicalPrices: historicalPrices, apiPeriodChanges: stockData.periodChanges, previousClose: stockData.previousClose, logoURL: stockData.logoURL)
                }
            } else {
                // Fallback to mock price if API fails
                print("⚠️ API failed for \(stock.ticker), using fallback price")
                let fallbackPrice = stock.mockCurrentPrice
                await MainActor.run {
                    updatePriceData(for: stock, newPrice: fallbackPrice)
                }
            }
            
            // If logo is missing, try to fetch it separately
            await MainActor.run {
                if stockPrices[stock.ticker]?.logoURL == nil || stockPrices[stock.ticker]?.logoURL?.isEmpty == true {
                    Task {
                        if let logoURL = await apiService.fetchCompanyLogo(for: stock.ticker) {
                            await MainActor.run {
                                if var existingData = stockPrices[stock.ticker] {
                                    existingData.logoURL = logoURL
                                    withAnimation {
                                        stockPrices[stock.ticker] = existingData
                                    }
                                    print("✅ Updated logo URL for \(stock.ticker): \(logoURL)")
                                }
                            }
                        } else {
                            print("⚠️ Failed to fetch logo for \(stock.ticker)")
                        }
                    }
                }
            }
        }
    }
    
    /// Fetches company logo separately (public method for manual fetching)
    func fetchLogo(for ticker: String) {
        Task {
            if let logoURL = await apiService.fetchCompanyLogo(for: ticker) {
                await MainActor.run {
                    if var existingData = stockPrices[ticker] {
                        existingData.logoURL = logoURL
                        withAnimation {
                            stockPrices[ticker] = existingData
                        }
                        print("✅ Fetched and updated logo URL for \(ticker): \(logoURL)")
                    }
                }
            }
        }
    }
    
    /// Updates the price data structure with a new price
    @MainActor
    private func updatePriceData(for stock: Stock, newPrice: Double, historicalPrices: [String: Double]? = nil, apiPeriodChanges: [String: Double]? = nil, previousClose: Double? = nil, logoURL: String? = nil) {
        let newProfitLoss = (newPrice * Double(stock.shares)) - stock.totalCost
        let newChangePercent = (newProfitLoss / stock.totalCost) * 100
        
        let now = Date()
        let existingData = stockPrices[stock.ticker]
        
        let calendar = Calendar.current
        
        // Initialize or update period start prices
        let isNewStock = existingData == nil
        
        // For new stocks, try to use historical prices from API, otherwise use current price
        var dailyStartPrice = existingData?.dailyStartPrice ?? (historicalPrices?["1d"] ?? newPrice)
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
        if !calendar.isDate(dailyStartTime, inSameDayAs: now) {
            dailyStartPrice = newPrice
            dailyStartTime = now
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
        if let apiChanges = apiPeriodChanges {
            updatedApiPeriodChanges.merge(apiChanges) { (_, new) in new }
        }
        
        // Update previous close if provided (use existing if not provided)
        let updatedPreviousClose = previousClose ?? existingData?.previousClose
        
        // Update logo URL if provided (use existing if not provided)
        let updatedLogoURL = logoURL ?? existingData?.logoURL
        
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
                logoURL: updatedLogoURL
            )
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
                manager.commit(newStock: updatedStock)
            }
            
            // Trigger price update to recalculate profit/loss with new aggregated values
            if let priceData = stockPrices[ticker] {
                updatePriceData(for: updatedStock, newPrice: priceData.currentPrice, apiPeriodChanges: priceData.apiPeriodChanges, previousClose: priceData.previousClose, logoURL: priceData.logoURL)
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
                manager.commit(newStock: newStock)
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
            updatePriceData(for: stock, newPrice: placeholderPrice)
            return
        }
        
        // Just fetch current price, skip historical data for now
        if let stockData = await apiService.fetchStockData(for: stock.ticker) {
            updatePriceData(for: stock, newPrice: stockData.price, apiPeriodChanges: stockData.periodChanges, previousClose: stockData.previousClose, logoURL: stockData.logoURL)
            
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
                            logoURL: existingData.logoURL
                        )
                    }
                }
            }
        } else {
            // Fallback to mock price if API fails
            print("⚠️ API failed for \(stock.ticker), using fallback price")
            let fallbackPrice = stock.mockCurrentPrice
            updatePriceData(for: stock, newPrice: fallbackPrice)
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
            stocks[index].companyName = stockData.companyName
            if useLocalStorage {
                saveLocalStocks()
            }
        }
    }
    
    func removeStock(ticker: String) {
        // Remove from local array
        stocks.removeAll { $0.ticker == ticker }
        stockPrices.removeValue(forKey: ticker)
        
        // FOR TESTING: Save locally instead of Firebase
        if useLocalStorage {
            saveLocalStocks()
        } else {
            manager.removeStock(ticker: ticker)
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
            
            // FOR TESTING: Save locally instead of Firebase
            if useLocalStorage {
                saveLocalStocks()
            } else {
                manager.commit(newStock: newStock)
            }
            
            // Trigger price update to recalculate profit/loss with new aggregated values
            if let priceData = stockPrices[ticker] {
                updatePriceData(for: newStock, newPrice: priceData.currentPrice, apiPeriodChanges: priceData.apiPeriodChanges, previousClose: priceData.previousClose, logoURL: priceData.logoURL)
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
                print("⚠️ Lot not found for ID: \(lotId)")
                return
            }
            
            var updatedLots = existingStock.lots
            let lot = updatedLots[lotIndex]
            
            // Validate shares to sell
            guard sharesToSell > 0 && sharesToSell <= lot.shares else {
                print("⚠️ Invalid shares to sell: \(sharesToSell), available: \(lot.shares)")
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
            
            // FOR TESTING: Save locally instead of Firebase
            if useLocalStorage {
                saveLocalStocks()
            } else {
                manager.commit(newStock: updatedStock)
            }
            
            // Trigger price update to recalculate profit/loss
            if let priceData = stockPrices[ticker] {
                updatePriceData(for: updatedStock, newPrice: priceData.currentPrice, apiPeriodChanges: priceData.apiPeriodChanges, previousClose: priceData.previousClose, logoURL: priceData.logoURL)
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
                print("⚠️ Lot not found for ID: \(lotId)")
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
            
            // FOR TESTING: Save locally instead of Firebase
            if useLocalStorage {
                saveLocalStocks()
            } else {
                manager.commit(newStock: updatedStock)
            }
            
            // Trigger price update to recalculate profit/loss
            if let priceData = stockPrices[ticker] {
                updatePriceData(for: updatedStock, newPrice: priceData.currentPrice, apiPeriodChanges: priceData.apiPeriodChanges, previousClose: priceData.previousClose, logoURL: priceData.logoURL)
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
        var totalStartValue: Double = 0
        
        for stock in stocks where stock.isMaritalStatus {
            guard let priceData = stockPrices[stock.ticker] else { continue }
            let currentValue = priceData.currentPrice * Double(stock.shares)
            totalValue += currentValue
            
            let startPrice: Double
            switch period {
            case .daily:
                startPrice = priceData.dailyStartPrice
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
            totalStartValue += startPrice * Double(stock.shares)
        }
        
        let change = totalValue - totalStartValue
        let percent = totalStartValue > 0 ? (change / totalStartValue) * 100 : 0
        return (change, percent)
    }
}

