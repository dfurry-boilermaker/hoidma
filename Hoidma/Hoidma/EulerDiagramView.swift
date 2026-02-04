import SwiftUI

// MARK: - Main Euler Diagram View

struct EulerDiagramView: View {
    let accounts: [String]
    let sharedData: [(ticker: String, accounts: [String], totalValue: Double, color: Color)]
    let accountValues: [String: Double]
    let showDollarAmounts: Bool
    
    // MARK: - Computed Properties
    
    private var minValue: Double {
        sharedData.map { $0.totalValue }.min() ?? 1
    }
    
    private var maxValue: Double {
        sharedData.map { $0.totalValue }.max() ?? 1
    }
    
    private let accountColors: [Color] = [
        Color(red: 0.2, green: 0.6, blue: 0.9),
        Color(red: 0.9, green: 0.4, blue: 0.2),
        Color(red: 0.3, green: 0.7, blue: 0.4)
    ]
    
    // MARK: - Helper Functions
    
    private func colorForAccount(_ account: String, _ index: Int) -> Color {
        accountColors[min(index, accountColors.count - 1)]
    }
    
    private func circleSize(for value: Double) -> CGFloat {
        let minSize: CGFloat = 28
        let maxSize: CGFloat = 70
        let normalized = (value - minValue) / (maxValue - minValue)
        return minSize + CGFloat(normalized) * (maxSize - minSize)
    }
    
    private func accountShapeSize(for account: String, maxAccountValue: Double, baseSize: CGFloat) -> CGFloat {
        let accountValue = accountValues[account] ?? 1
        let normalized = accountValue / maxAccountValue
        let minSize: CGFloat = baseSize * 0.6
        let maxSize: CGFloat = baseSize
        return minSize + CGFloat(normalized) * (maxSize - minSize)
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            // Make it a lot taller and just a little bit wider
            let baseSize = min(geometry.size.width * 0.65, geometry.size.height * 0.8)
            let maxAccountValue = accountValues.values.max() ?? 1
            
            ZStack {
                if accounts.count == 1 {
                    SingleAccountEulerView(
                        account: accounts[0],
                        accountValue: accountValues[accounts[0]] ?? 0,
                        stocks: sharedData,
                        center: center,
                        baseSize: baseSize,
                        accountColor: colorForAccount(accounts[0], 0),
                        circleSize: circleSize,
                        showDollarAmounts: showDollarAmounts
                    )
                } else if accounts.count == 2 {
                    TwoAccountEulerView(
                        accounts: accounts,
                        sharedData: sharedData,
                        accountValues: accountValues,
                        center: center,
                        baseSize: baseSize,
                        maxAccountValue: maxAccountValue,
                        accountColors: accountColors,
                        colorForAccount: colorForAccount,
                        accountShapeSize: accountShapeSize,
                        circleSize: circleSize,
                        showDollarAmounts: showDollarAmounts
                    )
                } else if accounts.count == 3 {
                    ThreeAccountEulerView(
                        accounts: accounts,
                        sharedData: sharedData,
                        accountValues: accountValues,
                        center: center,
                        baseSize: baseSize,
                        maxAccountValue: maxAccountValue,
                        accountColors: accountColors,
                        colorForAccount: colorForAccount,
                        accountShapeSize: accountShapeSize,
                        circleSize: circleSize,
                        showDollarAmounts: showDollarAmounts
                    )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: 1100)
    }
}

// MARK: - Single Account View

struct SingleAccountEulerView: View {
    let account: String
    let accountValue: Double
    let stocks: [(ticker: String, accounts: [String], totalValue: Double, color: Color)]
    let center: CGPoint
    let baseSize: CGFloat
    let accountColor: Color
    let circleSize: (Double) -> CGFloat
    let showDollarAmounts: Bool
    
