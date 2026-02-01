import SwiftUI

// MARK: - Heatmap Treemap Visualization
/// A treemap that shows stock positions sized by value and colored by daily performance

struct HeatmapTreemapView: View {
    let data: [(ticker: String, value: Double, changePercent: Double)]
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false

    /// Color based on performance percentage
    private func colorForChange(_ changePercent: Double) -> Color {
        if changePercent >= 0 {
            // Green shades for gains
            let intensity = min(abs(changePercent) / 10.0, 1.0) // Cap at 10%
            return Color(
                red: 0.15 + (0.1 * (1 - intensity)),
                green: 0.55 + (0.2 * intensity),
                blue: 0.35 + (0.1 * (1 - intensity))
            )
        } else {
            // Red/coral shades for losses (like the image)
            let intensity = min(abs(changePercent) / 10.0, 1.0) // Cap at 10%
            return Color(
                red: 0.85 + (0.1 * intensity),
                green: 0.45 - (0.15 * intensity),
                blue: 0.45 - (0.15 * intensity)
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
                    colorForChange: colorForChange
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

    var body: some View {
        let rects = calculateTreemapRects(items: items, totalValue: totalValue, rect: rect)

        ZStack(alignment: .topLeading) {
            ForEach(Array(rects.enumerated()), id: \.offset) { index, item in
                TreemapCell(
                    ticker: item.ticker,
                    changePercent: item.changePercent,
                    rect: item.rect,
                    color: colorForChange(item.changePercent)
                )
            }
        }
    }

    /// Squarified treemap algorithm
    private func calculateTreemapRects(
        items: [(ticker: String, value: Double, changePercent: Double)],
        totalValue: Double,
        rect: CGRect
    ) -> [(ticker: String, changePercent: Double, rect: CGRect)] {
        guard !items.isEmpty, totalValue > 0 else { return [] }

        var result: [(ticker: String, changePercent: Double, rect: CGRect)] = []
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

                result.append((ticker: item.ticker, changePercent: item.changePercent, rect: itemRect))
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
    let changePercent: Double
    let rect: CGRect
    let color: Color

    var body: some View {
        ZStack {
            Rectangle()
                .fill(color)

            Rectangle()
                .stroke(Color.black.opacity(0.2), lineWidth: 1)

            // Only show text if cell is large enough
            if rect.width > 35 && rect.height > 30 {
                VStack(spacing: 2) {
                    Text(ticker)
                        .font(.system(size: fontSize, weight: .bold, design: .default))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    Text(changeString)
                        .font(.system(size: max(fontSize * 0.7, 8), weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                }
                .padding(4)
            } else if rect.width > 20 && rect.height > 20 {
                // Just show ticker for smaller cells
                Text(ticker)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
        }
        .frame(width: rect.width, height: rect.height)
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

    private var changeString: String {
        let sign = changePercent >= 0 ? "" : ""
        return "\(sign)\(String(format: "%.2f", changePercent))%"
    }
}

// MARK: - Preview

#Preview("Heatmap Treemap") {
    let mockData: [(ticker: String, value: Double, changePercent: Double)] = [
        ("NBIS", 25000, -10.24),
        ("IREN", 8000, -10.19),
        ("SYNA", 6000, -3.94),
        ("GOOGL", 5000, -0.005),
        ("CRM", 4500, -0.84),
        ("HOOD", 3500, -1.74),
        ("QQQ", 5500, -1.20),
        ("CIFR", 3000, -9.83),
        ("STEM", 2500, -6.14),
        ("CCCX", 2800, -12.68),
        ("GLDD", 1500, -2.5),
    ]

    return VStack {
        Text("Performance Heatmap")
            .font(.headline)

        HeatmapTreemapView(data: mockData)
            .padding()
    }
}
