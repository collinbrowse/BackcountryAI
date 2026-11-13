import SwiftUI

/// A candidate mascot: a lynx that looks like a 3rd grader drew it. Wobbly marker outlines gone over
/// twice, crayon scribble fills that miss the edges, a head that's too big, googly eyes, and stubby legs.
/// The outlines "boil" (redraw slightly) a few times a second, like a flip-book.
/// Same moods and size as the pika, so either can stand in for Scout.
///
/// Drawn on an 800 × 800 sketch (the coordinates below) and mapped onto a 120 × 120 canvas.
struct LynxScout: View {
    typealias Mood = MascotMood
    var mood: Mood = .idle
    var size: CGFloat = 120

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var seed = Double.random(in: 0...10)

    private var paused: Bool {
        reduceMotion || scenePhase != .active || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    // Crayons and a marker.
    private let ink = Color(hex: 0x262422)
    private let tan = Color(hex: 0xE8A85A)
    private let paper = Color(hex: 0xFFF6E6)
    private let spot = Color(hex: 0x6B3E1E)
    private let pink = Color(hex: 0xF48FA6)
    private let nosePink = Color(hex: 0xF06C8C)
    private let blue = Color(hex: 0x2E6FE0)
    private let mouthRed = Color(hex: 0x9A2E36)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { context in
            let t = paused ? 0 : context.date.timeIntervalSinceReferenceDate + seed
            figure(t)
                .frame(width: 120, height: 120)
                .scaleEffect(size / 120)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Scout the lynx")
        .accessibilityHidden(true)
    }

    // MARK: Pose

    private func figure(_ t: Double) -> some View {
        // Outlines redraw ~3 times a second; fills stay put.
        let boil = UInt64(max(0, Int(t * 3) % 4))
        let hop: CGFloat = mood == .happy ? -CGFloat(abs(sin(t * 5))) * 4 : 0
        let shake: CGFloat = mood == .alert ? CGFloat(sin(t * 38)) * 0.7 : 0
        let headTurn: Double = switch mood {
        case .thinking: -7 + sin(t * 1.2) * 3
        case .writing: 7
        case .sleepy: 12
        case .happy: sin(t * 5) * 4
        default: sin(t * 0.8) * 1.5
        }
        return ZStack {
            Ellipse().fill(.black.opacity(0.10)).frame(width: 70, height: 5).position(x: 58, y: 114)
            ZStack {
                tail(t, boil)
                bodyAndLegs(boil)
                head(t, boil)
                    .rotationEffect(.degrees(headTurn), anchor: UnitPoint(x: M(400, 440).x / 120, y: M(400, 440).y / 120))
                    .offset(y: mood == .sleepy ? 2 : 0)
                scarf(boil)
            }
            .offset(x: shake, y: hop)
            if mood == .thinking { thoughtDots(t) }
            if mood == .sleepy { zzz(t) }
            if mood == .alert { alertMark.position(x: 106, y: 14) }
        }
    }

    // MARK: Parts

    private func tail(_ t: Double, _ boil: UInt64) -> some View {
        let wag: Double = switch mood {
        case .happy: sin(t * 9) * 14
        case .alert: -8
        case .sleepy: 10
        default: sin(t * 1.4) * 5
        }
        let tail = pts([(520, 590), (585, 560), (640, 480), (660, 410), (690, 405), (685, 470), (640, 560), (560, 625)])
        let tip = pts([(648, 455), (660, 405), (692, 402), (690, 460), (668, 478)])
        return ZStack {
            crayon(tail, tan, angle: 60, seed: 11)
            crayon(tip, ink, gap: 1.2, angle: 30, seed: 12, under: nil)
            marker(tail, seed: 13 &+ boil)
            blob(600, 540, 8, seed: 14)
            blob(640, 500, 7, seed: 15)
        }
        .rotationEffect(.degrees(wag), anchor: UnitPoint(x: M(540, 600).x / 120, y: M(540, 600).y / 120))
    }

    private func bodyAndLegs(_ boil: UInt64) -> some View {
        let body = ell(400, 560, 150, 120, n: 14)
        let spots: [(CGFloat, CGFloat, CGFloat)] = [(330, 520, 11), (380, 490, 8), (450, 510, 12), (500, 560, 9),
                                                    (340, 590, 10), (420, 600, 13), (480, 620, 7), (290, 560, 7)]
        let legs: [CGFloat] = [300, 360, 440, 500]
        return ZStack {
            crayon(body, tan, angle: 35, seed: 21)
            marker(body, seed: 22 &+ boil)
            ForEach(legs.indices, id: \.self) { i in
                let x = legs[i]
                let leg = pts([(x - 22, 630), (x + 22, 632), (x + 24, 700), (x - 24, 702)])
                ZStack {
                    crayon(leg, tan, angle: 90, seed: 30 + UInt64(i))
                    marker(leg, width: 1.8, seed: 40 + UInt64(i) &+ boil)
                    marker(pts([(x - 8, 688), (x - 8, 701)]), closed: false, width: 1, seed: 50 + UInt64(i), twice: false)
                    marker(pts([(x + 8, 688), (x + 8, 701)]), closed: false, width: 1, seed: 60 + UInt64(i), twice: false)
                }
            }
            ForEach(spots.indices, id: \.self) { i in
                blob(spots[i].0, spots[i].1, spots[i].2, seed: 70 + UInt64(i))
            }
        }
    }

    private func scarf(_ boil: UInt64) -> some View {
        let band = pts([(290, 440), (510, 430), (515, 478), (288, 488)])
        let flap = pts([(440, 470), (510, 470), (470, 560)])
        return ZStack {
            crayon(flap, blue, gap: 1.3, angle: 80, seed: 91, under: Color(hex: 0xDCE7FB))
            marker(flap, width: 1.8, seed: 92 &+ boil)
            crayon(band, blue, gap: 1.3, angle: 5, seed: 93, under: Color(hex: 0xDCE7FB))
            marker(band, width: 1.8, seed: 94 &+ boil)
        }
    }

    private func head(_ t: Double, _ boil: UInt64) -> some View {
        let head = ell(400, 330, 150, 128, n: 16, rot: -4)
        let earLift: CGFloat = mood == .alert ? -22 : 0
        let droop: CGFloat = mood == .sleepy ? 1 : 0
        let ears: [[(CGFloat, CGFloat)]] = [
            [(282, 260), (290 - droop * 30, 120 + earLift + droop * 25), (370, 215)],
            [(430, 210), (515 + droop * 30, 115 + earLift + droop * 25), (520, 258)],
        ]
        return ZStack {
            ForEach(ears.indices, id: \.self) { i in
                ear(ears[i], seed: 100 + UInt64(i) * 10, boil: boil)
            }
            crayon(head, tan, angle: 25, seed: 121)
            marker(head, seed: 122 &+ boil)
            ForEach([375.0, 400, 425].indices, id: \.self) { i in
                let x = CGFloat([375.0, 400, 425][i])
                marker(pts([(x, 220), (x + 2, 250)]), closed: false, width: 1.3, seed: 130 + UInt64(i), twice: false, color: spot)
            }
            crayon(ell(310, 375, 26, 18), pink, gap: 1.2, angle: 10, seed: 141, under: nil)
            crayon(ell(495, 368, 26, 18), pink, gap: 1.2, angle: 10, seed: 142, under: nil)
            eyes(t, boil)
            nose(boil)
            mouth(boil)
            whiskers(boil)
        }
    }

    private func ear(_ e: [(CGFloat, CGFloat)], seed: UInt64, boil: UInt64) -> some View {
        let tri = pts(e)
        let inner = pts([(e[0].0 * 0.7 + e[1].0 * 0.3 + 8, e[0].1 * 0.6 + e[1].1 * 0.4),
                         (e[1].0, e[1].1 + 40),
                         (e[2].0 * 0.7 + e[1].0 * 0.3 - 8, e[2].1 * 0.75 + e[1].1 * 0.25)])
        let (tx, ty) = e[1]
        let tufts: [(CGFloat, CGFloat)] = [(-14, -42), (0, -50), (14, -40)]
        return ZStack {
            crayon(tri, tan, angle: 70, seed: seed)
            crayon(inner, pink, gap: 1.2, angle: 50, seed: seed + 1, under: nil)
            marker(tri, seed: seed + 2 &+ boil)
            ForEach(tufts.indices, id: \.self) { i in
                marker(pts([(tx, ty + 4), (tx + tufts[i].0, ty + tufts[i].1)]), closed: false, width: 1.4,
                       seed: seed + 3 + UInt64(i) &+ boil, twice: false)
            }
        }
    }

    // MARK: Face

    @ViewBuilder private func eyes(_ t: Double, _ boil: UInt64) -> some View {
        let blinking = (t.truncatingRemainder(dividingBy: 4.1)) < 0.13
        let eyes: [(CGFloat, CGFloat, CGFloat)] = [(345, 315, 24), (455, 310, 20)]
        ForEach(eyes.indices, id: \.self) { i in
            let (cx, cy, r) = eyes[i]
            let s = 200 + UInt64(i) * 10
            switch mood {
            case .happy:
                marker(pts([(cx - r, cy + 8), (cx, cy - 14), (cx + r, cy + 8)]), closed: false, width: 2.2, seed: s &+ boil)
            case .sleepy:
                marker(pts([(cx - r, cy + 4), (cx, cy + 12), (cx + r, cy + 5)]), closed: false, width: 2, seed: s &+ boil)
            default:
                if blinking {
                    marker(pts([(cx - r, cy + 4), (cx + r, cy + 6)]), closed: false, width: 2, seed: s &+ boil)
                } else {
                    let big: CGFloat = mood == .alert ? 1.35 : 1
                    let look: (CGFloat, CGFloat) = switch mood {
                    case .thinking: (-7, -11)
                    case .writing: (2, 11)
                    case .alert: (0, 0)
                    default: (6, 6)
                    }
                    let white = ell(cx, cy, r * big, r * 1.15 * big, n: 12)
                    let pupil = mood == .alert ? r * 0.28 : r * 0.5
                    ZStack {
                        PathShape(p: wobbly(white, amt: 0.25, seed: s + 1)).fill(.white)
                        marker(white, width: 1.5, seed: s + 2 &+ boil, amt: 0.3)
                        blob(cx + look.0, cy + look.1, pupil, seed: s + 3, color: ink)
                        blob(cx + look.0 - 4, cy + look.1 - 6, r * 0.17, seed: s + 4, color: .white)
                    }
                }
            }
        }
    }

    private func nose(_ boil: UInt64) -> some View {
        let n = pts([(385, 352), (422, 350), (404, 375)])
        return ZStack {
            PathShape(p: wobbly(n, amt: 0.25, seed: 301)).fill(nosePink)
            marker(n, width: 1.5, seed: 302 &+ boil, amt: 0.3)
        }
    }

    @ViewBuilder private func mouth(_ boil: UInt64) -> some View {
        switch mood {
        case .happy:
            // Big open D grin with a tongue.
            let grin = pts([(345, 385), (463, 380), (440, 425), (404, 442), (368, 428)])
            ZStack {
                PathShape(p: wobbly(grin, amt: 0.3, seed: 311)).fill(mouthRed)
                blob(404, 428, 13, seed: 312, color: pink)
                marker(grin, width: 1.8, seed: 313 &+ boil, amt: 0.4)
            }
        case .alert:
            let o = ell(404, 412, 16, 21, n: 10)
            ZStack {
                PathShape(p: wobbly(o, amt: 0.3, seed: 321)).fill(mouthRed)
                marker(o, width: 1.8, seed: 322 &+ boil, amt: 0.3)
            }
        case .thinking:
            marker(pts([(372, 405), (392, 397), (414, 408), (436, 399)]), closed: false, width: 1.8, seed: 331 &+ boil, twice: false)
        case .sleepy:
            marker(pts([(385, 405), (404, 411), (423, 404)]), closed: false, width: 1.8, seed: 341 &+ boil, twice: false)
        case .writing:
            // Tongue poking out the side: concentrating.
            ZStack {
                smile(boil)
                blob(428, 410, 11, seed: 351, color: pink)
                marker(ell(428, 410, 11, 11, n: 8), width: 1.2, seed: 352 &+ boil, twice: false, amt: 0.25)
            }
        case .idle:
            smile(boil)
        }
    }

    private func smile(_ boil: UInt64) -> some View {
        ZStack {
            marker(pts([(404, 376), (404, 392)]), closed: false, width: 1.6, seed: 361, twice: false, amt: 0.2)
            marker(pts([(350, 385), (375, 420), (404, 392), (432, 420), (458, 383)]), closed: false, width: 1.8,
                   seed: 362 &+ boil, amt: 0.35)
        }
    }

    private func whiskers(_ boil: UInt64) -> some View {
        let fan: CGFloat = mood == .alert ? -14 : mood == .sleepy ? 14 : 0
        let lines: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (330, 390, 200, 360), (330, 400, 190, 405), (332, 410, 215, 450),
            (470, 385, 600, 350), (470, 395, 615, 398), (468, 405, 590, 445),
        ]
        return ZStack {
            ForEach(lines.indices, id: \.self) { i in
                let l = lines[i]
                marker(pts([(l.0, l.1), (l.2, l.3 + fan)]), closed: false, width: 0.9, seed: 400 + UInt64(i) &+ boil,
                       twice: false, amt: 0.5)
            }
        }
    }

