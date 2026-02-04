import SwiftUI

struct WaterfallChartView: View {
    @ObservedObject var viewModel: StockViewModel
    let showDollarAmounts: Bool

    @State private var animatedProgress: Double = 0
    @State private var selectedPosition: String? = nil
    @Environment(\.colorScheme) private var colorScheme
    private var isDarkMode: Bool { colorScheme == .dark }

    // Colors
    private var costBasisColor: Color { Color.gray }
    private var gainColor: Color { Color(red: 0.2, green: 0.7, blue: 0.3) }
    private var lossColor: Color { Color(red: 0.9, green: 0.3, blue: 0.3) }
    private var currentValueColor: Color { Color(red: 0.0, green: 0.48, blue: 1.0) }

    // Position data for waterfall
    private var positionGainsLosses: [(ticker: String, gainLoss: Double, costBasis: Double, currentValue: Double, color: Color)] {
        var positions: [(ticker: String, gainLoss: Double, costBasis: Double, currentValue: Double, color: Color)] = []

        for stock in viewModel.stocks where stock.isMaritalStatus {
            guard let priceData = viewModel.stockPrices[stock.ticker] else { continue }

            let totalShares = stock.lots.isEmpty ? Double(stock.shares) : stock.lots.reduce(0.0) { $0 + $1.shares }
            let stockCostBasis = stock.lots.isEmpty ? stock.totalCost : stock.lots.reduce(0.0) { $0 + $1.totalCost }
            let stockCurrentValue = priceData.currentPrice * totalShares
            let gainLoss = stockCurrentValue - stockCostBasis

            positions.append((
                ticker: stock.ticker,
                gainLoss: gainLoss,
                costBasis: stockCostBasis,
                currentValue: stockCurrentValue,
                color: colorForTicker(stock.ticker)
            ))
        }

        // Sort by gain/loss: gains first (descending), then losses (descending by magnitude)
        return positions.sorted { pos1, pos2 in
            if pos1.gainLoss >= 0 && pos2.gainLoss < 0 {
                return true // gains before losses
            } else if pos1.gainLoss < 0 && pos2.gainLoss >= 0 {
                return false // losses after gains
            } else if pos1.gainLoss >= 0 {
                return pos1.gainLoss > pos2.gainLoss // bigger gains first
            } else {
                return pos1.gainLoss < pos2.gainLoss // bigger losses first (more negative)
            }
        }
    }

