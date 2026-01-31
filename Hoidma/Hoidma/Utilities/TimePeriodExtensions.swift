import Foundation

// MARK: - TimePeriod Extensions
extension TimePeriod {
    /// Returns the API key string for this period (used in API responses)
    var apiKey: String {
        switch self {
        case .daily: return "1d"
        case .weekly: return "1w"
        case .monthly: return "1m"
        case .threeMonths: return "3m"
        case .ytd: return "ytd"
        case .allTime: return "all"
        }
    }

    /// Returns the start date for this period relative to now
    var startDate: Date {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: -1, to: now) ?? now
        case .weekly:
            return calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .monthly:
            return calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .threeMonths:
            return calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .ytd:
            return calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
        case .allTime:
            // For all-time, return a very old date
            return calendar.date(byAdding: .year, value: -100, to: now) ?? now
        }
    }

    /// Returns the number of days in this period (approximate for reset logic)
    var daysInPeriod: Int {
        switch self {
        case .daily: return 1
        case .weekly: return 7
        case .monthly: return 30
        case .threeMonths: return 90
        case .ytd: return 365 // Approximate, handled specially
        case .allTime: return Int.max
        }
    }
}

// MARK: - StockPriceData Period Helpers
extension StockPriceData {
    /// Returns the start price for a given period
    func startPrice(for period: TimePeriod) -> Double {
        switch period {
        case .daily: return dailyStartPrice
        case .weekly: return weeklyStartPrice
        case .monthly: return monthlyStartPrice
        case .threeMonths: return threeMonthsStartPrice
        case .ytd: return ytdStartPrice
        case .allTime: return allTimeStartPrice
        }
    }

    /// Returns the start time for a given period
    func startTime(for period: TimePeriod) -> Date {
        switch period {
        case .daily: return dailyStartTime
        case .weekly: return weeklyStartTime
        case .monthly: return monthlyStartTime
        case .threeMonths: return threeMonthsStartTime
        case .ytd: return ytdStartTime
        case .allTime: return allTimeStartTime
        }
    }
}