    // MARK: Drawing kit

    /// A wobbly marker line, gone over twice like a kid does.
    private func marker(_ p: [CGPoint], closed: Bool = true, width: CGFloat = 2, seed: UInt64, twice: Bool = true,
                        amt: CGFloat = 0.7, color: Color? = nil) -> some View {
        let c = color ?? ink
        let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        return ZStack {
            PathShape(p: wobbly(p, closed: closed, amt: amt, seed: seed)).stroke(c, style: style)
            if twice {
                PathShape(p: wobbly(p, closed: closed, amt: amt, seed: seed &+ 977))
                    .stroke(c.opacity(0.6), style: StrokeStyle(lineWidth: width * 0.6, lineCap: .round, lineJoin: .round))
            }
        }
    }

    /// Crayon scribbled back and forth inside a shape, missing the edges a little.
    private func crayon(_ p: [CGPoint], _ color: Color, width: CGFloat = 1.9, gap: CGFloat = 1.8, angle: Double,
                        seed: UInt64, under: Color?? = .some(nil)) -> some View {
        var rng = SplitMix(seed)
        let cx = p.map(\.x).reduce(0, +) / CGFloat(p.count), cy = p.map(\.y).reduce(0, +) / CGFloat(p.count)
        let dx = rng.jitter(0.9), dy = rng.jitter(0.9)
        let shrunk = p.map { CGPoint(x: cx + ($0.x - cx) * 0.93 + dx, y: cy + ($0.y - cy) * 0.93 + dy) }
        let fill: Color? = switch under {
        case .none: nil                 // explicitly no underlay
        case .some(.none): paper        // default
        case .some(.some(let c)): c
        }
        return ZStack {
            if let fill { PathShape(p: wobbly(p, amt: 0.3, seed: seed &+ 3)).fill(fill) }
            PathShape(p: zigzag(p, gap: gap, angle: angle, seed: seed &+ 5))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                .opacity(0.92)
                .clipShape(PathShape(p: wobbly(shrunk, amt: 0.5, seed: seed &+ 7)))
        }
    }

