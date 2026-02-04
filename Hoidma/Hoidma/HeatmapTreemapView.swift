import SwiftUI

// MARK: - Heatmap Treemap Visualization
/// A treemap that shows stock positions sized by value and colored by daily performance

struct HeatmapTreemapView: View {
    let data: [(ticker: String, value: Double, changePercent: Double)]
    let showDollarAmounts: Bool

    /// Color based on performance percentage using a diverging scale centered at 0
    /// Scale: ≤-3% (vibrant red) to 0% (white) to ≥+3% (vibrant green)
    private func colorForChange(_ changePercent: Double) -> Color {
        // Clamp intensity to ±3% range
        let intensity = min(abs(changePercent) / 3.0, 1.0)

        if abs(changePercent) < 0.01 {
            // Very close to 0% - neutral white/light gray
            return Color(red: 0.96, green: 0.96, blue: 0.96)
        } else if changePercent > 0 {
            // Positive: white to vibrant green gradient
            // At 0%: white (0.96, 0.96, 0.96)
            // At +3%: vibrant green (0.10, 0.72, 0.25)
            return Color(
                red: 0.96 - (0.86 * intensity),
                green: 0.96 - (0.24 * intensity),
                blue: 0.96 - (0.71 * intensity)
            )
        } else {
            // Negative: white to vibrant red gradient
            // At 0%: white (0.96, 0.96, 0.96)
            // At -3%: vibrant red (0.92, 0.15, 0.15)
            return Color(
                red: 0.96 - (0.04 * intensity),
                green: 0.96 - (0.81 * intensity),
                blue: 0.96 - (0.81 * intensity)
            )
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let sortedData = data.sorted { $0.value > $1.value }
            let totalValue = sortedData.reduce(0) { $0 + $1.value }

            if totalValue > 0 {
                TreemapLayout(
                    items: sortedData,
                    totalValue: totalValue,
                    rect: CGRect(x: 0, y: 0, width: geometry.size.width, height: geometry.size.height),
                    colorForChange: colorForChange,
                    showDollarAmounts: showDollarAmounts
                )
            }
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Treemap Layout using Squarified Algorithm

struct TreemapLayout: View {
    let items: [(ticker: String, value: Double, changePercent: Double)]
    let totalValue: Double
    let rect: CGRect
    let colorForChange: (Double) -> Color
    let showDollarAmounts: Bool

    var body: some View {
        let rects = calculateTreemapRects(items: items, totalValue: totalValue, rect: rect)

        ZStack(alignment: .topLeading) {
            ForEach(Array(rects.enumerated()), id: \.offset) { index, item in
                TreemapCell(
                    ticker: item.ticker,
                    value: item.value,
                    changePercent: item.changePercent,
                    rect: item.rect,
                    color: colorForChange(item.changePercent),
                    showDollarAmounts: showDollarAmounts
                )
            }
        }
    }

    /// Squarified treemap algorithm
    private func calculateTreemapRects(
        items: [(ticker: String, value: Double, changePercent: Double)],
        totalValue: Double,
        rect: CGRect
    ) -> [(ticker: String, value: Double, changePercent: Double, rect: CGRect)] {
        guard !items.isEmpty, totalValue > 0 else { return [] }

        var result: [(ticker: String, value: Double, changePercent: Double, rect: CGRect)] = []
        var remainingItems = items
        var currentRect = rect

        while !remainingItems.isEmpty {
            let remainingValue = remainingItems.reduce(0) { $0 + $1.value }

            // Decide layout direction based on aspect ratio
            let isHorizontal = currentRect.width >= currentRect.height

            // Find optimal row
            var row: [(ticker: String, value: Double, changePercent: Double)] = []
            var rowValue: Double = 0
            var bestAspectRatio: Double = .infinity

            for item in remainingItems {
                let testRow = row + [item]
                let testRowValue = rowValue + item.value
                let testAspectRatio = worstAspectRatio(
                    row: testRow,
                    rowValue: testRowValue,
                    totalValue: remainingValue,
                    rect: currentRect,
                    isHorizontal: isHorizontal
                )

                if testAspectRatio <= bestAspectRatio {
                    row = testRow
                    rowValue = testRowValue
                    bestAspectRatio = testAspectRatio
                } else {
                    break
                }
            }

            // Layout the row
            let rowFraction = rowValue / remainingValue
            let rowSize = isHorizontal
                ? currentRect.width * rowFraction
                : currentRect.height * rowFraction

            var offset: CGFloat = 0
            for item in row {
                let itemFraction = item.value / rowValue
                let itemSize = isHorizontal
                    ? currentRect.height * itemFraction
                    : currentRect.width * itemFraction

                let itemRect: CGRect
                if isHorizontal {
                    itemRect = CGRect(
                        x: currentRect.minX,
                        y: currentRect.minY + offset,
                        width: rowSize,
                        height: itemSize
                    )
                    offset += itemSize
                } else {
                    itemRect = CGRect(
                        x: currentRect.minX + offset,
                        y: currentRect.minY,
                        width: itemSize,
                        height: rowSize
                    )
                    offset += itemSize
                }

                result.append((ticker: item.ticker, value: item.value, changePercent: item.changePercent, rect: itemRect))
            }

            // Update remaining rect
            if isHorizontal {
                currentRect = CGRect(
                    x: currentRect.minX + rowSize,
                    y: currentRect.minY,
                    width: currentRect.width - rowSize,
                    height: currentRect.height
                )
            } else {
                currentRect = CGRect(
                    x: currentRect.minX,
                    y: currentRect.minY + rowSize,
                    width: currentRect.width,
                    height: currentRect.height - rowSize
                )
            }

            // Remove processed items
            remainingItems.removeFirst(row.count)
        }

        return result
    }

    private func worstAspectRatio(
        row: [(ticker: String, value: Double, changePercent: Double)],
        rowValue: Double,
        totalValue: Double,
        rect: CGRect,
        isHorizontal: Bool
    ) -> Double {
        guard !row.isEmpty, rowValue > 0, totalValue > 0 else { return .infinity }

        let rowFraction = rowValue / totalValue
        let rowSize = isHorizontal
            ? rect.width * rowFraction
            : rect.height * rowFraction

        let otherDimension = isHorizontal ? rect.height : rect.width

        var worstRatio: Double = 0
        for item in row {
            let itemFraction = item.value / rowValue
            let itemSize = otherDimension * itemFraction

            let width = isHorizontal ? rowSize : itemSize
            let height = isHorizontal ? itemSize : rowSize

            guard width > 0, height > 0 else { continue }

            let ratio = max(width / height, height / width)
            worstRatio = max(worstRatio, ratio)
        }

        return worstRatio
    }
}

// MARK: - Individual Treemap Cell

struct TreemapCell: View {
    let ticker: String
    let value: Double
    let changePercent: Double
    let rect: CGRect
    let color: Color
    let showDollarAmounts: Bool

    /// Text color based on background intensity - dark text for light backgrounds, white for dark
    private var textColor: Color {
        // For changes less than ~1.5%, use dark text since background is light
        if abs(changePercent) < 1.5 {
            return Color(red: 0.2, green: 0.2, blue: 0.2)
        } else {
            return .white
        }
    }

    private var secondaryTextColor: Color {
        if abs(changePercent) < 1.5 {
            return Color(red: 0.3, green: 0.3, blue: 0.3)
        } else {
            return .white.opacity(0.9)
        }
    }

    // Gap between cells
    private let cellGap: CGFloat = 2

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)

            // Only show text if cell is large enough
            if rect.width > 35 && rect.height > 30 {
                VStack(spacing: 1) {
                    Text(ticker)
                        .font(.system(size: fontSize, weight: .bold, design: .default))
                        .foregroundColor(textColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    Text(percentageString)
                        .font(.system(size: max(fontSize * 0.7, 8), weight: .medium))
                        .foregroundColor(secondaryTextColor)
                        .lineLimit(1)

                    if showDollarAmounts {
                        Text(dollarString)
                            .font(.system(size: max(fontSize * 0.65, 7), weight: .medium))
                            .foregroundColor(secondaryTextColor)
                            .lineLimit(1)
                    }
                }
                .padding(4)
            } else if rect.width > 20 && rect.height > 20 {
                // Just show ticker for smaller cells
                Text(ticker)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(textColor)
                    .lineLimit(1)
            }
        }
        .frame(width: max(rect.width - cellGap, 0), height: max(rect.height - cellGap, 0))
        .position(x: rect.midX, y: rect.midY)
    }

    private var fontSize: CGFloat {
        let minDimension = min(rect.width, rect.height)
        if minDimension > 100 {
            return 16
        } else if minDimension > 70 {
            return 14
        } else if minDimension > 50 {
            return 12
        } else {
            return 10
        }
    }

    private var percentageString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let formattedPercent = formatter.string(from: NSNumber(value: abs(changePercent))) ?? String(format: "%.2f", abs(changePercent))
        let sign = changePercent >= 0 ? "+" : "-"
        return "\(sign)\(formattedPercent)%"
    }

