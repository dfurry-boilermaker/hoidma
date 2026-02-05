import Foundation
import SwiftUI

/// Helper utilities for chart axis configuration and scaling
/// Handles Y-axis domain calculation and X-axis value generation
enum ChartAxisHelpers {

    // MARK: - Y-Axis Domain

    /// Calculate Y-axis domain with context-aware scaling
    /// - Parameters:
    ///   - data: Chart data points
    ///   - period: Time period (affects scaling strategy)
    /// - Returns: Domain range for Y-axis
    static func getYAxisDomain(
        data: [ChartDataPoint],
        period: ChartTimePeriod
    ) -> ClosedRange<Double> {
        guard !data.isEmpty else {
            return 0...100
        }

        let values = data.map { $0.value }
        guard let minValue = values.min(),
              let maxValue = values.max() else {
            return 0...100
        }

        // For 1D chart, use tight scaling to show intraday movement
        if period == .oneDay {
            let range = maxValue - minValue

            // If range is very small (less than 0.5%), expand it to at least 1%
            let minRange = maxValue * 0.01
            let effectiveRange = max(range, minRange)

            // Add 20% padding on each side of the actual range
            let padding = effectiveRange * 0.2
            let domainMin = minValue - padding
            let domainMax = maxValue + padding

            return domainMin...domainMax
        } else {
            // For ALL period, use wider scaling with 5% padding
            let range = maxValue - minValue
            let padding = range * 0.05
            let domainMin = max(0, minValue - padding)
            let domainMax = maxValue + padding

            return domainMin...domainMax
        }
    }

    // MARK: - X-Axis Values

    /// Get intraday axis values (market open, middle, close)
    /// - Returns: Array of Date values for intraday chart axis
    static func getIntradayAxisValues() -> [Date] {
        var values: [Date] = []

        // Use timezone helper to ensure consistent EST handling
        let calendar = ChartTimezoneHelper.estCalendar
        let todayEST = ChartTimezoneHelper.todayInEST()

        // Market open: 9:30 AM EST
        if let marketOpen = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: todayEST) {
            values.append(marketOpen)
        }

        // Market middle: 12:45 PM EST (middle of 9:30am - 4:00pm)
        if let marketMiddle = calendar.date(bySettingHour: 12, minute: 45, second: 0, of: todayEST) {
            values.append(marketMiddle)
        }

        // Market close: 4:00 PM EST
        if let marketClose = calendar.date(bySettingHour: 16, minute: 0, second: 0, of: todayEST) {
            values.append(marketClose)
        }

        return values
    }
}
