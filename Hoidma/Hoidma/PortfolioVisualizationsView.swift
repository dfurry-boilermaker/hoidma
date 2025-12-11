import SwiftUI

struct PortfolioVisualizationsView: View {
    @ObservedObject var viewModel: StockViewModel
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @AppStorage("selectedTab") private var selectedTab: Int = 1
    @State private var showDollarAmounts: Bool = false
    @Environment(\.dismiss) var dismiss
    
    // Helper function to generate consistent colors for ticker symbols
    private func colorForTicker(_ ticker: String) -> Color {
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
    
    // Calculate portfolio data for visualizations
    private var portfolioData: [(ticker: String, value: Double, percentage: Double, color: Color)] {
        let stocks = viewModel.stocks.filter { $0.isMaritalStatus }
        var data: [(ticker: String, value: Double, percentage: Double, color: Color)] = []
        
        for stock in stocks {
            if let priceData = viewModel.stockPrices[stock.ticker] {
                let totalShares = stock.lots.isEmpty ? Double(stock.shares) : stock.lots.reduce(0.0) { $0 + $1.shares }
                let stockValue = priceData.currentPrice * totalShares
                let percentage = viewModel.totalPortfolioValue > 0 ? (stockValue / viewModel.totalPortfolioValue) * 100 : 0
                
                if stockValue > 0 {
                    data.append((stock.ticker, stockValue, percentage, colorForTicker(stock.ticker)))
                }
            }
        }
        
        return data.sorted { $0.value > $1.value }
    }
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        // Portfolio Diversity header - appears as if pulled up from bottom
                        VStack(spacing: 12) {
                            
                            ZStack {
                                HStack {
                                    Spacer()
                                    
                                    Image(isDarkMode ? "hoidma.dark" : "hoidma")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(height: 40)
                                    
                                    Spacer()
                                }
                                
                                // Toggle button for dollar/percentage view - only show when there are positions
                                if viewModel.totalPortfolioValue > 0 {
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
                                    }
                                }
                            }
                        }
                        .padding(.top, 16)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 36)
                        .background(Color(UIColor.systemBackground))
                        
                        VStack(spacing: 24) {
                            if viewModel.totalPortfolioValue > 0 && !portfolioData.isEmpty {
                            // Pie Chart Section
                            VStack(spacing: 24) {
                                
                                // Pie Chart
                                PieChartView(data: portfolioData, showDollarAmounts: showDollarAmounts)
                                    .frame(height: 300)
                                    .padding(.bottom, 8)
                                
                                // Condensed Legend - 3 columns when showing only percentages, 2 columns when showing dollars
                                let columns = showDollarAmounts ? [
                                    GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)
                                ] : [
                                    GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)
                                ]
                                
                                LazyVGrid(columns: columns, spacing: 6) {
                                    ForEach(portfolioData, id: \.ticker) { item in
                                        HStack(spacing: 6) {
                                            // Small indicator
                                            Circle()
                                                .fill(item.color)
                                                .frame(width: 5, height: 5)
                                            
                                            Text(item.ticker)
                                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                                .foregroundColor(Color.primary)
                                            
                                            Spacer()
                                            
                                            HStack(spacing: 4) {
                                                if showDollarAmounts {
                                                    Text("$\(Int(round(item.value)))")
                                                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                                                        .foregroundColor(Color.secondary)
                                                }
                                                
                                                Text("\(item.percentage, specifier: "%.1f")%")
                                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                                    .foregroundColor(item.color)
                                            }
                                        }
                                        .padding(.vertical, 3)
                                        .padding(.horizontal, 4)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                            }
                            .padding(.horizontal, 20)
                            
                            // Placeholder for additional visualizations
                            VStack(spacing: 16) {
                                // HStack {
                                //     Text("Additional Visualizations")
                                //         .font(.system(size: 18, weight: .semibold))
                                //         .foregroundColor(Color.primary)
                                //     Spacer()
                                // }
                                
                                Text("More visualizations coming soon...")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(Color.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(20)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        } else {
                            // Empty state
                            VStack(spacing: 16) {
                                Text("No positions to visualize")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(Color.secondary)
                                
                                Text("Add stock positions to see portfolio visualizations")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(Color.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(40)
                        }
                        }
                    }
                }
                
                // Bottom navigation bar - outside ScrollView to stay fixed at bottom
                BottomNavigationBar(selectedTab: $selectedTab) { tabNumber in
                    // Navigation logic
                    if tabNumber == 1 {
                        // Navigate back to main page
                        dismiss()
                    } else if tabNumber == 2 {
                        // Already on portfolio visualizations view
                        // Do nothing
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// Futuristic Radial Bar Donut Chart - Inspired by Sci-Fi Interface
struct PieChartView: View {
    let data: [(ticker: String, value: Double, percentage: Double, color: Color)]
    let showDollarAmounts: Bool
    @State private var animatedProgress: Double = 0
    @State private var rotationAngle: Double = 0
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let outerRadius = size / 2 - 20
            let innerRadius = outerRadius * 0.5
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            
            ZStack {
                // Dark background circle
                Circle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: outerRadius * 2, height: outerRadius * 2)
                
                // Radial bar segments
                ForEach(Array(data.enumerated()), id: \.element.ticker) { index, item in
                    RadialBarSegment(
                        startAngle: angleForIndex(index, in: data),
                        endAngle: angleForIndex(index + 1, in: data),
                        innerRadius: innerRadius,
                        outerRadius: outerRadius,
                        gap: 0,
                        color: item.color,
                        showGrid: index % 2 == 1 // Alternate grid pattern
                    )
                    .opacity(animatedProgress)
                    .animation(
                        .spring(response: 1.2, dampingFraction: 0.8)
                        .delay(Double(index) * 0.15),
                        value: animatedProgress
                    )
                }
                
                // Outer labels with percentages and dollar values - omit small segments
                ForEach(Array(data.enumerated()), id: \.element.ticker) { index, item in
                    let startAngle = angleForIndex(index, in: data)
                    let endAngle = angleForIndex(index + 1, in: data)
                    let angleRange = endAngle - startAngle
                    let minAngleForLabel: Double = 8.0 // Minimum angle in degrees to show label
                    
                    // Only show label if segment is large enough
                    if abs(angleRange) >= minAngleForLabel {
                        let midAngle = (startAngle + endAngle) / 2
                        let labelRadius = outerRadius + 35
                        let labelX = center.x + cos(midAngle * .pi / 180) * labelRadius
                        let labelY = center.y + sin(midAngle * .pi / 180) * labelRadius
                        
                        VStack(spacing: 2) {
                            Text(item.ticker)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(item.color.opacity(0.8))
                            
                            Text("\(item.percentage, specifier: "%.2f")%")
                                .font(.system(size: 9, weight: .regular, design: .monospaced))
                                .foregroundColor(Color.secondary.opacity(0.7))
                            
                            if showDollarAmounts {
                                Text("$\(Int(round(item.value)))")
                                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                                    .foregroundColor(Color.secondary.opacity(0.6))
                            }
                        }
                        .position(x: labelX, y: labelY)
                        .opacity(animatedProgress)
                    }
                }
                
                // White center circle
                ZStack {
                    // White inner circle (adaptive for dark mode)
                    Circle()
                        .fill(isDarkMode ? Color(UIColor.systemBackground) : Color.white)
                        .frame(width: innerRadius * 2, height: innerRadius * 2)
                    
                    // Center content
                    VStack(spacing: 4) {
                        if showDollarAmounts {
                            Text("Total")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(Color.secondary.opacity(0.6))
                            
                            if !data.isEmpty {
                                let totalValue = data.reduce(0) { $0 + $1.value }
                                Text("$\(Int(round(totalValue)))")
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color.primary)
                                    .frame(maxWidth: innerRadius * 1.6)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            }
                        }
                    }
                }
                
                // Outer ring with faint lines
                Circle()
                    .stroke(
                        Color.gray.opacity(0.2),
                        lineWidth: 0.5
                    )
                    .frame(width: outerRadius * 2 + 2, height: outerRadius * 2 + 2)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onAppear {
                withAnimation(.easeOut(duration: 1.5)) {
                    animatedProgress = 1.0
                }
                
                // Very slow rotation
                withAnimation(.linear(duration: 180).repeatForever(autoreverses: false)) {
                    rotationAngle = 360
                }
            }
        }
    }
    
    private func angleForIndex(_ index: Int, in data: [(ticker: String, value: Double, percentage: Double, color: Color)]) -> Double {
        let total = data.reduce(0) { $0 + $1.value }
        guard total > 0 else { return 0 }
        
        var cumulative: Double = 0
        for i in 0..<index {
            cumulative += data[i].value
        }
        
        return (cumulative / total) * 360 - 90 // Start at top (-90 degrees)
    }
}

struct DonutSlice: Shape {
    let startAngle: Double
    let endAngle: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let gap: CGFloat
    
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let adjustedStartAngle = startAngle + (gap / 2)
        let adjustedEndAngle = endAngle - (gap / 2)
        
        var path = Path()
        
        // Convert angles to radians for calculations
        let endRad = adjustedEndAngle * .pi / 180
        
        // Outer arc
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .degrees(adjustedStartAngle),
            endAngle: .degrees(adjustedEndAngle),
            clockwise: false
        )
        
        // Line to inner arc (at end angle)
        let innerEndX = center.x + innerRadius * cos(endRad)
        let innerEndY = center.y + innerRadius * sin(endRad)
        path.addLine(to: CGPoint(x: innerEndX, y: innerEndY))
        
        // Inner arc (reverse direction)
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .degrees(adjustedEndAngle),
            endAngle: .degrees(adjustedStartAngle),
            clockwise: true
        )
        
        path.closeSubpath()
        
        return path
    }
}

