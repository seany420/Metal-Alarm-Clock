import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation

private struct SheetTitle: ToolbarContent {
    let text: String
    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(text).font(Theme.display(26)).foregroundStyle(Theme.bone)
        }
    }
}

// MARK: - Alarm

struct AlarmSheet: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: AlarmEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    DatePicker("Alarm time", selection: time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)

                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { i in
                            let on = store.settings.days[i]
                            Button {
                                store.settings.days[i].toggle()
                                engine.settingsChanged()
                            } label: {
                                Text(Calendar.current.veryShortWeekdaySymbols[i])
                                    .font(Theme.heavy(20))
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .foregroundStyle(on ? Theme.bone : Theme.ash)
                                    .background(on ? Theme.bloodDark : Theme.void, in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? Theme.bloodHi : Theme.line, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Calendar.current.weekdaySymbols[i])
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }

                    Toggle(isOn: armed) {
                        Text(store.settings.armed ? "Armed" : "Arm it").font(Theme.display(34))
                    }
                    .tint(Theme.blood)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Snooze gives you 9 minutes. Killing it means holding the button for 2 seconds, so you have to be at least half awake.")
                        Text("While armed, the app plays your full song even with the phone locked. If iOS closes the app overnight, a backup iPhone alarm plays a 30-second clip of the same song instead. Tap Full song on that alarm to get the whole thing.")
                    }
                    .font(Theme.body(19))
                    .foregroundStyle(Theme.ash)
                }
                .padding(16)
            }
            .background(Theme.void.ignoresSafeArea())
            .toolbar {
                SheetTitle(text: "The Summoning")
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: store.settings.hour, minute: store.settings.minute, second: 0, of: Date()) ?? Date() },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                store.settings.hour = c.hour ?? 6
                store.settings.minute = c.minute ?? 30
                engine.settingsChanged()
            }
        )
    }

    private var armed: Binding<Bool> {
        Binding(
            get: { store.settings.armed },
            set: { on in
                store.settings.armed = on
                if !on { store.snoozeUntil = nil }
                engine.settingsChanged()
            }
        )
    }
}

// MARK: - Setlist

struct SetlistSheet: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: AlarmEngine
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var editing: Track?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Each alarm plays the next song down the list, then wraps back to the top. Tap a song to load its file from the Files app. Songs with no file get skipped. Nothing loaded? You get the built-in riff with a tolling bell.")
                        .font(Theme.body(18))
                        .foregroundStyle(Theme.ash)
                        .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(Array(store.setlist.enumerated()), id: \.element.id) { idx, t in
                        Button { editing = t } label: {
                            TrackRow(number: idx + 1, track: t, isNext: store.upcomingIndex == idx, loaded: store.isLoaded(t))
                        }
                        .listRowBackground(Theme.crypt)
                    }
                    .onDelete { store.remove(at: $0); engine.settingsChanged() }
                    .onMove { store.move(from: $0, to: $1); engine.settingsChanged() }
                }
                Section {
                    Button("Add more songs") { adding = true }
                    Button("Restore default list") { store.restoreDefaults() }
                }
                .listRowBackground(Theme.crypt)
                .foregroundStyle(Theme.bloodHi)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.void.ignoresSafeArea())
            .toolbar {
                SheetTitle(text: "The Setlist")
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileImporter(isPresented: $adding, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    store.addTracks(urls) { engine.settingsChanged() }
                }
            }
            .sheet(item: $editing) { t in
                TrackEditor(trackID: t.id)
                    .environmentObject(store)
                    .environmentObject(engine)
                    .preferredColorScheme(.dark)
            }
        }
    }
}

struct TrackRow: View {
    let number: Int
    let track: Track
    let isNext: Bool
    let loaded: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(Theme.semi(18))
                .monospacedDigit()
                .foregroundStyle(Theme.ash)
                .frame(width: 24, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).font(Theme.heavy(21)).foregroundStyle(Theme.bone)
                Text(track.band).font(Theme.body(17)).foregroundStyle(Theme.ash)
            }
            Spacer()
            Pill(text: isNext ? "Next up" : loaded ? "Loaded" : "No file", on: isNext)
        }
        .padding(.vertical, 4)
    }
}

