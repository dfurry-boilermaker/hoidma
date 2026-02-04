import SwiftUI
import UIKit
import Combine

enum NavigationDestination: Hashable {
    case stockDetail(Stock)
    case accountDetail(AccountSummary)
}

struct ContentView: View {
    @ObservedObject var viewModel: StockViewModel
    @EnvironmentObject var authManager: SupabaseAuthManager
    @EnvironmentObject var biometricAuth: BiometricAuthManager
    @State private var showingCommitForm = false
    @State private var showingModal = false
    @State private var selectedTicker: String? = nil
    @State private var navigationPath = NavigationPath()
    @AppStorage("appearanceMode") private var appearanceMode: Int = AppearanceMode.auto.rawValue
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("selectedTab") private var selectedTab: Int = 1
    @State private var previousTab: Int = 1
    @State private var slideDirection: SlideDirection = .none
    @State private var showScrollButton: Bool = false
    @State private var initialScrollOffset: CGFloat? = nil
    @State private var showSignOutAlert = false
    @State private var selectedAccountName: String? = nil
    @State private var showDollarAmounts: Bool = false
    private let scrollThreshold: CGFloat = 50

    enum SlideDirection {
        case none, left, right
    }

    // Computed property for effective dark mode based on appearance setting
    private var isDarkMode: Bool {
        let mode = AppearanceMode(rawValue: appearanceMode) ?? .auto
        switch mode {
        case .light:
            return false
        case .dark:
            return true
        case .auto:
            return systemColorScheme == .dark
        }
    }

    // Color scheme for preferredColorScheme modifier (nil for auto to use system)
    private var preferredScheme: ColorScheme? {
        let mode = AppearanceMode(rawValue: appearanceMode) ?? .auto
        switch mode {
        case .light:
            return .light
        case .dark:
            return .dark
        case .auto:
            return nil
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Tab content with slide transitions
                    // Tab order: Portfolio (1), Visuals (2), Charts (3), Accounts (4), Profile (5)
                    ZStack {
                        if selectedTab == 1 {
                            PortfolioTabContent(
                                viewModel: viewModel,
                                showingModal: $showingModal,
                                showingCommitForm: $showingCommitForm,
                                selectedTicker: $selectedTicker,
                                navigationPath: $navigationPath,
                                selectedTab: $selectedTab,
                                showScrollButton: $showScrollButton,
                                initialScrollOffset: $initialScrollOffset,
                                scrollThreshold: scrollThreshold
                            )
                            .transition(slideTransition)
                        }

                        if selectedTab == 2 {
                            PortfolioVisualizationsView(viewModel: viewModel, selectedTab: $selectedTab, selectedAccountName: $selectedAccountName, showDollarAmounts: $showDollarAmounts, navigationPath: $navigationPath)
                                .transition(slideTransition)
                        }

                        if selectedTab == 3 {
                            ChartsView(viewModel: viewModel, selectedTab: $selectedTab, showDollarAmounts: $showDollarAmounts)
                                .transition(slideTransition)
                        }

                        if selectedTab == 4 {
                            AccountsView(viewModel: viewModel, selectedTab: $selectedTab, navigationPath: $navigationPath, selectedAccountName: $selectedAccountName)
                                .transition(slideTransition)
                        }

                        if selectedTab == 5 {
                            ProfileView(selectedTab: $selectedTab)
                                .transition(slideTransition)
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: selectedTab)

                    // Bottom navigation bar
                    BottomNavigationBar(selectedTab: $selectedTab) { tabNumber in
                        if tabNumber != selectedTab {
                            previousTab = selectedTab
                            slideDirection = tabNumber > selectedTab ? .left : .right
                            selectedTab = tabNumber
                        }
                    }
                }

                // Fixed header (show on all tabs)
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        // Solid background
                        Color(UIColor.systemBackground)
                            .frame(maxWidth: .infinity)
                            .frame(height: 120)
                            .ignoresSafeArea(edges: .top)

                        HStack {
                            Image(isDarkMode ? "hoidma.dark" : "hoidma")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 100, height: 50)
                                .cornerRadius(8)
                                .padding(.leading, 16)
                                .onLongPressGesture {
                                    showSignOutAlert = true
                                }

                            Spacer()
                        }

                        Button {
                            withAnimation {
                                // Toggle between light and dark only (auto is set in profile)
                                if isDarkMode {
                                    appearanceMode = AppearanceMode.light.rawValue
                                } else {
                                    appearanceMode = AppearanceMode.dark.rawValue
                                }
                            }
                        } label: {
                            Image(isDarkMode ? "dave.folly.logo.dark" : "dave.folly.logo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 50)
                        }
                    }

                    Spacer()
                }

