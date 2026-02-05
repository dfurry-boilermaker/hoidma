import Foundation
import Combine

// MARK: - Timezone Helpers

/// Helper functions to ensure consistent timezone handling across all chart operations
/// CRITICAL: All market-related times must use EST (America/New_York) timezone
enum ChartTimezoneHelper {
    /// EST timezone used for all market operations
    static let marketTimezone = TimeZone(identifier: "America/New_York")!

    /// Get a calendar configured for EST timezone
    static var estCalendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = marketTimezone
        return calendar
    }

    /// Get "today" in EST timezone (start of day)
    /// - Parameter date: The date to convert (usually Date())
    /// - Returns: Start of day in EST timezone
    static func todayInEST(from date: Date = Date()) -> Date {
        let calendar = estCalendar
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: components)!
    }

    /// Check if a date is in the future relative to now
    static func isInFuture(_ date: Date) -> Bool {
        return date > Date()
    }
}

// MARK: - Chart Time Periods

/// Time periods for chart display
enum ChartTimePeriod: String, CaseIterable, Identifiable {
    case oneDay = "1D"
    case all = "ALL"

    var id: String { rawValue }

    /// Calculate the start date for this time period
    var startDate: Date {
        let now = Date()

        switch self {
        case .oneDay:
            // For 1D chart: 9:30 AM EST (market open, no pre-market)
            let calendar = ChartTimezoneHelper.estCalendar
            let todayEST = ChartTimezoneHelper.todayInEST()
            var marketOpen = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: todayEST)!

            // If 9:30 AM EST today is in the future, use yesterday's 9:30 AM EST
            if ChartTimezoneHelper.isInFuture(marketOpen) {
                let yesterday = calendar.date(byAdding: .day, value: -1, to: todayEST)!
                marketOpen = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: yesterday)!
            }

            return marketOpen
        case .all:
            // 5 years ago from now (timezone-agnostic)
            let calendar = Calendar.current
            return calendar.date(byAdding: .year, value: -5, to: now) ?? now
        }
    }

    /// Calculate the end date for this time period
    var endDate: Date {
        let now = Date()

        switch self {
        case .oneDay:
            // For 1D chart: current time or 4:00 PM EST (market close), whichever is earlier
            let calendar = ChartTimezoneHelper.estCalendar
            var tradingDay = ChartTimezoneHelper.todayInEST()

            // If market hasn't opened yet today, use yesterday's close
            let marketOpen = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: tradingDay)!
            if ChartTimezoneHelper.isInFuture(marketOpen) {
                tradingDay = calendar.date(byAdding: .day, value: -1, to: tradingDay)!
            }

            let marketClose = calendar.date(bySettingHour: 16, minute: 0, second: 0, of: tradingDay)!

            // Use current time or 4:00 PM EST, whichever is earlier
            return min(now, marketClose)
        case .all:
            return now
        }
    }

    /// Display name for the period
    var displayName: String {
        switch self {
        case .oneDay: return "1 Day"
        case .all: return "All Time"
        }
    }
}

/// Data point for chart display
struct ChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

/// View model for managing chart data and state
@MainActor
class ChartDataViewModel: ObservableObject {
    // MARK: - Published Properties

    /// Portfolio value history for line chart
    @Published var portfolioHistory: [ChartDataPoint] = []

    /// Cost basis line (flat reference line)
    @Published var costBasisHistory: [ChartDataPoint] = []

    /// Currently selected time period
    @Published var selectedPeriod: ChartTimePeriod = .oneDay

    /// Loading state
    @Published var isLoading: Bool = false

    /// Error message if any
    @Published var errorMessage: String? = nil

    /// Selected individual ticker for detail chart
    @Published var selectedTicker: String? = nil

    /// Individual ticker price history
    @Published var tickerHistory: [ChartDataPoint] = []

    /// Normalized performance for comparison chart
    @Published var normalizedPerformance: [String: [ChartDataPoint]] = [:]

    /// Whether Polygon API is configured
    @Published var isPolygonConfigured: Bool = false

    // MARK: - Private Properties

    private weak var stockViewModel: StockViewModel?
    private var refreshTimer: Timer?

    // MARK: - Initialization

    init(stockViewModel: StockViewModel) {
        self.stockViewModel = stockViewModel
        self.isPolygonConfigured = APIConfig.isPolygonConfigured
    }

    // MARK: - Portfolio History

    /// Load portfolio value history for the selected time period
    func loadPortfolioHistory() async {
        guard let viewModel = stockViewModel else { return }

        // Prevent concurrent fetches
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        // Build current holdings map from stocks
        var holdings: [String: Double] = [:]
        for stock in viewModel.stocks where stock.isMaritalStatus {
            let shares = stock.lots.isEmpty
                ? Double(stock.shares)
                : stock.lots.reduce(0.0) { $0 + $1.shares }

            if shares > 0 {
                holdings[stock.ticker] = shares
            }
        }

        guard !holdings.isEmpty else {
            isLoading = false
            portfolioHistory = []
            return
        }

        // Check if Polygon is configured
        guard APIConfig.isPolygonConfigured else {
            errorMessage = "Charts require Polygon.io API key"
            isLoading = false
            return
        }

        // Fetch portfolio history from cache/API
        // Use 15-minute intraday data for 1D period
        let useIntraday = (selectedPeriod == .oneDay)
        let history = await HistoricalPriceCache.shared.getPortfolioHistory(
            holdings: holdings,
            from: selectedPeriod.startDate,
            to: selectedPeriod.endDate,
            useIntraday: useIntraday
        )

        // Convert to ChartDataPoint array
        portfolioHistory = history.map { ChartDataPoint(date: $0.date, value: $0.value) }

        // Build cost basis reference line
        let totalCost = viewModel.totalCostBasis
        if let firstDate = history.first?.date, let lastDate = history.last?.date {
            costBasisHistory = [
                ChartDataPoint(date: firstDate, value: totalCost),
                ChartDataPoint(date: lastDate, value: totalCost)
            ]
        }

        if portfolioHistory.isEmpty && holdings.count > 0 {
            errorMessage = "No historical data available"
        }

        isLoading = false
    }

