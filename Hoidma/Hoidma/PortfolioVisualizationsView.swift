import SwiftUI

struct PortfolioVisualizationsView: View {
    @ObservedObject var viewModel: StockViewModel
    @Binding var selectedTab: Int
    @Binding var selectedAccountName: String?
    @Binding var showDollarAmounts: Bool
    @Binding var navigationPath: NavigationPath
    @Environment(\.colorScheme) private var colorScheme
    private var isDarkMode: Bool { colorScheme == .dark }
    @State private var showAllTimeHeatmap: Bool = false
    @State private var showAllTimeAccountHeatmap: Bool = false
    @State private var showAllTimeWinnersLosers: Bool = false

    /// Calculate account summaries from all stocks and their lots
    private var accountSummaries: [AccountSummary] {
        var accountsDict: [String: AccountSummary] = [:]

        for stock in viewModel.stocks where stock.isMaritalStatus {
            let priceData = viewModel.stockPrices[stock.ticker]
            let currentPrice = priceData?.currentPrice ?? stock.purchasePrice
            let dailyChangePercent = priceData?.apiPeriodChanges["1d"] ?? 0

            for lot in stock.lots {
                let lotValue = currentPrice * lot.shares
                let lotCost = lot.totalCost
                let lotDailyGain = lotValue * (dailyChangePercent / (100 + dailyChangePercent))

                let position = AccountPosition(
                    ticker: stock.ticker,
                    companyName: stock.companyName,
                    shares: lot.shares,
                    value: lotValue,
                    cost: lotCost,
                    dailyChange: dailyChangePercent,
                    color: colorForTicker(stock.ticker)
                )

                if var existing = accountsDict[lot.accountName] {
                    existing.totalValue += lotValue
                    existing.totalCost += lotCost
                    existing.dailyGain += lotDailyGain
                    existing.positions.append(position)
                    accountsDict[lot.accountName] = existing
                } else {
                    accountsDict[lot.accountName] = AccountSummary(
                        accountName: lot.accountName,
                        totalValue: lotValue,
                        totalCost: lotCost,
                        dailyGain: lotDailyGain,
                        dailyGainPercent: 0,
                        positions: [position]
                    )
                }
            }
        }

        // Calculate daily gain percent for each account
        for (key, var account) in accountsDict {
            let previousValue = account.totalValue - account.dailyGain
            account.dailyGainPercent = previousValue > 0 ? (account.dailyGain / previousValue) * 100 : 0
            accountsDict[key] = account
        }

        return accountsDict.values.sorted { $0.totalValue > $1.totalValue }
    }

    // Calculate portfolio data for visualizations
    private var portfolioData: [(ticker: String, value: Double, percentage: Double, color: Color)] {
        let stocks = viewModel.stocks.filter { $0.isMaritalStatus }
        var data: [(ticker: String, value: Double, percentage: Double, color: Color)] = []
        
        for stock in stocks {
            if let priceData = viewModel.stockPrices[stock.ticker] {
                let totalShares = stock.lots.isEmpty ? Double(stock.shares) : stock.lots.reduce(0.0) { $0 + $1.shares }
                let stockValue = priceData.currentPrice * totalShares
                let percentage = viewModel.totalPortfolioValue > 0 ? (stockValue / viewModel.totalPortfolioValue) * 100 : 0
                
                if stockValue > 0 {
                    data.append((stock.ticker, stockValue, percentage, colorForTicker(stock.ticker)))
                }
            }
        }
        
        return data.sorted { $0.value > $1.value }
    }
    
    // Calculate all positions across accounts with per-account values
    private var allPositionsData: [(ticker: String, accounts: [String], totalValue: Double, accountValues: [String: Double], color: Color)] {
        let stocks = viewModel.stocks.filter { $0.isMaritalStatus }
        var allData: [(ticker: String, accounts: [String], totalValue: Double, accountValues: [String: Double], color: Color)] = []

        for stock in stocks {
            if let priceData = viewModel.stockPrices[stock.ticker] {
                // Calculate value per account from lots
                var perAccountValues: [String: Double] = [:]
                for lot in stock.lots {
                    let lotValue = priceData.currentPrice * lot.shares
                    perAccountValues[lot.accountName, default: 0] += lotValue
                }

                let accounts = Array(perAccountValues.keys).sorted()
                let totalValue = perAccountValues.values.reduce(0, +)

                if totalValue > 0 {
                    allData.append((stock.ticker, accounts, totalValue, perAccountValues, colorForTicker(stock.ticker)))
                }
            }
        }

        return allData.sorted { $0.totalValue > $1.totalValue }
    }