                // Add button at top-right (on tab 1 and tab 4 - Portfolio and Accounts)
                if selectedTab == 1 || selectedTab == 4 {
                    VStack {
                        HStack {
                            Spacer()

                            Button {
                                showingCommitForm = true
                            } label: {
                                Image(isDarkMode ? "add.button.dark" : "add.button")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 70, height: 43)
                            }
                            .padding(.trailing, 16)
                            .padding(.top, 4)
                        }

                        Spacer()
                    }
                }

                // Dollar/percentage toggle at top-right (on tabs 2 and 3)
                if (selectedTab == 2 || selectedTab == 3) && viewModel.totalPortfolioValue > 0 {
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                withAnimation {
                                    showDollarAmounts.toggle()
                                }
                            } label: {
                                Image(isDarkMode ? (showDollarAmounts ? "dollar.dark" : "percentage.dark") : (showDollarAmounts ? "dollar" : "percentage"))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 24, height: 24)
                            }
                            .padding(.trailing, 16)
                            .padding(.top, 14)
                        }
                        Spacer()
                    }
                }

                // Remove Stock Modal
                if showingModal, let ticker = selectedTicker {
                    RemoveStockModal(viewModel: viewModel, showingModal: $showingModal, ticker: ticker)
                }
            }
            .navigationBarHidden(true)
            .preferredColorScheme(preferredScheme)
            .navigationDestination(for: NavigationDestination.self) { destination in
                switch destination {
                case .stockDetail(let stock):
                    StockDetailView(
                        stock: stock,
                        priceData: viewModel.stockPrices[stock.ticker],
                        viewModel: viewModel,
                        navigationPath: $navigationPath
                    )
                case .accountDetail(let account):
                    AccountDetailView(
                        account: account,
                        totalAllAccounts: viewModel.totalPortfolioValue,
                        viewModel: viewModel,
                        navigationPath: $navigationPath
                    )
                }
            }
            .sheet(isPresented: $showingCommitForm) {
                AddStockFormView(viewModel: viewModel, isPresented: $showingCommitForm)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .confirmationDialog("Settings", isPresented: $showSignOutAlert, titleVisibility: .visible) {
                if biometricAuth.canUseBiometrics {
                    Button(biometricAuth.biometricAuthEnabled ? "Disable \(biometricAuth.biometricTypeName)" : "Enable \(biometricAuth.biometricTypeName)") {
                        biometricAuth.biometricAuthEnabled.toggle()
                    }
                }
                Button("Sign Out", role: .destructive) {
                    Task {
                        do {
                            try await authManager.signOut()
                        } catch {
                            AppLogger.error("Error signing out: \(error.localizedDescription)")
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                if biometricAuth.canUseBiometrics {
                    Text("\(biometricAuth.biometricTypeName) is \(biometricAuth.biometricAuthEnabled ? "enabled" : "disabled")")
                }
            }
        }
    }

    private var slideTransition: AnyTransition {
        switch slideDirection {
        case .left:
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
        case .right:
            return .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing)
            )
        case .none:
            return .opacity
        }
    }
}

// MARK: - Portfolio Tab Content
private struct PortfolioTabContent: View {
    @ObservedObject var viewModel: StockViewModel
    @Binding var showingModal: Bool
    @Binding var showingCommitForm: Bool
    @Binding var selectedTicker: String?
    @Binding var navigationPath: NavigationPath
    @Binding var selectedTab: Int
    @Binding var showScrollButton: Bool
    @Binding var initialScrollOffset: CGFloat?
    let scrollThreshold: CGFloat

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: ScrollOffsetPreferenceKey.self, value: geometry.frame(in: .named("scroll")).minY)
                }
                .frame(height: 0)

                Spacer()
                    .frame(height: 78)

                PortfolioView(
                    viewModel: viewModel,
                    showingModal: $showingModal,
                    showingCommitForm: $showingCommitForm,
                    selectedTicker: $selectedTicker,
                    navigationPath: $navigationPath
                )
            }
            .padding(.bottom, 50)
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            if initialScrollOffset == nil {
                initialScrollOffset = value
            }

            if let initial = initialScrollOffset {
                let scrollAmount = initial - value
                withAnimation(.easeInOut(duration: 0.2)) {
                    showScrollButton = scrollAmount > scrollThreshold
                }
            }
        }
        .simultaneousGesture(
            DragGesture()
                .onEnded { gesture in
                    // Swipe left to go to visualizations page (tab 2)
                    if gesture.translation.width < -100 && abs(gesture.translation.height) < 50 {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedTab = 2
                        }
                    }
                }
        )
    }
}

