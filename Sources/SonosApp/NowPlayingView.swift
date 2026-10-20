import SwiftUI
import SonosKit

struct NowPlayingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let group = model.selected, model.snapshot.groups.contains(where: { $0.id == group.id }) {
                player(group)
            } else if model.snapshot.isDiscovering && model.snapshot.groups.isEmpty {
                waiting
            } else {
                waiting
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var waiting: some View {
        VStack(spacing: 12) {
            Image(systemName: "hifispeaker")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text(model.snapshot.groups.isEmpty ? "Choose a room when one appears" : "Select a room")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }

    private func player(_ group: GroupSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let playing = group.nowPlaying
            let elapsed = model.projectedElapsed(for: group, now: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(group.name)
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.bottom, 18)

                    ArtworkView(url: group.artworkURL, cornerRadius: 14)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 460)
                        .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.14), radius: 28, y: 16)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(playing.title.isEmpty ? "Nothing playing" : playing.title)
                            .font(.system(size: 22, weight: .semibold))
                            .lineLimit(2)
                        Text(playing.artistLine.isEmpty ? " " : playing.artistLine)
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if !playing.source.isEmpty {
                            Text(playing.source)
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.top, 22)
                    .frame(maxWidth: 460, alignment: .leading)

                    progress(group, elapsed: elapsed, duration: playing.duration, enabled: playing.canSeek || playing.duration > 0)
                        .padding(.top, 18)
                        .frame(maxWidth: 460)

                    TransportControls(
                        isPlaying: playing.isPlaying,
                        onPrevious: { model.previous() },
                        onToggle: { model.togglePlay() },
                        onNext: { model.next() }
                    )
                    .frame(maxWidth: 460)
                    .padding(.top, 22)

                    volume(group)
                        .padding(.top, 26)
                        .frame(maxWidth: 460)

                    modes(group)
                        .padding(.top, 8)
                        .frame(maxWidth: 460, alignment: .leading)
                }
                .padding(.horizontal, 48)
                .padding(.top, 64)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func progress(_ group: GroupSnapshot, elapsed: Int, duration: Int, enabled: Bool) -> some View {
        VStack(spacing: 6) {
            ThinSlider(
                value: Binding(
                    get: { Double(model.seekDraft ?? Double(elapsed)) },
                    set: { model.setSeek($0, group: group) }
                ),
                range: 0...Double(max(duration, 1)),
                onEditingChanged: { editing in
                    if editing {
                        model.beginSeek(model.seekDraft ?? Double(elapsed))
                    } else {
                        model.endSeek()
                    }
                },
                accessibilityTitle: "Position"
            )
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.4)
            HStack {
                Text(SonosTime.display(elapsed))
                Spacer()
                Text(duration > 0 ? "-\(SonosTime.display(max(0, duration - elapsed)))" : SonosTime.display(0))
            }
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.secondary)
        }
    }

    private func volume(_ group: GroupSnapshot) -> some View {
        HStack(spacing: 10) {
            Button {
                model.toggleMute()
            } label: {
                Image(systemName: group.groupMuted || group.groupVolume == 0 ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(group.groupMuted ? "Unmute" : "Mute")
            ThinSlider(
                value: Binding(
                    get: { model.groupVolume(group) },
                    set: { model.setGroupVolume($0, group: group) }
                ),
                onEditingChanged: { editing in
                    if !editing { model.endGroupVolume(group) }
                },
                accessibilityTitle: group.members.count > 1 ? "Group volume" : "Volume"
            )
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 22)
        }
    }

    private func modes(_ group: GroupSnapshot) -> some View {
        let playing = group.nowPlaying
        return HStack(spacing: 4) {
            QuietButton(systemName: "shuffle", label: "Shuffle", active: playing.shuffle) { model.toggleShuffle() }
            QuietButton(
                systemName: playing.repeatMode == .one ? "repeat.1" : "repeat",
                label: "Repeat \(playing.repeatMode.title)",
                active: playing.repeatMode != .off
            ) { model.cycleRepeat() }
            QuietButton(systemName: "arrow.left.arrow.right", label: "Crossfade", active: playing.crossfade) {
                model.setCrossfade(!playing.crossfade)
            }
            Menu {
                Button("Off") { model.setSleep(minutes: nil) }
                Button("15 minutes") { model.setSleep(minutes: 15) }
                Button("30 minutes") { model.setSleep(minutes: 30) }
                Button("45 minutes") { model.setSleep(minutes: 45) }
                Button("1 hour") { model.setSleep(minutes: 60) }
                Button("2 hours") { model.setSleep(minutes: 120) }
            } label: {
                Image(systemName: playing.sleepRemaining.isEmpty ? "moon" : "moon.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(playing.sleepRemaining.isEmpty ? Color.primary.opacity(0.42) : Color.primary)
                    .frame(width: 34, height: 34)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 34)
            .help("Sleep timer")
            if !playing.sleepRemaining.isEmpty {
                Text(playing.sleepRemaining)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
