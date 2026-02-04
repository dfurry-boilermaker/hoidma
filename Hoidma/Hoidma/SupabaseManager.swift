import Foundation
import Combine
import Supabase

// MARK: - Database Models

/// Database model for Stock (matches PostgreSQL schema)
struct DBStock: Codable {
    let id: UUID?
    let userId: UUID
    let ticker: String
    let companyName: String
    let purchasePrice: Double
    let shares: Int
    let isCommitted: Bool
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case ticker
        case companyName = "company_name"
        case purchasePrice = "purchase_price"
        case shares
        case isCommitted = "is_committed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Convert from app's Stock model
    init(from stock: Stock, userId: UUID) {
        self.id = nil
        self.userId = userId
        self.ticker = stock.ticker.uppercased()
        self.companyName = stock.companyName
        self.purchasePrice = stock.purchasePrice
        self.shares = stock.shares
        self.isCommitted = stock.isMaritalStatus
        self.createdAt = nil
        self.updatedAt = nil
    }

    /// Convert to app's Stock model
    func toStock(lots: [StockLot] = []) -> Stock {
        return Stock(
            ticker: ticker,
            companyName: companyName,
            purchasePrice: purchasePrice,
            shares: shares,
            isMaritalStatus: isCommitted,
            lots: lots
        )
    }
}

/// Database model for StockLot (matches PostgreSQL schema)
struct DBStockLot: Codable {
    let id: UUID?
    let stockId: UUID
    let accountName: String
    let shares: Double
    let purchasePrice: Double
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case stockId = "stock_id"
        case accountName = "account_name"
        case shares
        case purchasePrice = "purchase_price"
        case createdAt = "created_at"
    }

    /// Convert from app's StockLot model
    init(from lot: StockLot, stockId: UUID) {
        self.id = nil  // Let DB generate UUID
        self.stockId = stockId
        self.accountName = lot.accountName
        self.shares = lot.shares
        self.purchasePrice = lot.purchasePrice
        self.createdAt = nil
    }

    /// Convert to app's StockLot model
    func toStockLot() -> StockLot {
        return StockLot(
            accountName: accountName,
            shares: shares,
            purchasePrice: purchasePrice
        )
    }
}

/// Database model for User
struct DBUser: Codable {
    let id: UUID?
    let email: String
    let authUserId: UUID
    let createdAt: Date?
    let lastSignInAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case authUserId = "auth_user_id"
        case createdAt = "created_at"
        case lastSignInAt = "last_sign_in_at"
    }
}

// MARK: - Supabase Error Types

/// Specific error types for Supabase operations
enum SupabaseError: Error, LocalizedError {
    case networkError(underlying: Error)
    case authenticationRequired
    case userNotFound
    case databaseError(message: String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network error"
        case .authenticationRequired:
            return "Authentication required"
        case .userNotFound:
            return "User not found"
        case .databaseError(let message):
            return "Database error: \(message)"
        case .timeout:
            return "Request timed out"
        }
    }

    /// Whether this error is transient and should be retried
    var isRetryable: Bool {
        switch self {
        case .networkError, .timeout:
            return true
        default:
            return false
        }
    }
}

// MARK: - Supabase Manager

/// Manages Supabase database interactions for user portfolios
/// Provides real-time sync using Supabase Realtime
///
/// SECURITY FEATURES:
/// - User ownership validation on all data operations
/// - Proper task cancellation to prevent memory leaks
/// - Safe optional handling (no force-unwraps)
/// - Retry logic for transient network failures
@MainActor
class SupabaseManager: ObservableObject {
    @Published var stocks: [Stock] = []
    @Published var userId: UUID?      // Auth user ID
    @Published var dbUserId: UUID?    // Users table ID

    private nonisolated(unsafe) var realtimeChannel: RealtimeChannelV2?
    private var cancellables = Set<AnyCancellable>()

    /// SECURITY FIX: Store listener task for proper cancellation
    private var listenerTask: Task<Void, Never>?

    /// Maximum retry attempts for transient errors
    private let maxRetryAttempts = 3

