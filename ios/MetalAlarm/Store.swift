import Foundation
import UIKit

struct Track: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var band: String
    var fileName: String? = nil
    /// Where the 30-second lock-screen clip starts, in seconds into the song.
    var clipStart: Double = 0
}

struct AlarmSettings: Codable, Equatable {
    var hour = 6
    var minute = 30
    /// Index 0 is Sunday, matching Calendar's weekday - 1.
    var days: [Bool] = Array(repeating: true, count: 7)
    var armed = false
}

private struct Persisted: Codable {
    var settings: AlarmSettings
    var setlist: [Track]
    var next: Int
    var snoozeUntil: Date?
}

final class Store: ObservableObject {
    static let shared = Store()

    static let defaultSetlist: [Track] = [
        Track(id: "d1", title: "For Whom the Bell Tolls", band: "Metallica"),
        Track(id: "d2", title: "Raining Blood", band: "Slayer"),
        Track(id: "d3", title: "Domination", band: "Pantera"),
        Track(id: "d4", title: "(sic)", band: "Slipknot"),
        Track(id: "d5", title: "Blackened", band: "Metallica"),
        Track(id: "d6", title: "Blind", band: "Korn"),
        Track(id: "d7", title: "Epic", band: "Faith No More"),
        Track(id: "d8", title: "Master of Puppets", band: "Metallica"),
        Track(id: "d9", title: "Iron Man", band: "Black Sabbath"),
    ]

    @Published var settings = AlarmSettings() { didSet { save() } }
    @Published var setlist: [Track] = Store.defaultSetlist { didSet { save() } }
    @Published var next = 0 { didSet { save() } }
    @Published var snoozeUntil: Date? { didSet { save() } }
    @Published private(set) var wallpaper: UIImage?

