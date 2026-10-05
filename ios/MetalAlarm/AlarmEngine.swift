import Foundation
import AVFoundation
import MediaPlayer
import UserNotifications
import UIKit
import SwiftUI
import AlarmKit
import ActivityKit
import AppIntents

struct MetalAlarmMeta: AlarmMetadata {}

/// The "Full song" button on the lock-screen alarm. Opens the app, which takes over with the whole track.
struct PlayFullSongIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Play the full song"
    static var openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(Date(), forKey: AlarmEngine.fullSongKey)
        await MainActor.run { AlarmEngine.shared.consumeFullSongRequest() }
        return .result()
    }
}

private struct BackupAlarm: Codable {
    var id: UUID
    var date: Date
    var handled = false
}

/// Two layers of alarm:
/// 1. While armed, the app keeps a silent audio loop running so iOS leaves it alive in the
///    background. At alarm time it plays the full song, even with the phone locked.
/// 2. Backup iPhone alarms (AlarmKit) with a 30-second clip of the same song, in case iOS
///    or you closed the app. These break through silent mode and Focus.
/// When the app is alive it cancels the backup a few seconds early so you only hear one.
final class AlarmEngine: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = AlarmEngine()
    static let fullSongKey = "fullSongRequestedAt"
    static let snoozeMinutes: Double = 9

    @Published private(set) var ringing = false
    @Published private(set) var songTitle = ""
    @Published private(set) var songBand = ""
    @Published private(set) var alarmKitAllowed = true
    @Published private(set) var volume: Float = 1

    private let store = Store.shared
    private let session = AVAudioSession.sharedInstance()
    private var keepAlive: AVAudioPlayer?
    private var player: AVAudioPlayer?
    private var tick: Timer?
    private var ramp: Timer?
    private var lastCheck = Date()
    private var started = false
    private var pendingChange: DispatchWorkItem?
    private var generation = 0

    private var backups: [BackupAlarm] {
        get {
            guard let d = UserDefaults.standard.data(forKey: "backups"),
                  let b = try? JSONDecoder().decode([BackupAlarm].self, from: d) else { return [] }
            return b
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "backups") }
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted(_:)),
                                               name: AVAudioSession.interruptionNotification, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(mediaReset),
                                               name: AVAudioSession.mediaServicesWereResetNotification, object: session)
        setupRemoteCommands()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(t, forMode: .common)
        tick = t
        Task { @MainActor in
            await self.authorizeAlarmKit()
            self.applySettings()
            self.appBecameActive()
        }
    }

    func appBecameActive() {
        volume = session.outputVolume
        consumeFullSongRequest()
        // Anything that already rang on the lock screen is done; stop it so it can't double up.
        var list = backups
        var changed = false
        for i in list.indices where !list[i].handled && list[i].date <= Date() {
            try? AlarmManager.shared.stop(id: list[i].id)
            list[i].handled = true
            changed = true
        }
        if changed { backups = list }
        check()
    }

    /// Called when the lock-screen alarm's "Full song" button opened the app.
    func consumeFullSongRequest() {
        guard let at = UserDefaults.standard.object(forKey: Self.fullSongKey) as? Date else { return }
        UserDefaults.standard.removeObject(forKey: Self.fullSongKey)
        guard Date().timeIntervalSince(at) < 120 else { return }
        for b in backups where b.date <= Date() { try? AlarmManager.shared.stop(id: b.id) }
        if let s = store.snoozeUntil, s <= Date() { store.snoozeUntil = nil }
        fire()
    }

    /// Debounced: call after any change to time, days, arming, or the setlist.
    func settingsChanged() {
        pendingChange?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applySettings() }
        pendingChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func applySettings() {
        updateKeepAlive()
        Task { @MainActor in await self.rescheduleBackups() }
    }

    // MARK: - Keep-alive

    private var shouldStayAlive: Bool { store.settings.armed || store.snoozeUntil != nil }

    private func updateKeepAlive() {
        guard !ringing else { return }
        if shouldStayAlive { startKeepAlive() } else { stopKeepAlive() }
    }

    private func startKeepAlive() {
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch { print("Session error: \(error)") }
        if keepAlive == nil {
            keepAlive = try? AVAudioPlayer(data: Self.silence)
            keepAlive?.numberOfLoops = -1
            keepAlive?.volume = 0.05
        }
        if keepAlive?.isPlaying != true { keepAlive?.play() }
    }

    private func stopKeepAlive() {
        keepAlive?.stop()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static let silence: Data = {
        let n = 8000, sr: UInt32 = 8000
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + n * 2))
        d.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(1); u32(sr); u32(sr * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(n * 2))
        d.append(Data(count: n * 2))
        return d
    }()

    // MARK: - Clock tick

    private func check() {
        let now = Date()
        volume = session.outputVolume
        if !ringing {
            if let s = store.snoozeUntil, now >= s {
                store.snoozeUntil = nil
                fire()
            } else if store.settings.armed, store.snoozeUntil == nil,
                      let t = store.occurrences(after: lastCheck, count: 1).first,
                      t <= now, now.timeIntervalSince(t) < 15 * 60 {
                if !rangOnLockScreen(t) { fire() }
            } else {
                preemptBackups(now)
            }
        }
        lastCheck = now
    }

    /// True if the backup for this time already went off while the app was frozen.
    /// That alarm owns the wake-up; starting the song on top of it would double up.
    private func rangOnLockScreen(_ t: Date) -> Bool {
        var list = backups
        guard let i = list.firstIndex(where: { !$0.handled && abs($0.date.timeIntervalSince(t)) < 1 }) else { return false }
        list[i].handled = true
        backups = list
        return true
    }

    /// The app is alive and about to play the full song, so silence the lock-screen backup.
    private func preemptBackups(_ now: Date) {
        guard keepAlive?.isPlaying == true else { return }
        var list = backups
        var changed = false
        for i in list.indices where !list[i].handled {
            let dt = list[i].date.timeIntervalSince(now)
            if dt > 0 && dt < 6 {
                try? AlarmManager.shared.cancel(id: list[i].id)
                list[i].handled = true
                changed = true
            }
        }
        if changed { backups = list }
    }

    // MARK: - Ringing

    func fire() {
        guard !ringing else { return }
        ringing = true
        keepAlive?.stop()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch { print("Session error: \(error)") }
        playNext()
        notifyIfBackground()
        Task { @MainActor in await self.rescheduleBackups() }
    }

    func snooze() {
        guard ringing else { return }
        endRinging()
        store.snoozeUntil = Date().addingTimeInterval(Self.snoozeMinutes * 60)
        applySettings()
    }

    func kill() {
        guard ringing else { return }
        endRinging()
        store.snoozeUntil = nil
        applySettings()
    }

    private func endRinging() {
        stopPlayer()
        ringing = false
        songTitle = ""
        songBand = ""
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["ringing"])
    }

    private func playNext() {
        stopPlayer()
        if let next = store.takeNext(), let p = try? AVAudioPlayer(contentsOf: next.url) {
            begin(p, title: next.track.title, band: next.track.band, loops: 0)
        } else if let url = Bundle.main.url(forResource: "bell-riff", withExtension: "caf"),
                  let p = try? AVAudioPlayer(contentsOf: url) {
            begin(p, title: "The Bell Tolls", band: "Built-in riff", loops: -1)
        }
    }

    private func begin(_ p: AVAudioPlayer, title: String, band: String, loops: Int) {
        player = p
        p.delegate = self
        p.numberOfLoops = loops
        p.volume = 0.45
        p.prepareToPlay()
        p.play()
        songTitle = title
        songBand = band
        updateNowPlaying()
        ramp?.invalidate()
        let r = Timer(timeInterval: 1.5, repeats: true) { [weak self] t in
            guard let p = self?.player else { t.invalidate(); return }
            p.volume = min(1, p.volume + 0.05)
            if p.volume >= 1 { t.invalidate() }
        }
        RunLoop.main.add(r, forMode: .common)
        ramp = r
    }

    private func stopPlayer() {
        ramp?.invalidate()
        player?.stop()
        player = nil
    }

    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            if self.ringing && p === self.player { self.playNext() }
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ p: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async {
            if self.ringing && p === self.player { self.playNext() }
        }
    }

    private func notifyIfBackground() {
        guard UIApplication.shared.applicationState != .active else { return }
        let c = UNMutableNotificationContent()
        c.title = "WAKE UP"
        c.body = "\(songTitle) · \(songBand). Open the app to snooze or kill it."
        c.sound = nil
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "ringing", content: c, trigger: nil))
    }

    // MARK: - Lock screen / Control Center

    private func setupRemoteCommands() {
        let rc = MPRemoteCommandCenter.shared()
        let pauseIsSnooze: (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus = { [weak self] _ in
            guard let self, self.ringing else { return .commandFailed }
            self.snooze()
            return .success
        }
        rc.pauseCommand.addTarget(handler: pauseIsSnooze)
        rc.togglePlayPauseCommand.addTarget(handler: pauseIsSnooze)
        rc.stopCommand.addTarget(handler: pauseIsSnooze)
        rc.playCommand.addTarget { _ in .success }
        rc.nextTrackCommand.isEnabled = false
        rc.previousTrackCommand.isEnabled = false
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: songTitle,
            MPMediaItemPropertyArtist: songBand,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
        if let img = UIImage(named: "mask") {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    @objc private func interrupted(_ n: Notification) {
        guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw), type == .ended else { return }
        DispatchQueue.main.async {
            if self.ringing {
                try? self.session.setActive(true)
                self.player?.play()
            } else {
                self.updateKeepAlive()
            }
        }
    }

    @objc private func mediaReset() {
        DispatchQueue.main.async {
            self.keepAlive = nil
            self.player = nil
            if self.ringing { self.playNext() } else { self.updateKeepAlive() }
        }
    }

    // MARK: - Lock-screen backup (AlarmKit)

    @MainActor
    func authorizeAlarmKit() async {
        switch AlarmManager.shared.authorizationState {
        case .authorized:
            alarmKitAllowed = true
        case .denied:
            alarmKitAllowed = false
        case .notDetermined:
            let state = try? await AlarmManager.shared.requestAuthorization()
            alarmKitAllowed = state == .authorized
        @unknown default:
            alarmKitAllowed = false
        }
    }

    @MainActor
    func rescheduleBackups() async {
        generation += 1
        let gen = generation
        for b in backups { try? AlarmManager.shared.cancel(id: b.id) }
        backups = []
        guard alarmKitAllowed else { return }

        var dates: [Date] = []
        if let s = store.snoozeUntil, s > Date() { dates.append(s) }
        if store.settings.armed { dates += store.occurrences(after: Date(), count: 6) }
        let order = store.rotation()

        for (k, date) in dates.enumerated() {
            let track: Track? = order.isEmpty ? nil : order[k % order.count]
            let sound = track.flatMap { store.hasClip($0) ? store.clipName($0) : nil } ?? "bell-riff.caf"
            let title = track.map { "WAKE UP · \($0.title)" } ?? "WAKE UP"
            guard let id = try? await scheduleAlarm(at: date, sound: sound, title: title) else { continue }
            if gen != generation {
                try? AlarmManager.shared.cancel(id: id)
                return
            }
            backups.append(BackupAlarm(id: id, date: date))
        }
    }

    /// Schedules a one-off lock-screen alarm a minute from now so you can hear what the backup sounds like.
    @MainActor
    func testLockScreen() async -> Bool {
        if !alarmKitAllowed { await authorizeAlarmKit() }
        guard alarmKitAllowed else { return false }
        let track = store.rotation().first
        let sound = track.flatMap { store.hasClip($0) ? store.clipName($0) : nil } ?? "bell-riff.caf"
        let title = track.map { "WAKE UP · \($0.title)" } ?? "WAKE UP"
        return (try? await scheduleAlarm(at: Date().addingTimeInterval(60), sound: sound, title: title)) != nil
    }

    @MainActor
    private func scheduleAlarm(at date: Date, sound: String, title: String) async throws -> UUID {
        let id = UUID()
        let stop = AlarmButton(text: "Kill it", textColor: .white, systemImageName: "xmark")
        let full = AlarmButton(text: "Full song", textColor: .white, systemImageName: "music.note")
        let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: title),
                                            stopButton: stop,
                                            secondaryButton: full,
                                            secondaryButtonBehavior: .custom)
        let attributes = AlarmAttributes<MetalAlarmMeta>(presentation: AlarmPresentation(alert: alert),
                                                         metadata: MetalAlarmMeta(),
                                                         tintColor: Color(red: 0.85, green: 0.08, blue: 0.12))
        let config = AlarmManager.AlarmConfiguration<MetalAlarmMeta>(countdownDuration: nil,
                                                                     schedule: .fixed(date),
                                                                     attributes: attributes,
                                                                     stopIntent: nil,
                                                                     secondaryIntent: PlayFullSongIntent(),
                                                                     sound: .named(sound))
        _ = try await AlarmManager.shared.schedule(id: id, configuration: config)
        return id
    }
}
