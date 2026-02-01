import SwiftUI

// MARK: - App Colors
/// Centralized color definitions for the app
enum AppColors {
    /// Green color for positive values (profit, gains)
    static let positive = Color(red: 0.231, green: 0.706, blue: 0.494)

    /// Red color for negative values (loss)
    static let negative = Color.red

    /// Returns the appropriate color based on whether a value is positive or negative
    static func forValue(_ value: Double) -> Color {
        value >= 0 ? positive : negative
    }
}

// MARK: - Stock Position Colors
/// 30 vibrant, maximally distinct colors for stock positions
/// Colors are ordered to maximize visual distinction between adjacent colors
/// Assigned from largest to smallest position
private let stockPositionColors: [Color] = [
    // Primary vibrant colors (most different from each other)
    Color(red: 0.000, green: 0.478, blue: 1.000),  // 1. Vivid Blue
    Color(red: 1.000, green: 0.400, blue: 0.000),  // 2. Bright Orange
    Color(red: 0.000, green: 0.800, blue: 0.400),  // 3. Emerald Green
    Color(red: 1.000, green: 0.200, blue: 0.200),  // 4. Vibrant Red
    Color(red: 0.600, green: 0.200, blue: 0.900),  // 5. Electric Purple
    Color(red: 0.000, green: 0.800, blue: 0.800),  // 6. Bright Cyan
    Color(red: 1.000, green: 0.300, blue: 0.600),  // 7. Hot Pink
    Color(red: 1.000, green: 0.800, blue: 0.000),  // 8. Golden Yellow
    Color(red: 0.400, green: 0.800, blue: 0.200),  // 9. Lime Green
    Color(red: 0.900, green: 0.300, blue: 0.900),  // 10. Magenta

    // Secondary vibrant colors
    Color(red: 0.200, green: 0.600, blue: 1.000),  // 11. Sky Blue
    Color(red: 1.000, green: 0.550, blue: 0.200),  // 12. Tangerine
    Color(red: 0.200, green: 0.900, blue: 0.600),  // 13. Mint
    Color(red: 1.000, green: 0.400, blue: 0.400),  // 14. Coral
    Color(red: 0.750, green: 0.450, blue: 1.000),  // 15. Violet
    Color(red: 0.000, green: 0.650, blue: 0.650),  // 16. Teal
    Color(red: 1.000, green: 0.500, blue: 0.700),  // 17. Rose
    Color(red: 0.900, green: 0.700, blue: 0.100),  // 18. Amber
    Color(red: 0.500, green: 0.900, blue: 0.400),  // 19. Spring Green
    Color(red: 0.400, green: 0.400, blue: 1.000),  // 20. Periwinkle

    // Tertiary vibrant colors
    Color(red: 0.100, green: 0.350, blue: 0.850),  // 21. Cobalt Blue
    Color(red: 0.950, green: 0.350, blue: 0.100),  // 22. Vermillion
    Color(red: 0.100, green: 0.700, blue: 0.300),  // 23. Kelly Green
    Color(red: 0.850, green: 0.100, blue: 0.350),  // 24. Crimson
    Color(red: 0.500, green: 0.100, blue: 0.750),  // 25. Grape
    Color(red: 0.100, green: 0.600, blue: 0.700),  // 26. Ocean
    Color(red: 1.000, green: 0.250, blue: 0.500),  // 27. Watermelon
    Color(red: 0.800, green: 0.600, blue: 0.000),  // 28. Mustard
    Color(red: 0.300, green: 0.700, blue: 0.100),  // 29. Grass Green
    Color(red: 0.650, green: 0.300, blue: 0.800),  // 30. Amethyst
]

// MARK: - Stock Color Manager
/// Manages color assignment for stocks based on their position size
class StockColorManager {
    static let shared = StockColorManager()

    /// Maps ticker to assigned color index based on position ranking
    private var tickerColorIndex: [String: Int] = [:]

    private init() {}

    /// Updates color assignments based on sorted stock positions
    /// - Parameter sortedTickers: Array of tickers sorted by position value (largest first)
    func updateColorAssignments(sortedTickers: [String]) {
        tickerColorIndex.removeAll()
        for (index, ticker) in sortedTickers.enumerated() {
            tickerColorIndex[ticker] = index
        }
    }

    /// Gets the color for a ticker based on its position ranking
    /// - Parameter ticker: The stock ticker symbol
    /// - Returns: Color assigned to this ticker, or a default color if not assigned
    func color(for ticker: String) -> Color {
        if let index = tickerColorIndex[ticker] {
            return stockPositionColors[index % stockPositionColors.count]
        }
        // Fallback: use hash-based color if ticker not in sorted list
        return colorFromHash(ticker)
    }

    /// Generates a color from ticker hash (fallback method)
    private func colorFromHash(_ ticker: String) -> Color {
        var hash = 0
        for char in ticker.uppercased() {
            hash = Int(char.asciiValue ?? 0) + ((hash << 5) - hash)
        }
        hash = abs(hash)
        return stockPositionColors[hash % stockPositionColors.count]
    }
}

// MARK: - Global Color Function
/// Gets color for a ticker - uses position-based assignment if available
/// - Parameter ticker: The stock ticker symbol
/// - Returns: Color for the ticker
func colorForTicker(_ ticker: String) -> Color {
    return StockColorManager.shared.color(for: ticker)
}
