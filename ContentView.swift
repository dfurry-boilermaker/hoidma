import SwiftUI
import Combine

// --- 1. DATA MODELS & UTILITIES ---

/// Defines the data structure for a committed stock.
struct Stock: Codable {
    let ticker: String
    let purchasePrice: Double
    let shares: Int
    var isMaritalStatus: Bool = false
    
    // MARK: Financial Calculations
    
    var totalCost: Double {
        return purchasePrice * Double(shares)
    }
    
    // NOTE: This property is a placeholder for the live price in a real app.
    // In this simulation, we generate a mock price based on the purchase price.
    var mockCurrentPrice: Double {
        let initialSeedPrice = purchasePrice * 1.05
        let fluctuation = (Double.random(in: 0...1) - 0.5) * 0.4 // +/- 20% fluctuation
        return initialSeedPrice * (1 + fluctuation)
    }
}

/// Utility class to manage simulated database interaction.
class FirebaseManager: ObservableObject {
    // In a real app, you would initialize and connect to Firebase here.
    @Published var currentStock: Stock? = nil
    @Published var userId: String? = UUID().uuidString
    
    // MARK: Placeholder for Firebase functions

    // Placeholder for real-time listener (simulated by polling)
    func startDataListener() {
        print("--- FIREBASE MOCK: Starting data listener...")
        
        // Simulating loading a stock (if one was previously saved)
        if UserDefaults.standard.object(forKey: "committedStock") != nil {
            if let data = UserDefaults.standard.data(forKey: "committedStock"),
               let decodedStock = try? JSONDecoder().decode(Stock.self, from: data) {
                
                // Only load if it hasn't been 'un-married'
                if decodedStock.isMaritalStatus {
                     self.currentStock = decodedStock
                     print("FIREBASE MOCK: Found and loaded committed stock: \(decodedStock.ticker)")
                }
            }
        }
    }
    
    func commit(newStock: Stock) {
        print("FIREBASE MOCK: Committing stock \(newStock.ticker) to Firestore...")
        
        // In a real app, this would be a Firestore setDoc call.
        // Here, we use UserDefaults for simple persistence across sessions.
        var committedStock = newStock
        committedStock.isMaritalStatus = true // Officially married
        
        if let encoded = try? JSONEncoder().encode(committedStock) {
            UserDefaults.standard.set(encoded, forKey: "committedStock")
        }
        self.currentStock = committedStock
    }
    
    func unMarryStock() {
        print("FIREBASE MOCK: Removing commitment/Un-marrying stock...")
        
        // In a real app, this would update the Firestore document status.
        UserDefaults.standard.removeObject(forKey: "committedStock")
        self.currentStock = Stock(ticker: "DIVORCED", purchasePrice: 0, shares: 0, isMaritalStatus: false)
    }
}

// --- 2. MAIN VIEW MODEL (The Brain) ---

class StockViewModel: ObservableObject {
    @Published var stock: Stock?
    @Published var currentPrice: Double = 0
    @Published var changePercent: Double = 0
    @Published var profitLoss: Double = 0
    
    // Used to simulate price updates every 5 seconds
    private var timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
    // The placeholder Firebase Manager
    @ObservedObject var manager = FirebaseManager()
    