// Grid Pattern View - Creates dot grid pattern
struct GridPatternView: View {
    let startAngle: Double
    let endAngle: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let color: Color
    
    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            
            // Create grid of dots
            let gridSpacing: CGFloat = 8
            let radialSteps = Int((outerRadius - innerRadius) / gridSpacing)
            let angularSteps = Int((endAngle - startAngle) / 5)
            
            ZStack {
                ForEach(0..<radialSteps, id: \.self) { r in
                    ForEach(0..<angularSteps, id: \.self) { a in
                        let radius = innerRadius + CGFloat(r) * gridSpacing
                        let angle = startAngle + Double(a) * ((endAngle - startAngle) / Double(angularSteps))
                        let angleRad = angle * .pi / 180
                        
                        Circle()
                            .fill(color)
                            .frame(width: 2, height: 2)
                            .position(
                                x: center.x + radius * cos(angleRad),
                                y: center.y + radius * sin(angleRad)
                            )
                    }
                }
            }
            .clipShape(
                DonutSlice(
                    startAngle: startAngle,
                    endAngle: endAngle,
                    innerRadius: innerRadius,
                    outerRadius: outerRadius,
                    gap: 0
                )
            )
        }
    }
}

// Radial Bar Segment - Creates sunburst effect with thin radial bars
struct RadialBarSegment: View {
    let startAngle: Double
    let endAngle: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let gap: CGFloat
    let color: Color
    let showGrid: Bool
    
    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let adjustedStartAngle = startAngle + (gap / 2)
            let adjustedEndAngle = endAngle - (gap / 2)
            let angleRange = adjustedEndAngle - adjustedStartAngle
            let numberOfBars = Int(angleRange / 2) // One bar every 2 degrees
            
