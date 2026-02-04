import SwiftUI

struct SectorDiversificationView: View {
    @ObservedObject var viewModel: StockViewModel
    let showDollarAmounts: Bool

    @State private var selectedSector: StockSector?
    @State private var animatedProgress: Double = 0
    @Environment(\.colorScheme) private var colorScheme
    private var isDarkMode: Bool { colorScheme == .dark }

    private var sectorData: [(sector: StockSector, value: Double, percentage: Double, color: Color)] {
        viewModel.sectorBreakdown.map { item in
            (item.sector, item.value, item.percentage, Color(red: item.color.red, green: item.color.green, blue: item.color.blue))
        }
    }

    // Futuristic accent color
    private var accentCyan: Color { Color(red: 0.0, green: 0.9, blue: 1.0) }
    private var accentPurple: Color { Color(red: 0.6, green: 0.2, blue: 1.0) }

    var body: some View {
        VStack(spacing: 16) {
            // Futuristic Header
            HStack {
                HStack(spacing: 8) {
                    // Hexagonal indicator
                    Image(systemName: "hexagon.fill")
                        .font(.system(size: 10))
                        .foregroundColor(accentCyan)
                        .shadow(color: accentCyan.opacity(0.8), radius: 4, x: 0, y: 0)

                    Text("SECTOR ANALYSIS")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(accentCyan)
                        .tracking(2)
                }
                Spacer()
                // Futuristic status indicator
                HStack(spacing: 4) {
                    ForEach(0..<3) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(accentCyan.opacity(0.4 + Double(i) * 0.2))
                            .frame(width: 3, height: 8 + CGFloat(i) * 2)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(accentCyan.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(accentCyan.opacity(0.3), lineWidth: 1)
                        )
                )
            }

            if sectorData.isEmpty {
                Text("NO DATA STREAM")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(accentCyan.opacity(0.6))
                    .padding()
            } else {
                // Futuristic Donut Chart
                ZStack {
                    GeometryReader { geometry in
                        let size = min(geometry.size.width, geometry.size.height)
                        let outerRadius = size / 2 - 20
                        let innerRadius = outerRadius * 0.52
                        let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

                        ZStack {
                            // Radial grid background
                            ForEach(0..<8) { i in
                                Circle()
                                    .stroke(accentCyan.opacity(0.08), lineWidth: 0.5)
                                    .frame(width: outerRadius * 2 * CGFloat(i + 3) / 10, height: outerRadius * 2 * CGFloat(i + 3) / 10)
                            }

                            // Grid lines
                            ForEach(0..<12) { i in
                                Rectangle()
                                    .fill(accentCyan.opacity(0.06))
                                    .frame(width: 0.5, height: outerRadius)
                                    .offset(y: -outerRadius / 2)
                                    .rotationEffect(.degrees(Double(i) * 30))
                            }

                            // Outer static ring with gradient
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            accentCyan.opacity(0.4),
                                            accentPurple.opacity(0.3),
                                            accentCyan.opacity(0.2)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                                .frame(width: outerRadius * 2 + 24, height: outerRadius * 2 + 24)

                            // Second static ring
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            accentPurple.opacity(0.2),
                                            accentCyan.opacity(0.15),
                                            accentPurple.opacity(0.1)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                                .frame(width: outerRadius * 2 + 36, height: outerRadius * 2 + 36)

                            // Tick marks on outer ring
                            ForEach(0..<36) { i in
                                Rectangle()
                                    .fill(accentCyan.opacity(i % 3 == 0 ? 0.4 : 0.15))
                                    .frame(width: 1, height: i % 3 == 0 ? 8 : 4)
                                    .offset(y: -outerRadius - 16)
                                    .rotationEffect(.degrees(Double(i) * 10))
                            }

                            // Background glow
                            Circle()
                                .fill(
                                    RadialGradient(
                                        gradient: Gradient(colors: [
                                            accentCyan.opacity(0.15),
                                            Color.clear
                                        ]),
                                        center: .center,
                                        startRadius: innerRadius,
                                        endRadius: outerRadius + 20
                                    )
                                )
                                .frame(width: outerRadius * 2 + 40, height: outerRadius * 2 + 40)
                                .opacity(0.6)

                            // Sector segments with futuristic styling
                            ForEach(Array(sectorData.enumerated()), id: \.element.sector) { index, item in
                                FuturisticDonutSlice(
                                    startAngle: angleForIndex(index),
                                    endAngle: angleForIndex(index + 1),
                                    innerRadius: innerRadius,
                                    outerRadius: selectedSector == item.sector ? outerRadius + 10 : outerRadius,
                                    color: item.color,
                                    isSelected: selectedSector == item.sector,
                                    glowOpacity: 0.6
                                )
                                .opacity(animatedProgress)
                                .animation(
                                    .spring(response: 0.8, dampingFraction: 0.7)
                                    .delay(Double(index) * 0.1),
                                    value: animatedProgress
                                )
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedSector = selectedSector == item.sector ? nil : item.sector
                                    }
                                }
                            }

                            // Static corner accents for futuristic look
                            ForEach([0, 90, 180, 270], id: \.self) { angle in
                                HexCornerAccent(color: accentCyan)
                                    .frame(width: 12, height: 12)
                                    .offset(y: -outerRadius - 22)
                                    .rotationEffect(.degrees(Double(angle)))
                            }

                            // Futuristic center hub
                            ZStack {
                                // Outer glow ring
                                Circle()
                                    .stroke(accentCyan.opacity(0.3), lineWidth: 2)
                                    .frame(width: innerRadius * 2 + 4, height: innerRadius * 2 + 4)
                                    .shadow(color: accentCyan.opacity(0.5), radius: 8, x: 0, y: 0)

                                // Glass background
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            gradient: Gradient(colors: [
                                                (isDarkMode ? Color.black : Color.white).opacity(0.95),
                                                (isDarkMode ? Color.black : Color.white).opacity(0.8)
                                            ]),
                                            center: .center,
                                            startRadius: 0,
                                            endRadius: innerRadius
                                        )
                                    )
                                    .frame(width: innerRadius * 2 - 8, height: innerRadius * 2 - 8)
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [
                                                        accentCyan.opacity(0.5),
                                                        accentPurple.opacity(0.3),
                                                        accentCyan.opacity(0.2)
                                                    ]),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1.5
                                            )
                                    )
                                    .shadow(color: accentCyan.opacity(0.3), radius: 12, x: 0, y: 0)