struct TrackEditor: View {
    let trackID: String
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: AlarmEngine
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var preview: AVAudioPlayer?
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Group {
                if let i = store.setlist.firstIndex(where: { $0.id == trackID }) {
                    form(i)
                } else {
                    Text("This song was removed.").foregroundStyle(Theme.ash)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.void.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { stopPreview(); dismiss() } }
            }
        }
        .onDisappear { stopPreview() }
    }

    private func form(_ i: Int) -> some View {
        let t = store.setlist[i]
        return Form {
            Section("Song") {
                TextField("Title", text: $store.setlist[i].title)
                TextField("Band", text: $store.setlist[i].band)
            }
            .listRowBackground(Theme.crypt)

            Section {
                Button(store.isLoaded(t) ? "Replace song file" : "Load song file") { picking = true }
                if !error.isEmpty { Text(error).foregroundStyle(Theme.bloodHi) }
            } footer: {
                Text("Pick an MP3, M4A, or WAV you own from the Files app. Songs bought from iTunes work. Apple Music downloads are locked to the Music app and won't load.")
            }
            .listRowBackground(Theme.crypt)

            if store.isLoaded(t) {
                Section {
                    Stepper(value: $store.setlist[i].clipStart, in: 0...900, step: 5) {
                        Text("Clip starts at \(Int(t.clipStart) / 60):\(String(format: "%02d", Int(t.clipStart) % 60))")
                    }
                    Button(preview == nil ? "Preview clip" : "Stop preview") { togglePreview(t) }
                } header: {
                    Text("Lock-screen clip")
                } footer: {
                    Text("If iOS closes the app, the backup alarm plays 30 seconds of this song. Start it at the part that hits hardest.")
                }
                .listRowBackground(Theme.crypt)

                Section {
                    Button("Play this one next") {
                        store.next = i
                        engine.settingsChanged()
                        dismiss()
                    }
                }
                .listRowBackground(Theme.crypt)
            }

            Section {
                Button("Remove from setlist", role: .destructive) {
                    store.remove(at: IndexSet(integer: i))
                    engine.settingsChanged()
                    dismiss()
                }
            }
            .listRowBackground(Theme.crypt)
        }
        .font(Theme.body(19))
        .tint(Theme.bloodHi)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url):
                do {
                    try store.attach(url, to: trackID)
                    error = ""
                    if let saved = store.setlist.first(where: { $0.id == trackID }) {
                        store.refreshClip(saved) { engine.settingsChanged() }
                    }
                } catch {
                    self.error = "That file couldn't be copied. Try downloading it to your iPhone first."
                }
            case .failure:
                error = "That file couldn't be opened."
            }
        }
        .onChange(of: t.clipStart) { _, _ in
            stopPreview()
            if let saved = store.setlist.first(where: { $0.id == trackID }) {
                store.refreshClip(saved) { engine.settingsChanged() }
            }
        }
    }

    private func togglePreview(_ t: Track) {
        if preview != nil { stopPreview(); return }
        let url = Clipper.soundsDir.appendingPathComponent(store.clipName(t))
        guard let p = try? AVAudioPlayer(contentsOf: url) else {
            error = "The clip is still being made. Try again in a second."
            return
        }
        p.play()
        preview = p
    }

    private func stopPreview() {
        preview?.stop()
        preview = nil
    }
}

// MARK: - Backdrop

struct BackdropSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Put any picture behind the clock: your favorite slasher still, an album cover, a shot of your own haunted bedroom. It gets washed into grayscale so the blood stays red.")
                        .font(Theme.body(19))
                        .foregroundStyle(Theme.ash)
                    if let img = store.wallpaper {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .grayscale(1)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    PhotosPicker(selection: $item, matching: .images) {
                        Text(store.wallpaper == nil ? "Choose picture" : "Change picture")
                    }
                    .buttonStyle(BloodButtonStyle(primary: true))
                    if store.wallpaper != nil {
                        Button("Remove picture") { store.setWallpaper(nil) }
                            .buttonStyle(BloodButtonStyle())
                    }
                }
                .padding(16)
            }
            .background(Theme.void.ignoresSafeArea())
            .toolbar {
                SheetTitle(text: "The Backdrop")
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: item) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        store.setWallpaper(img)
                    }
                }
            }
        }
    }
}