    var body: some View {
        ZStack {
            // A lot taller and just a little bit wider
            let shapeWidth = baseSize * 1.3
            let shapeHeight = baseSize * 2.2
            
            // Account shape
            RoundedRectangle(cornerRadius: 20)
                .fill(accountColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    accountColor.opacity(0.8),
                                    accountColor.opacity(0.4)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .frame(width: shapeWidth, height: shapeHeight)
                .position(center)
            
            // Account label
            Text(account)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(accountColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(accountColor.opacity(0.15))
                        .overlay(
                            Capsule()
                                .stroke(accountColor.opacity(0.4), lineWidth: 1)
                        )
                )
                .position(x: center.x, y: center.y - shapeHeight * 0.45)
            
            // Stocks inside
            let stockPositions = calculateStockPositions(
                stocks: stocks,
                containerSize: CGSize(width: shapeWidth, height: shapeHeight),
                center: center
            )
            
            ForEach(Array(stocks.enumerated()), id: \.element.ticker) { index, stock in
                if index < stockPositions.count {
                    PositionCircle(
                        ticker: stock.ticker,
                        value: stock.totalValue,
                        color: stock.color,
                        size: circleSize(stock.totalValue),
                        position: stockPositions[index],
                        showDollarAmounts: showDollarAmounts
                    )
                }
            }
        }
    }
    
    // MARK: - Position Calculation
    
    private func calculateStockPositions(
        stocks: [(ticker: String, accounts: [String], totalValue: Double, color: Color)],
        containerSize: CGSize,
        center: CGPoint
    ) -> [CGPoint] {
        guard !stocks.isEmpty else { return [] }
        var positions: [CGPoint] = []
        let sizes: [CGFloat] = stocks.map { circleSize($0.totalValue) }
        
        let padding: CGFloat = 40
        let availableWidth = containerSize.width - padding * 2
        let availableHeight = containerSize.height - padding * 2
        
        if stocks.count <= 4 {
            let cols = stocks.count <= 2 ? stocks.count : 2
            let rows = (stocks.count + cols - 1) / cols
            let cellWidth = availableWidth / CGFloat(cols)
            let cellHeight = availableHeight / CGFloat(rows)
            
            for (index, _) in stocks.enumerated() {
                let col = index % cols
                let row = index / cols
                let x = center.x - containerSize.width/2 + padding + cellWidth * (CGFloat(col) + 0.5)
                let y = center.y - containerSize.height/2 + padding + cellHeight * (CGFloat(row) + 0.5)
                positions.append(CGPoint(x: x, y: y))
            }
        } else {
            let angleStep = 2 * .pi / Double(stocks.count)
            let maxRadius = min(availableWidth, availableHeight) * 0.35
            
            for (index, _) in stocks.enumerated() {
                let angle = Double(index) * angleStep
                let spiralRadius = maxRadius * sqrt(Double(index + 1) / Double(stocks.count))
                let x = center.x + spiralRadius * cos(angle)
                let y = center.y + spiralRadius * sin(angle)
                positions.append(CGPoint(x: x, y: y))
            }
            
            resolveCollisionsInSingleAccount(positions: &positions, sizes: sizes, containerSize: containerSize, center: center, padding: padding, accountCenter: center, accountSize: containerSize)
        }
        
        return positions
    }
    
    // MARK: - Boundary Checking Helpers (Single Account)
    
    private func isPointInRoundedRect(_ point: CGPoint, center: CGPoint, size: CGSize, bubbleRadius: CGFloat) -> Bool {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        let cornerRadius: CGFloat = 20
        
        let minX = center.x - halfWidth + cornerRadius
        let maxX = center.x + halfWidth - cornerRadius
        let minY = center.y - halfHeight + cornerRadius
        let maxY = center.y + halfHeight - cornerRadius
        
        if point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY {
            return true
        }
        
        let corners = [
            CGPoint(x: center.x - halfWidth + cornerRadius, y: center.y - halfHeight + cornerRadius),
            CGPoint(x: center.x + halfWidth - cornerRadius, y: center.y - halfHeight + cornerRadius),
            CGPoint(x: center.x - halfWidth + cornerRadius, y: center.y + halfHeight - cornerRadius),
            CGPoint(x: center.x + halfWidth - cornerRadius, y: center.y + halfHeight - cornerRadius)
        ]
        
        for corner in corners {
            let dx = point.x - corner.x
            let dy = point.y - corner.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist <= cornerRadius + bubbleRadius {
                let inTopLeft = point.x <= minX && point.y <= minY
                let inTopRight = point.x >= maxX && point.y <= minY
                let inBottomLeft = point.x <= minX && point.y >= maxY
                let inBottomRight = point.x >= maxX && point.y >= maxY
                
                if inTopLeft && corner == corners[0] { return true }
                if inTopRight && corner == corners[1] { return true }
                if inBottomLeft && corner == corners[2] { return true }
                if inBottomRight && corner == corners[3] { return true }
            }
        }
        
        return false
    }
    
    private func constrainToAccount(_ point: CGPoint, bubbleRadius: CGFloat, accountCenter: CGPoint, accountSize: CGSize) -> CGPoint {
        var constrained = point
        let halfWidth = accountSize.width / 2
        let halfHeight = accountSize.height / 2
        let cornerRadius: CGFloat = 20
        
        let minX = accountCenter.x - halfWidth + bubbleRadius + cornerRadius
        let maxX = accountCenter.x + halfWidth - bubbleRadius - cornerRadius
        let minY = accountCenter.y - halfHeight + bubbleRadius + cornerRadius
        let maxY = accountCenter.y + halfHeight - bubbleRadius - cornerRadius
        
        constrained.x = max(minX, min(maxX, constrained.x))
        constrained.y = max(minY, min(maxY, constrained.y))
        
        if !isPointInRoundedRect(constrained, center: accountCenter, size: accountSize, bubbleRadius: bubbleRadius) {
            let dx = accountCenter.x - constrained.x
            let dy = accountCenter.y - constrained.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist > 0 {
                let scale = (min(halfWidth, halfHeight) - bubbleRadius - cornerRadius) / dist
                constrained = CGPoint(
                    x: accountCenter.x - dx * scale,
                    y: accountCenter.y - dy * scale
                )
            }
        }
        
        return constrained
    }
    
    private func resolveCollisionsInSingleAccount(positions: inout [CGPoint], sizes: [CGFloat], containerSize: CGSize, center: CGPoint, padding: CGFloat, accountCenter: CGPoint, accountSize: CGSize) {
        for _ in 0..<50 {
            var hasCollision = false
            
            for i in 0..<positions.count {
                // Constrain to account boundary
                positions[i] = constrainToAccount(
                    positions[i],
                    bubbleRadius: sizes[i] * 0.5,
                    accountCenter: accountCenter,
                    accountSize: accountSize
                )
                
                for j in (i+1)..<positions.count {
                    let dx = positions[i].x - positions[j].x
                    let dy = positions[i].y - positions[j].y
                    let distance = sqrt(dx * dx + dy * dy)
                    let minDistance = sizes[i] + sizes[j] + 15
                    
                    if distance < minDistance && distance > 0 {
                        hasCollision = true
                        let overlap = minDistance - distance
                        let nx = dx / distance
                        let ny = dy / distance
                        
                        positions[i].x += nx * overlap * 0.5
                        positions[i].y += ny * overlap * 0.5
                        positions[j].x -= nx * overlap * 0.5
                        positions[j].y -= ny * overlap * 0.5
                        
                        // Re-constrain after collision
                        positions[i] = constrainToAccount(
                            positions[i],
                            bubbleRadius: sizes[i] * 0.5,
                            accountCenter: accountCenter,
                            accountSize: accountSize
                        )
                        positions[j] = constrainToAccount(
                            positions[j],
                            bubbleRadius: sizes[j] * 0.5,
                            accountCenter: accountCenter,
                            accountSize: accountSize
                        )
                    }
                }
            }
            
            if !hasCollision { break }
        }
    }
}

// MARK: - Two Account View

struct TwoAccountEulerView: View {
    let accounts: [String]
    let sharedData: [(ticker: String, accounts: [String], totalValue: Double, color: Color)]
    let accountValues: [String: Double]
    let center: CGPoint
    let baseSize: CGFloat
    let maxAccountValue: Double
    let accountColors: [Color]
    let colorForAccount: (String, Int) -> Color
    let accountShapeSize: (String, Double, CGFloat) -> CGFloat
    let circleSize: (Double) -> CGFloat
    let showDollarAmounts: Bool
    
