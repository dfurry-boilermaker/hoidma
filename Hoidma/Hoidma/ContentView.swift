import SwiftUI
import UIKit

// Helper function to generate consistent colors for ticker symbols
private func colorForTicker(_ ticker: String) -> Color {
    // Generate a consistent color based on the ticker symbol
    // This creates a hash from the ticker and converts it to RGB values
    var hash = 0
    for char in ticker.uppercased() {
        hash = Int(char.asciiValue ?? 0) + ((hash << 5) - hash)
    }
    
    // Ensure hash is positive
    hash = abs(hash)
    
    // Use modulo to get better distribution for RGB components
    // This ensures we get a good range of colors
    let r = Double((hash & 0xFF0000) >> 16) / 255.0
    let g = Double((hash & 0x00FF00) >> 8) / 255.0
    let b = Double(hash & 0x0000FF) / 255.0
    
    // Use HSL-like approach for better color vibrancy
    // Calculate brightness and adjust to ensure visibility
    let brightness = (r * 0.299 + g * 0.587 + b * 0.114)
    let minBrightness: Double = 0.4
    let maxBrightness: Double = 0.85
    
    // Adjust brightness while maintaining color relationships
    var adjustedR = r
    var adjustedG = g
    var adjustedB = b
    
    if brightness < minBrightness {
        // Too dark - brighten proportionally
        let scale = minBrightness / brightness
        adjustedR = min(r * scale, 1.0)
        adjustedG = min(g * scale, 1.0)
        adjustedB = min(b * scale, 1.0)
    } else if brightness > maxBrightness {
        // Too light - darken proportionally
        let scale = maxBrightness / brightness
        adjustedR = r * scale
        adjustedG = g * scale
        adjustedB = b * scale
    }
    
    // Ensure minimum values for visibility
    adjustedR = max(adjustedR, 0.2)
    adjustedG = max(adjustedG, 0.2)
    adjustedB = max(adjustedB, 0.2)
    
    return Color(red: adjustedR, green: adjustedG, blue: adjustedB)
}

enum NavigationDestination: Hashable {
    case portfolioVisualizations
}

struct ContentView: View {
    // The main view model manages the state and logic
    @StateObject private var viewModel = StockViewModel()
    @State private var showingCommitForm = false
    @State private var showingModal = false
    @State private var selectedTicker: String? = nil
    @State private var navigationPath = NavigationPath()
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @AppStorage("selectedTab") private var selectedTab: Int = 1
    @State private var showScrollButton: Bool = false
    @State private var initialScrollOffset: CGFloat? = nil
    private let scrollThreshold: CGFloat = 50 // Show button after scrolling 50 points (reduced for easier testing)
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
        ZStack {
            // Adaptive background
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        // GeometryReader to track scroll position for button visibility
                        GeometryReader { geometry in
                            Color.clear
                                .preference(key: ScrollOffsetPreferenceKey.self, value: geometry.frame(in: .named("scroll")).minY)
                        }
                        .frame(height: 0)
                        
                        // Spacer to account for sticky header height
                        Spacer()
                            .frame(height: 78) // Reduced height to move content up
                        
                        PortfolioView(viewModel: viewModel, showingModal: $showingModal, showingCommitForm: $showingCommitForm, selectedTicker: $selectedTicker, navigationPath: $navigationPath)
                    }
                    .padding(.bottom, 50)
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    let offset = value
                    
                    // Track initial offset (when at top of scroll)
                    if initialScrollOffset == nil {
                        initialScrollOffset = offset
                    }
                    
