import SwiftUI
import UIKit

/// Sword-handed clock. Each hand is a full-size layer centered on the pivot, so rotating the image rotates the blade.
struct ClockFace: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(reduceMotion ? .periodic(from: .now, by: 1) : .animation(minimumInterval: 1.0 / 30)) { tl in
            let c = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: tl.date)
            let s = Double(c.second ?? 0) + (reduceMotion ? 0 : Double(c.nanosecond ?? 0) / 1e9)
            let m = Double(c.minute ?? 0) + s / 60
            let h = Double((c.hour ?? 0) % 12) + m / 60
            ZStack {
                art("face").resizable().scaledToFit()
                art("hand-hour").resizable().scaledToFit().rotationEffect(.degrees(h * 30))
                art("hand-min").resizable().scaledToFit().rotationEffect(.degrees(m * 6))
                art("hand-sec").resizable().scaledToFit().rotationEffect(.degrees(s * 6))
                art("cap").resizable().scaledToFit()
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Clock")
    }
}

struct ClockStage: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                ClockFace()
                    .frame(width: w * 0.96, height: w * 0.96)
                    .position(x: w / 2, y: w / 2)
                art("mask").resizable().scaledToFit()
                    .frame(width: w * 0.22)
                    .rotationEffect(.degrees(-14))
                    .shadow(color: .black.opacity(0.8), radius: 10, y: 8)
                    .position(x: w * 0.13, y: w * 0.80)
                art("knife").resizable().scaledToFit()
                    .frame(width: w * 0.10)
                    .rotationEffect(.degrees(22))
                    .shadow(color: .black.opacity(0.8), radius: 10, y: 8)
                    .position(x: w * 0.88, y: w * 0.76)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct Readout: View {
    @EnvironmentObject var store: Store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let now = tl.date
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(clockTime(now))
                        .font(Theme.heavy(96))
                        .monospacedDigit()
                        .shadow(color: Theme.bloodHi.opacity(0.35), radius: 16)
                    Text(amPM(now))
                        .font(Theme.heavy(34))
                        .foregroundStyle(Theme.bloodHi)
                }
                .foregroundStyle(Theme.bone)
                Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(Theme.gothic(24))
                    .foregroundStyle(Theme.ash)
                status(now)
                    .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private func status(_ now: Date) -> some View {
        HStack(spacing: 10) {
            if let s = store.snoozeUntil {
                Pill(text: "Snoozing", on: true)
                Text("Back at \(clockTime(s)) \(amPM(s))")
            } else if store.settings.armed, let a = store.occurrences(after: now, count: 1).first {
                Pill(text: "Armed", on: true)
                Text("\(a.formatted(.dateTime.weekday(.abbreviated))) \(clockTime(a)) \(amPM(a)) · tolls in \(until(a.timeIntervalSince(now)))")
            } else if store.settings.armed {
                Pill(text: "Armed", on: true)
                Text("Pick at least one day")
            } else {
                Pill(text: "Off")
                Text("No alarm armed")
            }
        }
        .font(Theme.body(19))
        .foregroundStyle(Theme.bone)
    }

    private func until(_ secs: TimeInterval) -> String {
        let mins = Int((secs / 60).rounded(.up))
        return mins >= 60 ? "\(mins / 60)h \(mins % 60)m" : "\(mins)m"
    }
}

/// Blood band across the top of the screen with drips that stretch, then let a drop fall.
struct BloodBand: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let drips = (0..<9).map(Drip.init)

    struct Drip {
        let x, width, length, period, phase: Double
        init(_ i: Int) {
            func r(_ k: Double) -> Double { let v = sin(Double(i) * 12.9898 + k * 78.233) * 43758.5453; return v - floor(v) }
            x = (Double(i) + 0.2 + r(1) * 0.6) / 9
            width = 3 + r(2) * 5
            length = 18 + r(3) * 70
            period = 7 + r(4) * 9
            phase = r(5) * 12
        }
    }

    var body: some View {
        let top = Self.topInset
        TimelineView(reduceMotion ? .periodic(from: .now, by: 60) : .animation(minimumInterval: 1.0 / 30)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                var band = Path()
                band.move(to: .zero)
                band.addLine(to: CGPoint(x: size.width, y: 0))
                band.addLine(to: CGPoint(x: size.width, y: top + 8))
                let steps = 25
                for i in stride(from: steps, to: 0, by: -1) {
                    let x0 = size.width * Double(i - 1) / Double(steps)
                    let xm = size.width * (Double(i) - 0.5) / Double(steps)
                    let dip = 10 + 14 * abs(sin(Double(i) * 1.7))
                    band.addQuadCurve(to: CGPoint(x: x0, y: top + 6 + 4 * abs(cos(Double(i) * 2.3))),
                                      control: CGPoint(x: xm, y: top + dip))
                }
                band.closeSubpath()
                ctx.fill(band, with: .color(Theme.blood))

                for d in drips {
                    let x = d.x * size.width
                    let p = reduceMotion ? 0.8 : ((t + d.phase).truncatingRemainder(dividingBy: d.period)) / d.period
                    let grow = min(1, p / 0.72)
                    let len = 4 + (d.length - 4) * grow * grow
                    let rect = CGRect(x: x - d.width / 2, y: top + 4, width: d.width, height: len + 8)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: d.width / 2), with: .color(Theme.blood))
                    if p > 0.72 {
                        let f = (p - 0.72) / 0.28
                        let y = top + 12 + len + f * f * size.height
                        let w = d.width * 1.5
                        ctx.fill(Path(ellipseIn: CGRect(x: x - w / 2, y: y, width: w, height: w * 1.33)), with: .color(Theme.blood))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static var topInset: CGFloat {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.windows.first?.safeAreaInsets.top ?? 47
    }
}

struct Backdrop: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            Theme.void
            RadialGradient(colors: [Theme.crypt2, Theme.void], center: .init(x: 0.5, y: 0.3), startRadius: 0, endRadius: 520)
            if let image {
                Color.clear
                    .overlay(
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .grayscale(1)
                            .contrast(1.25)
                            .brightness(-0.1)
                            .opacity(0.32)
                    )
                    .clipped()
            }
            LinearGradient(colors: [.clear, Theme.void], startPoint: .center, endPoint: .bottom)
            RadialGradient(colors: [.clear, Theme.bloodDark.opacity(0.45)], center: .center, startRadius: 200, endRadius: 700)
        }
        .ignoresSafeArea()
    }
}