// MARK: - Preview Helpers

// Helper for sheet binding
struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
    init(_ value: String) {
        self.value = value
    }
}

/// Mock StockViewModel for previews with sample data
class MockStockViewModel: StockViewModel {
    private var mockCancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        // Stop Firebase manager
        manager.stopDataListener()
        // Setup mock data immediately
        setupMockData()
        // Start mock price updates
        startMockPriceUpdates()
    }
    
    // Override to simulate price updates instead of calling API
    override func updateAllPrices() async {
        // Simulate price changes with small random variations
        await MainActor.run {
            for stock in stocks.filter({ $0.isMaritalStatus }) {
                guard var priceData = stockPrices[stock.ticker] else { continue }
                
                // Simulate small price movement (±2%)
                let changePercent = Double.random(in: -2.0...2.0)
                let newPrice = priceData.currentPrice * (1 + changePercent / 100)
                let profitLoss = (newPrice * Double(stock.shares)) - stock.totalCost
                let newChangePercent = (profitLoss / stock.totalCost) * 100
                
                // Update price data
                priceData.currentPrice = newPrice
                priceData.changePercent = newChangePercent
                priceData.profitLoss = profitLoss
                
                // Update period changes slightly
                priceData.apiPeriodChanges["1d"] = (priceData.apiPeriodChanges["1d"] ?? 0) + changePercent
                
                stockPrices[stock.ticker] = priceData
            }
        }
    }
    
    private func startMockPriceUpdates() {
        // Update prices every 5 seconds for testing (faster than real API)
        Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.updateAllPrices()
                }
            }
            .store(in: &mockCancellables)
    }
    
    private func setupMockData() {
        // Create mock stocks with sample data
        let fakeStockLots: [(ticker: String, companyName: String, price: Double, shares: Double, account: String)] = [
            // Stocks in single accounts
            ("GOOGL", "Alphabet Inc.", 140.75, 25, "Roth IRA"),
            ("AMZN", "Amazon.com Inc.", 145.00, 40, "Indv"),
            ("META", "Meta Platforms Inc.", 320.00, 35, "Roth IRA"),
            ("TSLA", "Tesla Inc.", 245.75, 60, "Indv"),
            ("JPM", "JPMorgan Chase & Co.", 155.25, 45, "401k"),
            ("V", "Visa Inc.", 250.00, 30, "Roth IRA"),
            ("JNJ", "Johnson & Johnson", 160.50, 50, "Indv"),
            ("WMT", "Walmart Inc.", 165.75, 40, "401k"),
            ("PG", "Procter & Gamble Co.", 150.00, 35, "Roth IRA"),
            ("MA", "Mastercard Inc.", 420.25, 25, "Indv"),
            ("DIS", "The Walt Disney Company", 95.50, 70, "401k"),
            ("NFLX", "Netflix Inc.", 425.00, 20, "Roth IRA"),
            
            // Shared positions - MSFT in multiple accounts
            ("MSFT", "Microsoft Corporation", 380.25, 30, "401k"),
            ("MSFT", "Microsoft Corporation", 385.00, 25, "Roth IRA"),
            
            // Shared positions - AAPL in multiple accounts
            ("AAPL", "Apple Inc.", 175.50, 50, "Indv"),
            ("AAPL", "Apple Inc.", 176.00, 40, "401k"),
            
            // Shared positions - NVDA in multiple accounts
            ("NVDA", "NVIDIA Corporation", 485.50, 20, "401k"),
            ("NVDA", "NVIDIA Corporation", 490.00, 15, "Roth IRA"),
        ]
        
        // Create stocks array, grouping by ticker to handle multiple lots
        var stocksDict: [String: (companyName: String, lots: [StockLot])] = [:]
        
        for stockLot in fakeStockLots {
            let lot = StockLot(accountName: stockLot.account, shares: stockLot.shares, purchasePrice: stockLot.price)
            
            if var existing = stocksDict[stockLot.ticker] {
                // Add lot to existing stock
                existing.lots.append(lot)
                stocksDict[stockLot.ticker] = existing
            } else {
                // Create new stock entry
                stocksDict[stockLot.ticker] = (companyName: stockLot.companyName, lots: [lot])
            }
        }
        
        // Convert dictionary to Stock array
        var mockStocks: [Stock] = []
        for (ticker, data) in stocksDict {
            let totalShares = data.lots.reduce(0.0) { $0 + $1.shares }
            let totalCost = data.lots.reduce(0.0) { $0 + $1.totalCost }
            let averagePurchasePrice = totalShares > 0 ? totalCost / totalShares : 0
            
            let newStock = Stock(
                ticker: ticker,
                companyName: data.companyName,
                purchasePrice: averagePurchasePrice,
                shares: Int(totalShares),
                isMaritalStatus: true,
                lots: data.lots
            )
            mockStocks.append(newStock)
        }
        
        // Set stocks
        self.stocks = mockStocks
        
        // Create mock price data for each stock
        let now = Date()
        for stock in mockStocks {
            let currentPrice = stock.purchasePrice * Double.random(in: 0.85...1.25) // Random price variation
            let profitLoss = (currentPrice * Double(stock.shares)) - stock.totalCost
            let changePercent = (profitLoss / stock.totalCost) * 100
            
            self.stockPrices[stock.ticker] = StockPriceData(
                ticker: stock.ticker,
                currentPrice: currentPrice,
                changePercent: changePercent,
                profitLoss: profitLoss,
                dailyStartPrice: stock.purchasePrice * 0.98,
                weeklyStartPrice: stock.purchasePrice * 0.95,
                monthlyStartPrice: stock.purchasePrice * 0.92,
                threeMonthsStartPrice: stock.purchasePrice * 0.88,
                ytdStartPrice: stock.purchasePrice * 0.85,
                allTimeStartPrice: stock.purchasePrice,
                dailyStartTime: now,
                weeklyStartTime: now,
                monthlyStartTime: now,
                threeMonthsStartTime: now,
                ytdStartTime: now,
                allTimeStartTime: now,
                apiPeriodChanges: [
                    "1d": Double.random(in: -5...5),
                    "1w": Double.random(in: -10...10),
                    "1m": Double.random(in: -15...15),
                    "3m": Double.random(in: -20...20),
                    "ytd": Double.random(in: -25...25)
                ],
                previousClose: currentPrice * 0.99
            )
        }
    }
}