    private var dollarString: String {
        // Calculate dollar gain/loss from percentage and value
        // value is current position value, changePercent is the gain/loss %
        // dollarChange = value * (changePercent / (100 + changePercent))
        // This calculates the actual dollar change from the current value and percent change
        let dollarChange = value * (changePercent / (100 + changePercent))
        let sign = dollarChange >= 0 ? "+" : "-"
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let formattedNumber = formatter.string(from: NSNumber(value: abs(dollarChange))) ?? "\(Int(abs(dollarChange)))"
        return "\(sign)$\(formattedNumber)"
    }
}

// MARK: - Preview

#Preview("Heatmap Treemap") {
    let mockData: [(ticker: String, value: Double, changePercent: Double)] = [
        ("AAPL", 25000, 2.85),      // Strong gain (dark green)
        ("MSFT", 18000, 1.50),      // Moderate gain (medium green)
        ("GOOGL", 12000, 0.25),     // Slight gain (light green)
        ("AMZN", 10000, -0.10),     // Flat (near white)
        ("NVDA", 8000, -1.20),      // Moderate loss (medium red)
        ("META", 6000, -2.75),      // Strong loss (dark red)
        ("TSLA", 5000, 0.80),       // Light gain (light green)
        ("AMD", 4000, -0.50),       // Slight loss (light red)
        ("CRM", 3500, 3.50),        // Very strong gain (capped dark green)
        ("NFLX", 3000, -3.20),      // Very strong loss (capped dark red)
        ("INTC", 2000, 0.00),       // Flat (white)
    ]

    return VStack {
        Text("Performance Heatmap")
            .font(.headline)

        HeatmapTreemapView(data: mockData, showDollarAmounts: false)
            .padding()
    }
}