    // Calculate data for the performance heatmap (daily)
    private var dailyHeatmapData: [(ticker: String, value: Double, changePercent: Double)] {
        let stocks = viewModel.stocks.filter { $0.isMaritalStatus }
        var data: [(ticker: String, value: Double, changePercent: Double)] = []

        for stock in stocks {
            if let priceData = viewModel.stockPrices[stock.ticker] {
                let totalShares = stock.lots.isEmpty ? Double(stock.shares) : stock.lots.reduce(0.0) { $0 + $1.shares }
                let stockValue = priceData.currentPrice * totalShares

                // Get daily change percent - prioritize API data, then calculate from previousClose
                let dailyChange: Double
                if let apiDaily = priceData.apiPeriodChanges["1d"] {
                    dailyChange = apiDaily
                } else if let prevClose = priceData.previousClose, prevClose > 0 {
                    // Calculate daily change from previousClose if API didn't provide it
                    dailyChange = ((priceData.currentPrice - prevClose) / prevClose) * 100
                } else {
                    // Fall back to calculated daily change from dailyStartPrice
                    let startPrice = priceData.dailyStartPrice
                    dailyChange = startPrice > 0 ? ((priceData.currentPrice - startPrice) / startPrice) * 100 : 0
                }

                if stockValue > 0 {
                    data.append((stock.ticker, stockValue, dailyChange))
                }
            }
        }

        return data.sorted { $0.value > $1.value }
    }

    // Calculate data for the performance heatmap (all-time / total gain)
    private var allTimeHeatmapData: [(ticker: String, value: Double, changePercent: Double)] {
        let stocks = viewModel.stocks.filter { $0.isMaritalStatus }
        var data: [(ticker: String, value: Double, changePercent: Double)] = []

        for stock in stocks {
            if let priceData = viewModel.stockPrices[stock.ticker] {
                let totalShares = stock.lots.isEmpty ? Double(stock.shares) : stock.lots.reduce(0.0) { $0 + $1.shares }
                let stockValue = priceData.currentPrice * totalShares
                let totalCost = stock.lots.isEmpty ? stock.totalCost : stock.lots.reduce(0.0) { $0 + $1.totalCost }

                // Calculate all-time gain/loss percentage
                let allTimeChange = totalCost > 0 ? ((stockValue - totalCost) / totalCost) * 100 : 0

                if stockValue > 0 {
                    data.append((stock.ticker, stockValue, allTimeChange))
                }
            }
        }

        return data.sorted { $0.value > $1.value }
    }

    // Current heatmap data based on toggle
    private var heatmapData: [(ticker: String, value: Double, changePercent: Double)] {
        showAllTimeHeatmap ? allTimeHeatmapData : dailyHeatmapData
    }

    // Calculate data for the account heatmap (daily performance)
    private var accountDailyHeatmapData: [(ticker: String, value: Double, changePercent: Double)] {
        accountSummaries.map { account in
            (ticker: account.accountName, value: account.totalValue, changePercent: account.dailyGainPercent)
        }
    }

    // Calculate data for the account heatmap (all-time performance)
    private var accountAllTimeHeatmapData: [(ticker: String, value: Double, changePercent: Double)] {
        accountSummaries.map { account in
            (ticker: account.accountName, value: account.totalValue, changePercent: account.profitLossPercent)
        }
    }

    // Current account heatmap data based on toggle
    private var accountHeatmapData: [(ticker: String, value: Double, changePercent: Double)] {
        showAllTimeAccountHeatmap ? accountAllTimeHeatmapData : accountDailyHeatmapData
    }

    // Winners and Losers data - sorted by change percent (best performers first)
    // Value here represents the dollar gain/loss for the period, not total position value
    private var winnersLosersData: [(ticker: String, dollarGainLoss: Double, changePercent: Double)] {
        let stocks = viewModel.stocks.filter { $0.isMaritalStatus }
        var data: [(ticker: String, dollarGainLoss: Double, changePercent: Double)] = []

        for stock in stocks {
            if let priceData = viewModel.stockPrices[stock.ticker] {
                let totalShares = stock.lots.isEmpty ? Double(stock.shares) : stock.lots.reduce(0.0) { $0 + $1.shares }
                let currentValue = priceData.currentPrice * totalShares

                let changePercent: Double
                let dollarGainLoss: Double

                if showAllTimeWinnersLosers {
                    // All-time: compare to cost basis
                    let totalCost = stock.lots.isEmpty ? stock.totalCost : stock.lots.reduce(0.0) { $0 + $1.totalCost }
                    changePercent = totalCost > 0 ? ((currentValue - totalCost) / totalCost) * 100 : 0
                    dollarGainLoss = currentValue - totalCost
                } else {
                    // Daily: use API daily change or calculate from previous close
                    if let apiDaily = priceData.apiPeriodChanges["1d"] {
                        changePercent = apiDaily
                    } else if let prevClose = priceData.previousClose, prevClose > 0 {
                        changePercent = ((priceData.currentPrice - prevClose) / prevClose) * 100
                    } else {
                        let startPrice = priceData.dailyStartPrice
                        changePercent = startPrice > 0 ? ((priceData.currentPrice - startPrice) / startPrice) * 100 : 0
                    }
                    // Calculate dollar gain: currentValue - previousValue
                    // previousValue = currentValue / (1 + changePercent/100)
                    let previousValue = changePercent != -100 ? currentValue / (1 + changePercent / 100) : currentValue
                    dollarGainLoss = currentValue - previousValue
                }

                if currentValue > 0 {
                    data.append((stock.ticker, dollarGainLoss, changePercent))
                }
            }
        }

        return data.sorted { $0.changePercent > $1.changePercent }
    }

