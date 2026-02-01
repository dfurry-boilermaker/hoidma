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

// MARK: - Supabase Manager

/// Manages Supabase database interactions for user portfolios
/// Provides real-time sync using Supabase Realtime
@MainActor
class SupabaseManager: ObservableObject {
    @Published var stocks: [Stock] = []
    @Published var userId: UUID?      // Auth user ID
    @Published var dbUserId: UUID?    // Users table ID

    private nonisolated(unsafe) var realtimeChannel: RealtimeChannelV2?
    private var cancellables = Set<AnyCancellable>()

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
            print("SupabaseManager: No active session")
        }
    }

    /// Create or update user record in users table
    private func setupUser() async {
        guard let authUserId = userId else { return }

        do {
            // Get email from auth user
            let user = try await SupabaseConfig.client.auth.user()
            guard let email = user.email else {
                print("SupabaseManager: No email for user")
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
                // Update last sign in
                self.dbUserId = existingUser.id
                try await SupabaseConfig.client
                    .from("users")
                    .update(["last_sign_in_at": ISO8601DateFormatter().string(from: Date())])
                    .eq("id", value: existingUser.id!.uuidString)
                    .execute()
                print("SupabaseManager: Updated user record")
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
                print("SupabaseManager: Created user record with ID: \(self.dbUserId?.uuidString ?? "nil")")
            }
        } catch {
            print("SupabaseManager: Error setting up user: \(error.localizedDescription)")
        }
    }

    // MARK: - Real-time Listener

    /// Start listening to user's portfolio data via Supabase Realtime
    func startDataListener() async {
        guard let dbUserId = dbUserId else {
            print("SupabaseManager: No user ID, cannot start listener")
            return
        }

        // Stop existing listener
        stopDataListener()

        print("SupabaseManager: Starting realtime listener for user \(dbUserId)...")

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

        // Listen for stock changes
        Task {
            for await _ in stocksStream {
                print("SupabaseManager: Stocks changed")
                await fetchStocks()
            }
        }

        do {
            try await channel.subscribeWithError()
        } catch {
            print("SupabaseManager: Failed to subscribe to realtime: \(error.localizedDescription)")
        }
        self.realtimeChannel = channel
        print("SupabaseManager: Realtime subscription active")
    }

    /// Stop listening to Supabase realtime updates
    func stopDataListener() {
        Task {
            await realtimeChannel?.unsubscribe()
            realtimeChannel = nil
        }
    }

    // MARK: - Fetch Operations

    /// Fetch all stocks for current user
    private func fetchStocks() async {
        guard let dbUserId = dbUserId else { return }

        do {
            // Fetch committed stocks
            let dbStocks: [DBStock] = try await SupabaseConfig.client
                .from("stocks")
                .select()
                .eq("user_id", value: dbUserId.uuidString)
                .eq("is_committed", value: true)
                .execute()
                .value

            // Fetch lots for each stock
            var stocksWithLots: [Stock] = []
            for dbStock in dbStocks {
                guard let stockId = dbStock.id else { continue }

                let dbLots: [DBStockLot] = try await SupabaseConfig.client
                    .from("stock_lots")
                    .select()
                    .eq("stock_id", value: stockId.uuidString)
                    .execute()
                    .value

                let lots = dbLots.map { $0.toStockLot() }
                let stock = dbStock.toStock(lots: lots)
                stocksWithLots.append(stock)
            }

            self.stocks = stocksWithLots
            print("SupabaseManager: Loaded \(stocks.count) stocks")
        } catch {
            print("SupabaseManager: Error fetching stocks: \(error.localizedDescription)")
        }
    }

    // MARK: - CRUD Operations

    /// Commit a stock to Supabase
    func commit(newStock: Stock) async {
        guard let dbUserId = dbUserId else {
            print("SupabaseManager: No user ID, cannot commit stock")
            return
        }

        print("SupabaseManager: Committing stock \(newStock.ticker)...")

        var committedStock = newStock
        committedStock.isMaritalStatus = true

        do {
            // Check if stock already exists
            let existingStocks: [DBStock] = try await SupabaseConfig.client
                .from("stocks")
                .select()
                .eq("user_id", value: dbUserId.uuidString)
                .eq("ticker", value: newStock.ticker.uppercased())
                .execute()
                .value

            var stockId: UUID

            if let existingStock = existingStocks.first, let existingId = existingStock.id {
                // Update existing stock
                stockId = existingId
                let updateData: [String: AnyEncodable] = [
                    "company_name": AnyEncodable(committedStock.companyName),
                    "purchase_price": AnyEncodable(committedStock.purchasePrice),
                    "shares": AnyEncodable(committedStock.shares),
                    "is_committed": AnyEncodable(true),
                    "updated_at": AnyEncodable(ISO8601DateFormatter().string(from: Date()))
                ]
                try await SupabaseConfig.client
                    .from("stocks")
                    .update(updateData)
                    .eq("id", value: stockId.uuidString)
                    .execute()

                // Delete existing lots and re-insert
                try await SupabaseConfig.client
                    .from("stock_lots")
                    .delete()
                    .eq("stock_id", value: stockId.uuidString)
                    .execute()

                print("SupabaseManager: Updated existing stock \(newStock.ticker)")
            } else {
                // Insert new stock
                let insertData: [String: AnyEncodable] = [
                    "user_id": AnyEncodable(dbUserId.uuidString),
                    "ticker": AnyEncodable(committedStock.ticker.uppercased()),
                    "company_name": AnyEncodable(committedStock.companyName),
                    "purchase_price": AnyEncodable(committedStock.purchasePrice),
                    "shares": AnyEncodable(committedStock.shares),
                    "is_committed": AnyEncodable(true)
                ]
                let insertedStocks: [DBStock] = try await SupabaseConfig.client
                    .from("stocks")
                    .insert(insertData)
                    .select()
                    .execute()
                    .value

                guard let insertedStock = insertedStocks.first, let insertedId = insertedStock.id else {
                    print("SupabaseManager: Failed to get inserted stock ID")
                    return
                }
                stockId = insertedId
                print("SupabaseManager: Inserted new stock \(newStock.ticker) with ID \(stockId)")
            }

            // Insert lots
            for lot in committedStock.lots {
                let lotData: [String: AnyEncodable] = [
                    "stock_id": AnyEncodable(stockId.uuidString),
                    "account_name": AnyEncodable(lot.accountName),
                    "shares": AnyEncodable(lot.shares),
                    "purchase_price": AnyEncodable(lot.purchasePrice)
                ]
                try await SupabaseConfig.client
                    .from("stock_lots")
                    .insert(lotData)
                    .execute()
            }

            print("SupabaseManager: Successfully committed stock \(newStock.ticker) with \(committedStock.lots.count) lots")
        } catch {
            print("SupabaseManager: Error committing stock: \(error.localizedDescription)")
        }
    }

    /// Remove a stock from Supabase
    func removeStock(ticker: String) async {
        guard let dbUserId = dbUserId else {
            print("SupabaseManager: No user ID, cannot remove stock")
            return
        }

        print("SupabaseManager: Removing stock \(ticker)...")

        do {
            // CASCADE delete will handle stock_lots
            try await SupabaseConfig.client
                .from("stocks")
                .delete()
                .eq("user_id", value: dbUserId.uuidString)
                .eq("ticker", value: ticker.uppercased())
                .execute()

            print("SupabaseManager: Successfully removed stock \(ticker)")
        } catch {
            print("SupabaseManager: Error removing stock: \(error.localizedDescription)")
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