            ZStack {
                // Base slice with gradient
                DonutSlice(
                    startAngle: startAngle,
                    endAngle: endAngle,
                    innerRadius: innerRadius,
                    outerRadius: outerRadius,
                    gap: gap
                )
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            color.opacity(0.9),
                            color.opacity(0.7),
                            color.opacity(0.5),
                            color.opacity(0.7),
                            color.opacity(0.9)
                        ]),
                        startPoint: UnitPoint(
                            x: 0.5 + 0.5 * cos((adjustedStartAngle + angleRange / 2) * .pi / 180),
                            y: 0.5 + 0.5 * sin((adjustedStartAngle + angleRange / 2) * .pi / 180)
                        ),
                        endPoint: UnitPoint(
                            x: 0.5 - 0.5 * cos((adjustedStartAngle + angleRange / 2) * .pi / 180),
                            y: 0.5 - 0.5 * sin((adjustedStartAngle + angleRange / 2) * .pi / 180)
                        )
                    )
                )
                .shadow(color: color.opacity(0.6), radius: 8, x: 0, y: 0)
                
                // Radial bars overlay
                ForEach(0..<numberOfBars, id: \.self) { barIndex in
                    let barAngle = adjustedStartAngle + Double(barIndex) * (angleRange / Double(numberOfBars))
                    let barRad = barAngle * .pi / 180
                    
                    Path { path in
                        let startX = center.x + innerRadius * cos(barRad)
                        let startY = center.y + innerRadius * sin(barRad)
                        let endX = center.x + outerRadius * cos(barRad)
                        let endY = center.y + outerRadius * sin(barRad)
                        
                        path.move(to: CGPoint(x: startX, y: startY))
                        path.addLine(to: CGPoint(x: endX, y: endY))
                    }
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                color.opacity(0.8),
                                color.opacity(0.4),
                                color.opacity(0.8)
                            ]),
                            startPoint: .init(x: 0, y: 0),
                            endPoint: .init(x: 1, y: 1)
                        ),
                        lineWidth: 1.5
                    )
                }
                
                // Grid pattern overlay (for alternating segments)
                if showGrid {
                    GridPatternView(
                        startAngle: startAngle,
                        endAngle: endAngle,
                        innerRadius: innerRadius,
                        outerRadius: outerRadius,
                        color: color.opacity(0.2)
                    )
                }
            }
        }
    }
}

