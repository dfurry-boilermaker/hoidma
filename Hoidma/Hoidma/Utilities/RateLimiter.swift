import Foundation

/// Thread-safe rate limiter with exponential backoff support
///
/// SECURITY: Prevents brute force attacks on OTP verification and
/// respects API rate limits to avoid service denial.
///
/// Usage:
/// ```
/// let limiter = RateLimiter(maxAttempts: 5, windowSeconds: 60)
///
/// // Check if action is allowed
/// if limiter.canAttempt() {
///     limiter.recordAttempt()
///     // perform action
/// } else {
///     let waitTime = limiter.timeUntilNextAttempt()
///     // show "try again in X seconds"
/// }
///
/// // Reset after success
/// limiter.reset()
/// ```
actor RateLimiter {

    // MARK: - Configuration

    /// Maximum attempts allowed within the time window
    let maxAttempts: Int

    /// Time window in seconds for counting attempts
    let windowSeconds: TimeInterval

    /// Base delay for exponential backoff (in seconds)
    let baseBackoffDelay: TimeInterval

    /// Maximum backoff delay (in seconds)
    let maxBackoffDelay: TimeInterval

    /// Lockout duration after exceeding max attempts (in seconds)
    let lockoutDuration: TimeInterval

    // MARK: - State

    private var attempts: [Date] = []
    private var consecutiveFailures: Int = 0
    private var lockoutEndTime: Date?

    // MARK: - Initialization

    /// Initialize a rate limiter
    /// - Parameters:
    ///   - maxAttempts: Maximum attempts allowed in the time window (default: 5)
    ///   - windowSeconds: Time window for counting attempts (default: 60)
    ///   - baseBackoffDelay: Base delay for exponential backoff (default: 1.0)
    ///   - maxBackoffDelay: Maximum backoff delay (default: 60.0)
    ///   - lockoutDuration: Lockout duration after max attempts (default: 1800 = 30 min)
    init(
        maxAttempts: Int = 5,
        windowSeconds: TimeInterval = 60,
        baseBackoffDelay: TimeInterval = 1.0,
        maxBackoffDelay: TimeInterval = 60.0,
        lockoutDuration: TimeInterval = 1800
    ) {
        self.maxAttempts = maxAttempts
        self.windowSeconds = windowSeconds
        self.baseBackoffDelay = baseBackoffDelay
        self.maxBackoffDelay = maxBackoffDelay
        self.lockoutDuration = lockoutDuration
    }

    // MARK: - Public API

    /// Check if an attempt is currently allowed
    /// - Returns: true if attempt is allowed, false if rate limited or locked out
    func canAttempt() -> Bool {
        // Check if locked out
        if let lockoutEnd = lockoutEndTime, Date() < lockoutEnd {
            return false
        }

        // Clear lockout if expired
        if lockoutEndTime != nil && Date() >= lockoutEndTime! {
            lockoutEndTime = nil
        }

        // Clean up old attempts outside the window
        pruneOldAttempts()

        // Check if under the limit
        return attempts.count < maxAttempts
    }

    /// Record an attempt (call this before performing the rate-limited action)
    func recordAttempt() {
        pruneOldAttempts()
        attempts.append(Date())
    }

    /// Record a failed attempt (increments consecutive failures for backoff)
    func recordFailure() {
        consecutiveFailures += 1

        // Check if we should lock out
        if consecutiveFailures >= maxAttempts * 2 {
            lockoutEndTime = Date().addingTimeInterval(lockoutDuration)
            AppLogger.warning("Rate limiter lockout activated for \(Int(lockoutDuration)) seconds")
        }
    }

    /// Record a successful attempt (resets consecutive failures)
    func recordSuccess() {
        consecutiveFailures = 0
    }

    /// Reset the rate limiter (call after successful operation)
    func reset() {
        attempts.removeAll()
        consecutiveFailures = 0
        lockoutEndTime = nil
    }

    /// Get the current backoff delay based on consecutive failures
    /// - Returns: Delay in seconds before next attempt should be made
    func currentBackoffDelay() -> TimeInterval {
        guard consecutiveFailures > 0 else { return 0 }

        // Exponential backoff: base * 2^(failures-1)
        let delay = baseBackoffDelay * pow(2.0, Double(consecutiveFailures - 1))
        return min(delay, maxBackoffDelay)
    }

    /// Get time until next attempt is allowed
    /// - Returns: Seconds until next attempt, or 0 if attempt is allowed now
    func timeUntilNextAttempt() -> TimeInterval {
        // Check lockout first
        if let lockoutEnd = lockoutEndTime {
            let remaining = lockoutEnd.timeIntervalSinceNow
            if remaining > 0 {
                return remaining
            }
        }

        // Check rate limit window
        pruneOldAttempts()
        if attempts.count < maxAttempts {
            return max(0, currentBackoffDelay())
        }

        // Find when the oldest attempt will expire
        guard let oldestAttempt = attempts.first else {
            return 0
        }

        let windowEnd = oldestAttempt.addingTimeInterval(windowSeconds)
        let remaining = windowEnd.timeIntervalSinceNow
        return max(0, remaining)
    }

    /// Get remaining attempts in the current window
    /// - Returns: Number of attempts remaining, or 0 if locked out
    func remainingAttempts() -> Int {
        if lockoutEndTime != nil && Date() < lockoutEndTime! {
            return 0
        }

        pruneOldAttempts()
        return max(0, maxAttempts - attempts.count)
    }

    /// Check if currently locked out
    /// - Returns: true if locked out
    func isLockedOut() -> Bool {
        guard let lockoutEnd = lockoutEndTime else { return false }
        return Date() < lockoutEnd
    }

    // MARK: - Private

    private func pruneOldAttempts() {
        let cutoff = Date().addingTimeInterval(-windowSeconds)
        attempts.removeAll { $0 < cutoff }
    }
}

