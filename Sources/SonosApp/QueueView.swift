import SwiftUI
import SonosKit

struct QueueView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Queue")
                        .font(.system(size: 17, weight: .semibold))
                    Text(model.queue.isEmpty ? "Empty" : "\(model.queue.count) tracks")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear") { model.clearQueue() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .disabled(model.queue.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.top, 64)
            .padding(.bottom, 12)

            if model.queueLoading && model.queue.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .padding(24)
                Spacer()
            } else if model.queue.isEmpty {
                Text("Nothing queued. Play a favorite and it will show up here, or add tracks from the library.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.queue) { item in
                            row(item)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .onAppear { model.reloadQueue() }
    }

    private func row(_ item: QueueItem) -> some View {
        let current = model.selected?.nowPlaying.trackNumber == item.position && model.selected?.nowPlaying.transport != .stopped
        return Button {
            model.playQueue(position: item.position)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(String(format: "%02d", item.position))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(current ? Color.primary : Color.secondary)
                    .frame(width: 24, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14, weight: current ? .semibold : .regular))
                        .lineLimit(1)
                    if !item.artist.isEmpty {
                        Text(item.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Play") { model.playQueue(position: item.position) }
            Button("Move up") { model.moveQueue(from: item.position, to: max(1, item.position - 1)) }
                .disabled(item.position == 1)
            Button("Move down") { model.moveQueue(from: item.position, to: min(model.queue.count, item.position + 1)) }
                .disabled(item.position == model.queue.count)
            Divider()
            Button("Remove", role: .destructive) { model.removeQueue(item) }
        }
    }
}

struct LibrarySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var tab: LibraryTab = .favorites
    @State private var items: [MediaItem] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Library")
                    .font(.system(size: 22, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)

            HStack(spacing: 18) {
                ForEach(LibraryTab.allCases) { item in
                    Button(item.rawValue) { tab = item }
                        .buttonStyle(.plain)
                        .font(.system(size: 14, weight: tab == item ? .semibold : .regular))
                        .foregroundStyle(tab == item ? Color.primary : Color.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider().opacity(0.4)

            content
        }
        .frame(width: 560, height: 640)
        .background(Palette.background(scheme))
        .task(id: tab) { await load() }
    }

    @ViewBuilder private var content: some View {
        if loading {
            Spacer()
            HStack { Spacer(); ProgressView(); Spacer() }
            Spacer()
        } else if let error {
            VStack(alignment: .leading, spacing: 8) {
                Text("Couldn’t load \(tab.rawValue.lowercased())")
                    .font(.system(size: 16, weight: .semibold))
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            Spacer()
        } else if items.isEmpty {
            Text(emptyCopy)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(24)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(items) { item in
                        libraryRow(item)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var emptyCopy: String {
        switch tab {
        case .favorites: return "No Sonos favorites are saved on this system."
        case .playlists: return "No playlists were returned by the speaker."
        case .inputs: return "No line-in or TV input is available from this room."
        case .radio: return "No radio stations are saved on this system."
        }
    }

    private func libraryRow(_ item: MediaItem) -> some View {
        HStack(spacing: 12) {
            ArtworkView(
                url: model.selected.flatMap { model.artworkURL(for: item.artURI, group: $0) },
                fallbackURL: model.selected.flatMap { model.artworkFallbackURL(for: item.artURI, group: $0) },
                cornerRadius: 6
            )
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Text(item.subtitle.isEmpty ? item.itemClass : item.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                model.play(item)
                dismiss()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 12))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(item.title)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .contextMenu {
            Button("Play") { model.play(item); dismiss() }
            Button("Play next") { model.enqueue(item, next: true) }
            Button("Add to queue") { model.enqueue(item, next: false) }
        }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            items = try await model.loadLibrary(tab)
            loading = false
        } catch {
            items = []
            loading = false
            self.error = (error as? SonosError)?.message ?? error.localizedDescription
        }
    }
}
