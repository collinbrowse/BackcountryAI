import SwiftUI
import UIKit

/// The "Alpenglow" palette: warm ember on pine and glacier, with a paper-warm light mode and a
/// deep-forest dark mode. Every color adapts to light and dark.
enum Theme {
    static let ember = Color(light: 0xF2683A, dark: 0xFF7A4A)
    static let emberDeep = Color(light: 0xD9481F, dark: 0xF2683A)
    static let gold = Color(light: 0xF2A93B, dark: 0xF5B84F)
    static let pine = Color(light: 0x1E4636, dark: 0x7FC4A0)
    static let moss = Color(light: 0x4C7A5A, dark: 0x8FBF9A)
    static let sky = Color(light: 0x3E8FC2, dark: 0x6DB6E3)
    static let danger = Color(light: 0xD93A3F, dark: 0xFF5C61)

    static let background = Color(light: 0xF6F2EA, dark: 0x0D1512)
    static let card = Color(light: 0xFFFFFF, dark: 0x16211C)
    static let cardRaised = Color(light: 0xFBF8F3, dark: 0x1D2A24)
    static let ink = Color(light: 0x1B2420, dark: 0xEEF2EE)
    static let inkSoft = Color(light: 0x5E6B64, dark: 0x9DABA3)
    static let hairline = Color(light: 0xE6DFD3, dark: 0x26332D)

    static let emberGradient = LinearGradient(colors: [gold, ember, emberDeep],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Color {
    /// A color with separate light- and dark-mode values, as 0xRRGGBB.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Surfaces

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = 22
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: .rect(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

extension View {
    func card(padding: CGFloat = 16, radius: CGFloat = 22) -> some View {
        modifier(CardBackground(padding: padding, radius: radius))
    }

    /// Section label used across screens.
    func sectionLabel() -> some View {
        font(.footnote.weight(.bold)).textCase(.uppercase).tracking(0.8).foregroundStyle(Theme.inkSoft)
    }
}

// MARK: - Buttons

/// Springy press for tappable cards and tiles.
struct SquishyButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.95
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// The main call to action: a warm gradient capsule.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: AnyShapeStyle = AnyShapeStyle(Theme.emberGradient)
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(tint, in: .capsule)
            .opacity(isEnabled ? 1 : 0.45)
            .shadow(color: Theme.ember.opacity(isEnabled ? 0.35 : 0), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.cardRaised, in: .capsule)
            .overlay(Capsule().strokeBorder(Theme.hairline))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Small rounded status pill, e.g. "Offline · ready".
struct Pill: View {
    let text: String
    var symbol: String? = nil
    var tint: Color = Theme.inkSoft
    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.caption2.weight(.bold)) }
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(tint.opacity(0.13), in: .capsule)
    }
}

// MARK: - Motion

extension Animation {
    static let bouncy = Animation.spring(response: 0.42, dampingFraction: 0.72)
}

/// Fades and lifts content in, staggered by `index`, the first time it appears.
struct RiseIn: ViewModifier {
    var index = 0
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                withAnimation(.bouncy.delay(reduceMotion ? 0 : Double(index) * 0.045)) { shown = true }
            }
    }
}

extension View {
    func riseIn(_ index: Int = 0) -> some View { modifier(RiseIn(index: index)) }
}
