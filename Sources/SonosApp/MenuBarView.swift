import SwiftUI
import SonosKit

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WindowOpener()
            if let group = model.selected {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    player(group, elapsed: model.projectedElapsed(for: group, now: context.date))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.snapshot.isDiscovering ? "Looking for speakers" : "No speakers found")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Sonos Local stays on your Wi-Fi. Nothing is sent to a Sonos account.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("Search again") { model.refresh() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.top, 4)
                }
                .padding(18)
            }
        }
        .frame(width: 320)
        .background(Palette.background(scheme))
        .task { await model.start() }
    }

    private func player(_ group: GroupSnapshot, elapsed: Int) -> some View {
        let playing = group.nowPlaying
        return VStack(alignment: .leading, spacing: 12) {
            ArtworkView(url: group.artworkURL, cornerRadius: 10)
                .frame(height: 200)
            Text(playing.title.isEmpty ? "Nothing playing" : playing.title)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
            Text(playing.artistLine.isEmpty ? group.name : playing.artistLine)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            ThinSlider(
                value: Binding(
                    get: { model.seekDraft ?? Double(elapsed) },
                    set: { model.setSeek($0, group: group) }
                ),
                range: 0...Double(max(playing.duration, 1)),
                onEditingChanged: { editing in
                    if editing { model.beginSeek(model.seekDraft ?? Double(elapsed)) }
                    else { model.endSeek() }
                },
                accessibilityTitle: "Position"
            )
            HStack {
                Text(SonosTime.display(elapsed))
                Spacer()
                Text(playing.duration > 0 ? "-\(SonosTime.display(max(0, playing.duration - elapsed)))" : "")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            TransportControls(
                isPlaying: playing.isPlaying,
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
                LabeledContent("Discovery", value: "SSDP and Bonjour on this network")
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