    // MARK: - Risk Metrics

    /// Helper function for beta scale visualization
    private func betaScaleColor(index: Int, beta: Double) -> Color {
        // Scale: 0=0.5, 1=0.75, 2=1.0, 3=1.25, 4=1.5+
        let thresholds: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5]
        let isActive = beta >= thresholds[index]

        if !isActive {
            return Color.gray.opacity(0.2)
        }

        // Color based on risk level
        if index <= 1 {
            return AppColors.positive.opacity(0.8)
        } else if index == 2 {
            return Color.primary.opacity(0.5)
        } else {
            return AppColors.negative.opacity(0.8)
        }
    }

    /// Helper function for concentration scale visualization
    private func concentrationScaleColor(index: Int, score: Double) -> Color {
        // Scale: 0=500, 1=1000, 2=1500, 3=2000, 4=2500+
        let thresholds: [Double] = [500, 1000, 1500, 2000, 2500]
        let isActive = score >= thresholds[index]

        if !isActive {
            return Color.gray.opacity(0.2)
        }

        // Color based on concentration level (inverted - lower is better)
        if index <= 1 {
            return AppColors.positive.opacity(0.8)
        } else if index == 2 {
            return Color.orange.opacity(0.8)
        } else {
            return AppColors.negative.opacity(0.8)
        }
    }

    /// Weighted Average Beta - measures portfolio volatility relative to market
    /// Beta = 1.0 means portfolio moves with market, >1 = more volatile, <1 = less volatile
    /// Returns nil if no stocks have real beta data - we don't fake 1.0 values
    private var portfolioBetaData: (beta: Double, coverage: Double)? {
        let stocks = viewModel.stocks.filter { $0.isMaritalStatus }
        AppLogger.debug("BETA DEBUG: Checking \(stocks.count) stocks")

        guard viewModel.totalPortfolioValue > 0 else {
            AppLogger.debug("BETA DEBUG: Portfolio value is 0, returning nil")
            return nil
        }

        var weightedBetaSum: Double = 0
        var totalWeightWithBeta: Double = 0
        var stocksWithBeta: [String] = []
        var stocksWithoutBeta: [String] = []

        for stock in stocks {
            if let priceData = viewModel.stockPrices[stock.ticker],
               let beta = priceData.beta {
                stocksWithBeta.append("\(stock.ticker):\(String(format: "%.2f", beta))")
                let totalShares = stock.lots.isEmpty ? Double(stock.shares) : stock.lots.reduce(0.0) { $0 + $1.shares }
                let stockValue = priceData.currentPrice * totalShares
                let weight = stockValue / viewModel.totalPortfolioValue

                weightedBetaSum += beta * weight
                totalWeightWithBeta += weight
            } else {
                stocksWithoutBeta.append(stock.ticker)
            }
        }

        AppLogger.debug("BETA DEBUG: Stocks WITH beta: \(stocksWithBeta)")
        AppLogger.debug("BETA DEBUG: Stocks WITHOUT beta: \(stocksWithoutBeta)")
        AppLogger.debug("BETA DEBUG: Coverage: \(String(format: "%.1f", totalWeightWithBeta * 100))%")

        // Only return beta if we have real data - don't fake 1.0 values
        guard totalWeightWithBeta > 0 else {
            AppLogger.debug("BETA DEBUG: No beta data available from any source, returning nil")
            return nil
        }

        // Calculate weighted average beta based on stocks that have real data
        // Scale up to account for positions without data (divide by coverage)
        let beta = weightedBetaSum / totalWeightWithBeta
        AppLogger.debug("BETA DEBUG: Final beta: \(String(format: "%.2f", beta)), coverage: \(String(format: "%.1f", totalWeightWithBeta * 100))%")
        return (beta, totalWeightWithBeta)
    }

    /// Convenience property for backward compatibility
    private var portfolioBeta: Double? {
        portfolioBetaData?.beta
    }

    /// Concentration Risk (Herfindahl-Hirschman Index) - measures portfolio diversification
    /// Range: 0 to 10000. Lower = more diversified, Higher = more concentrated
    /// <1500 = Diversified, 1500-2500 = Moderate, >2500 = Concentrated
    private var concentrationRisk: (score: Double, level: String, color: Color) {
        let stocks = viewModel.stocks.filter { $0.isMaritalStatus }
        guard viewModel.totalPortfolioValue > 0 else { return (0, "N/A", Color.secondary) }

        var hhi: Double = 0

        for stock in stocks {
            if let priceData = viewModel.stockPrices[stock.ticker] {
                let totalShares = stock.lots.isEmpty ? Double(stock.shares) : stock.lots.reduce(0.0) { $0 + $1.shares }
                let stockValue = priceData.currentPrice * totalShares
                let weight = (stockValue / viewModel.totalPortfolioValue) * 100 // Convert to percentage
                hhi += weight * weight
            }
        }

        // Determine risk level and color
        let level: String
        let color: Color
        if hhi < 1500 {
            level = "Diversified"
            color = AppColors.positive
        } else if hhi < 2500 {
            level = "Moderate"
            color = Color.orange
        } else {
            level = "Concentrated"
            color = AppColors.negative
        }

        return (hhi, level, color)
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        // Spacer for fixed header
                        Spacer()
                            .frame(height: 90)

                        VStack(spacing: 24) {
                            if viewModel.totalPortfolioValue > 0 && !portfolioData.isEmpty {
                            // Pie Chart Section
                            VStack(spacing: 24) {

                                // Pie Chart
                                PieChartView(data: portfolioData, showDollarAmounts: showDollarAmounts)
                                    .frame(height: 300)
                                    .padding(.bottom, 8)

                                // Condensed Legend - 3 columns when showing only percentages, 2 columns when showing dollars
                                let columns = showDollarAmounts ? [
                                    GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)
                                ] : [
                                    GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)
                                ]

                                LazyVGrid(columns: columns, alignment: .center, spacing: 6) {
                                    ForEach(portfolioData, id: \.ticker) { item in
                                        HStack(spacing: 4) {
                                            // Small indicator
                                            Circle()
                                                .fill(item.color)
                                                .frame(width: 5, height: 5)

                                            Text(item.ticker)
                                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                                .foregroundColor(Color.primary)

                                            Text("\(item.percentage, specifier: "%.1f")%")
                                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                                .foregroundColor(item.color)

                                            if showDollarAmounts {
                                                Text("$\(Int(round(item.value)))")
                                                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                                                    .foregroundColor(Color.secondary)
                                            }
                                        }
                                        .padding(.vertical, 3)
                                        .padding(.horizontal, 4)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                            }

                            // Winners vs Losers Section
                            if !winnersLosersData.isEmpty {
                                VStack(spacing: 16) {
                                    HStack {
                                        Text("Winners vs Losers")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(Color.primary)
                                        Spacer()

                                        // Daily / All-Time toggle button
                                        Button {
                                            withAnimation {
                                                showAllTimeWinnersLosers.toggle()
                                            }
                                        } label: {
                                            Image(isDarkMode ? (showAllTimeWinnersLosers ? "alltime.dark" : "daily.dark") : (showAllTimeWinnersLosers ? "alltime" : "daily"))
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(height: 15)
                                        }
                                    }

                                    WinnersLosersBarChart(data: winnersLosersData, showDollarAmounts: showDollarAmounts)
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 24)
                            }

                            // Position Heatmap Section
                            if !heatmapData.isEmpty {
                                VStack(spacing: 16) {
                                    HStack {
                                        Text("Position Heatmap")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(Color.primary)
                                        Spacer()

                                        // Daily / All-Time toggle button
                                        Button {
                                            withAnimation {
                                                showAllTimeHeatmap.toggle()
                                            }
                                        } label: {
                                            Image(isDarkMode ? (showAllTimeHeatmap ? "alltime.dark" : "daily.dark") : (showAllTimeHeatmap ? "alltime" : "daily"))
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(height: 15)
                                        }
                                    }

                                    HeatmapTreemapView(data: heatmapData, showDollarAmounts: showDollarAmounts)
                                        .id(showAllTimeHeatmap ? "alltime" : "daily")
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 24)
                            }

                            // Account Heatmap Section
                            if !accountHeatmapData.isEmpty {
                                VStack(spacing: 16) {
                                    HStack {
                                        Text("Account Heatmap")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(Color.primary)
                                        Spacer()

                                        // Daily / All-Time toggle button
                                        Button {
                                            withAnimation {
                                                showAllTimeAccountHeatmap.toggle()
                                            }
                                        } label: {
                                            Image(isDarkMode ? (showAllTimeAccountHeatmap ? "alltime.dark" : "daily.dark") : (showAllTimeAccountHeatmap ? "alltime" : "daily"))
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(height: 15)
                                        }
                                    }

                                    HeatmapTreemapView(data: accountHeatmapData, showDollarAmounts: showDollarAmounts)
                                        .id(showAllTimeAccountHeatmap ? "account-alltime" : "account-daily")
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 24)
                            }

                            // All Positions Across Accounts Section (Venn Diagram)
                            if !allPositionsData.isEmpty {
                                VStack(spacing: 16) {
                                    HStack {
                                        Text("Positions by Account")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(Color.primary)
                                        Spacer()
                                    }

                                    SharedPositionsView(
                                        sharedData: allPositionsData,
                                        showDollarAmounts: showDollarAmounts,
                                        onAccountTap: { accountName in
                                            // Navigate directly to account detail
                                            if let account = accountSummaries.first(where: { $0.accountName == accountName }) {
                                                navigationPath.append(NavigationDestination.accountDetail(account))
                                            }
                                        }
                                    )
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)
                            }

                            // Risk Metrics Section
                            VStack(spacing: 16) {
                                HStack {
                                    Text("Risk Metrics")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(Color.primary)
                                    Spacer()
                                }

                                HStack(spacing: 12) {
                                    // Portfolio Beta Card
                                    VStack(spacing: 6) {
                                        Text("Portfolio Beta")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(Color.secondary)

                                        if let betaData = portfolioBetaData {
                                            Text(String(format: "%.2f", betaData.beta))
                                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                                .foregroundColor(betaData.beta > 1.2 ? AppColors.negative : (betaData.beta < 0.8 ? AppColors.positive : Color.primary))

                                            // Visual scale indicator
                                            HStack(spacing: 2) {
                                                ForEach(0..<5) { i in
                                                    RoundedRectangle(cornerRadius: 2)
                                                        .fill(betaScaleColor(index: i, beta: betaData.beta))
                                                        .frame(width: 16, height: 4)
                                                }
                                            }
                                            .padding(.top, 2)

                                            // Show risk level and coverage if less than 100%
                                            if betaData.coverage < 0.95 {
                                                Text("\(betaData.beta > 1.2 ? "Higher" : (betaData.beta < 0.8 ? "Lower" : "Market")) (\(Int(betaData.coverage * 100))%)")
                                                    .font(.system(size: 9, weight: .medium))
                                                    .foregroundColor(betaData.beta > 1.2 ? AppColors.negative : (betaData.beta < 0.8 ? AppColors.positive : Color.secondary))
                                                    .padding(.top, 2)
                                            } else {
                                                Text(betaData.beta > 1.2 ? "Higher Risk" : (betaData.beta < 0.8 ? "Lower Risk" : "Market Risk"))
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundColor(betaData.beta > 1.2 ? AppColors.negative : (betaData.beta < 0.8 ? AppColors.positive : Color.secondary))
                                                    .padding(.top, 2)
                                            }
                                        } else if viewModel.isDataReady {
                                            Text("--")
                                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                                .foregroundColor(Color.secondary)

                                            Text("No Data")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundColor(Color.secondary)
                                        } else {
                                            Text("--")
                                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                                .foregroundColor(Color.secondary)

                                            Text("Loading...")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundColor(Color.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 8)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(12)

                                    // Concentration Risk Card
                                    VStack(spacing: 6) {
                                        Text("Concentration")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(Color.secondary)

                                        Text(String(format: "%.0f", concentrationRisk.score))
                                            .font(.system(size: 32, weight: .bold, design: .rounded))
                                            .foregroundColor(concentrationRisk.color)

                                        // Visual scale indicator
                                        HStack(spacing: 2) {
                                            ForEach(0..<5) { i in
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(concentrationScaleColor(index: i, score: concentrationRisk.score))
                                                    .frame(width: 16, height: 4)
                                            }
                                        }
                                        .padding(.top, 2)

                                        Text(concentrationRisk.level)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(concentrationRisk.color)
                                            .padding(.top, 2)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 8)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(12)
                                }

                                // Improved explanation
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .top, spacing: 6) {
                                        Text("β")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(Color.secondary)
                                            .frame(width: 14)
                                        Text("Beta measures systematic risk relative to the S&P 500. A beta of 1.0 moves with the market; <1.0 is defensive (less volatile); >1.0 is aggressive (amplifies market swings). Weighted by position size.")
                                            .font(.system(size: 10, weight: .regular))
                                            .foregroundColor(Color.secondary)
                                    }

                                    HStack(alignment: .top, spacing: 6) {
                                        Text("C")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(Color.secondary)
                                            .frame(width: 14)
                                        Text("Concentration uses the Herfindahl-Hirschman Index (HHI), which sums the squared portfolio weights. Used by regulators to measure market concentration. Range 0-10,000: <1500 diversified, 1500-2500 moderate, >2500 concentrated.")
                                            .font(.system(size: 10, weight: .regular))
                                            .foregroundColor(Color.secondary)
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                        } else {
                            // Empty state
                            VStack(spacing: 16) {
                                Text("No positions to visualize")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(Color.secondary)
                                
                                Text("Add stock positions to see portfolio visualizations")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(Color.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(40)
                        }
                        }
                    }
                }
            }

        }
        .gesture(
            DragGesture()
                .onEnded { gesture in
                    // Swipe right to go to main page (tab 1)
                    if gesture.translation.width > 100 {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedTab = 1
                        }
                    }
                    // Swipe left to go to charts page (tab 3)
                    else if gesture.translation.width < -100 {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedTab = 3
                        }
                    }
                }
        )
    }
}

