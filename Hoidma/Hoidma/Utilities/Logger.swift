import Foundation
import os.log

/// Log levels for conditional logging
enum LogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    nonisolated static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Centralized logging utility with conditional output based on build configuration
///
/// In DEBUG builds: All log levels are output
/// In Release builds: Only warning and error levels are output
///
/// Usage:
/// ```
/// AppLogger.debug("Detailed debug info")
/// AppLogger.info("Operation completed")
/// AppLogger.warning("Something unexpected")
/// AppLogger.error("Operation failed")
/// ```
struct AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.hoidma"

    /// Minimum log level based on build configuration
    nonisolated static var minimumLevel: LogLevel {
        #if DEBUG
        return .debug
        #else
        return .warning
        #endif
    }

    /// Log a debug message (only in DEBUG builds)
    /// Use for detailed diagnostic information during development
    nonisolated static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard minimumLevel <= .debug else { return }
        let fileName = (file as NSString).lastPathComponent
        print("[\(fileName):\(line)] \(message)")
    }

    /// Log an info message (only in DEBUG builds)
    /// Use for general operational information
    nonisolated static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard minimumLevel <= .info else { return }
        let fileName = (file as NSString).lastPathComponent
        print("[\(fileName):\(line)] \(message)")
    }

    /// Log a warning message (appears in both DEBUG and Release builds)
    /// Use for unexpected but recoverable situations
    nonisolated static func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard minimumLevel <= .warning else { return }
        let fileName = (file as NSString).lastPathComponent
        os_log(.error, "[%{public}@:%{public}d] %{public}@", fileName, line, message)
    }

    /// Log an error message (appears in both DEBUG and Release builds)
    /// Use for errors that affect functionality
    nonisolated static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        os_log(.fault, "[%{public}@:%{public}d] %{public}@", fileName, line, message)
    }
}