    private var totalCostBasis: Double { viewModel.totalCostBasis }
    private var totalCurrentValue: Double { viewModel.totalPortfolioValue }
    private var totalGainLoss: Double { viewModel.totalUnrealizedGainLoss }
    private var dailyGainLoss: Double { viewModel.totalDailyGainLoss }
    private var dailyGainLossPercent: Double { viewModel.totalDailyGainLossPercent }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Position Gains & Losses")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.primary)
                Spacer()
            }

            if totalCostBasis > 0 && !positionGainsLosses.isEmpty {
                // Bridge Waterfall Chart
                VStack(spacing: 12) {
                    // Chart area
                    GeometryReader { geometry in
                        let chartWidth = geometry.size.width
                        let chartHeight = geometry.size.height - 20

                        // Calculate the range for the chart
                        let maxValue = max(totalCostBasis, totalCurrentValue) * 1.1

                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.05))

                            // Waterfall bars
                            WaterfallBridgeView(
                                positions: positionGainsLosses,
                                totalCostBasis: totalCostBasis,
                                totalCurrentValue: totalCurrentValue,
                                maxValue: maxValue,
                                chartWidth: chartWidth,
                                chartHeight: chartHeight,
                                animatedProgress: animatedProgress,
                                showDollarAmounts: showDollarAmounts,
                                selectedPosition: $selectedPosition,
                                gainColor: gainColor,
                                lossColor: lossColor,
                                costBasisColor: costBasisColor,
                                currentValueColor: currentValueColor
                            )
                        }
                    }
                    .frame(height: 180)

                    // Position breakdown list
                    VStack(spacing: 6) {
                        ForEach(positionGainsLosses.prefix(8), id: \.ticker) { position in
                            PositionGainLossRow(
                                ticker: position.ticker,
                                gainLoss: position.gainLoss,
                                costBasis: position.costBasis,
                                currentValue: position.currentValue,
                                totalGainLoss: totalGainLoss,
                                color: position.color,
                                isSelected: selectedPosition == position.ticker,
                                showDollarAmounts: showDollarAmounts,
                                animatedProgress: animatedProgress,
                                gainColor: gainColor,
                                lossColor: lossColor
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    if selectedPosition == position.ticker {
                                        selectedPosition = nil
                                    } else {
                                        selectedPosition = position.ticker
                                    }
                                }
                            }
                        }

                        // Show "and X more" if there are more positions
                        if positionGainsLosses.count > 8 {
                            let remainingCount = positionGainsLosses.count - 8
                            let remainingGainLoss = positionGainsLosses.dropFirst(8).reduce(0) { $0 + $1.gainLoss }
                            Text("and \(remainingCount) more (\(formatDollar(remainingGainLoss, showSign: true)))")
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundColor(Color.secondary)
                                .padding(.top, 4)
                        }
                    }

                    // Summary Row
                    Divider()
                        .background(Color.gray.opacity(0.3))

                    HStack(spacing: 16) {
                        // Total Gain/Loss
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total Gain/Loss")
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundColor(Color.secondary)

                            HStack(spacing: 4) {
                                Text(formatDollar(totalGainLoss, showSign: true))
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundColor(totalGainLoss >= 0 ? gainColor : lossColor)

                                Text("(\(formatPercent(totalGainLoss / totalCostBasis * 100)))")
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundColor(totalGainLoss >= 0 ? gainColor.opacity(0.8) : lossColor.opacity(0.8))
                            }
                        }

                        Spacer()

                        // Daily Change
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Today's Change")
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundColor(Color.secondary)

                            HStack(spacing: 4) {
                                Text(formatDollar(dailyGainLoss, showSign: true))
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundColor(dailyGainLoss >= 0 ? gainColor : lossColor)

                                Text("(\(formatPercent(dailyGainLossPercent)))")
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundColor(dailyGainLoss >= 0 ? gainColor.opacity(0.8) : lossColor.opacity(0.8))
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.08))
                    )
                }
            } else {
                Text("No position data available")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color.secondary)
                    .padding()
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) {
                animatedProgress = 1.0
            }
        }
    }

    private func formatDollar(_ value: Double, showSign: Bool = false) -> String {
        let absValue = abs(value)
        let formatted: String
        if absValue >= 1_000_000 {
            formatted = String(format: "$%.1fM", absValue / 1_000_000)
        } else if absValue >= 1_000 {
            formatted = String(format: "$%.1fK", absValue / 1_000)
        } else {
            formatted = String(format: "$%.0f", absValue)
        }

        if showSign {
            return value >= 0 ? "+\(formatted)" : "-\(formatted.dropFirst())"
        }
        return formatted
    }

    private func formatPercent(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value))%"
    }
}

// Bridge waterfall visualization
struct WaterfallBridgeView: View {
    let positions: [(ticker: String, gainLoss: Double, costBasis: Double, currentValue: Double, color: Color)]
    let totalCostBasis: Double
    let totalCurrentValue: Double
    let maxValue: Double
    let chartWidth: CGFloat
    let chartHeight: CGFloat
    let animatedProgress: Double
    let showDollarAmounts: Bool
    @Binding var selectedPosition: String?
    let gainColor: Color
    let lossColor: Color
    let costBasisColor: Color
    let currentValueColor: Color

    var body: some View {
        let barWidth: CGFloat = 50
        let middleWidth = chartWidth - barWidth * 2 - 40

        HStack(alignment: .bottom, spacing: 0) {
            // Cost Basis Bar (left)
            VStack(spacing: 2) {
                if showDollarAmounts {
                    Text(formatCompact(totalCostBasis))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(costBasisColor)
                }

                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [costBasisColor, costBasisColor.opacity(0.6)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: barWidth, height: barHeight(for: totalCostBasis))
                }

                Text("Cost")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.secondary)
            }
            .frame(width: barWidth + 10)