// MARK: - API Rate Limiter

/// Specialized rate limiter for API calls with per-endpoint tracking
actor APIRateLimiter {

    // MARK: - Configuration

    struct EndpointConfig {
        let callsPerMinute: Int
        let callsPerDay: Int

        // Polygon.io rate limits based on subscription tier
        static let polygon = EndpointConfig(
            callsPerMinute: APIConfig.polygonTier.callsPerMinute,
            callsPerDay: Int.max
        )

        static let fmp = EndpointConfig(callsPerMinute: 5, callsPerDay: 250)
        static let yahoo = EndpointConfig(callsPerMinute: 30, callsPerDay: Int.max)
    }

    // MARK: - State

    private var minuteAttempts: [String: [Date]] = [:]
    private var dailyAttempts: [String: [Date]] = [:]

    // MARK: - Public API

    /// Check if an API call is allowed for the given endpoint
    /// - Parameter endpoint: The API endpoint identifier
    /// - Parameter config: Rate limit configuration for this endpoint
    /// - Returns: true if call is allowed
    func canMakeRequest(endpoint: String, config: EndpointConfig) -> Bool {
        pruneOldAttempts(endpoint: endpoint)

        let minuteCount = minuteAttempts[endpoint]?.count ?? 0
        let dailyCount = dailyAttempts[endpoint]?.count ?? 0

        return minuteCount < config.callsPerMinute && dailyCount < config.callsPerDay
    }

    /// Record an API call for the given endpoint
    func recordRequest(endpoint: String) {
        let now = Date()

        if minuteAttempts[endpoint] == nil {
            minuteAttempts[endpoint] = []
        }
        minuteAttempts[endpoint]?.append(now)

        if dailyAttempts[endpoint] == nil {
            dailyAttempts[endpoint] = []
        }
        dailyAttempts[endpoint]?.append(now)
    }

    /// Get time until next request is allowed
    /// - Parameter endpoint: The API endpoint identifier
    /// - Parameter config: Rate limit configuration for this endpoint
    /// - Returns: Seconds until next request, or 0 if allowed now
    func timeUntilNextRequest(endpoint: String, config: EndpointConfig) -> TimeInterval {
        pruneOldAttempts(endpoint: endpoint)

        // Check minute limit
        if let attempts = minuteAttempts[endpoint], attempts.count >= config.callsPerMinute {
            if let oldest = attempts.first {
                let windowEnd = oldest.addingTimeInterval(60)
                let remaining = windowEnd.timeIntervalSinceNow
                if remaining > 0 {
                    return remaining
                }
            }
        }

        // Check daily limit
        if let attempts = dailyAttempts[endpoint], attempts.count >= config.callsPerDay {
            // Daily limit exceeded - calculate time until midnight
            let calendar = Calendar.current
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) {
                return tomorrow.timeIntervalSinceNow
            }
        }

        return 0
    }

    // MARK: - Private

    private func pruneOldAttempts(endpoint: String) {
        let oneMinuteAgo = Date().addingTimeInterval(-60)
        let oneDayAgo = Date().addingTimeInterval(-86400)

        minuteAttempts[endpoint]?.removeAll { $0 < oneMinuteAgo }
        dailyAttempts[endpoint]?.removeAll { $0 < oneDayAgo }
    }
}

