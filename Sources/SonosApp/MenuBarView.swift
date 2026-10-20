import SwiftUI
import SonosKit

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openSettings) private var openSettings
    @State private var showOutput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WindowOpener()
            if let group = model.selected {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    player(group, elapsed: model.projectedElapsed(for: group, now: context.date))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Searching for speakers…")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Sonos Local stays on your Wi-Fi and keeps looking.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(18)
            }
        }
        .frame(width: 320)
        .background(Palette.background(scheme))
        .task { await model.start() }
        .sheet(isPresented: $showOutput) {
            GroupSheet()
                .environment(model)
        }
    }

    private func player(_ group: GroupSnapshot, elapsed: Int) -> some View {
        let playing = group.nowPlaying
        return VStack(alignment: .leading, spacing: 12) {
            ArtworkView(
                url: group.artworkURL,
                fallbackURL: group.artworkFallbackURL,
                placeholderSymbol: playing.symbolName,
                cornerRadius: 10
            )
            .frame(height: 200)
            Text(playing.title.isEmpty ? "Nothing playing" : playing.title)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
            if !playing.artistLine.isEmpty {
                Text(playing.artistLine)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            OutputButton(name: group.name, grouped: group.members.count > 1) {
                showOutput = true
            }
            if playing.isLive || !playing.canSeek {
                HStack(spacing: 8) {
                    Circle()
                        .fill(playing.isPlaying ? Color.primary : Color.secondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text(playing.isLive ? "Live" : "Not seekable")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                let duration = max(playing.duration, 1)
                let position = min(elapsed, duration)
                ThinSlider(
                    value: Binding(
                        get: { Double(model.seekDraft ?? Double(position)) },
                        set: { model.setSeek($0, group: group) }
                    ),
                    range: 0...Double(duration),
                    onEditingChanged: { editing in
                        if editing { model.beginSeek(model.seekDraft ?? Double(position)) }
                        else { model.endSeek() }
                    },
                    accessibilityTitle: "Position"
                )
                HStack {
                    Text(SonosTime.display(position))
                    Spacer()
                    Text("-\(SonosTime.display(max(0, duration - position)))")
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            }
            TransportControls(
                isPlaying: playing.isPlaying,
                showsSkip: playing.showsSkip,
                diameter: 52,
                onPrevious: { model.previous() },
                onToggle: { model.togglePlay() },
                onNext: { model.next() }
            )
            .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                Image(systemName: group.groupMuted ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                ThinSlider(
                    value: Binding(
                        get: { model.groupVolume(group) },
                        set: { model.setGroupVolume($0, group: group) }
                    ),
                    onEditingChanged: { editing in
                        if !editing { model.endGroupVolume(group) }
                    },
                    accessibilityTitle: "Volume"
                )
            }
            if model.snapshot.groups.count > 0 {
                Text("Rooms")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.snapshot.groups) { room in
                            Button {
                                model.select(room)
                            } label: {
                                HStack {
                                    Text(room.name)
                                        .font(.system(size: 13, weight: room.id == group.id ? .semibold : .regular))
                                        .lineLimit(1)
                                    Spacer()
                                    if room.id == group.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(room.id == group.id ? Palette.cardActive(scheme) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
            HStack {
                Button("Open window") { model.openMainWindow() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
        .padding(18)
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { model.menuBarOnly },
                    set: { model.setMenuBarOnly($0) }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Menu bar only")
                        Text("Hide the Dock icon. The menu bar still has playback, volume, and room switching. Open the window from there whenever you want it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Menu bar")
            }
            Section {
                TextField("192.168.1.62", text: $model.speakerIP)
                    .textFieldStyle(.roundedBorder)
                Button("Add speaker by IP") { model.addSpeakerIP() }
                    .disabled(model.speakerIP.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Forget speakers and rescan") { model.forgetSpeakers() }
            } header: {
                Text("Speakers")
            } footer: {
                Text("Saved speakers are contacted directly on the next launch. Discovery logs: log stream --predicate 'subsystem == \"com.sonoslocal.mac\"'")
            }
            Section {
                LabeledContent("Discovery", value: "Bonjour and SSDP on this network")
                LabeledContent("Control", value: "Speaker UPnP on port 1400")
                LabeledContent("Account", value: "None")
            } header: {
                Text("Privacy")
            } footer: {
                Text("Sonos Local is not affiliated with Sonos, Inc. Signing into music services, measuring Trueplay, voice setup, and firmware updates still belong to the official app. Favorites and services already linked on the speakers keep working.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding(20)
    }
}
