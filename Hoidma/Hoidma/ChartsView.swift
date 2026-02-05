import SwiftUI
import Charts

/// Main Charts tab view displaying portfolio performance over time
struct ChartsView: View {
    @ObservedObject var viewModel: StockViewModel
    @StateObject private var chartViewModel: ChartDataViewModel
    @Binding var selectedTab: Int
    @Binding var showDollarAmounts: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool { colorScheme == .dark }

    init(viewModel: StockViewModel, selectedTab: Binding<Int>, showDollarAmounts: Binding<Bool>) {
        self.viewModel = viewModel
        self._selectedTab = selectedTab
        self._showDollarAmounts = showDollarAmounts
        self._chartViewModel = StateObject(wrappedValue: ChartDataViewModel(stockViewModel: viewModel))
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Header spacer for fixed header
                    Spacer().frame(height: 75)

                    // API Configuration Warning
                    if !chartViewModel.isPolygonConfigured {
                        APIConfigWarningCard()
                            .padding(.horizontal, 20)
                    }

                    // Chart area with pull-to-refresh
                    if chartViewModel.isPolygonConfigured {
                        ScrollView {
                            UnifiedChart(
                                chartViewModel: chartViewModel,
                                viewModel: viewModel,
                                showDollarAmounts: showDollarAmounts
                            )
                            .frame(height: geometry.size.height - 180)
                        }
                        .refreshable {
                            await chartViewModel.refreshChartData()
                        }

                        // Time Period Selector (fixed, not scrollable)
                        TimePeriodSelector(
                            selectedPeriod: $chartViewModel.selectedPeriod,
                            onChange: { chartViewModel.onPeriodChange() }
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                        // Portfolio/Stock Selector (fixed, not scrollable)
                        UnifiedStockSelector(
                            stocks: viewModel.stocks.filter { $0.isMaritalStatus },
                            stockPrices: viewModel.stockPrices,
                            selectedTicker: chartViewModel.selectedTicker,
                            selectedPeriod: chartViewModel.selectedPeriod,
                            onSelect: { ticker in
                                if let ticker = ticker {
                                    // Selected a stock
                                    Task {
                                        await chartViewModel.loadTickerHistory(ticker: ticker)
                                    }
                                } else {
                                    // Selected portfolio
                                    chartViewModel.clearSelectedTicker()
                                    Task {
                                        await chartViewModel.loadPortfolioHistory()
                                    }
                                }
                            }
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }

                    Spacer()
                }
            }
        }
        .task {
            await chartViewModel.loadPortfolioHistory()
        }
        .onAppear {
            chartViewModel.startAutoRefresh()
        }
        .onDisappear {
            chartViewModel.stopAutoRefresh()
        }
        .gesture(
            DragGesture()
                .onEnded { gesture in
                    // Swipe right to go to previous tab
                    if gesture.translation.width > 100 {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedTab = 2 // Visuals
                        }
                    }
                    // Swipe left to go to next tab
                    else if gesture.translation.width < -100 {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedTab = 4 // Accounts
                        }
                    }
                }
        )
    }
}

// MARK: - Unified Chart

struct UnifiedChart: View {
    @ObservedObject var chartViewModel: ChartDataViewModel
    @ObservedObject var viewModel: StockViewModel
    let showDollarAmounts: Bool

    private var isPortfolioView: Bool {
        chartViewModel.selectedTicker == nil
    }

    private var chartData: [ChartDataPoint] {
        isPortfolioView ? chartViewModel.portfolioHistory : chartViewModel.tickerHistory
    }

    private var isPositive: Bool {
        guard let first = chartData.first, let last = chartData.last else { return true }
        return last.value >= first.value
    }

    private var chartColor: Color {
        isPositive ? AppColors.positive : Color.red
    }

