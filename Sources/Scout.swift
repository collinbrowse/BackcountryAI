import SwiftUI

/// Scout, the app's mascot: a pika (a small mountain cousin of the rabbit) in an ember bandana.
/// Drawn entirely with SwiftUI shapes so it can react to what the app is doing.
struct Scout: View {
    enum Mood: Equatable {
        case idle       // breathing, blinking
        case thinking   // searching the library / waiting for the model
        case writing    // the answer is streaming in
        case happy      // done, or a celebration
        case alert      // an emergency question
        case sleepy     // nothing installed yet
    }

    var mood: Mood = .idle
    var size: CGFloat = 120

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// Desyncs blinks when several Scouts are on screen.
    @State private var seed = Double.random(in: 0...10)

    /// Battery matters more than charm here: the animation stops in Low Power Mode, with Reduce Motion,
    /// and whenever the app isn't in front. It runs at 30 fps, which is plenty for a slow idle.
    private var paused: Bool {
        reduceMotion || scenePhase != .active || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { context in
            let t = paused ? 0 : context.date.timeIntervalSinceReferenceDate + seed
            figure(t)
                .frame(width: 120, height: 120)
                .scaleEffect(size / 120)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Scout the pika")
        .accessibilityHidden(true)
    }

    // MARK: Pose

    private func figure(_ t: Double) -> some View {
        let breathe = 1 + 0.018 * sin(t * 2.2)
        let hop = mood == .happy ? -abs(sin(t * 4.5)) * 7 : 0
        let tilt: Double = switch mood {
        case .thinking: sin(t * 1.3) * 6
        case .writing: sin(t * 3) * 1.5
        case .sleepy: 8
        default: 0
        }
        // An ear twitch every few seconds.
        let twitch = (t.truncatingRemainder(dividingBy: 5.3)) < 0.25 ? 12.0 : 0
        let earLift: Double = mood == .alert ? -6 : 0

        return ZStack {
            Ellipse().fill(.black.opacity(0.12)).frame(width: 70 - hop * 2, height: 8).position(x: 60, y: 113)
            ZStack {
                // Ears sit behind the body.
                ear.rotationEffect(.degrees(-14 + (mood == .alert ? -8 : 0)), anchor: .bottom)
                    .position(x: 33, y: 33 + earLift)
                ear.rotationEffect(.degrees(14 + twitch + (mood == .alert ? 8 : 0)), anchor: .bottom)
                    .position(x: 87, y: 33 + earLift)
                // Body.
                Ellipse()
                    .fill(LinearGradient(colors: [Color(hex: 0xDDA672), Color(hex: 0xB8764A)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 94, height: 86).position(x: 60, y: 66)
                Ellipse().fill(Color(hex: 0xF4DEC4)).frame(width: 58, height: 40).position(x: 60, y: 84)
                feet
                bandana
                face(t)
            }
            .scaleEffect(x: 1, y: breathe, anchor: .bottom)
            .rotationEffect(.degrees(tilt), anchor: .bottom)
            .offset(y: hop)
            if mood == .thinking { thoughtDots(t) }
            if mood == .sleepy { zzz(t) }
            if mood == .alert { alertMark.position(x: 104, y: 22) }
        }
    }

    private var ear: some View {
        ZStack {
            Circle().fill(Color(hex: 0xC4834F)).frame(width: 32, height: 32)
            Circle().fill(Color(hex: 0xF0A796)).frame(width: 17, height: 17).offset(y: 2)
        }
    }

    private var feet: some View {
        ZStack {
            Ellipse().fill(Color(hex: 0xA2643A)).frame(width: 20, height: 10).position(x: 43, y: 107)
            Ellipse().fill(Color(hex: 0xA2643A)).frame(width: 20, height: 10).position(x: 77, y: 107)
        }
    }

    private var bandana: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 30, y: 83))
                p.addQuadCurve(to: CGPoint(x: 90, y: 83), control: CGPoint(x: 60, y: 95))
                p.addLine(to: CGPoint(x: 88, y: 89))
                p.addQuadCurve(to: CGPoint(x: 32, y: 89), control: CGPoint(x: 60, y: 101))
                p.closeSubpath()
            }
            .fill(Theme.emberDeep)
            Path { p in
                p.move(to: CGPoint(x: 44, y: 90))
                p.addLine(to: CGPoint(x: 76, y: 90))
                p.addQuadCurve(to: CGPoint(x: 60, y: 108), control: CGPoint(x: 66, y: 102))
                p.addQuadCurve(to: CGPoint(x: 44, y: 90), control: CGPoint(x: 54, y: 102))
            }
            .fill(LinearGradient(colors: [Color(hex: 0xFF8A55), Color(hex: 0xE5532A)], startPoint: .top, endPoint: .bottom))
            Circle().fill(.white.opacity(0.8)).frame(width: 3, height: 3).position(x: 55, y: 95)
            Circle().fill(.white.opacity(0.8)).frame(width: 3, height: 3).position(x: 65, y: 96)
            Circle().fill(.white.opacity(0.8)).frame(width: 3, height: 3).position(x: 60, y: 101)
        }
    }

    private func face(_ t: Double) -> some View {
        let blinking = (t.truncatingRemainder(dividingBy: 4.1)) < 0.13
        let look: CGSize = switch mood {
        case .thinking: CGSize(width: 2.5 * sin(t * 1.7), height: -2.5)
        case .writing: CGSize(width: 1.5 * sin(t * 3.4), height: 2)
        default: .zero
        }
        return ZStack {
            eye(blinking: blinking).offset(look).position(x: 45, y: 59)
            eye(blinking: blinking).offset(look).position(x: 75, y: 59)
            Ellipse().fill(Color(hex: 0xF29A8A).opacity(0.55)).frame(width: 13, height: 7).position(x: 34, y: 71)
            Ellipse().fill(Color(hex: 0xF29A8A).opacity(0.55)).frame(width: 13, height: 7).position(x: 86, y: 71)
            Capsule().fill(Color(hex: 0x5A3A2A)).frame(width: 8, height: 5).position(x: 60, y: 68)
            mouth.stroke(Color(hex: 0x5A3A2A), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }
    }

    @ViewBuilder private func eye(blinking: Bool) -> some View {
        let ink = Color(hex: 0x2A1E17)
        switch mood {
        case .happy:
            Path { p in
                p.move(to: CGPoint(x: 0, y: 6))
                p.addQuadCurve(to: CGPoint(x: 10, y: 6), control: CGPoint(x: 5, y: -2))
            }
            .stroke(ink, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            .frame(width: 10, height: 8)
        case .sleepy:
            Capsule().fill(ink).frame(width: 9, height: 2.4)
        default:
            let big = mood == .alert
            ZStack {
                Ellipse().fill(ink).frame(width: big ? 11 : 9, height: big ? 13 : 11)
                Circle().fill(.white).frame(width: 3.5, height: 3.5).offset(x: -1.6, y: -2.6)
            }
            .scaleEffect(x: 1, y: blinking ? 0.1 : 1)
        }
    }

    private var mouth: Path {
        Path { p in
            switch mood {
            case .happy:
                p.move(to: CGPoint(x: 54, y: 72))
                p.addQuadCurve(to: CGPoint(x: 66, y: 72), control: CGPoint(x: 60, y: 80))
            case .alert:
                p.addEllipse(in: CGRect(x: 57.5, y: 72, width: 5, height: 6))
            default:
                p.move(to: CGPoint(x: 56, y: 72))
                p.addQuadCurve(to: CGPoint(x: 60, y: 73), control: CGPoint(x: 58, y: 75))
                p.addQuadCurve(to: CGPoint(x: 64, y: 72), control: CGPoint(x: 62, y: 75))
            }
        }
    }

    private func thoughtDots(_ t: Double) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle().fill(Theme.ember)
                    .frame(width: 6, height: 6)
                    .opacity(0.35 + 0.65 * max(0, sin(t * 4 - Double(i) * 0.9)))
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(Theme.card, in: .capsule)
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .position(x: 104, y: 18)
    }

    private func zzz(_ t: Double) -> some View {
        let phase = (t * 0.6).truncatingRemainder(dividingBy: 1)
        return Text("z").font(.system(size: 16, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.sky)
            .opacity(1 - phase)
            .offset(x: phase * 10, y: -phase * 18)
            .position(x: 100, y: 28)
    }

    private var alertMark: some View {
        Text("!").font(.system(size: 18, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Theme.danger, in: .circle)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

#Preview {
    HStack {
        Scout(mood: .idle, size: 90)
        Scout(mood: .thinking, size: 90)
        Scout(mood: .happy, size: 90)
    }
}
