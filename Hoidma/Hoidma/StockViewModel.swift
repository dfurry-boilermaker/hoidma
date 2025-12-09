import Foundation
import Combine

class StockViewModel: ObservableObject {
    @Published var stocks: [Stock] = []
    @Published var stockPrices: [String: StockPriceData] = [:]
    
    // Used to update prices every 30 seconds (reduced frequency to respect API limits)
    private var timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    
    // The placeholder Firebase Manager
    @ObservedObject var manager = FirebaseManager()
    
    // API service for fetching real stock data
    private let apiService = StockAPIService.shared
    
    init() {
        manager.startDataListener()
        
        // Monitor stocks from the Firebase Manager
        manager.$stocks
            .sink { [weak self] newStocks in
                guard let self = self else { return }
                self.stocks = newStocks
                // Initialize prices for new stocks using API
                Task {
                    await self.updateAllPrices()
                }
            }
            .store(in: &cancellables)
        
        // Start the price update timer (fetches real data from API)
        timer
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.updateAllPrices()
                }
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    /// Updates prices for all stocks using the API
    @MainActor
    func updateAllPrices() async {
        let activeStocks = stocks.filter { $0.isMaritalStatus }
        guard !activeStocks.isEmpty else { return }
        
        let tickers = activeStocks.map { $0.ticker }
        
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
                updatePriceData(for: stock, newPrice: stockData.price, historicalPrices: historicalPrices, apiPeriodChanges: stockData.periodChanges, previousClose: stockData.previousClose)
                
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
            
            // Save to UserDefaults
            if let encoded = try? JSONEncoder().encode(manager.stocks) {
                UserDefaults.standard.set(encoded, forKey: "committedStocks")
            }
            
            print("✅ Updated company name for \(ticker) to \(newName)")
        }
    }
    
    /// Updates price for a single stock (async version for API calls)
    func updatePrice(for stock: Stock) {
        guard stock.isMaritalStatus else { return }
        
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
                    updatePriceData(for: stock, newPrice: stockData.price, historicalPrices: historicalPrices, apiPeriodChanges: stockData.periodChanges, previousClose: stockData.previousClose)
                }
            } else {
                // Fallback to mock price if API fails
                print("⚠️ API failed for \(stock.ticker), using fallback price")
                let fallbackPrice = stock.mockCurrentPrice
                await MainActor.run {
                    updatePriceData(for: stock, newPrice: fallbackPrice)
                }
            }
        }
    }
    
    /// Updates the price data structure with a new price
    @MainActor
    private func updatePriceData(for stock: Stock, newPrice: Double, historicalPrices: [String: Double]? = nil, apiPeriodChanges: [String: Double]? = nil, previousClose: Double? = nil) {
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
                previousClose: updatedPreviousClose
            )
        }
    }
    
    func commitStock(ticker: String, price: Double, shares: Int) {
        Task {
            // Fetch company name from API
            let companyName: String
            if let stockData = await apiService.fetchStockData(for: ticker) {
                companyName = stockData.companyName
            } else {
                // Fallback to ticker if API fails
                companyName = ticker.uppercased()
            }
            
            await MainActor.run {
                let newStock = Stock(ticker: ticker, companyName: companyName, purchasePrice: price, shares: shares)
                manager.commit(newStock: newStock)
            }
        }
    }
    
    func removeStock(ticker: String) {
        manager.removeStock(ticker: ticker)
        stockPrices.removeValue(forKey: ticker)
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

