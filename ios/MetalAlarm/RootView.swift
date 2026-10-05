import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: AlarmEngine
    @State private var sheet: Sheet?
    @State private var testNote = ""
    @AppStorage("keepScreenOn") private var keepScreenOn = false

    enum Sheet: String, Identifiable {
        case alarm, setlist, backdrop
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            Backdrop(image: store.wallpaper)
            ScrollView {
                VStack(spacing: 22) {
                    header
                    ClockStage().frame(maxWidth: 520)
                    Readout()
                    warnings
                    menu
                    extras
                }
                .padding(.horizontal, 16)
                .padding(.top, 36)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
            BloodBand().ignoresSafeArea()
            if engine.ringing {
                RingView().transition(.opacity)
            }
        }
        .foregroundStyle(Theme.bone)
        .sheet(item: $sheet) { s in
            Group {
                switch s {
                case .alarm: AlarmSheet()
                case .setlist: SetlistSheet()
                case .backdrop: BackdropSheet()
                }
            }
            .environmentObject(store)
            .environmentObject(engine)
            .preferredColorScheme(.dark)
        }
        .onChange(of: engine.ringing) { _, ringing in
            if ringing { sheet = nil }
        }
        .onChange(of: keepScreenOn, initial: true) { _, on in
            UIApplication.shared.isIdleTimerDisabled = on
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            (Text("Metal ") + Text("Alarm").foregroundColor(Theme.bloodHi))
                .font(Theme.display(42))
                .shadow(color: Theme.bloodHi.opacity(0.35), radius: 12)
            Spacer()
            Text("WAKE UP SCREAMING")
                .font(Theme.semi(14))
                .tracking(2)
                .foregroundStyle(Theme.ash)
        }
    }

    @ViewBuilder
    private var warnings: some View {
        if engine.volume < 0.5 {
            Note(text: "Volume is at \(Int(engine.volume * 100))%. Turn it up before bed, or you might sleep through Slayer.")
        }
        if !engine.alarmKitAllowed {
            VStack(alignment: .leading, spacing: 8) {
                Note(text: "Lock-screen backup alarms are off. If iOS closes the app overnight, nothing will ring. Turn on Alarms for Metal Alarm in Settings.")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(BloodButtonStyle())
            }
        }
    }

    private var menu: some View {
        VStack(spacing: 10) {
            MenuRow(title: "The Summoning", detail: alarmSummary) { sheet = .alarm }
            MenuRow(title: "The Setlist", detail: "\(store.loadedCount) of \(store.setlist.count) songs loaded") { sheet = .setlist }
            MenuRow(title: "The Backdrop", detail: store.wallpaper == nil ? "No picture yet" : "Picture set") { sheet = .backdrop }
        }
    }

    private var extras: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $keepScreenOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep the clock on screen").font(Theme.semi(20))
                    Text("For the nightstand. The alarm rings either way.").font(Theme.body(17)).foregroundStyle(Theme.ash)
                }
            }
            .tint(Theme.blood)
            HStack(spacing: 10) {
                Button("Test alarm") { engine.fire() }
                    .buttonStyle(BloodButtonStyle(primary: true))
                Button("Test locked") {
                    Task {
                        let ok = await engine.testLockScreen()
                        testNote = ok ? "Lock-screen alarm set for 1 minute from now. Lock your phone." : "Couldn't set it. Allow Alarms for Metal Alarm in Settings."
                    }
                }
                .buttonStyle(BloodButtonStyle())
            }
            if !testNote.isEmpty {
                Text(testNote).font(Theme.body(18)).foregroundStyle(Theme.bloodHi)
            }
        }
        .padding(16)
        .background(Theme.crypt.opacity(0.92), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
    }

    private var alarmSummary: String {
        let s = store.settings
        let d = Calendar.current.date(bySettingHour: s.hour, minute: s.minute, second: 0, of: Date()) ?? Date()
        let days: String
        switch s.days {
        case Array(repeating: true, count: 7): days = "every day"
        case [false, true, true, true, true, true, false]: days = "weekdays"
        case [true, false, false, false, false, false, true]: days = "weekends"
        default:
            let names = Calendar.current.shortWeekdaySymbols
            days = zip(names, s.days).filter(\.1).map(\.0).joined(separator: " ")
        }
        return "\(clockTime(d)) \(amPM(d)), \(days) · \(s.armed ? "armed" : "off")"
    }
}

struct MenuRow: View {
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.display(28)).foregroundStyle(Theme.bone)
                    Text(detail).font(Theme.body(18)).foregroundStyle(Theme.ash)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.bloodHi)
            }
            .padding(16)
            .background(Theme.crypt.opacity(0.92), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct Note: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.body(18))
            .foregroundStyle(Theme.bone)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.bloodDark, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.bloodHi, lineWidth: 1))
    }
}
