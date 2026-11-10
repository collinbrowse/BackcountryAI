import SwiftUI

/// The header landscape: sky that follows the time of day, two mountain ridges, stars at night.
/// It fades into the app background at the bottom so content can sit on top of it.
struct Scenery: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var now = Date.now

    enum Sky { case dawn, day, dusk, night }

    private var sky: Sky {
        if colorScheme == .dark { return .night }
        switch Calendar.current.component(.hour, from: now) {
        case 5..<8: return .dawn
        case 8..<17: return .day
        case 17..<20: return .dusk
        default: return .night
        }
    }

    private var palette: (top: Color, bottom: Color, back: Color, front: Color, sun: Color) {
        switch sky {
        case .dawn: (Color(hex: 0xF4A98A), Color(hex: 0xFCE6CC), Color(hex: 0xB98A8F), Color(hex: 0x5E6F68), Color(hex: 0xFFE0A3))
        case .day: (Color(hex: 0x7EC1E6), Color(hex: 0xE3F2F7), Color(hex: 0x8FB0B8), Color(hex: 0x3F6B57), Color(hex: 0xFFF3C4))
        case .dusk: (Color(hex: 0xE7764F), Color(hex: 0xF8C99B), Color(hex: 0x9C6A70), Color(hex: 0x3D4A48), Color(hex: 0xFFD08A))
        case .night: (Color(hex: 0x0B1626), Color(hex: 0x1E3347), Color(hex: 0x2B4152), Color(hex: 0x15241F), Color(hex: 0xF3EBD2))
        }
    }

    var body: some View {
        let p = palette
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                LinearGradient(colors: [p.top, p.bottom], startPoint: .top, endPoint: .bottom)
                if sky == .night { stars(w: w, h: h) }
                // Sun or moon.
                Circle()
                    .fill(p.sun)
                    .frame(width: 46, height: 46)
                    .shadow(color: p.sun.opacity(0.8), radius: 24)
                    .overlay(alignment: .topTrailing) {
                        if sky == .night { Circle().fill(p.top).frame(width: 36, height: 36).offset(x: 10, y: -6) }
                    }
                    .position(x: w * 0.7, y: h * 0.34)
                Ridge(points: [(0, 0.58), (0.16, 0.36), (0.3, 0.5), (0.48, 0.2), (0.66, 0.46), (0.82, 0.32), (1, 0.52)])
                    .fill(p.back)
                SnowCap().fill(.white.opacity(sky == .night ? 0.35 : 0.85))
                Ridge(points: [(0, 0.78), (0.22, 0.58), (0.42, 0.72), (0.64, 0.54), (0.84, 0.7), (1, 0.62)])
                    .fill(p.front)
                LinearGradient(colors: [.clear, Theme.background], startPoint: .init(x: 0.5, y: 0.7), endPoint: .bottom)
            }
        }
        .accessibilityHidden(true)
        .onReceive(Timer.publish(every: 600, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private func stars(w: CGFloat, h: CGFloat) -> some View {
        // Fixed positions so the sky doesn't reshuffle on every redraw.
        let spots: [(CGFloat, CGFloat, CGFloat)] = [(0.08, 0.12, 2), (0.2, 0.3, 1.5), (0.33, 0.08, 2.2), (0.42, 0.26, 1.4),
            (0.56, 0.1, 1.8), (0.62, 0.34, 1.3), (0.7, 0.06, 2), (0.9, 0.42, 1.6), (0.95, 0.12, 1.4), (0.14, 0.44, 1.2),
            (0.5, 0.4, 1.1), (0.27, 0.18, 1.2)]
        return ForEach(spots.indices, id: \.self) { i in
            Circle().fill(.white.opacity(0.85)).frame(width: spots[i].2, height: spots[i].2)
                .position(x: spots[i].0 * w, y: spots[i].1 * h)
        }
    }
}

/// A ridgeline through normalized points, filled down to the bottom edge.
struct Ridge: Shape {
    let points: [(CGFloat, CGFloat)]
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            for (x, y) in points { p.addLine(to: CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height)) }
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

/// Snow on the tallest back peak (at x 0.48, y 0.2 of the back ridge).
struct SnowCap: Shape {
    func path(in r: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        return Path { p in
            p.move(to: pt(0.48, 0.2))
            p.addLine(to: pt(0.535, 0.275))
            p.addLine(to: pt(0.51, 0.27))
            p.addLine(to: pt(0.49, 0.295))
            p.addLine(to: pt(0.465, 0.27))
            p.addLine(to: pt(0.438, 0.29))
            p.closeSubpath()
        }
    }
}