// Futuristic Radial Bar Donut Chart - Inspired by Sci-Fi Interface
struct PieChartView: View {
    let data: [(ticker: String, value: Double, percentage: Double, color: Color)]
    let showDollarAmounts: Bool
    @State private var animatedProgress: Double = 0
    @State private var rotationAngle: Double = 0
    @Environment(\.colorScheme) private var colorScheme
    private var isDarkMode: Bool { colorScheme == .dark }
    
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let outerRadius = size / 2 - 20
            let innerRadius = outerRadius * 0.5
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            
            ZStack {
                // Dark background circle
                Circle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: outerRadius * 2, height: outerRadius * 2)
                
                // Radial bar segments
                ForEach(Array(data.enumerated()), id: \.element.ticker) { index, item in
                    RadialBarSegment(
                        startAngle: angleForIndex(index, in: data),
                        endAngle: angleForIndex(index + 1, in: data),
                        innerRadius: innerRadius,
                        outerRadius: outerRadius,
                        gap: 0,
                        color: item.color,
                        showGrid: index % 2 == 1 // Alternate grid pattern
                    )
                    .opacity(animatedProgress)
                    .animation(
                        .spring(response: 1.2, dampingFraction: 0.8)
                        .delay(Double(index) * 0.15),
                        value: animatedProgress
                    )
                }
                