    init() {
        // Listen for auth state changes
        NotificationCenter.default.publisher(for: .supabaseAuthStateChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let userId = notification.userInfo?["userId"] as? UUID {
                    self?.userId = userId
                    Task {
                        await self?.setupUser()
                        await self?.startDataListener()
                    }
                } else {
                    self?.userId = nil
                    self?.dbUserId = nil
                    Task { @MainActor in
                        self?.stopDataListener()
                    }
                    self?.stocks = []
                }
            }
            .store(in: &cancellables)

        // Check initial auth state
        Task {
            await checkInitialAuthState()
        }
    }

    deinit {
        // SECURITY FIX: Cancel listener task to prevent memory leak
        listenerTask?.cancel()
        listenerTask = nil

        let channel = realtimeChannel
        Task {
            await channel?.unsubscribe()
        }
    }

    // MARK: - Auth State

    /// Check initial auth state on startup
    private func checkInitialAuthState() async {
        do {
            let session = try await SupabaseConfig.client.auth.session
            self.userId = session.user.id
            await setupUser()
            await startDataListener()
        } catch {
            AppLogger.debug("SupabaseManager: No active session")
        }
    }

    /// Create or update user record in users table
    private func setupUser() async {
        guard let authUserId = userId else { return }

        do {
            // Get email from auth user
            let user = try await SupabaseConfig.client.auth.user()
            guard let email = user.email else {
                AppLogger.debug("SupabaseManager: No email for user")
                return
            }

            // Check if user exists
            let existingUsers: [DBUser] = try await SupabaseConfig.client
                .from("users")
                .select()
                .eq("auth_user_id", value: authUserId.uuidString)
                .execute()
                .value

            if let existingUser = existingUsers.first {
                // SECURITY: Verify ownership - ensure returned user matches authenticated user
                guard existingUser.authUserId == authUserId else {
                    AppLogger.warning("SupabaseManager: User ownership mismatch - security violation")
                    return
                }

                // SECURITY FIX: Safe optional handling instead of force-unwrap
                guard let existingUserId = existingUser.id else {
                    AppLogger.warning("SupabaseManager: User record has no ID")
                    return
                }

                // Update last sign in
                self.dbUserId = existingUserId
                try await SupabaseConfig.client
                    .from("users")
                    .update(["last_sign_in_at": ISO8601DateFormatter().string(from: Date())])
                    .eq("id", value: existingUserId.uuidString)
                    .execute()
                AppLogger.debug("SupabaseManager: Updated user record")
            } else {
                // Create new user
                let newUser: [String: String] = [
                    "email": email,
                    "auth_user_id": authUserId.uuidString
                ]
                let insertedUsers: [DBUser] = try await SupabaseConfig.client
                    .from("users")
                    .insert(newUser)
                    .select()
                    .execute()
                    .value

                self.dbUserId = insertedUsers.first?.id
                AppLogger.debug("SupabaseManager: Created user record")
            }
        } catch {
            AppLogger.error("SupabaseManager: Error setting up user: \(error.localizedDescription)")
        }
    }

    // MARK: - Real-time Listener

    /// Start listening to user's portfolio data via Supabase Realtime
    func startDataListener() async {
        guard let dbUserId = dbUserId else {
            AppLogger.debug("SupabaseManager: No user ID, cannot start listener")
            return
        }

        // Stop existing listener
        stopDataListener()

        AppLogger.debug("SupabaseManager: Starting realtime listener...")

        // Initial fetch
        await fetchStocks()

        // Set up realtime subscription for stocks table
        let channel = SupabaseConfig.client.realtimeV2.channel("stocks-\(dbUserId.uuidString)")

        let stocksStream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "stocks",
            filter: .eq("user_id", value: dbUserId.uuidString)
        )

        // SECURITY FIX: Store listener task for proper cancellation
        listenerTask = Task { [weak self] in
            for await _ in stocksStream {
                guard let self = self else { break }
                AppLogger.debug("SupabaseManager: Stocks changed")
                await self.fetchStocks()
            }
        }