    static let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let tracksDir: URL = {
        let u = docs.appendingPathComponent("Tracks", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    private static let stateURL = docs.appendingPathComponent("state.json")
    private static let wallpaperURL = docs.appendingPathComponent("wallpaper.jpg")

    init() {
        if let data = try? Data(contentsOf: Self.stateURL),
           let p = try? JSONDecoder().decode(Persisted.self, from: data) {
            settings = p.settings
            setlist = p.setlist
            next = p.next
            snoozeUntil = p.snoozeUntil
        }
        if let d = try? Data(contentsOf: Self.wallpaperURL) { wallpaper = UIImage(data: d) }
    }

    func save() {
        let p = Persisted(settings: settings, setlist: setlist, next: next, snoozeUntil: snoozeUntil)
        if let d = try? JSONEncoder().encode(p) { try? d.write(to: Self.stateURL, options: .atomic) }
    }

    // MARK: - Rotation

    func fileURL(_ t: Track) -> URL? {
        guard let f = t.fileName else { return nil }
        let u = Self.tracksDir.appendingPathComponent(f)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    func isLoaded(_ t: Track) -> Bool { fileURL(t) != nil }

    var loadedCount: Int { setlist.filter(isLoaded).count }

    /// Index of the song the next alarm will play.
    var upcomingIndex: Int? {
        guard !setlist.isEmpty else { return nil }
        for i in 0..<setlist.count {
            let idx = (next + i) % setlist.count
            if isLoaded(setlist[idx]) { return idx }
        }
        return nil
    }

    /// Loaded songs in the order the coming alarms will play them.
    func rotation() -> [Track] {
        guard let start = upcomingIndex else { return [] }
        return (0..<setlist.count).map { setlist[(start + $0) % setlist.count] }.filter(isLoaded)
    }

    /// Returns the next song and moves the rotation past it.
    func takeNext() -> (track: Track, url: URL)? {
        guard let idx = upcomingIndex, let url = fileURL(setlist[idx]) else { return nil }
        next = (idx + 1) % setlist.count
        return (setlist[idx], url)
    }

    // MARK: - Schedule

    func occurrences(after from: Date, count: Int) -> [Date] {
        guard settings.days.contains(true), count > 0 else { return [] }
        let cal = Calendar.current
        var res: [Date] = []
        var day = cal.startOfDay(for: from)
        var guardDays = 0
        while res.count < count && guardDays < 400 {
            if let d = cal.date(bySettingHour: settings.hour, minute: settings.minute, second: 0, of: day),
               d > from, settings.days[cal.component(.weekday, from: d) - 1] {
                res.append(d)
            }
            day = cal.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)
            guardDays += 1
        }
        return res
    }

    // MARK: - Files

    func clipName(_ t: Track) -> String { "clip-\(t.id).caf" }

    func hasClip(_ t: Track) -> Bool {
        FileManager.default.fileExists(atPath: Clipper.soundsDir.appendingPathComponent(clipName(t)).path)
    }

    /// Copies a picked audio file into the app and attaches it to a setlist slot.
    func attach(_ src: URL, to id: String) throws {
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        guard let i = setlist.firstIndex(where: { $0.id == id }) else { return }
        let ext = src.pathExtension.isEmpty ? "m4a" : src.pathExtension.lowercased()
        let name = "\(id)-\(Int(Date().timeIntervalSince1970)).\(ext)"
        let dst = Self.tracksDir.appendingPathComponent(name)
        try FileManager.default.copyItem(at: src, to: dst)
        if let old = setlist[i].fileName {
            try? FileManager.default.removeItem(at: Self.tracksDir.appendingPathComponent(old))
        }
        setlist[i].fileName = name
    }

    func addTracks(_ urls: [URL], done: @escaping () -> Void) {
        for (n, url) in urls.enumerated() {
            let base = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
            let parts = base.components(separatedBy: " - ")
            let t = Track(id: "u\(Int(Date().timeIntervalSince1970))\(n)",
                          title: parts.count > 1 ? parts.dropFirst().joined(separator: " - ") : base,
                          band: parts.count > 1 ? parts[0] : "Your file")
            setlist.append(t)
            if (try? attach(url, to: t.id)) != nil, let saved = setlist.first(where: { $0.id == t.id }) {
                refreshClip(saved, done: done)
            } else {
                setlist.removeAll { $0.id == t.id }
            }
        }
        done()
    }

    func remove(at offsets: IndexSet) {
        for i in offsets {
            let t = setlist[i]
            if let f = t.fileName { try? FileManager.default.removeItem(at: Self.tracksDir.appendingPathComponent(f)) }
            try? FileManager.default.removeItem(at: Clipper.soundsDir.appendingPathComponent(clipName(t)))
        }
        let before = offsets.filter { $0 < next }.count
        setlist.remove(atOffsets: offsets)
        next = setlist.isEmpty ? 0 : max(0, next - before) % setlist.count
    }

    func move(from: IndexSet, to: Int) {
        let upcomingID = upcomingIndex.map { setlist[$0].id }
        setlist.move(fromOffsets: from, toOffset: to)
        if let id = upcomingID, let i = setlist.firstIndex(where: { $0.id == id }) { next = i }
    }

    func restoreDefaults() {
        let ids = Set(setlist.map(\.id))
        setlist.append(contentsOf: Self.defaultSetlist.filter { !ids.contains($0.id) })
    }

    /// Rebuilds the 30-second clip the lock-screen alarm plays for this song.
    func refreshClip(_ t: Track, done: (() -> Void)? = nil) {
        guard let url = fileURL(t) else { return }
        let name = clipName(t), start = t.clipStart
        DispatchQueue.global(qos: .userInitiated).async {
            do { try Clipper.makeClip(from: url, start: start, name: name) } catch { print("Clip failed: \(error)") }
            DispatchQueue.main.async {
                self.objectWillChange.send()
                done?()
            }
        }
    }

    func setWallpaper(_ image: UIImage?) {
        if let image, let d = image.jpegData(compressionQuality: 0.85) {
            try? d.write(to: Self.wallpaperURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: Self.wallpaperURL)
        }
        wallpaper = image
    }
}