    private func blob(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, seed: UInt64, color: Color? = nil) -> some View {
        var rng = SplitMix(seed)
        let squash = 0.8 + CGFloat(rng.next()) * 0.3
        return PathShape(p: wobbly(ell(x, y, r, r * squash, n: 10), amt: 0.35, step: 1, seed: seed)).fill(color ?? spot)
    }

    // MARK: Badges (match the pika's)

    private func thoughtDots(_ t: Double) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle().fill(Theme.accent)
                    .frame(width: 6, height: 6)
                    .opacity(0.35 + 0.65 * max(0, sin(t * 4 - Double(i) * 0.9)))
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(Theme.card, in: .capsule)
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .position(x: 102, y: 10)
    }

    private func zzz(_ t: Double) -> some View {
        let phase = (t * 0.6).truncatingRemainder(dividingBy: 1)
        return Text("z").font(.system(size: 16, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.sky)
            .opacity(1 - phase)
            .offset(x: phase * 10, y: -phase * 18)
            .position(x: 100, y: 22)
    }

    private var alertMark: some View {
        Text("!").font(.system(size: 18, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Theme.danger, in: .circle)
    }
}

// MARK: - Geometry helpers

/// Maps the 800 × 800 sketch onto the 120 × 120 canvas.
private func M(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (x - 240) * 0.17 + 26, y: (y - 70) * 0.17 + 4) }