        do {
            try await channel.subscribeWithError()
        } catch {
            AppLogger.error("SupabaseManager: Failed to subscribe to realtime: \(error.localizedDescription)")
        }
        self.realtimeChannel = channel
        AppLogger.debug("SupabaseManager: Realtime subscription active")
    }

    /// Stop listening to Supabase realtime updates
    func stopDataListener() {
        // SECURITY FIX: Cancel listener task to prevent memory leak
        listenerTask?.cancel()
        listenerTask = nil

        Task {
            await realtimeChannel?.unsubscribe()
            realtimeChannel = nil
        }
    }

    // MARK: - Retry Logic

    /// Perform an operation with retry logic for transient errors
    /// - Parameters:
    ///   - operation: The name of the operation (for logging)
    ///   - attempt: Current attempt number (used internally)
    ///   - action: The async operation to perform
    /// - Returns: The result of the operation
    @discardableResult
    private func performWithRetry<T>(
        operation: String,
        attempt: Int = 1,
        action: () async throws -> T
    ) async throws -> T {
        do {
            return try await action()
        } catch let error as URLError where error.code == .timedOut || error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            // Network errors are retryable
            if attempt < maxRetryAttempts {
                let delay = pow(2.0, Double(attempt - 1)) // Exponential backoff: 1s, 2s, 4s
                AppLogger.debug("SupabaseManager: Retrying \(operation) after \(delay)s (attempt \(attempt + 1)/\(maxRetryAttempts))")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await performWithRetry(operation: operation, attempt: attempt + 1, action: action)
            }
            throw SupabaseError.networkError(underlying: error)
        } catch {
            // Check if error message indicates a transient error
            let errorMessage = error.localizedDescription.lowercased()
            let isTransient = errorMessage.contains("network") ||
                              errorMessage.contains("timeout") ||
                              errorMessage.contains("connection")

            if isTransient && attempt < maxRetryAttempts {
                let delay = pow(2.0, Double(attempt - 1))
                AppLogger.debug("SupabaseManager: Retrying \(operation) after \(delay)s (attempt \(attempt + 1)/\(maxRetryAttempts))")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await performWithRetry(operation: operation, attempt: attempt + 1, action: action)
            }
            throw error
        }
    }

    // MARK: - Fetch Operations

    /// Fetch all stocks for current user
    private func fetchStocks() async {
        guard let dbUserId = dbUserId else { return }

        do {
            // Fetch committed stocks with retry
            let dbStocks: [DBStock] = try await performWithRetry(operation: "fetchStocks") {
                try await SupabaseConfig.client
                    .from("stocks")
                    .select()
                    .eq("user_id", value: dbUserId.uuidString)
                    .eq("is_committed", value: true)
                    .execute()
                    .value
            }

            // Fetch lots for each stock
            var stocksWithLots: [Stock] = []
            for dbStock in dbStocks {
                guard let stockId = dbStock.id else { continue }

                let dbLots: [DBStockLot] = try await performWithRetry(operation: "fetchLots-\(dbStock.ticker)") {
                    try await SupabaseConfig.client
                        .from("stock_lots")
                        .select()
                        .eq("stock_id", value: stockId.uuidString)
                        .execute()
                        .value
                }

                let lots = dbLots.map { $0.toStockLot() }
                let stock = dbStock.toStock(lots: lots)
                stocksWithLots.append(stock)
            }

            self.stocks = stocksWithLots
            AppLogger.info("SupabaseManager: Loaded \(stocks.count) stocks")
        } catch {
            AppLogger.error("SupabaseManager: Error fetching stocks: \(error.localizedDescription)")
        }
    }

    // MARK: - CRUD Operations

    /// Commit a stock to Supabase
    func commit(newStock: Stock) async {
        guard let dbUserId = dbUserId else {
            AppLogger.debug("SupabaseManager: No user ID, cannot commit stock")
            return
        }

        AppLogger.debug("SupabaseManager: Committing stock \(newStock.ticker)...")

        var committedStock = newStock
        committedStock.isMaritalStatus = true

        do {
            // Check if stock already exists (with retry)
            let existingStocks: [DBStock] = try await performWithRetry(operation: "checkExistingStock-\(newStock.ticker)") {
                try await SupabaseConfig.client
                    .from("stocks")
                    .select()
                    .eq("user_id", value: dbUserId.uuidString)
                    .eq("ticker", value: newStock.ticker.uppercased())
                    .execute()
                    .value
            }

            var stockId: UUID

            if let existingStock = existingStocks.first, let existingId = existingStock.id {
                // Update existing stock (with retry)
                stockId = existingId
                let updateData: [String: AnyEncodable] = [
                    "company_name": AnyEncodable(committedStock.companyName),
                    "purchase_price": AnyEncodable(committedStock.purchasePrice),
                    "shares": AnyEncodable(committedStock.shares),
                    "is_committed": AnyEncodable(true),
                    "updated_at": AnyEncodable(ISO8601DateFormatter().string(from: Date()))
                ]
                try await performWithRetry(operation: "updateStock-\(newStock.ticker)") {
                    try await SupabaseConfig.client
                        .from("stocks")
                        .update(updateData)
                        .eq("id", value: stockId.uuidString)
                        .execute()
                }

                // Delete existing lots and re-insert (with retry)
                try await performWithRetry(operation: "deleteLots-\(newStock.ticker)") {
                    try await SupabaseConfig.client
                        .from("stock_lots")
                        .delete()
                        .eq("stock_id", value: stockId.uuidString)
                        .execute()
                }

                AppLogger.debug("SupabaseManager: Updated existing stock \(newStock.ticker)")
            } else {
                // Insert new stock (with retry)
                let insertData: [String: AnyEncodable] = [
                    "user_id": AnyEncodable(dbUserId.uuidString),
                    "ticker": AnyEncodable(committedStock.ticker.uppercased()),
                    "company_name": AnyEncodable(committedStock.companyName),
                    "purchase_price": AnyEncodable(committedStock.purchasePrice),
                    "shares": AnyEncodable(committedStock.shares),
                    "is_committed": AnyEncodable(true)
                ]
                let insertedStocks: [DBStock] = try await performWithRetry(operation: "insertStock-\(newStock.ticker)") {
                    try await SupabaseConfig.client
                        .from("stocks")
                        .insert(insertData)
                        .select()
                        .execute()
                        .value
                }

                guard let insertedStock = insertedStocks.first, let insertedId = insertedStock.id else {
                    AppLogger.error("SupabaseManager: Failed to get inserted stock ID")
                    return
                }
                stockId = insertedId
                AppLogger.debug("SupabaseManager: Inserted new stock \(newStock.ticker)")
            }

            // Insert lots (with retry for each)
            for lot in committedStock.lots {
                let lotData: [String: AnyEncodable] = [
                    "stock_id": AnyEncodable(stockId.uuidString),
                    "account_name": AnyEncodable(lot.accountName),
                    "shares": AnyEncodable(lot.shares),
                    "purchase_price": AnyEncodable(lot.purchasePrice)
                ]
                try await performWithRetry(operation: "insertLot-\(newStock.ticker)") {
                    try await SupabaseConfig.client
                        .from("stock_lots")
                        .insert(lotData)
                        .execute()
                }
            }

            AppLogger.debug("SupabaseManager: Successfully committed stock \(newStock.ticker) with \(committedStock.lots.count) lots")
        } catch {
            AppLogger.error("SupabaseManager: Error committing stock: \(error.localizedDescription)")
        }
    }

    /// Remove a stock from Supabase
    func removeStock(ticker: String) async {
        guard let dbUserId = dbUserId else {
            AppLogger.debug("SupabaseManager: No user ID, cannot remove stock")
            return
        }

        AppLogger.debug("SupabaseManager: Removing stock \(ticker)...")

        do {
            // CASCADE delete will handle stock_lots (with retry)
            try await performWithRetry(operation: "removeStock-\(ticker)") {
                try await SupabaseConfig.client
                    .from("stocks")
                    .delete()
                    .eq("user_id", value: dbUserId.uuidString)
                    .eq("ticker", value: ticker.uppercased())
                    .execute()
            }

            AppLogger.debug("SupabaseManager: Successfully removed stock \(ticker)")
        } catch {
            AppLogger.error("SupabaseManager: Error removing stock: \(error.localizedDescription)")
        }
    }
}

// MARK: - AnyEncodable Helper

/// Helper to encode any value for Supabase queries
struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        _encode = { encoder in
            try value.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