    /// Reload data when period changes
    func onPeriodChange() {
        // Stop existing auto-refresh
        stopAutoRefresh()

        Task {
            await loadPortfolioHistory()
            if let ticker = selectedTicker {
                await loadTickerHistory(ticker: ticker)
            }

            // Restart auto-refresh if appropriate
            startAutoRefresh()
        }
    }

    // MARK: - Individual Ticker

    /// Load price history for a specific ticker
    func loadTickerHistory(ticker: String) async {
        guard APIConfig.isPolygonConfigured else {
            errorMessage = "Charts require Polygon.io API key"
            return
        }

        // Prevent concurrent fetches
        guard !isLoading else { return }

        selectedTicker = ticker
        isLoading = true

        // Use 15-minute intraday data for 1D period
        let useIntraday = (selectedPeriod == .oneDay)
        let prices = await HistoricalPriceCache.shared.getPrices(
            for: ticker,
            from: selectedPeriod.startDate,
            to: selectedPeriod.endDate,
            useIntraday: useIntraday
        )

        // Convert to sorted ChartDataPoint array
        tickerHistory = prices
            .map { ChartDataPoint(date: $0.key, value: $0.value) }
            .sorted { $0.date < $1.date }

        isLoading = false
    }

    /// Clear selected ticker
    func clearSelectedTicker() {
        selectedTicker = nil
        tickerHistory = []
    }

    // MARK: - Comparison Chart

    /// Load normalized performance for multiple tickers
    func loadNormalizedPerformance(tickers: [String]) async {
        guard APIConfig.isPolygonConfigured else { return }

        isLoading = true

        let performance = await HistoricalPriceCache.shared.getNormalizedPerformance(
            tickers: tickers,
            from: selectedPeriod.startDate,
            to: Date()
        )

        // Convert to ChartDataPoint format
        normalizedPerformance = performance.mapValues { points in
            points.map { ChartDataPoint(date: $0.date, value: $0.value) }
        }

        isLoading = false
    }

    // MARK: - Computed Properties

    /// Calculate period return from portfolio history
    var periodReturn: (value: Double, percent: Double) {
        guard let first = portfolioHistory.first,
              let last = portfolioHistory.last,
              first.value > 0 else {
            return (0, 0)
        }

        let change = last.value - first.value
        let percent = (change / first.value) * 100
        return (change, percent)
    }

    /// Calculate total return vs cost basis
    var totalReturn: (value: Double, percent: Double) {
        guard let costBasis = costBasisHistory.first?.value,
              let currentValue = portfolioHistory.last?.value,
              costBasis > 0 else {
            return (0, 0)
        }

        let change = currentValue - costBasis
        let percent = (change / costBasis) * 100
        return (change, percent)
    }

    /// Whether there's data to display
    var hasData: Bool {
        !portfolioHistory.isEmpty
    }

    /// Current portfolio value (latest in history)
    var currentValue: Double {
        portfolioHistory.last?.value ?? 0
    }

    /// Minimum value in chart (for Y-axis scaling)
    var chartMinValue: Double {
        let dataMin = portfolioHistory.map { $0.value }.min() ?? 0
        let costMin = costBasisHistory.map { $0.value }.min() ?? 0
        return min(dataMin, costMin) * 0.95
    }

    /// Maximum value in chart (for Y-axis scaling)
    var chartMaxValue: Double {
        let dataMax = portfolioHistory.map { $0.value }.max() ?? 0
        let costMax = costBasisHistory.map { $0.value }.max() ?? 0
        return max(dataMax, costMax) * 1.05
    }

    /// Whether portfolio is up or down for the period
    var isPositivePeriod: Bool {
        periodReturn.value >= 0
    }

    // MARK: - Auto-Refresh

    /// Start auto-refresh for 1D charts during market hours
    func startAutoRefresh() {
        // Only auto-refresh for 1D period during market hours
        guard selectedPeriod == .oneDay else { return }
        guard isMarketHours() else { return }

        // Refresh every 2 minutes
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                await self.loadPortfolioHistory()
                if let ticker = self.selectedTicker {
                    await self.loadTickerHistory(ticker: ticker)
                }
            }
        }
    }

    /// Stop auto-refresh timer
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Check if currently in market hours (9:30 AM - 4:00 PM EST, Monday-Friday)
    private func isMarketHours() -> Bool {
        let now = Date()
        let calendar = ChartTimezoneHelper.estCalendar

        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let weekday = calendar.component(.weekday, from: now)

        // Monday-Friday (2-6), 9:30 AM - 4:00 PM EST
        guard weekday >= 2 && weekday <= 6 else { return false }
        if hour < 9 || hour > 16 { return false }
        if hour == 9 && minute < 30 { return false }
        if hour == 16 && minute > 0 { return false }

        return true
    }

    /// Refresh chart data (for pull-to-refresh)
    func refreshChartData() async {
        await loadPortfolioHistory()
        if let ticker = selectedTicker {
            await loadTickerHistory(ticker: ticker)
        }
    }

    deinit {
        // Invalidate timer synchronously in deinit
        refreshTimer?.invalidate()
    }
}