    var body: some View {
        let account1Color = colorForAccount(accounts[0], 0)
        let account2Color = colorForAccount(accounts[1], 1)
        let size1 = accountShapeSize(accounts[0], maxAccountValue, baseSize)
        let size2 = accountShapeSize(accounts[1], maxAccountValue, baseSize)
        
        // Stack vertically instead of horizontally
        let overlapAmount: CGFloat = 0.25
        let shape1Center = CGPoint(x: center.x, y: center.y - size1 * overlapAmount)
        let shape2Center = CGPoint(x: center.x, y: center.y + size2 * overlapAmount)
        
        // A lot taller and just a little bit wider
        let shapeWidth = max(size1, size2) * 1.2
        let shapeHeight = max(size1, size2) * 2.0
        
        ZStack {
            // Account shapes
            accountShape(color: account1Color, center: shape1Center, width: shapeWidth, height: shapeHeight)
            accountShape(color: account2Color, center: shape2Center, width: shapeWidth, height: shapeHeight)
            
            // Account labels - positioned for vertical layout
            accountLabel(text: accounts[0], color: account1Color, center: CGPoint(x: shape1Center.x, y: shape1Center.y - shapeHeight * 0.45))
            accountLabel(text: accounts[1], color: account2Color, center: CGPoint(x: shape2Center.x, y: shape2Center.y + shapeHeight * 0.45))
            
            // Shared stocks
            let sharedStocks = sharedData.filter { $0.accounts.count == 2 }
            let sharedPositions = calculatePositionsInOverlap(
                stocks: sharedStocks,
                overlapCenter: center,
                radius: min(shapeWidth, shapeHeight) * 0.2,
                account1Center: shape1Center,
                account1Size: CGSize(width: shapeWidth, height: shapeHeight),
                account2Center: shape2Center,
                account2Size: CGSize(width: shapeWidth, height: shapeHeight)
            )
            
            ForEach(Array(sharedStocks.enumerated()), id: \.element.ticker) { index, stock in
                if index < sharedPositions.count {
                    PositionCircle(
                        ticker: stock.ticker,
                        value: stock.totalValue,
                        color: stock.color,
                        size: circleSize(stock.totalValue),
                        position: sharedPositions[index],
                        showDollarAmounts: showDollarAmounts
                    )
                }
            }
            
            // Account 1 only stocks - positioned for vertical layout
            let account1OnlyStocks = sharedData.filter { item in
                item.accounts.count == 1 && item.accounts.contains(accounts[0])
            }
            let account1Positions = calculatePositionsInRegion(
                stocks: account1OnlyStocks,
                regionCenter: CGPoint(x: shape1Center.x, y: shape1Center.y - shapeHeight * 0.25),
                regionSize: CGSize(width: shapeWidth * 0.6, height: shapeHeight * 0.4),
                account1Center: shape1Center,
                account1Size: CGSize(width: shapeWidth, height: shapeHeight),
                account2Center: shape2Center,
                account2Size: CGSize(width: shapeWidth, height: shapeHeight),
                isAccount1Only: true
            )
            
            ForEach(Array(account1OnlyStocks.enumerated()), id: \.element.ticker) { index, stock in
                if index < account1Positions.count {
                    PositionCircle(
                        ticker: stock.ticker,
                        value: stock.totalValue,
                        color: stock.color,
                        size: circleSize(stock.totalValue),
                        position: account1Positions[index],
                        showDollarAmounts: showDollarAmounts
                    )
                }
            }
            
            // Account 2 only stocks - positioned for vertical layout
            let account2OnlyStocks = sharedData.filter { item in
                item.accounts.count == 1 && item.accounts.contains(accounts[1])
            }
            let account2Positions = calculatePositionsInRegion(
                stocks: account2OnlyStocks,
                regionCenter: CGPoint(x: shape2Center.x, y: shape2Center.y + shapeHeight * 0.25),
                regionSize: CGSize(width: shapeWidth * 0.6, height: shapeHeight * 0.4),
                account1Center: shape1Center,
                account1Size: CGSize(width: shapeWidth, height: shapeHeight),
                account2Center: shape2Center,
                account2Size: CGSize(width: shapeWidth, height: shapeHeight),
                isAccount1Only: false
            )
            
            ForEach(Array(account2OnlyStocks.enumerated()), id: \.element.ticker) { index, stock in
                if index < account2Positions.count {
                    PositionCircle(
                        ticker: stock.ticker,
                        value: stock.totalValue,
                        color: stock.color,
                        size: circleSize(stock.totalValue),
                        position: account2Positions[index],
                        showDollarAmounts: showDollarAmounts
                    )
                }
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func accountShape(color: Color, center: CGPoint, width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(color.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                color.opacity(0.8),
                                color.opacity(0.4)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
            .frame(width: width, height: height)
            .position(center)
    }
    
    private func accountLabel(text: String, color: Color, center: CGPoint) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundColor(color)
            .padding(.horizontal, 13)
            .padding(.vertical, 6.5)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
                    .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
            )
            .position(center)
    }
    
    // MARK: - Position Calculation
    
    private func calculatePositionsInOverlap(
        stocks: [(ticker: String, accounts: [String], totalValue: Double, color: Color)],
        overlapCenter: CGPoint,
        radius: CGFloat,
        account1Center: CGPoint,
        account1Size: CGSize,
        account2Center: CGPoint,
        account2Size: CGSize
    ) -> [CGPoint] {
        guard !stocks.isEmpty else { return [] }
        var positions: [CGPoint] = []
        let sizes: [CGFloat] = stocks.map { circleSize($0.totalValue) }
        
        if stocks.count == 1 {
            positions.append(overlapCenter)
        } else {
            let angleStep = 2 * .pi / Double(stocks.count)
            let maxRadius = radius * 0.7
            
            for (index, _) in stocks.enumerated() {
                let angle = Double(index) * angleStep
                let spiralRadius = maxRadius * sqrt(Double(index + 1) / Double(stocks.count))
                let x = overlapCenter.x + spiralRadius * cos(angle)
                let y = overlapCenter.y + spiralRadius * sin(angle)
                positions.append(CGPoint(x: x, y: y))
            }
            
            resolveCollisionsInOverlap(positions: &positions, sizes: sizes, center: overlapCenter, radius: radius, account1Center: account1Center, account1Size: account1Size, account2Center: account2Center, account2Size: account2Size)
        }
        
        return positions
    }
    
    private func calculatePositionsInRegion(
        stocks: [(ticker: String, accounts: [String], totalValue: Double, color: Color)],
        regionCenter: CGPoint,
        regionSize: CGSize,
        account1Center: CGPoint,
        account1Size: CGSize,
        account2Center: CGPoint,
        account2Size: CGSize,
        isAccount1Only: Bool
    ) -> [CGPoint] {
        guard !stocks.isEmpty else { return [] }
        var positions: [CGPoint] = []
        let sizes: [CGFloat] = stocks.map { circleSize($0.totalValue) }
        
        let padding: CGFloat = 25
        let availableWidth = regionSize.width - padding * 2
        let availableHeight = regionSize.height - padding * 2
        
        if stocks.count <= 3 {
            let cols = stocks.count <= 2 ? stocks.count : 2
            let rows = (stocks.count + cols - 1) / cols
            let cellWidth = availableWidth / CGFloat(cols)
            let cellHeight = availableHeight / CGFloat(rows)
            
            for (index, _) in stocks.enumerated() {
                let col = index % cols
                let row = index / cols
                let x = regionCenter.x - regionSize.width/2 + padding + cellWidth * (CGFloat(col) + 0.5)
                let y = regionCenter.y - regionSize.height/2 + padding + cellHeight * (CGFloat(row) + 0.5)
                positions.append(CGPoint(x: x, y: y))
            }
        } else {
            let angleStep = 2 * .pi / Double(stocks.count)
            let maxRadius = min(availableWidth, availableHeight) * 0.35
            
            for (index, _) in stocks.enumerated() {
                let angle = Double(index) * angleStep
                let spiralRadius = maxRadius * sqrt(Double(index + 1) / Double(stocks.count))
                let x = regionCenter.x + spiralRadius * cos(angle)
                let y = regionCenter.y + spiralRadius * sin(angle)
                positions.append(CGPoint(x: x, y: y))
            }
            
            resolveCollisionsInRegion(positions: &positions, sizes: sizes, regionCenter: regionCenter, regionSize: regionSize, padding: padding, account1Center: account1Center, account1Size: account1Size, account2Center: account2Center, account2Size: account2Size, isAccount1Only: isAccount1Only)
        }
        
        return positions
    }
    
    private func resolveCollisions(positions: inout [CGPoint], sizes: [CGFloat], center: CGPoint, radius: CGFloat) {
        for _ in 0..<30 {
            var hasCollision = false
            
            for i in 0..<positions.count {
                let dist = sqrt(pow(positions[i].x - center.x, 2) + pow(positions[i].y - center.y, 2))
                let margin = sizes[i] * 0.6
                if dist + margin > radius {
                    let angle = atan2(positions[i].y - center.y, positions[i].x - center.x)
                    positions[i] = CGPoint(
                        x: center.x + (radius - margin) * cos(angle),
                        y: center.y + (radius - margin) * sin(angle)
                    )
                }
                
                for j in (i+1)..<positions.count {
                    let dx = positions[i].x - positions[j].x
                    let dy = positions[i].y - positions[j].y
                    let distance = sqrt(dx * dx + dy * dy)
                    let minDistance = sizes[i] + sizes[j] + 15
                    
                    if distance < minDistance && distance > 0 {
                        hasCollision = true
                        let overlap = minDistance - distance
                        let nx = dx / distance
                        let ny = dy / distance
                        
                        positions[i].x += nx * overlap * 0.5
                        positions[i].y += ny * overlap * 0.5
                        positions[j].x -= nx * overlap * 0.5
                        positions[j].y -= ny * overlap * 0.5
                    }
                }
            }
            
            if !hasCollision { break }
        }
    }
    
    private func resolveCollisionsInOverlap(
        positions: inout [CGPoint],
        sizes: [CGFloat],
        center: CGPoint,
        radius: CGFloat,
        account1Center: CGPoint,
        account1Size: CGSize,
        account2Center: CGPoint,
        account2Size: CGSize
    ) {
        for _ in 0..<50 {
            var hasCollision = false
            
            for i in 0..<positions.count {
                // Constrain to overlap region
                positions[i] = constrainToOverlap(
                    positions[i],
                    bubbleRadius: sizes[i] * 0.5,
                    account1Center: account1Center,
                    account1Size: account1Size,
                    account2Center: account2Center,
                    account2Size: account2Size
                )
                
                // Also constrain to circular radius
                let dist = sqrt(pow(positions[i].x - center.x, 2) + pow(positions[i].y - center.y, 2))
                let margin = sizes[i] * 0.5
                if dist + margin > radius {
                    let angle = atan2(positions[i].y - center.y, positions[i].x - center.x)
                    positions[i] = CGPoint(
                        x: center.x + (radius - margin) * cos(angle),
                        y: center.y + (radius - margin) * sin(angle)
                    )
                }
                
                for j in (i+1)..<positions.count {
                    let dx = positions[i].x - positions[j].x
                    let dy = positions[i].y - positions[j].y
                    let distance = sqrt(dx * dx + dy * dy)
                    let minDistance = sizes[i] + sizes[j] + 15
                    
                    if distance < minDistance && distance > 0 {
                        hasCollision = true
                        let overlap = minDistance - distance
                        let nx = dx / distance
                        let ny = dy / distance
                        
                        positions[i].x += nx * overlap * 0.5
                        positions[i].y += ny * overlap * 0.5
                        positions[j].x -= nx * overlap * 0.5
                        positions[j].y -= ny * overlap * 0.5
                        
                        // Re-constrain after collision
                        positions[i] = constrainToOverlap(
                            positions[i],
                            bubbleRadius: sizes[i] * 0.5,
                            account1Center: account1Center,
                            account1Size: account1Size,
                            account2Center: account2Center,
                            account2Size: account2Size
                        )
                        positions[j] = constrainToOverlap(
                            positions[j],
                            bubbleRadius: sizes[j] * 0.5,
                            account1Center: account1Center,
                            account1Size: account1Size,
                            account2Center: account2Center,
                            account2Size: account2Size
                        )
                    }
                }
            }
            
            if !hasCollision { break }
        }
    }
    
    // MARK: - Boundary Checking Helpers
    
    private func isPointInRoundedRect(_ point: CGPoint, center: CGPoint, size: CGSize, bubbleRadius: CGFloat) -> Bool {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        let cornerRadius: CGFloat = 20
        
        // Check if bubble center + radius is within the rectangle bounds
        let minX = center.x - halfWidth + cornerRadius
        let maxX = center.x + halfWidth - cornerRadius
        let minY = center.y - halfHeight + cornerRadius
        let maxY = center.y + halfHeight - cornerRadius
        
        // Check if point is in the rectangular part (excluding corners)
        if point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY {
            return true
        }
        
        // Check if point is in one of the rounded corners
        let corners = [
            CGPoint(x: center.x - halfWidth + cornerRadius, y: center.y - halfHeight + cornerRadius), // top-left
            CGPoint(x: center.x + halfWidth - cornerRadius, y: center.y - halfHeight + cornerRadius), // top-right
            CGPoint(x: center.x - halfWidth + cornerRadius, y: center.y + halfHeight - cornerRadius), // bottom-left
            CGPoint(x: center.x + halfWidth - cornerRadius, y: center.y + halfHeight - cornerRadius)  // bottom-right
        ]
        
        for corner in corners {
            let dx = point.x - corner.x
            let dy = point.y - corner.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist <= cornerRadius + bubbleRadius {
                // Check which corner region we're in
                let inTopLeft = point.x <= minX && point.y <= minY
                let inTopRight = point.x >= maxX && point.y <= minY
                let inBottomLeft = point.x <= minX && point.y >= maxY
                let inBottomRight = point.x >= maxX && point.y >= maxY
                
                if inTopLeft && corner == corners[0] { return true }
                if inTopRight && corner == corners[1] { return true }
                if inBottomLeft && corner == corners[2] { return true }
                if inBottomRight && corner == corners[3] { return true }
            }
        }
        
        return false
    }
    
    private func isPointInOverlap(_ point: CGPoint, bubbleRadius: CGFloat, account1Center: CGPoint, account1Size: CGSize, account2Center: CGPoint, account2Size: CGSize) -> Bool {
        let inAccount1 = isPointInRoundedRect(point, center: account1Center, size: account1Size, bubbleRadius: bubbleRadius)
        let inAccount2 = isPointInRoundedRect(point, center: account2Center, size: account2Size, bubbleRadius: bubbleRadius)
        return inAccount1 && inAccount2
    }
    
    private func constrainToAccount(_ point: CGPoint, bubbleRadius: CGFloat, accountCenter: CGPoint, accountSize: CGSize) -> CGPoint {
        var constrained = point
        let halfWidth = accountSize.width / 2
        let halfHeight = accountSize.height / 2
        let cornerRadius: CGFloat = 20
        
        // Simple rectangular constraint first
        let minX = accountCenter.x - halfWidth + bubbleRadius + cornerRadius
        let maxX = accountCenter.x + halfWidth - bubbleRadius - cornerRadius
        let minY = accountCenter.y - halfHeight + bubbleRadius + cornerRadius
        let maxY = accountCenter.y + halfHeight - bubbleRadius - cornerRadius
        
        constrained.x = max(minX, min(maxX, constrained.x))
        constrained.y = max(minY, min(maxY, constrained.y))
        
        // If still not in bounds, move towards center
        if !isPointInRoundedRect(constrained, center: accountCenter, size: accountSize, bubbleRadius: bubbleRadius) {
            let dx = accountCenter.x - constrained.x
            let dy = accountCenter.y - constrained.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist > 0 {
                let scale = (min(halfWidth, halfHeight) - bubbleRadius - cornerRadius) / dist
                constrained = CGPoint(
                    x: accountCenter.x - dx * scale,
                    y: accountCenter.y - dy * scale
                )
            }
        }
        
        return constrained
    }
    
    private func constrainToOverlap(_ point: CGPoint, bubbleRadius: CGFloat, account1Center: CGPoint, account1Size: CGSize, account2Center: CGPoint, account2Size: CGSize) -> CGPoint {
        var constrained = point
        
        // Move towards the overlap center if outside
        if !isPointInOverlap(constrained, bubbleRadius: bubbleRadius, account1Center: account1Center, account1Size: account1Size, account2Center: account2Center, account2Size: account2Size) {
            // Find the overlap center (intersection of the two rectangles)
            let overlapCenter = CGPoint(
                x: (account1Center.x + account2Center.x) / 2,
                y: (account1Center.y + account2Center.y) / 2
            )
            
            let dx = overlapCenter.x - constrained.x
            let dy = overlapCenter.y - constrained.y
            let dist = sqrt(dx * dx + dy * dy)
            
            if dist > 0 {
                // Move towards overlap center
                let step = min(dist, 10.0)
                constrained = CGPoint(
                    x: constrained.x + (dx / dist) * step,
                    y: constrained.y + (dy / dist) * step
                )
            }
        }
        
        return constrained
    }
    
    private func resolveCollisionsInRegion(
        positions: inout [CGPoint],
        sizes: [CGFloat],
        regionCenter: CGPoint,
        regionSize: CGSize,
        padding: CGFloat,
        account1Center: CGPoint,
        account1Size: CGSize,
        account2Center: CGPoint,
        account2Size: CGSize,
        isAccount1Only: Bool
    ) {
        for _ in 0..<50 {
            var hasCollision = false
            
            for i in 0..<positions.count {
                // Constrain to the specific account (not the overlap)
                let accountCenter = isAccount1Only ? account1Center : account2Center
                let accountSize = isAccount1Only ? account1Size : account2Size
                
                // First constrain to account boundary
                positions[i] = constrainToAccount(
                    positions[i],
                    bubbleRadius: sizes[i] * 0.5,
                    accountCenter: accountCenter,
                    accountSize: accountSize
                )
                
                // Also ensure it's NOT in the other account (for single-account stocks)
                if isAccount1Only {
                    // Make sure it's not in account 2
                    if isPointInRoundedRect(positions[i], center: account2Center, size: account2Size, bubbleRadius: sizes[i] * 0.5) {
                        // Move away from account 2
                        let dx = positions[i].x - account2Center.x
                        let dy = positions[i].y - account2Center.y
                        let dist = sqrt(dx * dx + dy * dy)
                        if dist > 0 {
                            let moveAway = sizes[i] * 0.6
                            positions[i] = CGPoint(
                                x: positions[i].x + (dx / dist) * moveAway,
                                y: positions[i].y + (dy / dist) * moveAway
                            )
                        }
                    }
                } else {
                    // Make sure it's not in account 1
                    if isPointInRoundedRect(positions[i], center: account1Center, size: account1Size, bubbleRadius: sizes[i] * 0.5) {
                        // Move away from account 1
                        let dx = positions[i].x - account1Center.x
                        let dy = positions[i].y - account1Center.y
                        let dist = sqrt(dx * dx + dy * dy)
                        if dist > 0 {
                            let moveAway = sizes[i] * 0.6
                            positions[i] = CGPoint(
                                x: positions[i].x + (dx / dist) * moveAway,
                                y: positions[i].y + (dy / dist) * moveAway
                            )
                        }
                    }
                }
                
                // Re-constrain to account after moving
                positions[i] = constrainToAccount(
                    positions[i],
                    bubbleRadius: sizes[i] * 0.5,
                    accountCenter: accountCenter,
                    accountSize: accountSize
                )
                
                for j in (i+1)..<positions.count {
                    let dx = positions[i].x - positions[j].x
                    let dy = positions[i].y - positions[j].y
                    let distance = sqrt(dx * dx + dy * dy)
                    let minDistance = sizes[i] + sizes[j] + 15
                    
                    if distance < minDistance && distance > 0 {
                        hasCollision = true
                        let overlap = minDistance - distance
                        let nx = dx / distance
                        let ny = dy / distance
                        
                        positions[i].x += nx * overlap * 0.5
                        positions[i].y += ny * overlap * 0.5
                        positions[j].x -= nx * overlap * 0.5
                        positions[j].y -= ny * overlap * 0.5
                        
                        // Re-constrain after collision
                        positions[i] = constrainToAccount(
                            positions[i],
                            bubbleRadius: sizes[i] * 0.5,
                            accountCenter: accountCenter,
                            accountSize: accountSize
                        )
                        let otherAccountCenter = isAccount1Only ? account2Center : account1Center
                        let otherAccountSize = isAccount1Only ? account2Size : account1Size
                        positions[j] = constrainToAccount(
                            positions[j],
                            bubbleRadius: sizes[j] * 0.5,
                            accountCenter: otherAccountCenter,
                            accountSize: otherAccountSize
                        )
                    }
                }
            }
            
            if !hasCollision { break }
        }
    }
}

// MARK: - Three Account View

struct ThreeAccountEulerView: View {
    let accounts: [String]
    let sharedData: [(ticker: String, accounts: [String], totalValue: Double, color: Color)]
    let accountValues: [String: Double]
    let center: CGPoint
    let baseSize: CGFloat
    let maxAccountValue: Double
    let accountColors: [Color]
    let colorForAccount: (String, Int) -> Color
    let accountShapeSize: (String, Double, CGFloat) -> CGFloat
    let circleSize: (Double) -> CGFloat
    let showDollarAmounts: Bool
    
    private let triangleHeight: CGFloat = 0.866
    
    var body: some View {
        let account1Color = colorForAccount(accounts[0], 0)
        let account2Color = colorForAccount(accounts[1], 1)
        let account3Color = colorForAccount(accounts[2], 2)
        let size1 = accountShapeSize(accounts[0], maxAccountValue, baseSize)
        let size2 = accountShapeSize(accounts[1], maxAccountValue, baseSize)
        let size3 = accountShapeSize(accounts[2], maxAccountValue, baseSize)
        
        // A lot taller and just a little bit wider
        let shapeWidth = max(size1, size2, size3) * 1.15
        let shapeHeight = max(size1, size2, size3) * 1.9
        
        // More vertical arrangement - stack accounts more vertically
        let shape1Center = CGPoint(x: center.x, y: center.y - baseSize * 0.35)
        let shape2Center = CGPoint(x: center.x - baseSize * 0.28 * triangleHeight, y: center.y + baseSize * 0.2)
        let shape3Center = CGPoint(x: center.x + baseSize * 0.28 * triangleHeight, y: center.y + baseSize * 0.2)
        
        ZStack {
            // Account shapes
            accountShape(color: account1Color, center: shape1Center, width: shapeWidth, height: shapeHeight)
            accountShape(color: account2Color, center: shape2Center, width: shapeWidth, height: shapeHeight)
            accountShape(color: account3Color, center: shape3Center, width: shapeWidth, height: shapeHeight)
            
            // Account labels - adjusted for vertical layout
            accountLabel(text: accounts[0], color: account1Color, center: CGPoint(x: shape1Center.x, y: shape1Center.y - shapeHeight * 0.45))
            accountLabel(text: accounts[1], color: account2Color, center: CGPoint(x: shape2Center.x - shapeWidth * 0.3, y: shape2Center.y + shapeHeight * 0.4))
            accountLabel(text: accounts[2], color: account3Color, center: CGPoint(x: shape3Center.x + shapeWidth * 0.3, y: shape3Center.y + shapeHeight * 0.4))
            
            // All three accounts overlap - need to check all three accounts
            let allThreeStocks = sharedData.filter { $0.accounts.count == 3 }
            let account1Size = CGSize(width: shapeWidth, height: shapeHeight)
            let account2Size = CGSize(width: shapeWidth, height: shapeHeight)
            let account3Size = CGSize(width: shapeWidth, height: shapeHeight)
            let centerPositions = calculatePositionsInThreeWayOverlap(
                stocks: allThreeStocks,
                overlapCenter: center,
                radius: min(shapeWidth, shapeHeight) * 0.2,
                account1Center: shape1Center,
                account1Size: account1Size,
                account2Center: shape2Center,
                account2Size: account2Size,
                account3Center: shape3Center,
                account3Size: account3Size
            )
            
            ForEach(Array(allThreeStocks.enumerated()), id: \.element.ticker) { index, stock in
                if index < centerPositions.count {
                    PositionCircle(
                        ticker: stock.ticker,
                        value: stock.totalValue,
                        color: stock.color,
                        size: circleSize(stock.totalValue),
                        position: centerPositions[index],
                        showDollarAmounts: showDollarAmounts
                    )
                }
            }
            
            // Pairwise overlaps
            renderPairwiseOverlap(accounts: [accounts[0], accounts[1]], exclude: accounts[2], shape1Center: shape1Center, shape2Center: shape2Center, shape3Center: shape3Center, shapeWidth: shapeWidth, shapeHeight: shapeHeight)
            renderPairwiseOverlap(accounts: [accounts[0], accounts[2]], exclude: accounts[1], shape1Center: shape1Center, shape2Center: shape3Center, shape3Center: shape2Center, shapeWidth: shapeWidth, shapeHeight: shapeHeight)
            renderPairwiseOverlap(accounts: [accounts[1], accounts[2]], exclude: accounts[0], shape1Center: shape2Center, shape2Center: shape3Center, shape3Center: shape1Center, shapeWidth: shapeWidth, shapeHeight: shapeHeight)
            
            // Single account stocks - adjusted for vertical layout
            renderSingleAccountStocks(account: accounts[0], center: shape1Center, shape1Center: shape1Center, shape2Center: shape2Center, shape3Center: shape3Center, shapeWidth: shapeWidth, shapeHeight: shapeHeight, offset: CGPoint(x: 0, y: -shapeHeight * 0.25))
            renderSingleAccountStocks(account: accounts[1], center: shape2Center, shape1Center: shape1Center, shape2Center: shape2Center, shape3Center: shape3Center, shapeWidth: shapeWidth, shapeHeight: shapeHeight, offset: CGPoint(x: -shapeWidth * 0.15, y: shapeHeight * 0.25))
            renderSingleAccountStocks(account: accounts[2], center: shape3Center, shape1Center: shape1Center, shape2Center: shape2Center, shape3Center: shape3Center, shapeWidth: shapeWidth, shapeHeight: shapeHeight, offset: CGPoint(x: shapeWidth * 0.15, y: shapeHeight * 0.25))
        }
    }
    
    // MARK: - Helper Views
    
    private func accountShape(color: Color, center: CGPoint, width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(color.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                color.opacity(0.8),
                                color.opacity(0.4)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
            .frame(width: width, height: height)
            .position(center)
    }
    
    private func accountLabel(text: String, color: Color, center: CGPoint) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundColor(color)
            .padding(.horizontal, 11)
            .padding(.vertical, 5.5)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
                    .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
            )
            .position(center)
    }
    
    // MARK: - Stock Rendering Helpers
    
    private func renderPairwiseOverlap(accounts: [String], exclude: String, shape1Center: CGPoint, shape2Center: CGPoint, shape3Center: CGPoint, shapeWidth: CGFloat, shapeHeight: CGFloat) -> some View {
        let overlapCenter = CGPoint(
            x: (shape1Center.x + shape2Center.x) / 2,
            y: (shape1Center.y + shape2Center.y) / 2
        )
        let stocks = sharedData.filter { item in
            let itemAccounts = Set(item.accounts)
            return itemAccounts.contains(accounts[0]) && itemAccounts.contains(accounts[1]) && !itemAccounts.contains(exclude)
        }
        // For three-account view, we need to find which two accounts are overlapping
        let account1Index = accounts[0] == self.accounts[0] ? 0 : (accounts[0] == self.accounts[1] ? 1 : 2)
        let account2Index = accounts[1] == self.accounts[0] ? 0 : (accounts[1] == self.accounts[1] ? 1 : 2)
        let account1Center = account1Index == 0 ? shape1Center : (account1Index == 1 ? shape2Center : shape3Center)
        let account2Center = account2Index == 0 ? shape1Center : (account2Index == 1 ? shape2Center : shape3Center)
        let account1Size = CGSize(width: shapeWidth, height: shapeHeight)
        let account2Size = CGSize(width: shapeWidth, height: shapeHeight)
        
        let positions = calculatePositionsInOverlap(
            stocks: stocks,
            overlapCenter: overlapCenter,
            radius: min(shapeWidth, shapeHeight) * 0.18,
            account1Center: account1Center,
            account1Size: account1Size,
            account2Center: account2Center,
            account2Size: account2Size
        )
        
        return ForEach(Array(stocks.enumerated()), id: \.element.ticker) { index, stock in
            if index < positions.count {
                PositionCircle(
                    ticker: stock.ticker,
                    value: stock.totalValue,
                    color: stock.color,
                    size: circleSize(stock.totalValue),
                    position: positions[index],
                    showDollarAmounts: showDollarAmounts
                )
            }
        }
    }
    
    private func renderSingleAccountStocks(account: String, center: CGPoint, shape1Center: CGPoint, shape2Center: CGPoint, shape3Center: CGPoint, shapeWidth: CGFloat, shapeHeight: CGFloat, offset: CGPoint) -> some View {
        let stocks = sharedData.filter { item in
            item.accounts.count == 1 && item.accounts.contains(account)
        }
        // Find which account this is for
        let accountIndex = account == accounts[0] ? 0 : (account == accounts[1] ? 1 : 2)
        let accountCenter = accountIndex == 0 ? shape1Center : (accountIndex == 1 ? shape2Center : shape3Center)
        let accountSize = CGSize(width: shapeWidth, height: shapeHeight)
        let otherAccount1Center = accountIndex == 0 ? shape2Center : shape1Center
        let otherAccount1Size = CGSize(width: shapeWidth, height: shapeHeight)
        let _ = accountIndex == 2 ? shape2Center : shape3Center // otherAccount2Center
        let _ = CGSize(width: shapeWidth, height: shapeHeight) // otherAccount2Size
        
        let positions = calculatePositionsInRegion(
            stocks: stocks,
            regionCenter: CGPoint(x: center.x + offset.x, y: center.y + offset.y),
            regionSize: CGSize(width: shapeWidth * 0.5, height: shapeHeight * 0.3),
            account1Center: accountCenter,
            account1Size: accountSize,
            account2Center: otherAccount1Center,
            account2Size: otherAccount1Size,
            isAccount1Only: true
        )
        
        return ForEach(Array(stocks.enumerated()), id: \.element.ticker) { index, stock in
            if index < positions.count {
                PositionCircle(
                    ticker: stock.ticker,
                    value: stock.totalValue,
                    color: stock.color,
                    size: circleSize(stock.totalValue),
                    position: positions[index],
                    showDollarAmounts: showDollarAmounts
                )
            }
        }
    }
    
    // MARK: - Position Calculation
    
    private func calculatePositionsInThreeWayOverlap(
        stocks: [(ticker: String, accounts: [String], totalValue: Double, color: Color)],
        overlapCenter: CGPoint,
        radius: CGFloat,
        account1Center: CGPoint,
        account1Size: CGSize,
        account2Center: CGPoint,
        account2Size: CGSize,
        account3Center: CGPoint,
        account3Size: CGSize
    ) -> [CGPoint] {
        guard !stocks.isEmpty else { return [] }
        var positions: [CGPoint] = []
        let sizes: [CGFloat] = stocks.map { circleSize($0.totalValue) }
        
        if stocks.count == 1 {
            positions.append(overlapCenter)
        } else {
            let angleStep = 2 * .pi / Double(stocks.count)
            let maxRadius = radius * 0.7
            
            for (index, _) in stocks.enumerated() {
                let angle = Double(index) * angleStep
                let spiralRadius = maxRadius * sqrt(Double(index + 1) / Double(stocks.count))
                let x = overlapCenter.x + spiralRadius * cos(angle)
                let y = overlapCenter.y + spiralRadius * sin(angle)
                positions.append(CGPoint(x: x, y: y))
            }
            
            resolveCollisionsInThreeWayOverlap(
                positions: &positions,
                sizes: sizes,
                center: overlapCenter,
                radius: radius,
                account1Center: account1Center,
                account1Size: account1Size,
                account2Center: account2Center,
                account2Size: account2Size,
                account3Center: account3Center,
                account3Size: account3Size
            )
        }
        
        return positions
    }
    
    private func isPointInRoundedRect(_ point: CGPoint, center: CGPoint, size: CGSize, bubbleRadius: CGFloat) -> Bool {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        let cornerRadius: CGFloat = 20
        
        let minX = center.x - halfWidth + cornerRadius
        let maxX = center.x + halfWidth - cornerRadius
        let minY = center.y - halfHeight + cornerRadius
        let maxY = center.y + halfHeight - cornerRadius
        
        if point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY {
            return true
        }
        
        let corners = [
            CGPoint(x: center.x - halfWidth + cornerRadius, y: center.y - halfHeight + cornerRadius),
            CGPoint(x: center.x + halfWidth - cornerRadius, y: center.y - halfHeight + cornerRadius),
            CGPoint(x: center.x - halfWidth + cornerRadius, y: center.y + halfHeight - cornerRadius),
            CGPoint(x: center.x + halfWidth - cornerRadius, y: center.y + halfHeight - cornerRadius)
        ]
        
        for corner in corners {
            let dx = point.x - corner.x
            let dy = point.y - corner.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist <= cornerRadius + bubbleRadius {
                let inTopLeft = point.x <= minX && point.y <= minY
                let inTopRight = point.x >= maxX && point.y <= minY
                let inBottomLeft = point.x <= minX && point.y >= maxY
                let inBottomRight = point.x >= maxX && point.y >= maxY
                
                if inTopLeft && corner == corners[0] { return true }
                if inTopRight && corner == corners[1] { return true }
                if inBottomLeft && corner == corners[2] { return true }
                if inBottomRight && corner == corners[3] { return true }
            }
        }
        
        return false
    }
    
    private func isPointInThreeWayOverlap(_ point: CGPoint, bubbleRadius: CGFloat, account1Center: CGPoint, account1Size: CGSize, account2Center: CGPoint, account2Size: CGSize, account3Center: CGPoint, account3Size: CGSize) -> Bool {
        let inAccount1 = isPointInRoundedRect(point, center: account1Center, size: account1Size, bubbleRadius: bubbleRadius)
        let inAccount2 = isPointInRoundedRect(point, center: account2Center, size: account2Size, bubbleRadius: bubbleRadius)
        let inAccount3 = isPointInRoundedRect(point, center: account3Center, size: account3Size, bubbleRadius: bubbleRadius)
        return inAccount1 && inAccount2 && inAccount3
    }
    
    private func constrainToThreeWayOverlap(_ point: CGPoint, bubbleRadius: CGFloat, account1Center: CGPoint, account1Size: CGSize, account2Center: CGPoint, account2Size: CGSize, account3Center: CGPoint, account3Size: CGSize) -> CGPoint {
        var constrained = point
        
        if !isPointInThreeWayOverlap(constrained, bubbleRadius: bubbleRadius, account1Center: account1Center, account1Size: account1Size, account2Center: account2Center, account2Size: account2Size, account3Center: account3Center, account3Size: account3Size) {
            let overlapCenter = CGPoint(
                x: (account1Center.x + account2Center.x + account3Center.x) / 3,
                y: (account1Center.y + account2Center.y + account3Center.y) / 3
            )
            
            let dx = overlapCenter.x - constrained.x
            let dy = overlapCenter.y - constrained.y
            let dist = sqrt(dx * dx + dy * dy)
            
            if dist > 0 {
                let step = min(dist, 10.0)
                constrained = CGPoint(
                    x: constrained.x + (dx / dist) * step,
                    y: constrained.y + (dy / dist) * step
                )
            }
        }
        
        return constrained
    }
    
    private func resolveCollisionsInThreeWayOverlap(
        positions: inout [CGPoint],
        sizes: [CGFloat],
        center: CGPoint,
        radius: CGFloat,
        account1Center: CGPoint,
        account1Size: CGSize,
        account2Center: CGPoint,
        account2Size: CGSize,
        account3Center: CGPoint,
        account3Size: CGSize
    ) {
        for _ in 0..<50 {
            var hasCollision = false
            
            for i in 0..<positions.count {
                positions[i] = constrainToThreeWayOverlap(
                    positions[i],
                    bubbleRadius: sizes[i] * 0.5,
                    account1Center: account1Center,
                    account1Size: account1Size,
                    account2Center: account2Center,
                    account2Size: account2Size,
                    account3Center: account3Center,
                    account3Size: account3Size
                )
                
                let dist = sqrt(pow(positions[i].x - center.x, 2) + pow(positions[i].y - center.y, 2))
                let margin = sizes[i] * 0.5
                if dist + margin > radius {
                    let angle = atan2(positions[i].y - center.y, positions[i].x - center.x)
                    positions[i] = CGPoint(
                        x: center.x + (radius - margin) * cos(angle),
                        y: center.y + (radius - margin) * sin(angle)
                    )
                }
                
                for j in (i+1)..<positions.count {
                    let dx = positions[i].x - positions[j].x
                    let dy = positions[i].y - positions[j].y
                    let distance = sqrt(dx * dx + dy * dy)
                    let minDistance = sizes[i] + sizes[j] + 15
                    
                    if distance < minDistance && distance > 0 {
                        hasCollision = true
                        let overlap = minDistance - distance
                        let nx = dx / distance
                        let ny = dy / distance
                        
                        positions[i].x += nx * overlap * 0.5
                        positions[i].y += ny * overlap * 0.5
                        positions[j].x -= nx * overlap * 0.5
                        positions[j].y -= ny * overlap * 0.5
                        
                        positions[i] = constrainToThreeWayOverlap(
                            positions[i],
                            bubbleRadius: sizes[i] * 0.5,
                            account1Center: account1Center,
                            account1Size: account1Size,
                            account2Center: account2Center,
                            account2Size: account2Size,
                            account3Center: account3Center,
                            account3Size: account3Size
                        )
                        positions[j] = constrainToThreeWayOverlap(
                            positions[j],
                            bubbleRadius: sizes[j] * 0.5,
                            account1Center: account1Center,
                            account1Size: account1Size,
                            account2Center: account2Center,
                            account2Size: account2Size,
                            account3Center: account3Center,
                            account3Size: account3Size
                        )
                    }
                }
            }
            
            if !hasCollision { break }
        }
    }
    
    private func calculatePositionsInOverlap(
        stocks: [(ticker: String, accounts: [String], totalValue: Double, color: Color)],
        overlapCenter: CGPoint,
        radius: CGFloat,
        account1Center: CGPoint,
        account1Size: CGSize,
        account2Center: CGPoint,
        account2Size: CGSize
    ) -> [CGPoint] {
        guard !stocks.isEmpty else { return [] }
        var positions: [CGPoint] = []
        let sizes: [CGFloat] = stocks.map { circleSize($0.totalValue) }
        
        if stocks.count == 1 {
            positions.append(overlapCenter)
        } else {
            let angleStep = 2 * .pi / Double(stocks.count)
            let maxRadius = radius * 0.7
            
            for (index, _) in stocks.enumerated() {
                let angle = Double(index) * angleStep
                let spiralRadius = maxRadius * sqrt(Double(index + 1) / Double(stocks.count))
                let x = overlapCenter.x + spiralRadius * cos(angle)
                let y = overlapCenter.y + spiralRadius * sin(angle)
                positions.append(CGPoint(x: x, y: y))
            }
            
            resolveCollisions(positions: &positions, sizes: sizes, center: overlapCenter, radius: radius)
        }
        
        return positions
    }
    
    private func calculatePositionsInRegion(
        stocks: [(ticker: String, accounts: [String], totalValue: Double, color: Color)],
        regionCenter: CGPoint,
        regionSize: CGSize,
        account1Center: CGPoint,
        account1Size: CGSize,
        account2Center: CGPoint,
        account2Size: CGSize,
        isAccount1Only: Bool
    ) -> [CGPoint] {
        guard !stocks.isEmpty else { return [] }
        var positions: [CGPoint] = []
        let sizes: [CGFloat] = stocks.map { circleSize($0.totalValue) }
        
        let padding: CGFloat = 25
        let availableWidth = regionSize.width - padding * 2
        let availableHeight = regionSize.height - padding * 2
        
        if stocks.count <= 3 {
            let cols = stocks.count <= 2 ? stocks.count : 2
            let rows = (stocks.count + cols - 1) / cols
            let cellWidth = availableWidth / CGFloat(cols)
            let cellHeight = availableHeight / CGFloat(rows)
            
            for (index, _) in stocks.enumerated() {
                let col = index % cols
                let row = index / cols
                let x = regionCenter.x - regionSize.width/2 + padding + cellWidth * (CGFloat(col) + 0.5)
                let y = regionCenter.y - regionSize.height/2 + padding + cellHeight * (CGFloat(row) + 0.5)
                positions.append(CGPoint(x: x, y: y))
            }
        } else {
            let angleStep = 2 * .pi / Double(stocks.count)
            let maxRadius = min(availableWidth, availableHeight) * 0.35
            
            for (index, _) in stocks.enumerated() {
                let angle = Double(index) * angleStep
                let spiralRadius = maxRadius * sqrt(Double(index + 1) / Double(stocks.count))
                let x = regionCenter.x + spiralRadius * cos(angle)
                let y = regionCenter.y + spiralRadius * sin(angle)
                positions.append(CGPoint(x: x, y: y))
            }
            
            resolveCollisionsInRegion(positions: &positions, sizes: sizes, regionCenter: regionCenter, regionSize: regionSize, padding: padding)
        }
        
        return positions
    }
    
    private func resolveCollisions(positions: inout [CGPoint], sizes: [CGFloat], center: CGPoint, radius: CGFloat) {
        for _ in 0..<30 {
            var hasCollision = false
            
            for i in 0..<positions.count {
                let dist = sqrt(pow(positions[i].x - center.x, 2) + pow(positions[i].y - center.y, 2))
                let margin = sizes[i] * 0.6
                if dist + margin > radius {
                    let angle = atan2(positions[i].y - center.y, positions[i].x - center.x)
                    positions[i] = CGPoint(
                        x: center.x + (radius - margin) * cos(angle),
                        y: center.y + (radius - margin) * sin(angle)
                    )
                }
                
                for j in (i+1)..<positions.count {
                    let dx = positions[i].x - positions[j].x
                    let dy = positions[i].y - positions[j].y
                    let distance = sqrt(dx * dx + dy * dy)
                    let minDistance = sizes[i] + sizes[j] + 15
                    
                    if distance < minDistance && distance > 0 {
                        hasCollision = true
                        let overlap = minDistance - distance
                        let nx = dx / distance
                        let ny = dy / distance
                        
                        positions[i].x += nx * overlap * 0.5
                        positions[i].y += ny * overlap * 0.5
                        positions[j].x -= nx * overlap * 0.5
                        positions[j].y -= ny * overlap * 0.5
                    }
                }
            }
            
            if !hasCollision { break }
        }
    }
    
    private func resolveCollisionsInRegion(positions: inout [CGPoint], sizes: [CGFloat], regionCenter: CGPoint, regionSize: CGSize, padding: CGFloat) {
        for _ in 0..<30 {
            var hasCollision = false
            
            for i in 0..<positions.count {
                let margin = sizes[i] * 0.6
                let minX = regionCenter.x - regionSize.width/2 + padding + margin
                let maxX = regionCenter.x + regionSize.width/2 - padding - margin
                let minY = regionCenter.y - regionSize.height/2 + padding + margin
                let maxY = regionCenter.y + regionSize.height/2 - padding - margin
                
                positions[i].x = max(minX, min(maxX, positions[i].x))
                positions[i].y = max(minY, min(maxY, positions[i].y))
                
                for j in (i+1)..<positions.count {
                    let dx = positions[i].x - positions[j].x
                    let dy = positions[i].y - positions[j].y
                    let distance = sqrt(dx * dx + dy * dy)
                    let minDistance = sizes[i] + sizes[j] + 15
                    
                    if distance < minDistance && distance > 0 {
                        hasCollision = true
                        let overlap = minDistance - distance
                        let nx = dx / distance
                        let ny = dy / distance
                        
                        positions[i].x += nx * overlap * 0.5
                        positions[i].y += ny * overlap * 0.5
                        positions[j].x -= nx * overlap * 0.5
                        positions[j].y -= ny * overlap * 0.5
                    }
                }
            }
            
            if !hasCollision { break }
        }
    }
    
}

// MARK: - Position Circle Component

struct PositionCircle: View {
    let ticker: String
    let value: Double
    let color: Color
    let size: CGFloat
    let position: CGPoint
    let showDollarAmounts: Bool
    @State private var isHovered = false
    
    var body: some View {
        ZStack {
            // Outer glow effect
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            color.opacity(0.3),
                            color.opacity(0.0)
                        ]),
                        center: .center,
                        startRadius: size * 0.3,
                        endRadius: size * 0.8
                    )
                )
                .frame(width: size * 1.6, height: size * 1.6)
                .blur(radius: 4)
            
            // Main circle with gradient
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            color.opacity(0.95),
                            color.opacity(0.85)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.6),
                                    color.opacity(0.8)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.4), radius: 6, x: 0, y: 3)
            
            // Ticker label
            Text(ticker)
                .font(.system(size: min(size * 0.35, 18), weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 1)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .position(position)
        .overlay(
            Group {
                if isHovered {
                    VStack(spacing: 6) {
                        Text(ticker)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                        if showDollarAmounts {
                            Text("$\(Int(round(value)))")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(UIColor.systemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(color.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                    )
                    .offset(y: -size - 25)
                }
            }
        )
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered.toggle()
            }
        }
    }
}
