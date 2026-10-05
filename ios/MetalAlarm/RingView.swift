import SwiftUI

struct RingView: View {
    @EnvironmentObject var engine: AlarmEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hold: CGFloat = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.65)) { tl in
            let flash = !reduceMotion && Int(tl.date.timeIntervalSinceReferenceDate / 0.65) % 2 == 0
            ZStack {
                (flash ? Theme.bloodDark : Theme.void).ignoresSafeArea()
                VStack(spacing: 18) {
                    Spacer()
                    Text("Wake up")
                        .font(Theme.display(88))
                        .shadow(color: Theme.bloodHi, radius: 20)
                    Text("\(clockTime(tl.date)) \(amPM(tl.date))")
                        .font(Theme.heavy(44))
                        .monospacedDigit()
                    VStack(spacing: 4) {
                        Text(engine.songTitle)
                            .font(Theme.gothic(36))
                            .multilineTextAlignment(.center)
                        Text(engine.songBand.uppercased())
                            .font(Theme.semi(17))
                            .tracking(2)
                            .foregroundStyle(Theme.ash)
                    }
                    Spacer()
                    Button { engine.snooze() } label: {
                        Text("Snooze 9 min")
                            .font(Theme.heavy(30))
                            .frame(maxWidth: .infinity, minHeight: 88)
                    }
                    .buttonStyle(BloodButtonStyle(primary: true))
                    killButton
                    Text("Pausing from the lock screen counts as snooze.")
                        .font(Theme.body(16))
                        .foregroundStyle(Theme.ash)
                }
                .foregroundStyle(Theme.bone)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private var killButton: some View {
        Text(hold > 0 ? "KEEP HOLDING…" : "HOLD TO KILL IT")
            .font(Theme.heavy(24))
            .tracking(1.5)
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(alignment: .leading) {
                GeometryReader { g in
                    Rectangle().fill(Theme.bloodHi).frame(width: g.size.width * hold)
                }
            }
            .background(Theme.crypt2)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.bloodHi, lineWidth: 1.5))
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 2, maximumDistance: 80) {
                hold = 0
                engine.kill()
            } onPressingChanged: { pressing in
                if pressing {
                    withAnimation(.linear(duration: 2)) { hold = 1 }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { hold = 0 }
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Kill the alarm")
            .accessibilityHint("Hold for 2 seconds")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { engine.kill() }
    }
}