            // Middle section with stacked gains/losses
            VStack(spacing: 0) {
                // Stacked waterfall segments
                GeometryReader { geometry in
                    let segmentHeight = chartHeight - 30

                    ZStack(alignment: .bottom) {
                        // Base line at cost basis level
                        let costBasisY = segmentHeight * (1 - CGFloat(totalCostBasis / maxValue))

                        // Dashed connector line
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: costBasisY))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: costBasisY))
                        }
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundColor(Color.gray.opacity(0.3))

                        // Stacked gain/loss segments
                        StackedSegmentsView(
                            positions: positions,
                            totalCostBasis: totalCostBasis,
                            maxValue: maxValue,
                            segmentHeight: segmentHeight,
                            segmentWidth: geometry.size.width,
                            animatedProgress: animatedProgress,
                            selectedPosition: $selectedPosition,
                            gainColor: gainColor,
                            lossColor: lossColor
                        )
                    }
                }
                .frame(height: chartHeight - 30)

                Text("Gains/Losses")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.secondary)
                    .frame(height: 20)
            }
            .frame(width: middleWidth)
            .padding(.horizontal, 10)

            // Current Value Bar (right)
            VStack(spacing: 2) {
                if showDollarAmounts {
                    Text(formatCompact(totalCurrentValue))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(currentValueColor)
                }

                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [currentValueColor, currentValueColor.opacity(0.6)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: barWidth, height: barHeight(for: totalCurrentValue))
                }

                Text("Value")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.secondary)
            }
            .frame(width: barWidth + 10)
        }
        .padding(.horizontal, 10)
    }

    private func barHeight(for value: Double) -> CGFloat {
        guard maxValue > 0 else { return 0 }
        return (chartHeight - 30) * CGFloat(value / maxValue) * CGFloat(animatedProgress)
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

// Stacked segments showing individual position gains/losses
struct StackedSegmentsView: View {
    let positions: [(ticker: String, gainLoss: Double, costBasis: Double, currentValue: Double, color: Color)]
    let totalCostBasis: Double
    let maxValue: Double
    let segmentHeight: CGFloat
    let segmentWidth: CGFloat
    let animatedProgress: Double
    @Binding var selectedPosition: String?
    let gainColor: Color
    let lossColor: Color

    var body: some View {
        let costBasisY = segmentHeight * (1 - CGFloat(totalCostBasis / maxValue))

        // Separate gains and losses
        let gains = positions.filter { $0.gainLoss > 0 }
        let losses = positions.filter { $0.gainLoss < 0 }

        ZStack(alignment: .bottom) {
            // Draw gains stacking upward from cost basis line
            ForEach(Array(gains.enumerated()), id: \.element.ticker) { index, position in
                let previousGains = gains.prefix(index).reduce(0.0) { $0 + $1.gainLoss }
                let segHeight = segmentHeight * CGFloat(position.gainLoss / maxValue) * CGFloat(animatedProgress)
                let yPosition = costBasisY - segmentHeight * CGFloat(previousGains / maxValue) * CGFloat(animatedProgress) - segHeight

                SegmentBar(
                    ticker: position.ticker,
                    value: position.gainLoss,
                    width: segmentWidth * 0.8,
                    height: segHeight,
                    yOffset: yPosition,
                    color: position.color,
                    isGain: true,
                    isSelected: selectedPosition == position.ticker,
                    animatedProgress: animatedProgress,
                    gainColor: gainColor
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedPosition = selectedPosition == position.ticker ? nil : position.ticker
                    }
                }
            }

            // Draw losses stacking downward from cost basis line
            ForEach(Array(losses.enumerated()), id: \.element.ticker) { index, position in
                let segHeight = segmentHeight * CGFloat(abs(position.gainLoss) / maxValue) * CGFloat(animatedProgress)
                let previousLosses = losses.prefix(index).reduce(0.0) { $0 + abs($1.gainLoss) }
                let yOffset = costBasisY + segmentHeight * CGFloat(previousLosses / maxValue) * CGFloat(animatedProgress)

                SegmentBar(
                    ticker: position.ticker,
                    value: position.gainLoss,
                    width: segmentWidth * 0.8,
                    height: segHeight,
                    yOffset: yOffset,
                    color: position.color,
                    isGain: false,
                    isSelected: selectedPosition == position.ticker,
                    animatedProgress: animatedProgress,
                    gainColor: lossColor
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedPosition = selectedPosition == position.ticker ? nil : position.ticker
                    }
                }
            }
        }
        .frame(width: segmentWidth, height: segmentHeight)
    }
}