                // Outer labels with percentages and dollar values - omit small segments
                ForEach(Array(data.enumerated()), id: \.element.ticker) { index, item in
                    let startAngle = angleForIndex(index, in: data)
                    let endAngle = angleForIndex(index + 1, in: data)
                    let angleRange = endAngle - startAngle
                    let minAngleForLabel: Double = 8.0 // Minimum angle in degrees to show label
                    
                    // Only show label if segment is large enough
                    if abs(angleRange) >= minAngleForLabel {
                        let midAngle = (startAngle + endAngle) / 2
                        let labelRadius = outerRadius + 35
                        let labelX = center.x + cos(midAngle * .pi / 180) * labelRadius
                        let labelY = center.y + sin(midAngle * .pi / 180) * labelRadius
                        
                        VStack(spacing: 2) {
                            Text(item.ticker)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(item.color.opacity(0.8))
                            
                            Text("\(item.percentage, specifier: "%.2f")%")
                                .font(.system(size: 9, weight: .regular, design: .monospaced))
                                .foregroundColor(Color.secondary.opacity(0.7))
                            
                            if showDollarAmounts {
                                Text("$\(Int(round(item.value)))")
                                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                                    .foregroundColor(Color.secondary.opacity(0.6))
                            }
                        }
                        .position(x: labelX, y: labelY)
                        .opacity(animatedProgress)
                    }
                }
                
