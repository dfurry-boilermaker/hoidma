import Foundation
import Combine

/// Utility class to manage simulated database interaction.
class FirebaseManager: ObservableObject {
    // In a real app, you would initialize and connect to Firebase here.
    @Published var stocks: [Stock] = []
    @Published var userId: String? = UUID().uuidString
    
    // MARK: Placeholder for Firebase functions

    // Placeholder for real-time listener (simulated by polling)
    func startDataListener() {
        print("--- FIREBASE MOCK: Starting data listener...")
        
        // Load all committed stocks
        if let data = UserDefaults.standard.data(forKey: "committedStocks"),
           let decodedStocks = try? JSONDecoder().decode([Stock].self, from: data) {
            self.stocks = decodedStocks.filter { $0.isMaritalStatus }
            print("FIREBASE MOCK: Loaded \(self.stocks.count) committed stocks")
        }
    }
    
    func commit(newStock: Stock) {
        print("FIREBASE MOCK: Committing stock \(newStock.ticker) to Firestore...")
        
        // In a real app, this would be a Firestore setDoc call.
        // Here, we use UserDefaults for simple persistence across sessions.
        var committedStock = newStock
        committedStock.isMaritalStatus = true // Officially married
        
        // Check if stock already exists (by ticker)
        if let existingIndex = stocks.firstIndex(where: { $0.ticker == newStock.ticker }) {
            stocks[existingIndex] = committedStock
        } else {
            stocks.append(committedStock)
        }
        
        // Save to UserDefaults
        if let encoded = try? JSONEncoder().encode(stocks) {
            UserDefaults.standard.set(encoded, forKey: "committedStocks")
        }
    }
    
    func removeStock(ticker: String) {
        print("FIREBASE MOCK: Removing stock \(ticker)...")
        
        stocks.removeAll { $0.ticker == ticker }
        
        // Save to UserDefaults
        if let encoded = try? JSONEncoder().encode(stocks) {
            UserDefaults.standard.set(encoded, forKey: "committedStocks")
        }
    }
}

