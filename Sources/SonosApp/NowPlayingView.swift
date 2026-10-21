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
            let playing = group.nowPlaying
            let showsModes = playing.showsModes || !playing.sleepRemaining.isEmpty
            let metrics = PlayerFit.metrics(width: geo.size.width, height: geo.size.height, showsModes: showsModes)
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let elapsed = model.projectedElapsed(for: group, now: context.date)
                VStack(alignment: .leading, spacing: 0) {
                    OutputButton(name: group.name, grouped: group.members.count > 1) {
                        model.showGroup = true
                    }
                    .frame(height: metrics.output, alignment: .leading)
                    .padding(.bottom, metrics.afterOutput)

                    ArtworkView(
                        url: group.artworkURL,
                        fallbackURL: group.artworkFallbackURL,
                        placeholderSymbol: playing.symbolName,
                        cornerRadius: 14
                    )
                    .frame(width: metrics.artwork, height: metrics.artwork)
                    .shadow(color: .black.opacity(scheme == .dark ? 0.28 : 0.1), radius: 8, y: 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(playing.title.isEmpty ? "Nothing playing" : playing.title)
                            .font(.system(size: 20, weight: .semibold))
                            .lineLimit(1)
                        if !playing.artistLine.isEmpty {
                            Text(playing.artistLine)
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if !playing.source.isEmpty {
                            Text(playing.source)
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: metrics.column, height: metrics.title, alignment: .topLeading)
                    .padding(.top, metrics.afterArt)

                    progress(group, playing: playing, elapsed: elapsed)
                        .frame(width: metrics.column, height: metrics.progress, alignment: .top)
                        .padding(.top, metrics.afterProgress)

                    TransportControls(
                        isPlaying: playing.isPlaying,
                        showsSkip: playing.showsSkip,
                        diameter: metrics.transport,
                        onPrevious: { model.previous() },
                        onToggle: { model.togglePlay() },
                        onNext: { model.next() }
                    )
                    .frame(width: metrics.column, height: metrics.transport)
                    .padding(.top, metrics.beforeTransport)

                    volume(group)
                        .frame(width: metrics.column, height: metrics.volume)
                        .padding(.top, metrics.beforeVolume)

                    if showsModes {
                        modes(group)
                            .frame(width: metrics.column, height: metrics.modes, alignment: .leading)
                    }
                }
                .frame(width: metrics.column, alignment: .leading)
                .padding(.top, metrics.topInset)
                .padding(.bottom, metrics.bottomInset)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
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
