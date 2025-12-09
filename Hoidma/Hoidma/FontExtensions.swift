import SwiftUI

// MARK: - Custom Font Extension
extension Font {
    // Logo font - decorative, artistic serif style (similar to Folly Nine)
    static func hoidmaLogo(size: CGFloat = 28) -> Font {
        // System serif with medium weight for decorative, artistic, hand-drawn aesthetic
        // Similar to Folly Nine: decorative serif, whimsical, artistic, hand-drawn qualities
        return .system(size: size, weight: .medium, design: .serif)
    }
    
    // Unique font styles for the app
    static func hoidmaTitle(size: CGFloat = 28) -> Font {
        // Using SF Pro Rounded for a unique, modern feel
        return .system(size: size, weight: .bold, design: .rounded)
    }
    
    static func hoidmaPrice(size: CGFloat = 56) -> Font {
        // Rounded design for numbers - clean and modern
        return .system(size: size, weight: .bold, design: .rounded)
    }
    
    static func hoidmaBody(size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        return .system(size: size, weight: weight, design: .rounded)
    }
    
    static func hoidmaMono(size: CGFloat = 16) -> Font {
        // Monospace for ticker symbols - tech/finance feel
        return .system(size: size, weight: .semibold, design: .monospaced)
    }
}