                    // Calculate how far we've scrolled from the initial position
                    if let initial = initialScrollOffset {
                        let scrollAmount = initial - offset // Positive when scrolled down
                        
                        // Show button when scrolled past threshold (scrolled down enough)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showScrollButton = scrollAmount > scrollThreshold
                        }
                    }
                }
                .sheet(isPresented: $showingCommitForm) {
                    AddStockFormView(viewModel: viewModel, isPresented: $showingCommitForm)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
                // Bottom navigation bar
                BottomNavigationBar(selectedTab: $selectedTab) { tabNumber in
                    // Navigation logic
                    if tabNumber == 1 {
                        // Navigate to main page (pop to root)
                        navigationPath.removeLast(navigationPath.count)
                    } else if tabNumber == 2 {
                        // Navigate to portfolio visualizations view
                        navigationPath.append(NavigationDestination.portfolioVisualizations)
                    }
                    // Tabs 3 and 4 - functionality to be added later
                }
            }
            
            // Fixed header with both logos (hides/shows based on scroll direction)
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    // Background to prevent content showing through - extends to top (renders first, behind everything)
                    Color(UIColor.systemBackground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 120) 
                        .ignoresSafeArea(edges: .top)
                    
                    // Hoidma logo at top-left
                    HStack {
                        Image(isDarkMode ? "hoidma.dark" : "hoidma")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 50)
                            .cornerRadius(8)
                            .padding(.leading, 16)
                        
                        Spacer()
                    }
                    
                    // Dave.folly logo centered - tap to toggle dark mode
                    Button {
                        withAnimation {
                            isDarkMode.toggle()
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
            
            // Add button at top-right - appears after scrolling threshold (fixed position)
            VStack {
                HStack {
                    Spacer()
                    
                    let hasStocks = viewModel.stocks.filter { $0.isMaritalStatus }.contains { stock in
                        let totalShares = stock.lots.isEmpty ? Double(stock.shares) : stock.lots.reduce(0.0) { $0 + $1.shares }
                        return totalShares > 0
                    }
                    
                    if showScrollButton && hasStocks {
                        Button {
                            showingCommitForm = true
                        } label: {
                            Image(isDarkMode ? "add.button.dark" : "add.button")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 55, height: 34)
                        }
                        .padding(.trailing, 16)
                        .padding(.top, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                
                Spacer()
            }

            // Remove Stock Modal
            if showingModal, let ticker = selectedTicker {
                RemoveStockModal(viewModel: viewModel, showingModal: $showingModal, ticker: ticker)
            }
        }
            .navigationBarHidden(true)
            .preferredColorScheme(isDarkMode ? .dark : .light)
            .navigationDestination(for: NavigationDestination.self) { destination in
                switch destination {
                case .portfolioVisualizations:
                    PortfolioVisualizationsView(viewModel: viewModel)
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    // Create 15 fake stocks for testing
    let fakeStocks: [(ticker: String, companyName: String, price: Double, shares: Double, account: String)] = [
        ("AAPL", "Apple Inc.", 175.50, 50, "Indv"),
        ("MSFT", "Microsoft Corporation", 380.25, 30, "401k"),
        ("GOOGL", "Alphabet Inc.", 140.75, 25, "Roth IRA"),
        ("AMZN", "Amazon.com Inc.", 145.00, 40, "Indv"),
        ("NVDA", "NVIDIA Corporation", 485.50, 20, "401k"),
        ("META", "Meta Platforms Inc.", 320.00, 35, "Roth IRA"),
        ("TSLA", "Tesla Inc.", 245.75, 60, "Indv"),
        ("JPM", "JPMorgan Chase & Co.", 155.25, 45, "401k"),
        ("V", "Visa Inc.", 250.00, 30, "Roth IRA"),
        ("JNJ", "Johnson & Johnson", 160.50, 50, "Indv"),
        ("WMT", "Walmart Inc.", 165.75, 40, "401k"),
        ("PG", "Procter & Gamble Co.", 150.00, 35, "Roth IRA"),
        ("MA", "Mastercard Inc.", 420.25, 25, "Indv"),
        ("DIS", "The Walt Disney Company", 95.50, 70, "401k"),
        ("NFLX", "Netflix Inc.", 425.00, 20, "Roth IRA")
    ]
    
    // Create stocks array
    var stocks: [Stock] = []
    for stock in fakeStocks {
        let lot = StockLot(accountName: stock.account, shares: stock.shares, purchasePrice: stock.price)
        let newStock = Stock(
            ticker: stock.ticker,
            companyName: stock.companyName,
            purchasePrice: stock.price,
            shares: Int(stock.shares),
            isMaritalStatus: true,
            lots: [lot]
        )
        stocks.append(newStock)
    }
    
    // Save to UserDefaults so the viewModel will load them
    if let encoded = try? JSONEncoder().encode(stocks) {
        UserDefaults.standard.set(encoded, forKey: "committedStocks")
    }
    
    return ContentView()
}

// Preference key to track scroll offset
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