                                VStack(spacing: 4) {
                                    if let selected = selectedSector,
                                       let data = sectorData.first(where: { $0.sector == selected }) {
                                        Text(selected.rawValue.uppercased())
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(data.color)
                                            .shadow(color: data.color.opacity(0.5), radius: 4, x: 0, y: 0)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(2)
                                            .frame(maxWidth: innerRadius * 1.4)

                                        Text("\(data.percentage, specifier: "%.1f")%")
                                            .font(.system(size: 18, weight: .black, design: .monospaced))
                                            .foregroundColor(data.color)
                                            .shadow(color: data.color.opacity(0.6), radius: 6, x: 0, y: 0)

                                        if showDollarAmounts {
                                            Text("$\(Int(round(data.value)))")
                                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                                .foregroundColor(accentCyan.opacity(0.8))
                                        }
                                    } else {
                                        Text("\(sectorData.count)")
                                            .font(.system(size: 28, weight: .black, design: .monospaced))
                                            .foregroundColor(accentCyan)
                                            .shadow(color: accentCyan.opacity(0.6), radius: 8, x: 0, y: 0)

                                        Text("SECTORS")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(accentCyan.opacity(0.7))
                                            .tracking(2)
                                    }
                                }
                            }
                            .position(center)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                    .frame(height: 280)
                }

                // Futuristic Legend
                VStack(spacing: 6) {
                    ForEach(sectorData, id: \.sector) { item in
                        FuturisticLegendRow(
                            sector: item.sector,
                            value: item.value,
                            percentage: item.percentage,
                            color: item.color,
                            showDollarAmounts: showDollarAmounts,
                            isSelected: selectedSector == item.sector,
                            animatedProgress: animatedProgress,
                            accentCyan: accentCyan
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedSector = selectedSector == item.sector ? nil : item.sector
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 16)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) {
                animatedProgress = 1.0
            }
        }
    }

    private func angleForIndex(_ index: Int) -> Double {
        let total = sectorData.reduce(0) { $0 + $1.value }
        guard total > 0 else { return 0 }

        var cumulative: Double = 0
        for i in 0..<min(index, sectorData.count) {
            cumulative += sectorData[i].value
        }

        return (cumulative / total) * 360 - 90
    }
}