                // White center circle
                ZStack {
                    // White inner circle (adaptive for dark mode)
                    Circle()
                        .fill(isDarkMode ? Color(UIColor.systemBackground) : Color.white)
                        .frame(width: innerRadius * 2, height: innerRadius * 2)
                    
                    // Center content
                    VStack(spacing: 2) {
                        if showDollarAmounts {
                            if !data.isEmpty {
                                let totalValue = data.reduce(0) { $0 + $1.value }
                                Text(totalValue, format: .currency(code: "USD"))
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(Color.primary)
                                    .frame(maxWidth: innerRadius * 1.8)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.4)
                            }

                            Text("Total")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(Color.secondary)
                        }
                    }
                }
                
                // Outer ring with faint lines
                Circle()
                    .stroke(
                        Color.gray.opacity(0.2),
                        lineWidth: 0.5
                    )
                    .frame(width: outerRadius * 2 + 2, height: outerRadius * 2 + 2)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onAppear {
                withAnimation(.easeOut(duration: 1.5)) {
                    animatedProgress = 1.0
                }
                
                // Very slow rotation
                withAnimation(.linear(duration: 180).repeatForever(autoreverses: false)) {
                    rotationAngle = 360
                }
            }
        }
    }
    
    private func angleForIndex(_ index: Int, in data: [(ticker: String, value: Double, percentage: Double, color: Color)]) -> Double {
        let total = data.reduce(0) { $0 + $1.value }
        guard total > 0 else { return 0 }
        
        var cumulative: Double = 0
        for i in 0..<index {
            cumulative += data[i].value
        }
        
        return (cumulative / total) * 360 - 90 // Start at top (-90 degrees)
    }
}

struct DonutSlice: Shape {
    let startAngle: Double
    let endAngle: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let gap: CGFloat
    
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let adjustedStartAngle = startAngle + (gap / 2)
        let adjustedEndAngle = endAngle - (gap / 2)
        
