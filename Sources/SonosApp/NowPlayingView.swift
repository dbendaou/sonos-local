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
            if model.snapshot.groups.isEmpty {
                ProgressView().controlSize(.small)
                Text("Searching for speakers…")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            } else {
                Text("Select a room")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func player(_ group: GroupSnapshot) -> some View {
        GeometryReader { geo in
            let column = min(460, max(260, geo.size.width - 72))
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let playing = group.nowPlaying
                let elapsed = model.projectedElapsed(for: group, now: context.date)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        OutputButton(name: group.name, grouped: group.members.count > 1) {
                            model.showGroup = true
                        }
                        .padding(.bottom, 18)

                        ArtworkView(
                            url: group.artworkURL,
                            fallbackURL: group.artworkFallbackURL,
                            placeholderSymbol: playing.symbolName,
                            cornerRadius: 14
                        )
                        .aspectRatio(1, contentMode: .fit)
                        .frame(width: column)
                        .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.14), radius: 28, y: 16)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(playing.title.isEmpty ? "Nothing playing" : playing.title)
                                .font(.system(size: 22, weight: .semibold))
                                .lineLimit(2)
                            if !playing.artistLine.isEmpty {
                                Text(playing.artistLine)
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            if !playing.source.isEmpty {
                                Text(playing.source)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.top, 22)
                        .frame(width: column, alignment: .leading)

                        progress(group, playing: playing, elapsed: elapsed)
                            .padding(.top, 18)
                            .frame(width: column)

                        TransportControls(
                            isPlaying: playing.isPlaying,
                            showsSkip: playing.showsSkip,
                            onPrevious: { model.previous() },
                            onToggle: { model.togglePlay() },
                            onNext: { model.next() }
                        )
                        .frame(width: column)
                        .padding(.top, 22)

                        volume(group)
                            .padding(.top, 26)
                            .frame(width: column)

                        if playing.showsModes || !playing.sleepRemaining.isEmpty {
                            modes(group)
                                .padding(.top, 8)
                                .frame(width: column, alignment: .leading)
                        }
                    }
                    .frame(width: column)
                    .padding(.top, 72)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func progress(_ group: GroupSnapshot, playing: NowPlaying, elapsed: Int) -> some View {
        if playing.isLive || !playing.canSeek {
            HStack(spacing: 8) {
                Circle()
                    .fill(playing.isPlaying ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
                Text(playing.isLive ? "Live" : "Not seekable")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else {
            let duration = max(playing.duration, 1)
            let position = min(elapsed, duration)
            VStack(spacing: 6) {
                ThinSlider(
                    value: Binding(
                        get: { Double(model.seekDraft ?? Double(position)) },
                        set: { model.setSeek($0, group: group) }
                    ),
                    range: 0...Double(duration),
                    onEditingChanged: { editing in
                        if editing {
                            model.beginSeek(model.seekDraft ?? Double(position))
                        } else {
                            model.endSeek()
                        }
                    },
                    accessibilityTitle: "Position"
                )
                HStack {
                    Text(SonosTime.display(position))
                    Spacer()
                    Text("-\(SonosTime.display(max(0, duration - position)))")
                }
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            }
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
            .buttonStyle(.borderless)
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
                .accessibilityHidden(true)
        }
    }

    private func modes(_ group: GroupSnapshot) -> some View {
        let playing = group.nowPlaying
        return HStack(spacing: 4) {
            if playing.showsModes {
                QuietButton(systemName: "shuffle", label: "Shuffle", active: playing.shuffle) { model.toggleShuffle() }
                QuietButton(
                    systemName: playing.repeatMode == .one ? "repeat.1" : "repeat",
                    label: "Repeat \(playing.repeatMode.title)",
                    active: playing.repeatMode != .off
                ) { model.cycleRepeat() }
                QuietButton(systemName: "arrow.left.arrow.right", label: "Crossfade", active: playing.crossfade) {
                    model.setCrossfade(!playing.crossfade)
                }
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
            .accessibilityLabel("Sleep timer")
            .help("Sleep timer")
            if !playing.sleepRemaining.isEmpty {
                Text(playing.sleepRemaining)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
