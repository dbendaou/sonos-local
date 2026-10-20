import SwiftUI
import SonosKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            RoomColumn()
                .frame(width: 340)
            ZStack(alignment: .trailing) {
                NowPlayingView()
                if model.showQueue {
                    QueueView()
                        .frame(width: 340)
                        .background(Palette.background(scheme))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Palette.hairline(scheme)).frame(width: 1)
                        }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .background(Palette.background(scheme))
        .overlay(alignment: .topTrailing) {
            toolbar
                .padding(.top, 18)
                .padding(.trailing, 18)
        }
        .overlay(alignment: .bottom) { toast }
        .animation(.easeInOut(duration: 0.22), value: model.showQueue)
        .task { await model.start() }
        .sheet(isPresented: $model.showLibrary) {
            LibrarySheet()
                .environment(model)
        }
        .sheet(isPresented: $model.showGroup) {
            GroupSheet()
                .environment(model)
        }
        .sheet(isPresented: $model.showRoomSettings) {
            RoomSettingsSheet(speakerID: model.selected?.coordinatorUUID ?? "")
                .environment(model)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            QuietButton(systemName: "list.bullet", label: "Queue", active: model.showQueue) {
                model.showQueue.toggle()
                model.reloadQueue()
            }
            QuietButton(systemName: "star", label: "Library") { model.showLibrary = true }
            QuietButton(systemName: "person.2", label: "Group rooms") { model.showGroup = true }
            QuietButton(systemName: "slider.horizontal.3", label: "Room settings") { model.showRoomSettings = true }
        }
        .padding(4)
        .background(Palette.card(scheme), in: Capsule())
    }

    @ViewBuilder private var toast: some View {
        if let message = model.message {
            Text(message)
                .font(.system(size: 13))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 22)
                .transition(.opacity)
        }
    }
}

struct RoomColumn: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Rooms")
                    .font(.system(size: 34, weight: .regular))
                Text(status)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 52)
            .padding(.bottom, 18)

            if model.snapshot.groups.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.snapshot.groups) { group in
                            RoomCard(group: group, selected: group.id == model.selected?.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var status: String {
        if model.snapshot.isDiscovering && model.snapshot.groups.isEmpty {
            return "Searching your network"
        }
        if model.snapshot.groups.isEmpty {
            return "Nothing on this network"
        }
        return "In your home"
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.snapshot.isDiscovering && !model.snapshot.hasCompletedDiscovery {
                ProgressView()
                    .controlSize(.small)
                Text("Looking for speakers on this Mac’s Wi-Fi.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No speakers found")
                    .font(.system(size: 17, weight: .semibold))
                Text("Sonos Local only talks to speakers on the local network. Check Wi-Fi, then search again.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Search again") { model.refresh() }
                    .buttonStyle(.borderedProminent)
                    .tint(.primary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct RoomCard: View {
    var group: GroupSnapshot
    var selected: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button {
            model.select(group)
        } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(group.nowPlaying.statusLine)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                ArtworkView(url: group.artworkURL, cornerRadius: 8)
                    .frame(width: 56, height: 56)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected ? Palette.cardActive(scheme) : Palette.card(scheme))
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(group.name), \(group.nowPlaying.statusLine)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
