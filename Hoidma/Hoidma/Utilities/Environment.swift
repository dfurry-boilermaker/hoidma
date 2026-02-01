import Foundation

// MARK: - App Environment
/// Centralized environment detection and configuration
enum AppEnvironment {
    // MARK: - UI Testing Detection

    /// Checks if the app is running in UI test mode
    /// Used to skip API calls and prevent test hangs
    nonisolated static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing") ||
        ProcessInfo.processInfo.environment["UI_TESTING"] == "1"
    }

    // MARK: - Storage Configuration

    /// Whether to use local storage instead of Supabase
    /// Set via build configuration or environment variable
    ///
    /// To enable Supabase:
    /// - Set USE_SUPABASE=1 in environment variables, or
    /// - Change the default value below for production builds
    nonisolated static var useLocalStorage: Bool {
        // Check environment variable first
        if let envValue = ProcessInfo.processInfo.environment["USE_SUPABASE"] {
            return envValue != "1"
        }
        // Default to local storage for development/testing
        // Change to `false` for production builds with Supabase
        return true
    }

    // MARK: - Debug Helpers

    /// Prints a debug message only in UI testing mode
    nonisolated static func testingLog(_ message: String) {
        if isUITesting {
            print("🧪 UI Testing mode: \(message)")
        }
    }
}

// MARK: - String Extensions
extension String {
    /// Returns a trimmed and uppercased version of the ticker symbol
    /// Removes whitespace and normalizes for API calls
    var trimmedTicker: String {
        trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Returns true if the string is a valid ticker (non-empty after trimming)
    var isValidTicker: Bool {
        !trimmedTicker.isEmpty
    }
}
