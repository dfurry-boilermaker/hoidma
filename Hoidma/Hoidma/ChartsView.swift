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

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        // Header spacer for fixed header
                        Spacer().frame(height: 90)

                        // Time Period Selector
                        TimePeriodSelector(
                            selectedPeriod: $chartViewModel.selectedPeriod,
                            onChange: { chartViewModel.onPeriodChange() }
                        )

                        // API Configuration Warning
                        if !chartViewModel.isPolygonConfigured {
                            APIConfigWarningCard()
                                .padding(.horizontal, 20)
                        }

                        // Portfolio Value Chart
                        if chartViewModel.isPolygonConfigured {
                            PortfolioLineChart(chartViewModel: chartViewModel)
                                .frame(height: 280)
                                .padding(.horizontal, 20)

                            // Performance Summary Card
                            if chartViewModel.hasData {
                                PerformanceSummaryCard(
                                    periodReturn: chartViewModel.periodReturn,
                                    totalReturn: chartViewModel.totalReturn,
                                    period: chartViewModel.selectedPeriod,
                                    costBasis: viewModel.totalCostBasis,
                                    showDollarAmounts: showDollarAmounts
                                )
                                .padding(.horizontal, 20)
                            }

                            // Individual Stock Selector
                            StockChartSelector(
                                stocks: viewModel.stocks.filter { $0.isMaritalStatus },
                                stockPrices: viewModel.stockPrices,
                                selectedTicker: chartViewModel.selectedTicker,
                                onSelect: { ticker in
                                    if chartViewModel.selectedTicker == ticker {
                                        chartViewModel.clearSelectedTicker()
                                    } else {
                                        Task {
                                            await chartViewModel.loadTickerHistory(ticker: ticker)
                                        }
                                    }
                                }
                            )
                            .padding(.horizontal, 20)

                            // Individual Stock Chart
                            if let ticker = chartViewModel.selectedTicker {
                                IndividualStockChart(
                                    ticker: ticker,
                                    data: chartViewModel.tickerHistory,
                                    color: colorForTicker(ticker),
                                    isLoading: chartViewModel.isLoading
                                )
                                .frame(height: 200)
                                .padding(.horizontal, 20)
                            }
                        }

                        // Bottom padding for tab bar
                        Spacer().frame(height: 100)
                    }
                }
            }
        }
        .task {
            await chartViewModel.loadPortfolioHistory()
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

// MARK: - Time Period Selector

struct TimePeriodSelector: View {
    @Binding var selectedPeriod: ChartTimePeriod
    var onChange: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ChartTimePeriod.allCases) { period in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedPeriod = period
                        onChange()
                    }
                } label: {
                    Text(period.rawValue)
                        .font(.system(size: 13, weight: selectedPeriod == period ? .bold : .medium))
                        .foregroundColor(selectedPeriod == period ? .white : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
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
        .padding(.horizontal, 20)
    }
}

// MARK: - Portfolio Line Chart

struct PortfolioLineChart: View {
    @ObservedObject var chartViewModel: ChartDataViewModel

    private var isPositive: Bool {
        chartViewModel.isPositivePeriod
    }

    private var chartColor: Color {
        isPositive ? AppColors.positive : AppColors.negative
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Portfolio Value")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.primary)

                Spacer()

                if chartViewModel.hasData {
                    Text(formatCurrency(chartViewModel.currentValue))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                }
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

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    chartColor.opacity(0.35),
                                    chartColor.opacity(0.15),
                                    chartColor.opacity(0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }

                    // Enhanced cost basis line
                    ForEach(chartViewModel.costBasisHistory) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Cost", point.value)
                        )
                        .foregroundStyle(Color.gray.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
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
                .chartYScale(domain: chartViewModel.chartMinValue...chartViewModel.chartMaxValue)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 10))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let val = value.as(Double.self) {
                                Text(formatCompact(val))
                                    .font(.system(size: 10))
                            }
                        }
                    }
                }
            }

            // Chart Legend
            if chartViewModel.hasData {
                HStack(spacing: 16) {
                    // Portfolio line indicator
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(chartColor)
                            .frame(width: 20, height: 3)
                        Text("Portfolio")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    // Cost basis indicator
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: 20, height: 3)
                            .overlay(
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: 8, height: 3)
                            )
                        Text("Cost Basis")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func formatCurrency(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
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

// MARK: - Stock Chart Selector

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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sortedStocks, id: \.ticker) { stock in
                        StockChipButton(
                            ticker: stock.ticker,
                            isSelected: selectedTicker == stock.ticker,
                            color: colorForTicker(stock.ticker),
                            onTap: { onSelect(stock.ticker) }
                        )
                    }
                }
            }
        }
    }

    private var sortedStocks: [Stock] {
        stocks.sorted { stock1, stock2 in
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
    let ticker: String
    let isSelected: Bool
    let color: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)

                Text(ticker)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ?
                          AnyShapeStyle(LinearGradient(
                              colors: [color, color.opacity(0.7)],
                              startPoint: .topLeading,
                              endPoint: .bottomTrailing
                          )) :
                          AnyShapeStyle(Color.gray.opacity(0.15)))
            )
            .shadow(color: isSelected ? color.opacity(0.3) : .clear,
                    radius: 3, x: 0, y: 1)
        }
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
        isPositive ? AppColors.positive : AppColors.negative
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
                HStack(spacing: 8) {
                    Circle()
                        .fill(color)
                        .frame(width: 12, height: 12)

                    Text(ticker)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Spacer()

                if let lastPrice = data.last?.value {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(lastPrice.formatted(.currency(code: "USD")))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.primary)

                        Text("\(priceChange.percent >= 0 ? "+" : "")\(String(format: "%.2f", priceChange.percent))%")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(chartColor)
                    }
                }
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
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Price", point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [chartColor.opacity(0.2), chartColor.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 9))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisValueLabel {
                            if let val = value.as(Double.self) {
                                Text("$\(Int(val))")
                                    .font(.system(size: 9))
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
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
