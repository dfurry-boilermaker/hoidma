import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

/// Manages Firestore database interactions for user portfolios
class FirebaseManager: ObservableObject {
    @Published var stocks: [Stock] = []
    @Published var userId: String?
    
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    
    init() {
        // Listen for auth state changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                if let uid = user?.uid {
                    self?.userId = uid
                    self?.startDataListener()
                } else {
                    self?.userId = nil
                    self?.stopDataListener()
                    self?.stocks = []
                }
            }
        }
        
        // Check initial auth state
        if let uid = Auth.auth().currentUser?.uid {
            self.userId = uid
            startDataListener()
        }
    }
    
    deinit {
        stopDataListener()
    }
    
    /// Start listening to user's portfolio data in Firestore
    func startDataListener() {
        guard let userId = userId else {
            print("FirebaseManager: No user ID, cannot start listener")
            return
        }
        
        // Stop existing listener if any
        stopDataListener()
        
        print("FirebaseManager: Starting data listener for user \(userId)...")
        
        // Listen to user's portfolio collection
        listener = db.collection("portfolios")
            .document(userId)
            .collection("stocks")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("FirebaseManager: Error listening to stocks: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("FirebaseManager: No documents found")
                    self.stocks = []
                    return
                }
                
                // Decode stocks from Firestore documents
                var decodedStocks: [Stock] = []
                for document in documents {
                    do {
                        let stock = try document.data(as: Stock.self)
                        decodedStocks.append(stock)
                    } catch {
                        print("FirebaseManager: Error decoding stock \(document.documentID): \(error.localizedDescription)")
                    }
                }
                
                DispatchQueue.main.async {
                    // Only show stocks that are committed (isMaritalStatus = true)
                    self.stocks = decodedStocks.filter { $0.isMaritalStatus }
                    print("FirebaseManager: Loaded \(self.stocks.count) committed stocks")
                }
            }
    }
    
    /// Stop listening to Firestore updates
    func stopDataListener() {
        listener?.remove()
        listener = nil
    }
    
    /// Commit a stock to Firestore
    func commit(newStock: Stock) {
        guard let userId = userId else {
            print("FirebaseManager: No user ID, cannot commit stock")
            return
        }
        
        print("FirebaseManager: Committing stock \(newStock.ticker) to Firestore...")
        
        var committedStock = newStock
        committedStock.isMaritalStatus = true // Officially committed
        
        do {
            // Use ticker as document ID for easy updates
            try db.collection("portfolios")
                .document(userId)
                .collection("stocks")
                .document(newStock.ticker.uppercased())
                .setData(from: committedStock) { error in
                    if let error = error {
                        print("FirebaseManager: Error committing stock: \(error.localizedDescription)")
                    } else {
                        print("FirebaseManager: Successfully committed stock \(newStock.ticker)")
                    }
                }
        } catch {
            print("FirebaseManager: Error encoding stock: \(error.localizedDescription)")
        }
    }
    
    /// Remove a stock from Firestore
    func removeStock(ticker: String) {
        guard let userId = userId else {
            print("FirebaseManager: No user ID, cannot remove stock")
            return
        }
        
        print("FirebaseManager: Removing stock \(ticker)...")
        
        db.collection("portfolios")
            .document(userId)
            .collection("stocks")
            .document(ticker.uppercased())
            .delete { error in
                if let error = error {
                    print("FirebaseManager: Error removing stock: \(error.localizedDescription)")
                } else {
                    print("FirebaseManager: Successfully removed stock \(ticker)")
                }
            }
    }
}