// Individual segment bar
struct SegmentBar: View {
    let ticker: String
    let value: Double
    let width: CGFloat
    let height: CGFloat
    let yOffset: CGFloat
    let color: Color
    let isGain: Bool
    let isSelected: Bool
    let animatedProgress: Double
    let gainColor: Color

    var body: some View {
        VStack(spacing: 0) {
            // Ticker label for selected or large segments
            if isSelected || height > 20 {
                Text(ticker)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(isSelected ? color : Color.white)
                    .opacity(animatedProgress)
            }

            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            color.opacity(isSelected ? 1.0 : 0.85),
                            color.opacity(isSelected ? 0.8 : 0.6)
                        ]),
                        startPoint: isGain ? .bottom : .top,
                        endPoint: isGain ? .top : .bottom
                    )
                )
                .frame(width: isSelected ? width + 8 : width, height: max(2, height))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isSelected ? color : Color.clear, lineWidth: 2)
                )
                .shadow(color: isSelected ? color.opacity(0.5) : Color.clear, radius: 4, x: 0, y: 0)
        }
        .position(x: width / 2 + (width * 0.1), y: yOffset + height / 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// Position gain/loss row in the list
struct PositionGainLossRow: View {
    let ticker: String
    let gainLoss: Double
    let costBasis: Double
    let currentValue: Double
    let totalGainLoss: Double
    let color: Color
    let isSelected: Bool
    let showDollarAmounts: Bool
    let animatedProgress: Double
    let gainColor: Color
    let lossColor: Color

    private var isGain: Bool { gainLoss >= 0 }
    private var percentOfTotal: Double {
        guard totalGainLoss != 0 else { return 0 }
        return (gainLoss / abs(totalGainLoss)) * 100
    }
    private var percentReturn: Double {
        guard costBasis > 0 else { return 0 }
        return (gainLoss / costBasis) * 100
    }

    var body: some View {
        HStack(spacing: 8) {
            // Color indicator
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            // Ticker
            Text(ticker)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .monospaced))
                .foregroundColor(isSelected ? color : Color.primary)
                .frame(width: 50, alignment: .leading)

            // Progress bar showing contribution
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 6)

                    // Fill - width based on absolute contribution
                    let maxContribution = abs(percentOfTotal)
                    let barWidth = min(geometry.size.width, geometry.size.width * CGFloat(maxContribution / 100) * CGFloat(animatedProgress))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    isGain ? gainColor : lossColor,
                                    (isGain ? gainColor : lossColor).opacity(0.6)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, barWidth), height: 6)
                }
            }
            .frame(height: 6)

            // Gain/Loss amount
            Text(formatDollar(gainLoss, showSign: true))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(isGain ? gainColor : lossColor)
                .frame(width: 65, alignment: .trailing)

            // Percent return
            Text("(\(formatPercent(percentReturn)))")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundColor((isGain ? gainColor : lossColor).opacity(0.8))
                .frame(width: 55, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? color.opacity(0.1) : Color.clear)
        )
    }

    private func formatDollar(_ value: Double, showSign: Bool = false) -> String {
        let absValue = abs(value)
        let formatted: String
        if absValue >= 1_000_000 {
            formatted = String(format: "$%.1fM", absValue / 1_000_000)
        } else if absValue >= 1_000 {
            formatted = String(format: "$%.1fK", absValue / 1_000)
        } else {
            formatted = String(format: "$%.0f", absValue)
        }

        if showSign {
            return value >= 0 ? "+\(formatted)" : "-\(formatted.dropFirst())"
        }
        return formatted
    }

    private func formatPercent(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", value))%"
    }
}