private func pts(_ p: [(CGFloat, CGFloat)]) -> [CGPoint] { p.map { M($0.0, $0.1) } }

/// Points around an ellipse, in sketch coordinates (mapped).
private func ell(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, n: Int = 28, rot: Double = 0) -> [CGPoint] {
    let r = rot * .pi / 180
    return (0..<n).map { i in
        let a = 2 * Double.pi * Double(i) / Double(n)
        let x = cx + rx * CGFloat(cos(a) * cos(r)) - ry * CGFloat(sin(a) * sin(r))
        let y = cy + rx * CGFloat(cos(a) * sin(r)) + ry * CGFloat(sin(a) * cos(r))
        return M(x, y)
    }
}

/// Small deterministic RNG so each line wobbles the same way every frame (until the seed changes).
private struct SplitMix {
    var state: UInt64
    init(_ seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 1 }
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
    mutating func jitter(_ a: CGFloat) -> CGFloat { CGFloat(next() * 2 - 1) * a }
}

/// Subdivides a polyline, jitters it, and smooths it into a hand-drawn path.
private func wobbly(_ p: [CGPoint], closed: Bool = true, amt: CGFloat, step: CGFloat = 3, seed: UInt64) -> Path {
    guard p.count > 1 else { return Path() }
    var rng = SplitMix(seed)
    let seq = closed ? p + [p[0]] : p
    var dense: [CGPoint] = []
    for (a, b) in zip(seq, seq.dropFirst()) {
        let n = max(1, Int(hypot(b.x - a.x, b.y - a.y) / step))
        for i in 0..<n {
            let t = CGFloat(i) / CGFloat(n)
            dense.append(CGPoint(x: a.x + (b.x - a.x) * t + rng.jitter(amt), y: a.y + (b.y - a.y) * t + rng.jitter(amt)))
        }
    }
    if closed { dense.append(dense[0]) } else {
        dense.append(CGPoint(x: seq.last!.x + rng.jitter(amt), y: seq.last!.y + rng.jitter(amt)))
    }
    var path = Path()
    path.move(to: dense[0])
    if dense.count == 2 { path.addLine(to: dense[1]); return path }
    for (a, b) in zip(dense.dropFirst(), dense.dropFirst(2)) {
        path.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a)
    }
    path.addLine(to: dense[dense.count - 1])
    return path
}