    private var priceChange: (value: Double, percent: Double) {
        guard let last = chartData.last else {
            return (0, 0)
        }

        // For individual ticker 1D charts, use dailyStartPrice to match the chip percentage
        if !isPortfolioView,
           chartViewModel.selectedPeriod == .oneDay,
           let ticker = chartViewModel.selectedTicker,
           let priceData = viewModel.stockPrices[ticker],
           priceData.dailyStartPrice > 0 {
            let change = last.value - priceData.dailyStartPrice
            let percent = (change / priceData.dailyStartPrice) * 100
            return (change, percent)
        }

        // For portfolio or ALL period, use first data point
        guard let first = chartData.first, first.value > 0 else {
            return (0, 0)
        }
        let change = last.value - first.value
        let percent = (change / first.value) * 100
        return (change, percent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if isPortfolioView {
                        Text("Portfolio")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.secondary)
                    } else if let ticker = chartViewModel.selectedTicker {
                        Text(ticker)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.secondary)

                        // Show company name below ticker
                        if let stock = viewModel.stocks.first(where: { $0.ticker == ticker }) {
                            Text(stock.companyName)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.primary)
                        }
                    }

                    if chartViewModel.hasData || !chartViewModel.tickerHistory.isEmpty {
                        let currentValue = chartData.last?.value ?? 0
                        if showDollarAmounts {
                            Text("***")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.primary)
                        } else {
                            Text(formatCurrency(currentValue))
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.primary)
                        }

                        HStack(spacing: 4) {
                            if showDollarAmounts {
                                // Show only percentage
                                Text("\(priceChange.percent >= 0 ? "+" : "")\(String(format: "%.2f", priceChange.percent))%")
                            } else {
                                // Show both dollar amount and percentage
                                Text("\(priceChange.value >= 0 ? "+" : "")\(formatChangeValue(priceChange.value))")
                                Text("(\(priceChange.percent >= 0 ? "+" : "")\(String(format: "%.2f", priceChange.percent))%)")
                            }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(chartColor)
                    }
                }

                Spacer()
            }
            .padding(.trailing, 20)

            // Chart
            if chartViewModel.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .scaleEffect(1.2)

                    Text("Loading data...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = chartViewModel.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if chartData.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.bottom, 4)

                    Text("No historical data available")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("Data will appear once Polygon.io fetches historical prices")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            } else {
                Chart {
                    ForEach(chartData) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(chartColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .shadow(color: chartColor.opacity(0.3), radius: 2, x: 0, y: 0)
                    }

                    if let lastPoint = chartData.last {
                        PointMark(
                            x: .value("Date", lastPoint.date),
                            y: .value("Value", lastPoint.value)
                        )
                        .foregroundStyle(chartColor)
                        .symbolSize(40)
                    }
                }
                .chartYScale(domain: getYAxisDomain())
                .chartXAxis {
                    if chartViewModel.selectedPeriod == .oneDay {
                        // Custom 1D axis - let chart auto-scale but use custom labels
                        AxisMarks(preset: .aligned, values: .automatic(desiredCount: 3)) { value in
                            if let date = value.as(Date.self) {
                                AxisValueLabel {
                                    Text(formatIntradayTime(date))
                                        .font(.system(size: 9))
                                }
                            }
                        }
                    } else {
                        // Standard axis for other periods
                        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .font(.system(size: 10))
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 6)) { value in
                        AxisValueLabel {
                            if let val = value.as(Double.self) {
                                Text(formatYAxis(val))
                                    .font(.system(size: 10))
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Formatting Helpers (using ChartFormatters)

    private func formatCurrency(_ value: Double) -> String {
        ChartFormatters.formatCurrency(value)
    }

    private func formatChangeValue(_ value: Double) -> String {
        ChartFormatters.formatChangeValue(value, isPortfolio: isPortfolioView)
    }

    private func formatCompact(_ value: Double) -> String {
        ChartFormatters.formatCompact(value)
    }

    private func formatYAxis(_ value: Double) -> String {
        ChartFormatters.formatYAxis(value, period: chartViewModel.selectedPeriod, isPortfolio: isPortfolioView)
    }

    // MARK: - Axis Helpers (using ChartAxisHelpers)

    private func getYAxisDomain() -> ClosedRange<Double> {
        ChartAxisHelpers.getYAxisDomain(data: chartData, period: chartViewModel.selectedPeriod)
    }

    private func getIntradayAxisValues() -> [Date] {
        ChartAxisHelpers.getIntradayAxisValues()
    }

    private func formatIntradayTime(_ date: Date) -> String {
        ChartFormatters.formatIntradayTime(date)
    }
}

// MARK: - Time Period Selector

struct TimePeriodSelector: View {
    @Binding var selectedPeriod: ChartTimePeriod
    var onChange: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(ChartTimePeriod.allCases) { period in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedPeriod = period
                        onChange()
                    }
                } label: {
                    Image(period == .oneDay ? "daily" : "alltime")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 10)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedPeriod == period ?
                                      AnyShapeStyle(LinearGradient(
                                          colors: [Color.blue, Color.blue.opacity(0.8)],
                                          startPoint: .top,
                                          endPoint: .bottom
                                      )) :
                                      AnyShapeStyle(Color.gray.opacity(0.15)))
                        )
                        .shadow(color: selectedPeriod == period ? Color.blue.opacity(0.3) : .clear,
                                radius: 4, x: 0, y: 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Portfolio Line Chart

struct PortfolioLineChart: View {
    @ObservedObject var chartViewModel: ChartDataViewModel

    private var isPositive: Bool {
        chartViewModel.isPositivePeriod
    }

    private var chartColor: Color {
        isPositive ? AppColors.positive : Color.red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if chartViewModel.hasData {
                        Text(formatCurrency(chartViewModel.currentValue))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.primary)

                        HStack(spacing: 4) {
                            Text("\(chartViewModel.periodReturn.value >= 0 ? "+" : "")\(formatCurrency(chartViewModel.periodReturn.value))")
                            Text("(\(chartViewModel.periodReturn.percent >= 0 ? "+" : "")\(String(format: "%.2f", chartViewModel.periodReturn.percent))%)")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(chartColor)
                    }
                }

                Spacer()
            }
            .padding(.bottom, 4)

            // Chart
            if chartViewModel.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .scaleEffect(1.2)

                    Text("Loading portfolio data...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = chartViewModel.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if chartViewModel.portfolioHistory.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.bottom, 4)

                    Text("No historical data available")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("Data will appear once Polygon.io fetches your portfolio history")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            } else {
                Chart {
                    // Portfolio value line with shadow
                    ForEach(chartViewModel.portfolioHistory) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(chartColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .shadow(color: chartColor.opacity(0.3), radius: 2, x: 0, y: 0)
                    }

                    // Current value marker
                    if let lastPoint = chartViewModel.portfolioHistory.last {
                        PointMark(
                            x: .value("Date", lastPoint.date),
                            y: .value("Value", lastPoint.value)
                        )
                        .foregroundStyle(chartColor)
                        .symbolSize(40)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 10))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                        AxisValueLabel {
                            if let val = value.as(Double.self) {
                                Text(formatCompact(val))
                                    .font(.system(size: 10))
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
    }

    private func formatCurrency(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000 {
            return String(format: "$%.2fM", value / 1_000_000)
        } else if absValue >= 1_000 {
            return String(format: "$%.2fK", value / 1_000)
        } else {
            return value.formatted(.currency(code: "USD"))
        }
    }

    private func formatCompact(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.0fK", value / 1_000)
        } else {
            return String(format: "$%.0f", value)
        }
    }
}

// MARK: - Performance Summary Card

struct PerformanceSummaryCard: View {
    let periodReturn: (value: Double, percent: Double)
    let totalReturn: (value: Double, percent: Double)
    let period: ChartTimePeriod
    let costBasis: Double
    let showDollarAmounts: Bool

    var body: some View {
        HStack(spacing: 16) {
            // Period Return
            VStack(alignment: .leading, spacing: 4) {
                Text("\(period.rawValue) Return")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Text("\(periodReturn.percent >= 0 ? "+" : "")\(String(format: "%.2f", periodReturn.percent))%")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(periodReturn.value >= 0 ? AppColors.positive : AppColors.negative)

                // Performance scale indicator
                HStack(spacing: 2) {
                    ForEach(0..<5) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(performanceScaleColor(index: i, percent: periodReturn.percent))
                            .frame(width: 20, height: 4)
                    }
                }
                .padding(.top, 4)

                if showDollarAmounts {
                    Text("\(periodReturn.value >= 0 ? "+" : "")\(formatCurrency(periodReturn.value))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor((periodReturn.value >= 0 ? AppColors.positive : AppColors.negative).opacity(0.8))
                }
            }

            Spacer()

            // Total Return
            VStack(alignment: .trailing, spacing: 4) {
                Text("Total Return")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Text("\(totalReturn.percent >= 0 ? "+" : "")\(String(format: "%.2f", totalReturn.percent))%")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(totalReturn.value >= 0 ? AppColors.positive : AppColors.negative)

                if showDollarAmounts {
                    Text("vs \(formatCurrency(costBasis)) cost")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func formatCurrency(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000 {
            return String(format: "$%.1fM", value / 1_000_000)
        } else if absValue >= 1_000 {
            return String(format: "$%.1fK", value / 1_000)
        } else {
            return value.formatted(.currency(code: "USD"))
        }
    }

    private func performanceScaleColor(index: Int, percent: Double) -> Color {
        let absPercent = abs(percent)
        let thresholds: [Double] = [1, 3, 5, 10, 20]  // % thresholds
        let isActive = absPercent >= thresholds[index]

        if !isActive {
            return Color.gray.opacity(0.2)
        }

        return percent >= 0 ? AppColors.positive.opacity(0.7) : AppColors.negative.opacity(0.7)
    }
}

// MARK: - Unified Stock Selector

struct UnifiedStockSelector: View {
    let stocks: [Stock]
    let stockPrices: [String: StockPriceData]
    let selectedTicker: String?
    let selectedPeriod: ChartTimePeriod
    let onSelect: (String?) -> Void

    @State private var scrollPosition: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // Portfolio button (first option)
                    Button(action: {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        onSelect(nil)
                    }) {
                        VStack(alignment: .center, spacing: 3) {
                            Text("Portfolio")
                                .font(.system(size: 13, weight: selectedTicker == nil ? .bold : .medium))
                                .multilineTextAlignment(.center)

                            // Empty spacer to match stock button height
                            Text(" ")
                                .font(.system(size: 9, weight: .semibold))
                                .opacity(0)
                        }
                        .frame(minWidth: 70, alignment: .center)
                        .foregroundColor(selectedTicker == nil ? .white : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(selectedTicker == nil ?
                                      AnyShapeStyle(LinearGradient(
                                          colors: [Color.blue, Color.blue.opacity(0.8)],
                                          startPoint: .topLeading,
                                          endPoint: .bottomTrailing
                                      )) :
                                      AnyShapeStyle(Color.gray.opacity(0.15)))
                        )
                        .shadow(color: selectedTicker == nil ? Color.blue.opacity(0.3) : .clear,
                                radius: 3, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)

                    // Individual stock buttons
                    ForEach(sortedStocks, id: \.ticker) { stock in
                        StockChipButton(
                            stock: stock,
                            priceData: stockPrices[stock.ticker],
                            selectedPeriod: selectedPeriod,
                            isSelected: selectedTicker == stock.ticker,
                            onTap: {
                                let impact = UIImpactFeedbackGenerator(style: .medium)
                                impact.impactOccurred()
                                onSelect(stock.ticker)
                            }
                        )
                        .id(stock.ticker)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 4)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrollPosition)
        }
    }

    private var sortedStocks: [Stock] {
        // Deduplicate stocks by ticker, keeping the one with more shares
        var uniqueStocks: [String: Stock] = [:]
        for stock in stocks {
            let shares = totalShares(stock)
            // Only include stocks with shares > 0 and valid ticker
            guard shares > 0,
                  !stock.ticker.isEmpty,
                  stock.ticker.count <= 6,  // Most tickers are 1-6 characters (e.g., KRKNF)
                  stock.ticker.uppercased() == stock.ticker,  // Tickers should be uppercase
                  stock.ticker.allSatisfy({ $0.isLetter || $0.isNumber }) else {
                continue
            }

            if let existing = uniqueStocks[stock.ticker] {
                // Keep the stock with more shares
                if shares > totalShares(existing) {
                    uniqueStocks[stock.ticker] = stock
                }
            } else {
                uniqueStocks[stock.ticker] = stock
            }
        }

        // Sort by portfolio value (price * shares), largest first
        return uniqueStocks.values.sorted { stock1, stock2 in
            let value1 = (stockPrices[stock1.ticker]?.currentPrice ?? 0) * totalShares(stock1)
            let value2 = (stockPrices[stock2.ticker]?.currentPrice ?? 0) * totalShares(stock2)
            return value1 > value2
        }
    }

    private func totalShares(_ stock: Stock) -> Double {
        stock.lots.isEmpty ? Double(stock.shares) : stock.lots.reduce(0) { $0 + $1.shares }
    }
}

struct StockChipButton: View {
    let stock: Stock
    let priceData: StockPriceData?
    let selectedPeriod: ChartTimePeriod
    let isSelected: Bool
    let onTap: () -> Void

    private var changePercent: Double {
        guard let priceData = priceData else { return 0 }

        switch selectedPeriod {
        case .oneDay:
            // Show 1D return (daily change from market open)
            let currentPrice = priceData.currentPrice
            let dailyStartPrice = priceData.dailyStartPrice
            guard dailyStartPrice > 0 else { return 0 }
            return ((currentPrice - dailyStartPrice) / dailyStartPrice) * 100
        case .all:
            // Show user's all-time return from their purchase price
            let currentPrice = priceData.currentPrice
            let purchasePrice = stock.purchasePrice
            guard purchasePrice > 0 else { return 0 }
            return ((currentPrice - purchasePrice) / purchasePrice) * 100
        }
    }

    private var changeColor: Color {
        changePercent >= 0 ? AppColors.positive : Color.red
    }

    private var ticker: String {
        stock.ticker
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                Text(ticker)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .white : .primary)

                if let _ = priceData {
                    HStack(spacing: 2) {
                        Image(systemName: changePercent >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 7, weight: .bold))
                        Text(String(format: "%.1f%%", abs(changePercent)))
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(isSelected ? .white.opacity(0.9) : changeColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ?
                          AnyShapeStyle(LinearGradient(
                              colors: [changeColor, changeColor.opacity(0.8)],
                              startPoint: .topLeading,
                              endPoint: .bottomTrailing
                          )) :
                          AnyShapeStyle(Color.gray.opacity(0.15)))
            )
            .shadow(color: isSelected ? changeColor.opacity(0.3) : .clear,
                    radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stock Chart Selector (Legacy - kept for reference)

struct StockChartSelector: View {
    let stocks: [Stock]
    let stockPrices: [String: StockPriceData]
    let selectedTicker: String?
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Individual Stocks")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)

            VStack(spacing: 8) {
                ForEach(sortedStocks, id: \.ticker) { stock in
                    StockSelectorCard(
                        ticker: stock.ticker,
                        companyName: stock.companyName,
                        priceData: stockPrices[stock.ticker],
                        isSelected: selectedTicker == stock.ticker,
                        onTap: { onSelect(stock.ticker) }
                    )
                }
            }
        }
    }

    private var sortedStocks: [Stock] {
        // Deduplicate stocks by ticker, keeping the one with more shares
        var uniqueStocks: [String: Stock] = [:]
        for stock in stocks {
            let shares = totalShares(stock)
            // Only include stocks with shares > 0 and valid ticker
            guard shares > 0,
                  !stock.ticker.isEmpty,
                  stock.ticker.count <= 6,  // Most tickers are 1-6 characters (e.g., KRKNF)
                  stock.ticker.uppercased() == stock.ticker,  // Tickers should be uppercase
                  stock.ticker.allSatisfy({ $0.isLetter || $0.isNumber }) else {
                continue
            }

            if let existing = uniqueStocks[stock.ticker] {
                // Keep the stock with more shares
                if shares > totalShares(existing) {
                    uniqueStocks[stock.ticker] = stock
                }
            } else {
                uniqueStocks[stock.ticker] = stock
            }
        }

        // Sort by portfolio value (price * shares), largest first
        return uniqueStocks.values.sorted { stock1, stock2 in
            let value1 = (stockPrices[stock1.ticker]?.currentPrice ?? 0) * totalShares(stock1)
            let value2 = (stockPrices[stock2.ticker]?.currentPrice ?? 0) * totalShares(stock2)
            return value1 > value2
        }
    }

    private func totalShares(_ stock: Stock) -> Double {
        stock.lots.isEmpty ? Double(stock.shares) : stock.lots.reduce(0) { $0 + $1.shares }
    }
}

struct StockSelectorCard: View {
    let ticker: String
    let companyName: String
    let priceData: StockPriceData?
    let isSelected: Bool
    let onTap: () -> Void

    private var dayChangePercent: Double {
        priceData?.changePercent ?? 0
    }

    private var dayChangeColor: Color {
        dayChangePercent >= 0 ? AppColors.positive : Color.red
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Ticker symbol
                Text(ticker)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 70, alignment: .leading)

                // Company name
                Text(companyName)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                // Day change percentage
                if let _ = priceData {
                    HStack(spacing: 4) {
                        Image(systemName: dayChangePercent >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text(String(format: "%.2f%%", abs(dayChangePercent)))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(dayChangeColor)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
            .shadow(color: isSelected ? Color.blue.opacity(0.2) : Color.black.opacity(0.05),
                    radius: isSelected ? 4 : 2, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Individual Stock Chart

struct IndividualStockChart: View {
    let ticker: String
    let data: [ChartDataPoint]
    let color: Color
    let isLoading: Bool

    private var isPositive: Bool {
        guard let first = data.first, let last = data.last else { return true }
        return last.value >= first.value
    }

    private var chartColor: Color {
        isPositive ? AppColors.positive : Color.red
    }

    private var priceChange: (value: Double, percent: Double) {
        guard let first = data.first, let last = data.last, first.value > 0 else {
            return (0, 0)
        }
        let change = last.value - first.value
        let percent = (change / first.value) * 100
        return (change, percent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ticker)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)

                    if let lastPrice = data.last?.value {
                        Text(lastPrice.formatted(.currency(code: "USD")))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.primary)

                        HStack(spacing: 4) {
                            Text("\(priceChange.value >= 0 ? "+" : "")\(String(format: "$%.2f", priceChange.value))")
                            Text("(\(priceChange.percent >= 0 ? "+" : "")\(String(format: "%.2f", priceChange.percent))%)")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(chartColor)
                    }
                }

                Spacer()
            }

            // Chart
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if data.isEmpty {
                Text("No data available")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart {
                    ForEach(data) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Price", point.value)
                        )
                        .foregroundStyle(chartColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .shadow(color: chartColor.opacity(0.3), radius: 2, x: 0, y: 0)
                    }

                    // Current value marker
                    if let lastPoint = data.last {
                        PointMark(
                            x: .value("Date", lastPoint.date),
                            y: .value("Price", lastPoint.value)
                        )
                        .foregroundStyle(chartColor)
                        .symbolSize(40)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 10))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisValueLabel {
                            if let val = value.as(Double.self) {
                                Text("$\(Int(val))")
                                    .font(.system(size: 10))
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
    }
}

// MARK: - API Config Warning Card

struct APIConfigWarningCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 16))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("API Key Required")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Text("Configure Polygon.io key for charts")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Link(destination: URL(string: "https://polygon.io/")!) {
                Text("Setup")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange)
                    .cornerRadius(6)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Preview

#Preview("Charts View with Header & Footer") {
    @Previewable @State var selectedTab = 3
    @Previewable @State var showDollarAmounts = true

    let viewModel = StockViewModel()

    // Add sample stocks
    let sampleStocks = [
        Stock(ticker: "AAPL", companyName: "Apple Inc.", purchasePrice: 150.0, shares: 10, isMaritalStatus: true, lots: []),
        Stock(ticker: "GOOGL", companyName: "Alphabet Inc.", purchasePrice: 2800.0, shares: 5, isMaritalStatus: true, lots: []),
        Stock(ticker: "MSFT", companyName: "Microsoft Corp.", purchasePrice: 300.0, shares: 8, isMaritalStatus: true, lots: []),
        Stock(ticker: "SPY", companyName: "SPDR S&P 500 ETF", purchasePrice: 400.0, shares: 15, isMaritalStatus: true, lots: [])
    ]

    // Add stocks to viewModel
    for stock in sampleStocks {
        viewModel.stocks.append(stock)
    }

    // Add sample price data
    viewModel.stockPrices["AAPL"] = StockPriceData(
        ticker: "AAPL",
        currentPrice: 175.50,
        changePercent: 2.5,
        profitLoss: 255.0,
        dailyStartPrice: 171.0,
        weeklyStartPrice: 170.0,
        monthlyStartPrice: 165.0,
        threeMonthsStartPrice: 160.0,
        ytdStartPrice: 155.0,
        allTimeStartPrice: 150.0,
        dailyStartTime: Date(),
        weeklyStartTime: Date(),
        monthlyStartTime: Date(),
        threeMonthsStartTime: Date(),
        ytdStartTime: Date(),
        allTimeStartTime: Date()
    )

    viewModel.stockPrices["GOOGL"] = StockPriceData(
        ticker: "GOOGL",
        currentPrice: 2950.0,
        changePercent: -1.2,
        profitLoss: 750.0,
        dailyStartPrice: 2985.0,
        weeklyStartPrice: 2900.0,
        monthlyStartPrice: 2850.0,
        threeMonthsStartPrice: 2800.0,
        ytdStartPrice: 2750.0,
        allTimeStartPrice: 2800.0,
        dailyStartTime: Date(),
        weeklyStartTime: Date(),
        monthlyStartTime: Date(),
        threeMonthsStartTime: Date(),
        ytdStartTime: Date(),
        allTimeStartTime: Date()
    )

    viewModel.stockPrices["MSFT"] = StockPriceData(
        ticker: "MSFT",
        currentPrice: 385.0,
        changePercent: 0.8,
        profitLoss: 680.0,
        dailyStartPrice: 382.0,
        weeklyStartPrice: 380.0,
        monthlyStartPrice: 375.0,
        threeMonthsStartPrice: 360.0,
        ytdStartPrice: 350.0,
        allTimeStartPrice: 300.0,
        dailyStartTime: Date(),
        weeklyStartTime: Date(),
        monthlyStartTime: Date(),
        threeMonthsStartTime: Date(),
        ytdStartTime: Date(),
        allTimeStartTime: Date()
    )

    viewModel.stockPrices["SPY"] = StockPriceData(
        ticker: "SPY",
        currentPrice: 485.0,
        changePercent: -0.4,
        profitLoss: 1275.0,
        dailyStartPrice: 487.0,
        weeklyStartPrice: 480.0,
        monthlyStartPrice: 475.0,
        threeMonthsStartPrice: 450.0,
        ytdStartPrice: 430.0,
        allTimeStartPrice: 400.0,
        dailyStartTime: Date(),
        weeklyStartTime: Date(),
        monthlyStartTime: Date(),
        threeMonthsStartTime: Date(),
        ytdStartTime: Date(),
        allTimeStartTime: Date()
    )

    return ZStack {
        Color(UIColor.systemBackground)
            .ignoresSafeArea()

        VStack(spacing: 0) {
            // Charts content
            ChartsView(
                viewModel: viewModel,
                selectedTab: $selectedTab,
                showDollarAmounts: $showDollarAmounts
            )

            // Bottom navigation bar
            BottomNavigationBar(selectedTab: $selectedTab)
        }

        // Fixed header (matching ContentView)
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Solid background
                Color(UIColor.systemBackground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .ignoresSafeArea(edges: .top)

                HStack {
                    Image("hoidma")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 50)
                        .cornerRadius(8)
                        .padding(.leading, 16)

                    Spacer()
                }

                Button {
                    // Toggle appearance in preview
                } label: {
                    Image("dave.folly.logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 50)
                }
            }

            Spacer()
        }

        // Dollar/percentage toggle (shown on Charts tab)
        VStack {
            HStack {
                Spacer()
                Button {
                    showDollarAmounts.toggle()
                } label: {
                    Image(showDollarAmounts ? "dollar" : "percentage")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                }
                .padding(.trailing, 16)
                .padding(.top, 14)
            }

            Spacer()
        }
    }
}