        var path = Path()
        
        // Convert angles to radians for calculations
        let endRad = adjustedEndAngle * .pi / 180
        
        // Outer arc
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .degrees(adjustedStartAngle),
            endAngle: .degrees(adjustedEndAngle),
            clockwise: false
        )
        
        // Line to inner arc (at end angle)
        let innerEndX = center.x + innerRadius * cos(endRad)
        let innerEndY = center.y + innerRadius * sin(endRad)
        path.addLine(to: CGPoint(x: innerEndX, y: innerEndY))
        
        // Inner arc (reverse direction)
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .degrees(adjustedEndAngle),
            endAngle: .degrees(adjustedStartAngle),
            clockwise: true
        )
        
        path.closeSubpath()
        
        return path
    }
}

// Grid Pattern View - Creates dot grid pattern
struct GridPatternView: View {
    let startAngle: Double
    let endAngle: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let color: Color
    
    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            
            // Create grid of dots
            let gridSpacing: CGFloat = 8
            let radialSteps = Int((outerRadius - innerRadius) / gridSpacing)
            let angularSteps = Int((endAngle - startAngle) / 5)
            
            ZStack {
                ForEach(0..<radialSteps, id: \.self) { r in
                    ForEach(0..<angularSteps, id: \.self) { a in
                        let radius = innerRadius + CGFloat(r) * gridSpacing
                        let angle = startAngle + Double(a) * ((endAngle - startAngle) / Double(angularSteps))
                        let angleRad = angle * .pi / 180
                        
                        Circle()
                            .fill(color)
                            .frame(width: 2, height: 2)
                            .position(
                                x: center.x + radius * cos(angleRad),
                                y: center.y + radius * sin(angleRad)
                            )
                    }
                }
            }
            .clipShape(
                DonutSlice(
                    startAngle: startAngle,
                    endAngle: endAngle,
                    innerRadius: innerRadius,
                    outerRadius: outerRadius,
                    gap: 0
                )
            )
        }
    }
}

// Radial Bar Segment - Creates sunburst effect with thin radial bars
struct RadialBarSegment: View {
    let startAngle: Double
    let endAngle: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let gap: CGFloat
    let color: Color
    let showGrid: Bool
    
    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let adjustedStartAngle = startAngle + (gap / 2)
            let adjustedEndAngle = endAngle - (gap / 2)
            let angleRange = adjustedEndAngle - adjustedStartAngle
            let numberOfBars = Int(angleRange / 2) // One bar every 2 degrees
            
            ZStack {
                // Base slice with gradient
                DonutSlice(
                    startAngle: startAngle,
                    endAngle: endAngle,
                    innerRadius: innerRadius,
                    outerRadius: outerRadius,
                    gap: gap
                )
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            color.opacity(0.9),
                            color.opacity(0.7),
                            color.opacity(0.5),
                            color.opacity(0.7),
                            color.opacity(0.9)
                        ]),
                        startPoint: UnitPoint(
                            x: 0.5 + 0.5 * cos((adjustedStartAngle + angleRange / 2) * .pi / 180),
                            y: 0.5 + 0.5 * sin((adjustedStartAngle + angleRange / 2) * .pi / 180)
                        ),
                        endPoint: UnitPoint(
                            x: 0.5 - 0.5 * cos((adjustedStartAngle + angleRange / 2) * .pi / 180),
                            y: 0.5 - 0.5 * sin((adjustedStartAngle + angleRange / 2) * .pi / 180)
                        )
                    )
                )
                .shadow(color: color.opacity(0.6), radius: 8, x: 0, y: 0)
                
                // Radial bars overlay
                ForEach(0..<numberOfBars, id: \.self) { barIndex in
                    let barAngle = adjustedStartAngle + Double(barIndex) * (angleRange / Double(numberOfBars))
                    let barRad = barAngle * .pi / 180
                    
                    Path { path in
                        let startX = center.x + innerRadius * cos(barRad)
                        let startY = center.y + innerRadius * sin(barRad)
                        let endX = center.x + outerRadius * cos(barRad)
                        let endY = center.y + outerRadius * sin(barRad)
                        
                        path.move(to: CGPoint(x: startX, y: startY))
                        path.addLine(to: CGPoint(x: endX, y: endY))
                    }
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                color.opacity(0.8),
                                color.opacity(0.4),
                                color.opacity(0.8)
                            ]),
                            startPoint: .init(x: 0, y: 0),
                            endPoint: .init(x: 1, y: 1)
                        ),
                        lineWidth: 1.5
                    )
                }
                
                // Grid pattern overlay (for alternating segments)
                if showGrid {
                    GridPatternView(
                        startAngle: startAngle,
                        endAngle: endAngle,
                        innerRadius: innerRadius,
                        outerRadius: outerRadius,
                        color: color.opacity(0.2)
                    )
                }
            }
        }
    }
}

