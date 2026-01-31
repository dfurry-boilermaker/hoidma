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

// MARK: - Ticker Color Generator
/// Generates consistent colors for ticker symbols based on hash
/// Used across portfolio views, visualizations, and charts
func colorForTicker(_ ticker: String) -> Color {
    // Generate a consistent color based on the ticker symbol
    // This creates a hash from the ticker and converts it to RGB values
    var hash = 0
    for char in ticker.uppercased() {
        hash = Int(char.asciiValue ?? 0) + ((hash << 5) - hash)
    }

    // Ensure hash is positive
    hash = abs(hash)

    // Use modulo to get better distribution for RGB components
    // This ensures we get a good range of colors
    let r = Double((hash & 0xFF0000) >> 16) / 255.0
    let g = Double((hash & 0x00FF00) >> 8) / 255.0
    let b = Double(hash & 0x0000FF) / 255.0

    // Use HSL-like approach for better color vibrancy
    // Calculate brightness and adjust to ensure visibility
    let brightness = (r * 0.299 + g * 0.587 + b * 0.114)
    let minBrightness: Double = 0.4
    let maxBrightness: Double = 0.85

    // Adjust brightness while maintaining color relationships
    var adjustedR = r
    var adjustedG = g
    var adjustedB = b

    if brightness < minBrightness {
        // Too dark - brighten proportionally
        let scale = minBrightness / brightness
        adjustedR = min(r * scale, 1.0)
        adjustedG = min(g * scale, 1.0)
        adjustedB = min(b * scale, 1.0)
    } else if brightness > maxBrightness {
        // Too light - darken proportionally
        let scale = maxBrightness / brightness
        adjustedR = r * scale
        adjustedG = g * scale
        adjustedB = b * scale
    }

    // Ensure minimum values for visibility
    adjustedR = max(adjustedR, 0.2)
    adjustedG = max(adjustedG, 0.2)
    adjustedB = max(adjustedB, 0.2)

    return Color(red: adjustedR, green: adjustedG, blue: adjustedB)
}
