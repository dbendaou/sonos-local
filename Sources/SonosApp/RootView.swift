import SwiftUI
import SonosKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openSettings) private var openSettings
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var headerOutput: CGFloat = 34
    @State private var headerGap: CGFloat = 14

    /// Inset of the toolbar pill from the window's top and trailing edges.
    private static let edgeInset: CGFloat = 24
    private static let toolbarPill: CGFloat = 42
    /// Room picker sits one inset below the pill.
    private var contentTop: CGFloat { Self.edgeInset + Self.toolbarPill + Self.edgeInset }

    var body: some View {
        @Bindable var model = model
        GeometryReader { proxy in
            let compact = proxy.size.width < 880
            NavigationSplitView(columnVisibility: $columnVisibility) {
                RoomColumn(topPadding: contentTop, outputHeight: headerOutput, headerGap: headerGap)
                    .navigationSplitViewColumnWidth(min: 216, ideal: 280, max: 320)
                    .ignoresSafeArea(edges: .top)
            } detail: {
                detail
                    .ignoresSafeArea(edges: .top)
            }
            .navigationSplitViewStyle(.balanced)
            .modifier(HiddenWindowToolbar())
            .onChange(of: compact) { _, isCompact in
                columnVisibility = isCompact ? .detailOnly : .all
            }
        }
        .frame(minWidth: 720, minHeight: 540)
        .ignoresSafeArea(edges: .top)
        .background(Palette.background(scheme))
        .background(ReleaseInitialFocus())
        .background(WindowChrome())
        .onPreferenceChange(NowPlayingHeaderKey.self) { header in
            headerOutput = header.output
            headerGap = header.gap
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

    private var detail: some View {
        GeometryReader { proxy in
            ZStack(alignment: .trailing) {
                NowPlayingView(topInset: contentTop)
                if model.showQueue {
                    QueueView()
                        .frame(width: min(320, max(220, proxy.size.width * 0.42)))
                        .background(Palette.background(scheme))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Palette.hairline(scheme)).frame(width: 1)
                        }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .overlay(alignment: .topTrailing) {
                toolbar
                    .fixedSize()
                    .padding(.top, Self.edgeInset)
                    .padding(.trailing, Self.edgeInset)
            }
        }
    }

    private var roomsCollapsed: Bool { columnVisibility == .detailOnly }

    private var toolbar: some View {
        HStack(spacing: 2) {
            QuietButton(systemName: "sidebar.left", label: roomsCollapsed ? "Show rooms" : "Hide rooms") {
                columnVisibility = roomsCollapsed ? .all : .detailOnly
            }
            QuietButton(systemName: "list.bullet", label: "Queue", active: model.showQueue) {
                model.showQueue.toggle()
                model.reloadQueue()
            }
            QuietButton(systemName: "star", label: "Library") { model.showLibrary = true }
            QuietButton(systemName: "hifispeaker.2", label: "Where is it playing") { model.showGroup = true }
            QuietButton(systemName: "slider.horizontal.3", label: "Room settings") { model.showRoomSettings = true }
            QuietButton(systemName: "gearshape", label: "Settings") { openSettings() }
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

struct NowPlayingHeader: Equatable {
    var output: CGFloat = 34
    var gap: CGFloat = 14
}

struct NowPlayingHeaderKey: PreferenceKey {
    static var defaultValue = NowPlayingHeader()
    static func reduce(value: inout NowPlayingHeader, nextValue: () -> NowPlayingHeader) {
        value = nextValue()
    }
}

private struct HiddenWindowToolbar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.toolbar(.hidden, for: .windowToolbar)
        } else {
            content
        }
    }
}

struct RoomColumn: View {
    var topPadding: CGFloat = 90
    var outputHeight: CGFloat = 34
    var headerGap: CGFloat = 14
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Rooms")
                    .font(.system(size: 28, weight: .regular))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: outputHeight)
                Text(status)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: headerGap, alignment: .top)
            }
            .padding(.horizontal, 24)
            .padding(.top, topPadding)

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
        if model.snapshot.groups.isEmpty {
            return "Searching for speakers…"
        }
        return "In your home"
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgressView()
                .controlSize(.small)
            Text("Searching for speakers…")
                .font(.system(size: 17, weight: .semibold))
            Text("Sonos Local keeps looking on this Mac’s Wi-Fi. A single search sometimes misses the household.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                ArtworkView(url: group.artworkURL, fallbackURL: group.artworkFallbackURL, cornerRadius: 8)
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