// Shared Positions Visualization - Euler Diagram Style
struct SharedPositionsView: View {
    let sharedData: [(ticker: String, accounts: [String], totalValue: Double, accountValues: [String: Double], color: Color)]
    let showDollarAmounts: Bool
    var onAccountTap: ((String) -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    private var isDarkMode: Bool { colorScheme == .dark }

    // Get all unique accounts
    private var allAccounts: [String] {
        let accountSet = Set(sharedData.flatMap { $0.accounts })
        return Array(accountSet).sorted()
    }

    // Calculate total value per account (sum of actual per-account values)
    private var totalAccountValues: [String: Double] {
        var values: [String: Double] = [:]
        for item in sharedData {
            for (account, value) in item.accountValues {
                values[account, default: 0] += value
            }
        }
        return values
    }

    var body: some View {
        if !allAccounts.isEmpty {
            TreemapView(
                accounts: allAccounts,
                sharedData: sharedData,
                accountValues: totalAccountValues,
                showDollarAmounts: showDollarAmounts,
                onAccountTap: onAccountTap
            )
        } else {
            Text("No positions to display")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(Color.secondary)
                .padding()
        }
    }
}

// MARK: - Winners vs Losers Bar Chart

struct WinnersLosersBarChart: View {
    let data: [(ticker: String, dollarGainLoss: Double, changePercent: Double)]
    let showDollarAmounts: Bool
    @Environment(\.colorScheme) private var colorScheme
    private var isDarkMode: Bool { colorScheme == .dark }

    // Find the maximum absolute change for scaling
    private var maxAbsChange: Double {
        let maxChange = data.map { abs($0.changePercent) }.max() ?? 1
        return max(maxChange, 0.1) // Prevent division by zero
    }

    // Fixed column widths for consistent alignment
    private let tickerLabelWidth: CGFloat = 50
    private let dollarLabelWidth: CGFloat = 70
    private let percentLabelWidth: CGFloat = 80

    var body: some View {
        VStack(spacing: 8) {
            ForEach(data, id: \.ticker) { item in
                GeometryReader { geometry in
                    let totalWidth = geometry.size.width
                    let centerY = geometry.size.height / 2
                    let dollarAmount = Int(round(abs(item.dollarGainLoss)))
                    let formattedDollar = NumberFormatter.localizedString(from: NSNumber(value: dollarAmount), number: .decimal)
                    let dollarText = "\(item.dollarGainLoss >= 0 ? "+" : "-")$\(formattedDollar)"

                    let percentFormatter: NumberFormatter = {
                        let formatter = NumberFormatter()
                        formatter.numberStyle = .decimal
                        formatter.minimumFractionDigits = 2
                        formatter.maximumFractionDigits = 2
                        return formatter
                    }()
                    let formattedPercent = percentFormatter.string(from: NSNumber(value: abs(item.changePercent))) ?? String(format: "%.2f", abs(item.changePercent))

                    // Calculate with true screen center for zero line
                    let centerX = totalWidth / 2
                    let leftSpace = centerX - tickerLabelWidth - 8
                    let rightSpace = centerX - percentLabelWidth - 4
                    let maxBarLength = min(leftSpace, rightSpace) - 4
                    let normalizedChange = item.changePercent / maxAbsChange
                    let barLength = abs(normalizedChange) * maxBarLength

                    ZStack {
                        // Ticker label - positioned on left
                        Text(item.ticker)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color.primary)
                            .frame(width: tickerLabelWidth, alignment: .leading)
                            .position(x: tickerLabelWidth / 2, y: centerY)

                        // Bar - positioned from center
                        RoundedRectangle(cornerRadius: 3)
                            .fill(item.changePercent >= 0 ? AppColors.positive : AppColors.negative)
                            .frame(width: max(barLength, 2), height: 14)
                            .position(
                                x: item.changePercent >= 0 ? centerX + barLength / 2 : centerX - barLength / 2,
                                y: centerY
                            )

                        // Dollar amount - positioned near center line
                        if showDollarAmounts {
                            Text(dollarText)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(AppColors.forValue(item.dollarGainLoss))
                                .frame(width: dollarLabelWidth, alignment: item.changePercent >= 0 ? .trailing : .leading)
                                .position(
                                    x: item.changePercent >= 0
                                        ? centerX - dollarLabelWidth / 2 - 4
                                        : centerX + dollarLabelWidth / 2 + 4,
                                    y: centerY
                                )
                        }

                        // Percent label - positioned on right
                        Text("\(item.changePercent >= 0 ? "+" : "-")\(formattedPercent)%")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(AppColors.forValue(item.changePercent))
                            .frame(width: percentLabelWidth, alignment: .trailing)
                            .position(x: totalWidth - percentLabelWidth / 2, y: centerY)
                    }
                }
                .frame(height: 22)
            }
        }
        .padding(.vertical, 8)
    }
}