// MARK: - OTP Rate Limiter

/// Specialized rate limiter for OTP verification
/// SECURITY: Limits attempts to prevent brute force attacks
actor OTPRateLimiter {

    // MARK: - Configuration

    /// Maximum OTP verification attempts per code
    private let maxAttemptsPerCode = 5

    /// Maximum total attempts before lockout
    private let maxTotalAttempts = 10

    /// Lockout duration in seconds (30 minutes)
    private let lockoutDuration: TimeInterval = 1800

    // MARK: - State

    private var attemptsForCurrentCode: Int = 0
    private var totalFailedAttempts: Int = 0
    private var lockoutEndTime: Date?
    private var lastCodeSentTime: Date?

    // MARK: - Public API

    /// Check if OTP verification attempt is allowed
    /// - Returns: Tuple of (allowed: Bool, message: String?)
    func canVerify() -> (allowed: Bool, message: String?) {
        // Check lockout
        if let lockoutEnd = lockoutEndTime, Date() < lockoutEnd {
            let remaining = Int(lockoutEnd.timeIntervalSinceNow)
            let minutes = remaining / 60
            let seconds = remaining % 60
            return (false, "Too many failed attempts. Try again in \(minutes)m \(seconds)s")
        }

        // Clear expired lockout
        if lockoutEndTime != nil && Date() >= lockoutEndTime! {
            lockoutEndTime = nil
            totalFailedAttempts = 0
        }

        // Check per-code limit
        if attemptsForCurrentCode >= maxAttemptsPerCode {
            return (false, "Maximum attempts for this code reached. Please request a new code.")
        }

        return (true, nil)
    }

    /// Record a verification attempt
    func recordAttempt() {
        attemptsForCurrentCode += 1
    }

    /// Record a failed verification
    func recordFailure() {
        totalFailedAttempts += 1

        // Check if we should lock out
        if totalFailedAttempts >= maxTotalAttempts {
            lockoutEndTime = Date().addingTimeInterval(lockoutDuration)
            AppLogger.warning("OTP verification locked out for \(Int(lockoutDuration / 60)) minutes after \(totalFailedAttempts) failed attempts")
        }
    }

    /// Record successful verification (resets all counters)
    func recordSuccess() {
        attemptsForCurrentCode = 0
        totalFailedAttempts = 0
        lockoutEndTime = nil
    }

    /// Called when a new OTP code is requested (resets per-code counter)
    func newCodeRequested() {
        attemptsForCurrentCode = 0
        lastCodeSentTime = Date()
    }

    /// Get remaining attempts for current code
    func remainingAttempts() -> Int {
        max(0, maxAttemptsPerCode - attemptsForCurrentCode)
    }

    /// Check if locked out
    func isLockedOut() -> Bool {
        guard let lockoutEnd = lockoutEndTime else { return false }
        return Date() < lockoutEnd
    }

    /// Get lockout remaining time in seconds
    func lockoutRemainingSeconds() -> Int {
        guard let lockoutEnd = lockoutEndTime else { return 0 }
        return max(0, Int(lockoutEnd.timeIntervalSinceNow))
    }
}
