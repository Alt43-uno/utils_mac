import SwiftUI
import AppKit

enum Theme {
    static let background = Color(hex: 0x202B43)
    static let sidebar = Color(hex: 0x182238)
    static let surface = Color(hex: 0x28354F)
    static let elevated = Color(hex: 0x303F5B)
    static let text = Color(hex: 0xEEF3FD)
    static let secondary = Color(hex: 0xA6B5D0)
    static let muted = Color(hex: 0x7082A2)
    static let accent = Color(hex: 0x6DE2C1)
    static let line = Color.white.opacity(0.075)
    static let colors: [NSColor] = [0x6BDDBA, 0xA5DE79, 0xEBD68A, 0xF3AF91, 0xE68DAC, 0xBD96EF,
                                    0x9099F1, 0x75BAF0, 0x6DDBDF, 0x75CDAC, 0xBACFE7, 0xD9C0ED].map { NSColor(hex: $0) }
    static func color(_ index: Int) -> Color { Color(nsColor: colors[abs(index) % colors.count]) }
}
extension Color {
    init(hex: Int) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
}
extension NSColor {
    convenience init(hex: Int) { self.init(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1) }
}
struct BloomButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 15).padding(.vertical, 9)
            .foregroundStyle(prominent ? Theme.sidebar : Theme.text)
            .background(destructive ? Color(hex: 0xD85D79) : (prominent ? Theme.accent : Theme.elevated), in: RoundedRectangle(cornerRadius: 9))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
struct IconButton: View {
    var symbol: String
    var help: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 13, weight: .medium)).frame(width: 29, height: 29) }
            .buttonStyle(.plain).foregroundStyle(Theme.secondary).background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
            .help(help).accessibilityLabel(help)
    }
}
struct Eyebrow: View {
    var text: String
    var body: some View { Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(Theme.muted) }
}
struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(22).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line)) }
}
struct CapacityBar: View {
    var used: Double
    var height: CGFloat = 5
    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(Theme.elevated)
                .overlay(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: [Color(hex: 0x83A3F3), Theme.accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * min(1, max(0, used)))
                }
        }.frame(height: height)
    }
}
