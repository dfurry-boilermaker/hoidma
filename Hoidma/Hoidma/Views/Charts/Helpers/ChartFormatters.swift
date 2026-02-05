import Foundation

/// Centralized formatting utilities for all chart-related values
/// Consolidates duplicate formatting logic from ChartsView components
enum ChartFormatters {

    // MARK: - Currency Formatting

    /// Format currency value with standard USD formatting
    /// - Parameter value: The currency value to format
    /// - Returns: Formatted string (e.g., "$1,234.56")
    static func formatCurrency(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }

    /// Format currency with privacy masking support
    /// - Parameters:
    ///   - value: The currency value to format
    ///   - masked: If true, returns "***" instead of actual value
    /// - Returns: Formatted string or masked placeholder
    static func formatCurrency(_ value: Double, masked: Bool) -> String {
        masked ? "***" : formatCurrency(value)
    }

    /// Format currency in compact form with K/M suffixes
    /// - Parameter value: The currency value to format
    /// - Returns: Compact formatted string (e.g., "$1.2M", "$5.0K", "$123")
    static func formatCompact(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.0fK", value / 1_000)
        } else {
            return String(format: "$%.0f", value)
        }
    }

    // MARK: - Change Formatting

    /// Format price change value (dollar amount)
    /// - Parameters:
    ///   - value: The change value
    ///   - isPortfolio: If true, uses K suffix for values >= 1000
    /// - Returns: Formatted change string with sign
    static func formatChangeValue(_ value: Double, isPortfolio: Bool) -> String {
        let sign = value >= 0 ? "+" : ""

        if isPortfolio {
            let absValue = abs(value)
            if absValue >= 1_000 {
                return "\(sign)$\(String(format: "%.2f", value / 1_000))K"
            }
        }

        return "\(sign)$\(String(format: "%.2f", value))"
    }

    /// Format percentage change
    /// - Parameter percent: The percentage value
    /// - Returns: Formatted percentage with sign (e.g., "+2.5%")
    static func formatPercentChange(_ percent: Double) -> String {
        let sign = percent >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", percent))%"
    }

    // MARK: - Axis Formatting

    /// Format Y-axis label based on chart period and context
    /// - Parameters:
    ///   - value: The value to format
    ///   - period: The chart time period (affects precision)
    ///   - isPortfolio: Whether this is a portfolio chart
    /// - Returns: Formatted string appropriate for Y-axis display
    static func formatYAxis(_ value: Double, period: ChartTimePeriod, isPortfolio: Bool) -> String {
        // For 1D charts, use precise formatting to show intraday movement
        if period == .oneDay {
            if value >= 1_000_000 {
                // Millions: always show 2 decimals (e.g., $1.23M)
                return String(format: "$%.2fM", value / 1_000_000)
            } else if value >= 10_000 {
                // Ten thousands and above: show 2 decimals in K (e.g., $17.92K, $18.05K)
                return String(format: "$%.2fK", value / 1_000)
            } else if value >= 1_000 {
                // Thousands: show 2 decimals in K (e.g., $1.23K)
                return String(format: "$%.2fK", value / 1_000)
            } else {
                // Under $1000: show full dollars
                return String(format: "$%.0f", value)
            }
        } else {
            // For ALL period, use standard compact format
            return formatCompact(value)
        }
    }

    /// Intraday time label parts for chart axis
    /// - Parameter date: The date to format
    /// - Returns: Tuple of (label, time) where label is "Open"/"Close"/nil and time is local timezone
    static func intradayTimeParts(_ date: Date) -> (label: String?, time: String) {
        // Get EST components to check for market open/close
        let calendar = ChartTimezoneHelper.estCalendar
        let estComponents = calendar.dateComponents([.hour, .minute], from: date)
        let estHour = estComponents.hour ?? 0
        let estMinute = estComponents.minute ?? 0

        // Format time in device's local timezone
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "h:mma"
        let localTime = formatter.string(from: date).lowercased()

        // Check if this is market open (9:30 AM EST)
        if estHour == 9 && estMinute == 30 {
            return ("Open", localTime)
        }

        // Check if this is market close (4:00 PM EST)
        if estHour == 16 && estMinute == 0 {
            return ("Close", localTime)
        }

        // For middle time, no label
        return (nil, localTime)
    }
}