    init() {
        manager.startDataListener()
        
        // Monitor the committed stock from the Firebase Manager
        manager.$currentStock
            .sink { [weak self] newStock in
                self?.stock = newStock
                // Immediately update prices when a new stock is committed
                if newStock?.isMaritalStatus == true {
                    self?.updatePrice()
                }
            }
            .store(in: &cancellables)
        
        // Start the price simulation timer
        timer
            .sink { [weak self] _ in
                if self?.stock?.isMaritalStatus == true {
                    self?.updatePrice()
                }
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    func updatePrice() {
        guard let stock = stock, stock.isMaritalStatus else { return }
        
        let newPrice = stock.mockCurrentPrice
        let newProfitLoss = (newPrice * Double(stock.shares)) - stock.totalCost
        let newChangePercent = (newProfitLoss / stock.totalCost) * 100
        
        withAnimation {
            self.currentPrice = newPrice
            self.profitLoss = newProfitLoss
            self.changePercent = newChangePercent
        }
    }
    
    func commitStock(ticker: String, price: Double, shares: Int) {
        let newStock = Stock(ticker: ticker, purchasePrice: price, shares: shares)
        manager.commit(newStock: newStock)
    }
    
    func unMarry() {
        manager.unMarryStock()
        self.stock = nil
    }
    
    var isGreen: Bool {
        return profitLoss >= 0
    }
    
    var convictionText: String {
        guard let stock = stock, stock.isMaritalStatus else { return "Ready to commit?" }
        
        if changePercent < -25 {
            return "This price is a gift! If you truly believe, now is the time to finalize your conviction and *average down*."
        } else if changePercent < -10 {
            return "True conviction isn't measured in green. Stick to your thesis, or prepare to be labeled 'paper hands' forever!"
        } else if changePercent < 0 {
            return "Patience is a virtue. This is the ultimate test of your research. Hoidma (Hold Fast)!"
        } else if changePercent < 15 {
            return "A little green isn't enough to sell. You committed to the future, not a fleeting gain. Let the good times run!"
        } else {
            return "You're a genius! Now prove your long-term thesis by letting it run. The wedding party has just begun!"
        }
    }
}


// --- 3. SWIFTUI VIEWS ---

struct ContentView: View {
    // The main view model manages the state and logic
    @StateObject private var viewModel = StockViewModel()
    @State private var showingCommitForm = false
    @State private var showingModal = false
    
    var body: some View {
        ZStack {
            // Background for the whole app
            Color(red: 0.05, green: 0.05, blue: 0.1)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                HeaderView()
                
                if viewModel.stock?.isMaritalStatus == true && viewModel.currentPrice > 0 {
                    StockDisplayView(viewModel: viewModel, showingModal: $showingModal)
                } else if showingCommitForm {
                    AddStockFormView(viewModel: viewModel, isPresented: $showingCommitForm)
                } else {
                    InitialView(showingCommitForm: $showingCommitForm)
                }
                
                Spacer()
                
                // Footer for Persistence Status
                HStack {
                    Text("User ID: \(viewModel.manager.userId?.prefix(8) ?? "Loading")...")
                    Spacer()
                    Image(systemName: "internaldrive.fill")
                    Text("Data Persistence via Mock Database")
                }
                .font(.caption2)
                .foregroundColor(.gray)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color(red: 0.1, green: 0.1, blue: 0.15))
            .cornerRadius(20)
            .shadow(radius: 20)
            .padding()

            // Divorce Modal
            if showingModal {
                DivorceModal(viewModel: viewModel, showingModal: $showingModal)
            }
        }
    }
}

// MARK: - Subviews

struct HeaderView: View {
    var body: some View {
        HStack {
            Text("HOIDMA")
                .font(.largeTitle)
                .fontWeight(.heavy)
                .foregroundColor(Color.yellow)
            
            Spacer()
            
            Image(systemName: "diamond.fill")
                .foregroundColor(Color.yellow)
                .font(.title)
        }
        .padding()
        .background(Color(red: 0.15, green: 0.15, blue: 0.2))
        .cornerRadius(20, corners: [.topLeft, .topRight])
        .shadow(color: .black.opacity(0.3), radius: 5)
    }
}

struct StockDisplayView: View {
    @ObservedObject var viewModel: StockViewModel
    @Binding var showingModal: Bool
    
    var body: some View {
        VStack(spacing: 25) {
            HStack {
                Text(viewModel.stock?.ticker ?? "N/A")
                    .font(.system(size: 48, weight: .heavy))
                    .foregroundColor(viewModel.isGreen ? Color.green : Color.red)
                
                Spacer()
                
                Button {
                    showingModal = true
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal)
            
            VStack(spacing: 15) {
                StatCard(label: "Current Price", value: viewModel.currentPrice, isCurrency: true)
                StatCard(label: "Purchase Price", value: viewModel.stock?.purchasePrice ?? 0, isCurrency: true)
                StatCard(label: "Shares Owned", value: Double(viewModel.stock?.shares ?? 0), isCurrency: false)
                StatCard(label: "Total Cost", value: viewModel.stock?.totalCost ?? 0, isCurrency: true)
            }
            
            ProfitLossCard(viewModel: viewModel)
            
            ConvictionCard(text: viewModel.convictionText, isGreen: viewModel.isGreen)
        }
        .padding(.top, 20)
        .padding(.bottom, 10)
    }
}

struct StatCard: View {
    let label: String
    let value: Double
    let isCurrency: Bool
    
