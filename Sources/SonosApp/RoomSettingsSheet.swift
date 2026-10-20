import SwiftUI
import SonosKit

struct RoomSettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var speakerID: String
    @State private var currentID: String

    init(speakerID: String) {
        self.speakerID = speakerID
        _currentID = State(initialValue: speakerID)
    }
    @State private var settings: RoomSettings?
    @State private var loading = true
    @State private var error: String?
    @State private var nameDraft = ""
    @State private var alarmTime = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
    @State private var alarmRecurrence = "DAILY"
    @State private var alarmVolume = 25.0
    @State private var alarmLinked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Room")
                    .font(.system(size: 22, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 8)

            if members.count > 1 {
                Picker("Speaker", selection: $currentID) {
                    ForEach(members) { member in
                        Text(member.name).tag(member.uuid)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }

            if loading {
                Spacer()
                HStack { Spacer(); ProgressView(); Spacer() }
                Spacer()
            } else if let error, settings == nil {
                Text(error)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(24)
                Spacer()
            } else if settings != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        identity
                        sound
                        homeTheater
                        trueplay
                        playback
                        hardware
                        alarms
                        systemInfo
                        limitations
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                }
            }
        }
        .frame(width: 560, height: 680)
        .background(Palette.background(scheme))
        .task(id: currentID) { await load() }
    }

    private var members: [MemberSnapshot] {
        model.selected?.members ?? []
    }

    @ViewBuilder private var identity: some View {
        if let settings {
            section("Name") {
                HStack(spacing: 10) {
                    TextField("Room name", text: $nameDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .semibold))
                    Button("Save") {
                        model.rename(uuid: settings.uuid, name: nameDraft)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .disabled(nameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.card(scheme)))
            }
        }
    }

    @ViewBuilder private var sound: some View {
        if let settings {
            section("Sound") {
                card {
                    if let bass = settings.bass {
                        commitSlider("Bass", value: bass, range: -10...10) { model.setBass(uuid: settings.uuid, value: $0) }
                    }
                    if let treble = settings.treble {
                        commitSlider("Treble", value: treble, range: -10...10) { model.setTreble(uuid: settings.uuid, value: $0) }
                    }
                    if settings.loudness != nil {
                        toggleRow("Loudness", \.loudness) { model.setLoudness(uuid: settings.uuid, enabled: $0) }
                    }
                    if settings.fixedOutput != nil {
                        toggleRow("Fixed volume", \.fixedOutput) { model.setFixedOutput(uuid: settings.uuid, enabled: $0) }
                    }
                    if settings.bass == nil && settings.treble == nil && settings.loudness == nil && settings.fixedOutput == nil {
                        Text("This speaker didn’t report tone controls.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private var homeTheater: some View {
        if let settings, hasTheater(settings) {
            section("Home theater") {
                card {
                    if settings.nightMode != nil {
                        toggleRow("Night mode", \.nightMode) { model.setEQ(uuid: settings.uuid, type: .nightMode, value: $0 ? 1 : 0) }
                    }
                    if settings.speechEnhancement != nil {
                        toggleRow("Speech enhancement", \.speechEnhancement) { model.setEQ(uuid: settings.uuid, type: .dialogLevel, value: $0 ? 1 : 0) }
                    }
                    if settings.surroundEnabled != nil {
                        toggleRow("Surrounds", \.surroundEnabled) { model.setEQ(uuid: settings.uuid, type: .surroundEnable, value: $0 ? 1 : 0) }
                    }
                    if let value = settings.surroundLevel {
                        commitSlider("TV surround", value: value, range: -15...15) { model.setEQ(uuid: settings.uuid, type: .surroundLevel, value: $0) }
                    }
                    if let value = settings.musicSurroundLevel {
                        commitSlider("Music surround", value: value, range: -15...15) { model.setEQ(uuid: settings.uuid, type: .musicSurroundLevel, value: $0) }
                    }
                    if let value = settings.surroundMode {
                        commitSlider("Surround mode", value: value, range: 0...1) { model.setEQ(uuid: settings.uuid, type: .surroundMode, value: $0) }
                    }
                    if let value = settings.subGain {
                        commitSlider("Sub level", value: value, range: -10...10) { model.setEQ(uuid: settings.uuid, type: .subGain, value: $0) }
                    }
                    if let value = settings.heightLevel {
                        commitSlider("Height", value: value, range: -10...10) { model.setEQ(uuid: settings.uuid, type: .heightChannelLevel, value: $0) }
                    }
                    if let value = settings.audioDelay {
                        commitSlider("Audio delay", value: value, range: 0...300) { model.setEQ(uuid: settings.uuid, type: .audioDelay, value: $0) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var trueplay: some View {
        if let settings, settings.trueplayAvailable != nil || settings.trueplayEnabled != nil {
            section("Trueplay") {
                card {
                    if settings.trueplayAvailable == false {
                        Text("No Trueplay tuning is stored on this speaker. Measuring a room still has to be done in the Sonos mobile app.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else if settings.trueplayEnabled != nil {
                        toggleRow("Use Trueplay tuning", \.trueplayEnabled) { model.setTrueplay(uuid: settings.uuid, enabled: $0) }
                        Text("This switches a tuning that was already measured. It doesn’t run the microphone setup.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private var playback: some View {
        if let settings {
            section("Playback") {
                card {
                    if settings.crossfade != nil {
                        toggleRow("Crossfade", \.crossfade) { model.setCrossfade($0) }
                    }
                    if let mode = settings.playMode {
                        HStack {
                            Text("Shuffle")
                            Spacer()
                            Text(mode.shuffle ? "On" : "Off")
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 14))
                        HStack {
                            Text("Repeat")
                            Spacer()
                            Text(mode.repeatMode.title)
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 14))
                    }
                    if let sleep = settings.sleepRemaining {
                        HStack {
                            Text("Sleep")
                            Spacer()
                            Text(sleep.isEmpty || sleep == "0:00:00" ? "Off" : sleep)
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 14))
                    }
                    Text("Shuffle, repeat, crossfade, and sleep also sit under the artwork.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var hardware: some View {
        if let settings {
            section("Speaker") {
                card {
                    if settings.statusLight != nil {
                        toggleRow("Status light", \.statusLight) { model.setStatusLight(uuid: settings.uuid, on: $0) }
                    }
                    if settings.buttonsLocked != nil {
                        toggleRow("Button lock", \.buttonsLocked) { model.setButtonLock(uuid: settings.uuid, locked: $0) }
                    }
                    if settings.statusLight == nil && settings.buttonsLocked == nil {
                        Text("No hardware switches were reported.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private var alarms: some View {
        if let settings {
            section("Alarms") {
                card {
                    if settings.alarms.isEmpty {
                        Text("No alarms.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(settings.alarms) { alarm in
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Self.clockLabel(alarm.startTime))
                                    .font(.system(size: 15, weight: .semibold))
                                Text("\(alarm.recurrenceTitle) · volume \(alarm.volume)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { alarm.enabled },
                                set: { on in
                                    var copy = alarm
                                    copy.enabled = on
                                    model.updateAlarm(copy)
                                    replace(copy)
                                }
                            ))
                            .labelsHidden()
                            Button {
                                model.deleteAlarm(id: alarm.id, speakerUUID: settings.uuid)
                                dropAlarm(alarm.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete alarm")
                        }
                    }
                    Divider().opacity(0.4)
                    Text("New alarm")
                        .font(.system(size: 13, weight: .semibold))
                    DatePicker("Time", selection: $alarmTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.field)
                    Picker("Repeat", selection: $alarmRecurrence) {
                        Text("Once").tag("ONCE")
                        Text("Weekdays").tag("WEEKDAYS")
                        Text("Weekends").tag("WEEKENDS")
                        Text("Daily").tag("DAILY")
                    }
                    HStack {
                        Text("Volume \(Int(alarmVolume.rounded()))")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        ThinSlider(value: $alarmVolume, accessibilityTitle: "Alarm volume")
                    }
                    Toggle("Include grouped rooms", isOn: $alarmLinked)
                    Button("Add alarm") {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
                        let clock = String(format: "%02d:%02d:00", parts.hour ?? 7, parts.minute ?? 0)
                        let draft = AlarmDraft(
                            startTime: clock,
                            recurrence: alarmRecurrence,
                            enabled: true,
                            roomUUID: settings.uuid,
                            volume: Int(alarmVolume.rounded()),
                            includeLinkedZones: alarmLinked
                        )
                        model.createAlarm(draft)
                        Task { await load() }
                    }
                    .buttonStyle(.bordered)
                    Text("New alarms use the speaker chime. Pick a favorite in the Sonos app if you want music instead — program metadata for service alarms isn’t available without their catalog.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var systemInfo: some View {
        if let settings {
            section("System") {
                card {
                    info("Model", settings.modelName.isEmpty ? settings.modelNumber : "\(settings.modelName) \(settings.modelNumber)")
                    info("Software", settings.softwareVersion)
                    info("Hardware", settings.hardwareVersion)
                    info("Serial", settings.serialNumber)
                    info("MAC", settings.macAddress)
                    info("IP", settings.ipAddress)
                    info("Household", settings.householdID)
                    info("Speaker time", settings.localTime)
                    info("Time zone", settings.timeZone)
                }
            }
        }
    }

    private var limitations: some View {
        section("Only on the local network") {
            Text("Music-service sign-in, full catalog browsing, Trueplay measurement, voice-assistant setup, firmware updates, and Sonos account registration are not available from the local API. Speakers still play services that are already linked.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func hasTheater(_ settings: RoomSettings) -> Bool {
        settings.nightMode != nil || settings.speechEnhancement != nil || settings.surroundEnabled != nil
            || settings.surroundLevel != nil || settings.musicSurroundLevel != nil || settings.subGain != nil
            || settings.heightLevel != nil || settings.audioDelay != nil || settings.surroundMode != nil
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card(scheme)))
    }

    private func toggleRow(_ title: String, _ keyPath: WritableKeyPath<RoomSettings, Bool?>, set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(
            get: { settings?[keyPath: keyPath] ?? false },
            set: { newValue in
                settings?[keyPath: keyPath] = newValue
                set(newValue)
            }
        )) {
            Text(title).font(.system(size: 14))
        }
        .toggleStyle(.switch)
    }

    private func commitSlider(_ title: String, value: Int, range: ClosedRange<Int>, commit: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 14))
                Spacer()
                Text("\(value)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            CommitSlider(value: value, range: range, commit: commit)
        }
    }

    private func info(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty ? "—" : value)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 13))
    }

    private func replace(_ alarm: Alarm) {
        guard var copy = settings else { return }
        if let index = copy.alarms.firstIndex(where: { $0.id == alarm.id }) {
            copy.alarms[index] = alarm
            settings = copy
        }
    }

    private func dropAlarm(_ id: Int) {
        settings?.alarms.removeAll { $0.id == id }
    }

    private func load() async {
        guard !currentID.isEmpty else {
            loading = false
            error = "Select a room first."
            return
        }
        loading = settings == nil
        do {
            let loaded = try await model.loadSettings(uuid: currentID)
            settings = loaded
            nameDraft = loaded.name
            loading = false
            error = nil
        } catch {
            loading = false
            if settings == nil {
                self.error = (error as? SonosError)?.message ?? error.localizedDescription
            }
        }
    }

    private static func clockLabel(_ raw: String) -> String {
        let parts = raw.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return raw }
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

private struct CommitSlider: View {
    @State private var value: Double
    var range: ClosedRange<Int>
    var commit: (Int) -> Void

    init(value: Int, range: ClosedRange<Int>, commit: @escaping (Int) -> Void) {
        _value = State(initialValue: Double(value))
        self.range = range
        self.commit = commit
    }

    var body: some View {
        ThinSlider(
            value: $value,
            range: Double(range.lowerBound)...Double(range.upperBound),
            onEditingChanged: { editing in
                if !editing { commit(Int(value.rounded())) }
            },
            accessibilityTitle: "Level"
        )
    }
}