/// Back-and-forth crayon strokes across a shape's bounding box.
private func zigzag(_ p: [CGPoint], gap: CGFloat, angle: Double, seed: UInt64) -> Path {
    var rng = SplitMix(seed)
    let xs = p.map(\.x), ys = p.map(\.y)
    let x0 = xs.min()! - 3, x1 = xs.max()! + 3, y0 = ys.min()! - 3, y1 = ys.max()! + 3
    let diag = hypot(x1 - x0, y1 - y0)
    let a = angle * .pi / 180
    let u = CGPoint(x: cos(a), y: sin(a)), v = CGPoint(x: -sin(a), y: cos(a))
    let mx = (x0 + x1) / 2, my = (y0 + y1) / 2
    var path = Path()
    var k = -diag / 2, flip: CGFloat = 1, first = true
    while k < diag / 2 {
        let pt = CGPoint(x: mx + v.x * k + u.x * diag / 2 * flip + rng.jitter(1),
                         y: my + v.y * k + u.y * diag / 2 * flip + rng.jitter(1))
        if first { path.move(to: pt); first = false } else { path.addLine(to: pt) }
        flip *= -1
        k += gap + rng.jitter(gap * 0.3)
    }
    return path
}

private struct PathShape: Shape {
    var p: Path
    func path(in rect: CGRect) -> Path { p }
}

/// Debug only: every mood of both candidates side by side. Launch with `-MascotGallery`.
struct MascotGallery: View {
    static var isOn: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-MascotGallery")
        #else
        false
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Text("Mood").frame(width: 80, alignment: .leading)
                    Text("Pika").frame(maxWidth: .infinity)
                    Text("Lynx (kid)").frame(maxWidth: .infinity)
                }
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 8)
                ForEach(MascotMood.allCases, id: \.self) { mood in
                    HStack {
                        Text(String(describing: mood).capitalized)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .frame(width: 80, alignment: .leading)
                        PikaScout(mood: mood, size: 112).frame(maxWidth: .infinity)
                        LynxScout(mood: mood, size: 112).frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 4)
                    Divider().opacity(0.4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

#Preview {
    MascotGallery()
}