// Hexagonal corner accent for futuristic look
struct HexCornerAccent: View {
    let color: Color

    var body: some View {
        Image(systemName: "diamond.fill")
            .font(.system(size: 6))
            .foregroundColor(color.opacity(0.6))
            .shadow(color: color.opacity(0.4), radius: 2, x: 0, y: 0)
    }
}

// Scanning line effect (kept for reference but no longer used)
struct ScanLineView: View {
    let angle: Double
    let radius: CGFloat
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            Path { path in
                path.move(to: center)
                let endX = center.x + radius * cos(angle * .pi / 180)
                let endY = center.y + radius * sin(angle * .pi / 180)
                path.addLine(to: CGPoint(x: endX, y: endY))
            }
            .stroke(
                LinearGradient(
                    gradient: Gradient(colors: [
                        color.opacity(0.8),
                        color.opacity(0.0)
                    ]),
                    startPoint: .init(x: 0.5, y: 0.5),
                    endPoint: .init(x: 0.5 + cos(angle * .pi / 180) * 0.5,
                                   y: 0.5 + sin(angle * .pi / 180) * 0.5)
                ),
                lineWidth: 2
            )
            .shadow(color: color.opacity(0.6), radius: 4, x: 0, y: 0)

            // Scan cone glow
            Path { path in
                path.move(to: center)
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(angle - 15),
                    endAngle: .degrees(angle),
                    clockwise: false
                )
                path.closeSubpath()
            }
            .fill(
                AngularGradient(
                    gradient: Gradient(colors: [
                        color.opacity(0.0),
                        color.opacity(0.15)
                    ]),
                    center: .center,
                    startAngle: .degrees(angle - 15),
                    endAngle: .degrees(angle)
                )
            )
        }
    }
}

// Animated data particle
struct DataParticle: View {
    let angle: Double
    let radius: CGFloat
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let x = center.x + radius * cos(angle * .pi / 180)
            let y = center.y + radius * sin(angle * .pi / 180)

            Circle()
                .fill(color)
                .frame(width: 4, height: 4)
                .shadow(color: color, radius: 4, x: 0, y: 0)
                .position(x: x, y: y)
        }
    }
}

// Futuristic donut slice with neon effects
struct FuturisticDonutSlice: View {
    let startAngle: Double
    let endAngle: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let color: Color
    let isSelected: Bool
    let glowOpacity: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Outer glow layer
                SectorSliceShape(
                    startAngle: startAngle,
                    endAngle: endAngle,
                    innerRadius: innerRadius - 2,
                    outerRadius: outerRadius + 4
                )
                .fill(color.opacity(isSelected ? 0.4 : 0.15))
                .blur(radius: 8)

                // Main slice with holographic gradient
                SectorSliceShape(
                    startAngle: startAngle,
                    endAngle: endAngle,
                    innerRadius: innerRadius,
                    outerRadius: outerRadius
                )
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            color.opacity(1.0),
                            color.opacity(0.8),
                            color.opacity(0.6)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: color.opacity(isSelected ? 0.8 : 0.4), radius: isSelected ? 12 : 6, x: 0, y: 0)

                // Inner edge highlight
                SectorSliceShape(
                    startAngle: startAngle,
                    endAngle: endAngle,
                    innerRadius: innerRadius,
                    outerRadius: innerRadius + 3
                )
                .fill(Color.white.opacity(0.3))

                // Outer edge highlight
                SectorSliceShape(
                    startAngle: startAngle,
                    endAngle: endAngle,
                    innerRadius: outerRadius - 2,
                    outerRadius: outerRadius
                )
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.4),
                            Color.white.opacity(0.1)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Selection border glow
                if isSelected {
                    SectorSliceShape(
                        startAngle: startAngle,
                        endAngle: endAngle,
                        innerRadius: innerRadius,
                        outerRadius: outerRadius
                    )
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                color,
                                Color.white.opacity(0.8),
                                color
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .shadow(color: color, radius: 8, x: 0, y: 0)
                }
            }
        }
    }
}