/// Mock AuthManager for previews (extends SupabaseAuthManager)
class MockAuthManager: SupabaseAuthManager {
    override init() {
        super.init()
        // Set mock authenticated state
        self.isAuthenticated = true
        self.email = "test@example.com"
    }
}

// MARK: - Preview
#Preview("Main Screen with Mock Data") {
    PreviewContent()
}

struct PreviewContent: View {
    @StateObject private var mockViewModel = MockStockViewModel()
    @StateObject private var mockAuthManager = MockAuthManager()
    @StateObject private var mockBiometricAuth = BiometricAuthManager()

    var body: some View {
        ContentView(viewModel: mockViewModel)
            .environmentObject(mockAuthManager)
            .environmentObject(mockBiometricAuth)
    }
}

// Preview-specific PortfolioView that works with MockStockViewModel
struct PortfolioViewPreviewContent: View {
    @ObservedObject var viewModel: MockStockViewModel
    @Binding var showingModal: Bool
    @Binding var showingCommitForm: Bool
    @Binding var selectedTicker: String?
    @Binding var navigationPath: NavigationPath
    @State private var selectedPeriod: TimePeriod = .daily
    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool { colorScheme == .dark }

    var periodReturn: (value: Double, percent: Double) {
        viewModel.totalReturnForPeriod(selectedPeriod)
    }
    
    var dayReturn: (value: Double, percent: Double) {
        viewModel.totalReturnForPeriod(.daily)
    }
    
    var totalReturn: (value: Double, percent: Double) {
        viewModel.totalReturnForPeriod(.allTime)
    }
    
