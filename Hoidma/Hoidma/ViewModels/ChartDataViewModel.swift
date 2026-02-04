import Foundation
import Combine

/// Time periods for chart display
enum ChartTimePeriod: String, CaseIterable, Identifiable {
    case oneWeek = "1W"
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1Y"
    case all = "ALL"

    var id: String { rawValue }

    /// Calculate the start date for this time period
    var startDate: Date {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .oneWeek:
            return calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .oneMonth:
            return calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .threeMonths:
            return calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .sixMonths:
            return calendar.date(byAdding: .month, value: -6, to: now) ?? now
        case .oneYear:
            return calendar.date(byAdding: .year, value: -1, to: now) ?? now
        case .all:
            // 5 years max for free tier, adjust based on your Polygon plan
            return calendar.date(byAdding: .year, value: -5, to: now) ?? now
        }
    }

    /// Display name for the period
    var displayName: String {
        switch self {
        case .oneWeek: return "1 Week"
        case .oneMonth: return "1 Month"
        case .threeMonths: return "3 Months"
        case .sixMonths: return "6 Months"
        case .oneYear: return "1 Year"
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
    @Published var selectedPeriod: ChartTimePeriod = .threeMonths

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

    // MARK: - Initialization

    init(stockViewModel: StockViewModel) {
        self.stockViewModel = stockViewModel
        self.isPolygonConfigured = APIConfig.isPolygonConfigured
    }

    // MARK: - Portfolio History

    /// Load portfolio value history for the selected time period
    func loadPortfolioHistory() async {
        guard let viewModel = stockViewModel else { return }

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
        let history = await HistoricalPriceCache.shared.getPortfolioHistory(
            holdings: holdings,
            from: selectedPeriod.startDate,
            to: Date()
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
        Task {
            await loadPortfolioHistory()
            if let ticker = selectedTicker {
                await loadTickerHistory(ticker: ticker)
            }
        }
    }

    // MARK: - Individual Ticker

    /// Load price history for a specific ticker
    func loadTickerHistory(ticker: String) async {
        guard APIConfig.isPolygonConfigured else {
            errorMessage = "Charts require Polygon.io API key"
            return
        }

        selectedTicker = ticker
        isLoading = true

        let prices = await HistoricalPriceCache.shared.getPrices(
            for: ticker,
            from: selectedPeriod.startDate,
            to: Date()
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
}
