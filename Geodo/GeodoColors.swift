import SwiftUI

extension Color {
    /// Cream color matching the Geodo logo (#E6E0CC)
    static let cream = Color(red: 230/255, green: 224/255, blue: 204/255)
}

extension ShapeStyle where Self == Color {
    /// Cream color matching the Geodo logo (#E6E0CC)
    static var cream: Color { .cream }
}