    var sortedStocks: [Stock] {
        viewModel.stocks
            .filter { $0.isMaritalStatus }
            .filter { stock in
                let totalShares = stock.lots.isEmpty ? Double(stock.shares) : stock.lots.reduce(0.0) { $0 + $1.shares }
                return totalShares > 0
            }
            .sorted { stock1, stock2 in
                let totalShares1 = stock1.lots.isEmpty ? Double(stock1.shares) : stock1.lots.reduce(0.0) { $0 + $1.shares }
                let totalShares2 = stock2.lots.isEmpty ? Double(stock2.shares) : stock2.lots.reduce(0.0) { $0 + $1.shares }
                
                let price1 = viewModel.stockPrices[stock1.ticker]?.currentPrice ?? 0.0
                let price2 = viewModel.stockPrices[stock2.ticker]?.currentPrice ?? 0.0
                
                let totalValue1 = price1 * totalShares1
                let totalValue2 = price2 * totalShares2
                
                return totalValue1 > totalValue2
            }
    }
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        // Portfolio summary card
                        VStack(spacing: 12) {
                            HStack {
                                Text(viewModel.totalPortfolioValue, format: .currency(code: "USD"))
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(Color.primary)
                                Spacer()
                            }
                            
                            // Gains section
                            HStack(alignment: .top, spacing: 0) {
                                VStack(spacing: 0) {
                                    HStack(spacing: 4) {
                                        Text(dayReturn.value >= 0 ? "+" : "")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(dayReturn.value >= 0 ? AppColors.positive : Color.red)
                                        Text(dayReturn.value, format: .currency(code: "USD"))
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(dayReturn.value >= 0 ? AppColors.positive : Color.red)
                                        Text("(\(dayReturn.percent >= 0 ? "+" : "")\(String(format: "%.2f", dayReturn.percent))%)")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(dayReturn.value >= 0 ? AppColors.positive : Color.red)
                                        Text("1D")
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(Color.secondary)
                                        Spacer()
                                    }
                                    
                                    HStack(spacing: 4) {
                                        Text(totalReturn.value >= 0 ? "+" : "")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(totalReturn.value >= 0 ? AppColors.positive : Color.red)
                                        Text(totalReturn.value, format: .currency(code: "USD"))
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(totalReturn.value >= 0 ? AppColors.positive : Color.red)
                                        Text("(\(totalReturn.percent >= 0 ? "+" : "")\(String(format: "%.2f", totalReturn.percent))%)")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(totalReturn.value >= 0 ? AppColors.positive : Color.red)
                                        Text("All")
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(Color.secondary)
                                        Spacer()
                                    }
                                    .padding(.top, 2)
                                }
                                
                                Spacer()
                                
                                if sortedStocks.count > 0 {
                                    Button {
                                        showingCommitForm = true
                                    } label: {
                                        Image(isDarkMode ? "add.button.dark" : "add.button")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 65, height: 40)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                        
                        // Portfolio Diversity section
                        VStack(spacing: 12) {
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    if viewModel.totalPortfolioValue == 0 {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.gray.opacity(isDarkMode ? 0.3 : 0.15))
                                            .frame(height: 3)
                                    }

                                    if viewModel.totalPortfolioValue > 0 {
                                        HStack(spacing: 0) {
                                            ForEach(sortedStocks, id: \.ticker) { stock in
                                                if let priceData = viewModel.stockPrices[stock.ticker] {
                                                    let totalShares = stock.lots.isEmpty ? Double(stock.shares) : stock.lots.reduce(0.0) { $0 + $1.shares }
                                                    let stockValue = priceData.currentPrice * totalShares
                                                    let portfolioPercentage = min((stockValue / viewModel.totalPortfolioValue), 1.0)

                                                    if portfolioPercentage > 0 {
                                                        RoundedRectangle(cornerRadius: 6)
                                                            .fill(colorForTicker(stock.ticker))
                                                            .frame(width: max(geometry.size.width * portfolioPercentage, 0), height: 3)
                                                    }
                                                }
                                            }
                                        }
                                        .frame(maxWidth: geometry.size.width, alignment: .leading)
                                        .clipped()
                                    }
                                }
                            }
                            .frame(height: 3)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                        
                        // Stock positions list
                        VStack(spacing: 0) {
                            ForEach(Array(sortedStocks.enumerated()), id: \.element.ticker) { index, stock in
                                VStack(spacing: 0) {
                                    NavigationLink(destination: Text("Stock Detail Preview")) {
                                        StockPositionRow(
                                            stock: stock,
                                            priceData: viewModel.stockPrices[stock.ticker],
                                            totalPortfolioValue: viewModel.totalPortfolioValue,
                                            selectedPeriod: selectedPeriod,
                                            onRemove: {
                                                selectedTicker = stock.ticker
                                                showingModal = true
                                            }
                                        )
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    if index < sortedStocks.count - 1 {
                                        Divider()
                                            .padding(.leading, 20)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// Preference key to track scroll offset
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