// Shape for sector slice
struct SectorSliceShape: Shape {
    let startAngle: Double
    let endAngle: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let gap: CGFloat = 1.5

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let adjustedStartAngle = startAngle + gap
        let adjustedEndAngle = endAngle - gap

        guard adjustedEndAngle > adjustedStartAngle else { return Path() }

        var path = Path()

        let endRad = adjustedEndAngle * .pi / 180

        // Outer arc
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .degrees(adjustedStartAngle),
            endAngle: .degrees(adjustedEndAngle),
            clockwise: false
        )

        // Line to inner arc
        let innerEndX = center.x + innerRadius * cos(endRad)
        let innerEndY = center.y + innerRadius * sin(endRad)
        path.addLine(to: CGPoint(x: innerEndX, y: innerEndY))

        // Inner arc (reverse)
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

// Futuristic legend row with neon styling
struct FuturisticLegendRow: View {
    let sector: StockSector
    let value: Double
    let percentage: Double
    let color: Color
    let showDollarAmounts: Bool
    let isSelected: Bool
    let animatedProgress: Double
    let accentCyan: Color

    @Environment(\.colorScheme) private var colorScheme
    private var isDarkMode: Bool { colorScheme == .dark }

    var body: some View {
        HStack(spacing: 10) {
            // Glowing color indicator
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .shadow(color: color.opacity(isSelected ? 0.9 : 0.5), radius: isSelected ? 6 : 3, x: 0, y: 0)

                if isSelected {
                    Circle()
                        .stroke(color.opacity(0.5), lineWidth: 2)
                        .frame(width: 14, height: 14)
                }
            }
            .frame(width: 16, height: 16)

            // Sector name with tech styling
            Text(sector.rawValue.uppercased())
                .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .monospaced))
                .foregroundColor(isSelected ? color : (isDarkMode ? Color.white : Color.black).opacity(0.8))
                .shadow(color: isSelected ? color.opacity(0.5) : .clear, radius: 4, x: 0, y: 0)
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)

            // Futuristic progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track background with grid pattern
                    RoundedRectangle(cornerRadius: 3)
                        .fill(accentCyan.opacity(0.1))
                        .frame(height: 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(accentCyan.opacity(0.2), lineWidth: 0.5)
                        )

                    // Tick marks
                    HStack(spacing: 0) {
                        ForEach(0..<10) { i in
                            Rectangle()
                                .fill(accentCyan.opacity(0.15))
                                .frame(width: 0.5)
                            if i < 9 {
                                Spacer()
                            }
                        }
                    }
                    .frame(height: 8)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                    // Glowing fill
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    color.opacity(0.9),
                                    color,
                                    color.opacity(0.7)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geometry.size.width * CGFloat(percentage / 100) * animatedProgress), height: 8)
                        .shadow(color: color.opacity(0.6), radius: 4, x: 0, y: 0)
                        .overlay(
                            // Shine effect
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.white.opacity(0.4),
                                            Color.white.opacity(0.0)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: 3)
                                .offset(y: -1.5)
                                .frame(width: max(0, geometry.size.width * CGFloat(percentage / 100) * animatedProgress), height: 8, alignment: .top)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        )

                    // End cap glow
                    if percentage > 2 {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 4, height: 4)
                            .shadow(color: color, radius: 3, x: 0, y: 0)
                            .offset(x: max(0, geometry.size.width * CGFloat(percentage / 100) * animatedProgress) - 4)
                    }
                }
            }
            .frame(height: 8)

            // Percentage with glow
            Text("\(percentage, specifier: "%.1f")%")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .shadow(color: color.opacity(0.4), radius: 2, x: 0, y: 0)
                .frame(width: 48, alignment: .trailing)

            // Dollar amount
            if showDollarAmounts {
                Text("$\(Int(round(value)))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(accentCyan.opacity(0.7))
                    .frame(width: 55, alignment: .trailing)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isSelected
                        ? color.opacity(isDarkMode ? 0.15 : 0.1)
                        : (isDarkMode ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isSelected
                                ? color.opacity(0.5)
                                : accentCyan.opacity(0.1),
                            lineWidth: isSelected ? 1.5 : 0.5
                        )
                )
                .shadow(color: isSelected ? color.opacity(0.3) : .clear, radius: 8, x: 0, y: 0)
        )
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}
