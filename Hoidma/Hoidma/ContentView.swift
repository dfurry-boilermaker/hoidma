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
            // Clean black background like Robinhood
            Color.black
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Minimal header
                    HStack(spacing: 12) {
                        // Logo
                        Image("dave.folly")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)
                            .cornerRadius(6)
                        
                        Text("HOiDMA")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                    
                    if viewModel.stock?.isMaritalStatus == true && viewModel.currentPrice > 0 {
                        StockDisplayView(viewModel: viewModel, showingModal: $showingModal)
                    } else if showingCommitForm {
                        AddStockFormView(viewModel: viewModel, isPresented: $showingCommitForm)
                    } else {
                        InitialView(showingCommitForm: $showingCommitForm)
                    }
                }
            }

            // Divorce Modal
            if showingModal {
                DivorceModal(viewModel: viewModel, showingModal: $showingModal)
            }
        }
    }
}

// MARK: - Subviews

struct StockDisplayView: View {
    @ObservedObject var viewModel: StockViewModel
    @Binding var showingModal: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Ticker and delete button
            HStack {
                Text(viewModel.stock?.ticker ?? "N/A")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button {
                    showingModal = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.gray)
                        .padding(8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
            
            // Large price display - Robinhood style
            VStack(spacing: 8) {
                Text(viewModel.currentPrice, format: .currency(code: "USD"))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                HStack(spacing: 8) {
                    Text(viewModel.changePercent >= 0 ? "+" : "")
                    Text(viewModel.changePercent, format: .percent.precision(.fractionLength(2)))
                        .font(.system(size: 20, weight: .semibold))
                    Text("(\(viewModel.profitLoss, format: .currency(code: "USD")))")
                        .font(.system(size: 20, weight: .semibold))
                }
                .foregroundColor(viewModel.isGreen ? Color(red: 0.231, green: 0.706, blue: 0.494) : Color.red)
            }
            .padding(.bottom, 40)
            
            // Portfolio value card - clean and simple
            VStack(spacing: 12) {
                HStack {
                    Text("Portfolio Value")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    Spacer()
                }
                
                HStack {
                    Text(viewModel.currentPrice * Double(viewModel.stock?.shares ?? 0), format: .currency(code: "USD"))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
            }
            .padding(20)
            .background(Color(red: 0.1, green: 0.1, blue: 0.1))
            .cornerRadius(12)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            
            // Stats in simple rows
            VStack(spacing: 0) {
                StatRow(label: "Shares", value: "\(viewModel.stock?.shares ?? 0)")
                Divider().background(Color.gray.opacity(0.2))
                StatRow(label: "Avg Cost", value: viewModel.stock?.purchasePrice ?? 0, isCurrency: true)
                Divider().background(Color.gray.opacity(0.2))
                StatRow(label: "Total Cost", value: viewModel.stock?.totalCost ?? 0, isCurrency: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
            
            // Conviction message - simplified
            if !viewModel.convictionText.isEmpty {
                Text(viewModel.convictionText)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
    }
}

struct StatRow: View {
    let label: String
    let valueString: String?
    let value: Double?
    let isCurrency: Bool
    
    init(label: String, value: String) {
        self.label = label
        self.valueString = value
        self.value = nil
        self.isCurrency = false
    }
    
    init(label: String, value: Double, isCurrency: Bool = false) {
        self.label = label
        self.valueString = nil
        self.value = value
        self.isCurrency = isCurrency
    }
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.gray)
            Spacer()
            if let valueString = valueString {
                Text(valueString)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            } else if let value = value {
                if isCurrency {
                    Text(value, format: .currency(code: "USD"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                } else {
                    Text(value, format: .number)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.vertical, 16)
    }
}

struct InitialView: View {
    @Binding var showingCommitForm: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 16) {
                Text("No positions")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Start by adding a stock to track")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.gray)
            }
            .padding(.bottom, 40)
            
            Button {
                showingCommitForm = true
            } label: {
                Text("Add Stock")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color(red: 0.231, green: 0.706, blue: 0.494))
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            
            Spacer()
        }
    }
}

struct AddStockFormView: View {
    @ObservedObject var viewModel: StockViewModel
    @Binding var isPresented: Bool
    
    @State private var tickerInput: String = ""
    @State private var priceInput: String = ""
    @State private var sharesInput: String = ""
    @State private var commitError: String? = nil
    @FocusState private var focusedField: Field?
    
    enum Field {
        case ticker, price, shares
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    isPresented = false
                } label: {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Text("Add Stock")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button {
                    attemptCommit()
                } label: {
                    Text("Add")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(red: 0.231, green: 0.706, blue: 0.494))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 30)
            
            // Form fields - clean and simple
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Symbol")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    
                    TextField("TSLA", text: $tickerInput)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.white)
                        .textInputAutocapitalization(.characters)
                        .focused($focusedField, equals: .ticker)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color(red: 0.1, green: 0.1, blue: 0.1))
                        .cornerRadius(8)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Purchase Price")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    
                    HStack {
                        Text("$")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(.gray)
                        TextField("0.00", text: $priceInput)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(.white)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .price)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color(red: 0.1, green: 0.1, blue: 0.1))
                    .cornerRadius(8)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Shares")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    
                    TextField("0", text: $sharesInput)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.white)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .shares)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color(red: 0.1, green: 0.1, blue: 0.1))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 20)
            
            if let commitError = commitError {
                Text(commitError)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.red)
                    .padding(.top, 16)
            }
            
            Spacer()
        }
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
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    showingModal = false
                }
            
            VStack(spacing: 0) {
                Text("Remove Position")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                
                Text("Are you sure you want to remove \(viewModel.stock?.ticker ?? "this stock") from your portfolio?")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                
                VStack(spacing: 12) {
                    Button {
                        viewModel.unMarry()
                        showingModal = false
                    } label: {
                        Text("Remove")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.red)
                            .cornerRadius(12)
                    }
                    
                    Button {
                        showingModal = false
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color(red: 0.1, green: 0.1, blue: 0.1))
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Color(red: 0.05, green: 0.05, blue: 0.05))
            .cornerRadius(16)
            .padding(.horizontal, 20)
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

// MARK: - Preview
#Preview {
    ContentView()
}