    var formattedValue: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = isCurrency ? .currency : .none
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = isCurrency ? 2 : 0
        return formatter.string(from: NSNumber(value: value)) ?? value.description
    }
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.gray)
                .font(.headline)
            Spacer()
            Text(formattedValue)
                .foregroundColor(.white)
                .font(.headline)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(red: 0.15, green: 0.15, blue: 0.25))
        .cornerRadius(10)
        .padding(.horizontal)
    }
}

struct ProfitLossCard: View {
    @ObservedObject var viewModel: StockViewModel
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("P/L (Total Value)")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            HStack(alignment: .lastTextBaseline) {
                Text(viewModel.profitLoss, format: .currency(code: "USD"))
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(viewModel.isGreen ? Color.green : Color.red)
                
                Text("(\(viewModel.changePercent, specifier: "%.2f")%)")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(viewModel.isGreen ? Color.green : Color.red)
                
                Spacer()
            }
            
            Text("Current Value: \(viewModel.currentPrice * Double(viewModel.stock?.shares ?? 0), format: .currency(code: "USD"))")
                .font(.callout)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color(red: 0.15, green: 0.15, blue: 0.25))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct ConvictionCard: View {
    let text: String
    let isGreen: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "diamond.fill")
                    .foregroundColor(.yellow)
                Text("Conviction Check")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            Text("“\(text)”")
                .font(.title3)
                .foregroundColor(.white)
                .italic()
        }
        .padding()
        .background(isGreen ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isGreen ? Color.green : Color.red, lineWidth: 2)
        )
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct InitialView: View {
    @Binding var showingCommitForm: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 80))
                .foregroundColor(.yellow)
                .padding(.top, 40)
            
            Text("Choose Your Life Partner")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Commit to a stock and practice **Hoidma** (The Art of Holding).")
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            Button {
                showingCommitForm = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Commit to a Stock")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.yellow)
                .foregroundColor(.black)
                .cornerRadius(30)
                .shadow(radius: 5)
            }
            .padding(.top, 10)
        }
        .padding(40)
    }
}

struct AddStockFormView: View {
    @ObservedObject var viewModel: StockViewModel
    @Binding var isPresented: Bool
    
    @State private var tickerInput: String = ""
    @State private var priceInput: String = ""
    @State private var sharesInput: String = ""
    @State private var commitError: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("The Vows")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            VStack(spacing: 15) {
                TextField("Ticker Symbol (e.g., TSLA)", text: $tickerInput)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
                    .foregroundColor(.white)
                
                TextField("Purchase Price per Share ($)", text: $priceInput)
                    .keyboardType(.decimalPad)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
                    .foregroundColor(.white)
                
                TextField("Number of Shares", text: $sharesInput)
                    .keyboardType(.numberPad)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
                    .foregroundColor(.white)
            }
            
            if let commitError = commitError {
                Text(commitError)
                    .foregroundColor(.red)
                    .padding(.top, 5)
            }
            
            Button {
                attemptCommit()
            } label: {
                Text("Finalize Commitment")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(30)
            }
            .buttonStyle(PlainButtonStyle())
            
            Button {
                isPresented = false
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 5)
                    .foregroundColor(.gray)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
    }
    
    private func attemptCommit() {
        guard let price = Double(priceInput), let shares = Int(sharesInput), !tickerInput.isEmpty else {
            commitError = "Please enter valid numbers and a ticker symbol."
            return
        }
        
        // Call the view model to commit and dismiss the form
        viewModel.commitStock(ticker: tickerInput.uppercased(), price: price, shares: shares)
        isPresented = false
    }
}

struct DivorceModal: View {
    @ObservedObject var viewModel: StockViewModel
    @Binding var showingModal: Bool
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                Text("Divorce Proceedings")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
                
                Text("Are you sure you want to end your commitment to **\(viewModel.stock?.ticker ?? "the stock")**? Realizing the loss (or gain) means admitting you were wrong (or right, but impatient). This action is non-reversible!")
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 20) {
                    Button("Stay Married (Cancel)") {
                        showingModal = false
                    }
                    .padding()
                    .background(Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    
                    Button {
                        viewModel.unMarry()
                        showingModal = false
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Un-Marry Now")
                        }
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
            }
            .padding(30)
            .background(Color(red: 0.1, green: 0.1, blue: 0.15))
            .cornerRadius(20)
            .shadow(radius: 20)
            .padding(40)
        }
    }
}

// Extension to allow setting custom rounded corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

// Xcode Live Preview Setup
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
