import Foundation
import SonosKit

@MainActor
@Observable
final class AppModel {
    static let menuBarOnlyKey = "menuBarOnly"
    static let selectedRoomKey = "selectedRoomUUID"

    private(set) var snapshot = SystemSnapshot.empty
    var selectedGroupID: String?
    var queue: [QueueItem] = []
    var queueLoading = false
    var showQueue = false
    var showLibrary = false
    var showGroup = false
    var showRoomSettings = false
    var message: String?
    var menuBarOnly: Bool
    var volumeDrafts: [String: Double] = [:]
    var seekDraft: Double?
    var speakerIP = ""

    private let system = SonosSystem()
    private var started = false
    private var listen: Task<Void, Never>?
    private var messageTask: Task<Void, Never>?
    private var queueTask: Task<Void, Never>?
    private var elapsedAnchor: (groupID: String, base: Int, at: Date)?
    private var preferredRoomUUID: String?

    init() {
        menuBarOnly = UserDefaults.standard.bool(forKey: Self.menuBarOnlyKey)
        preferredRoomUUID = UserDefaults.standard.string(forKey: Self.selectedRoomKey)
    }

    var selected: GroupSnapshot? {
        guard let selectedGroupID else { return snapshot.groups.first }
        return snapshot.groups.first { $0.id == selectedGroupID } ?? snapshot.groups.first
    }

    var menuBarSymbol: String {
        selected?.nowPlaying.isPlaying == true ? "hifispeaker.fill" : "hifispeaker"
    }

    func start() async {
        guard !started else { return }
        started = true
        let stream = await system.updates()
        listen = Task { [weak self] in
            for await snapshot in stream {
                self?.apply(snapshot)
            }
        }
        await system.start()
    }

    func refresh() {
        Task { await system.refresh() }
    }

    func addSpeakerIP() {
        let address = speakerIP
        perform {
            try await self.system.addSpeaker(host: address)
            self.speakerIP = ""
        }
    }

    func forgetSpeakers() {
        perform {
            await self.system.forgetSpeakers()
        }
    }

    func select(_ group: GroupSnapshot) {
        selectedGroupID = group.id
        preferredRoomUUID = group.coordinatorUUID
        UserDefaults.standard.set(group.coordinatorUUID, forKey: Self.selectedRoomKey)
        elapsedAnchor = (group.id, group.nowPlaying.elapsed, Date())
        reloadQueue()
    }

    func projectedElapsed(for group: GroupSnapshot, now: Date) -> Int {
        if let seekDraft, group.id == selected?.id {
            return Int(seekDraft.rounded())
        }
        let base = group.nowPlaying.elapsed
        guard group.nowPlaying.isPlaying, let anchor = elapsedAnchor, anchor.groupID == group.id, anchor.base == base else {
            return base
        }
        let extra = Int(now.timeIntervalSince(anchor.at))
        if group.nowPlaying.duration > 0 {
            return min(group.nowPlaying.duration, base + max(0, extra))
        }
        return base + max(0, extra)
    }

    func groupVolume(_ group: GroupSnapshot) -> Double {
        volumeDrafts["group-\(group.id)"] ?? Double(group.groupVolume)
    }

    func setGroupVolume(_ value: Double, group: GroupSnapshot) {
        volumeDrafts["group-\(group.id)"] = value
        Task { await system.setGroupVolume(groupID: group.id, volume: Int(value.rounded())) }
    }

    func endGroupVolume(_ group: GroupSnapshot) {
        let id = group.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            volumeDrafts["group-\(id)"] = nil
        }
    }

    func memberVolume(_ member: MemberSnapshot) -> Double {
        volumeDrafts["member-\(member.uuid)"] ?? Double(member.volume)
    }

    func setMemberVolume(_ value: Double, member: MemberSnapshot) {
        volumeDrafts["member-\(member.uuid)"] = value
        Task { await system.setMemberVolume(uuid: member.uuid, volume: Int(value.rounded())) }
    }

    func endMemberVolume(_ member: MemberSnapshot) {
        let uuid = member.uuid
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            volumeDrafts["member-\(uuid)"] = nil
        }
    }

    func beginSeek(_ value: Double) {
        seekDraft = value
    }

    func setSeek(_ value: Double, group: GroupSnapshot) {
        seekDraft = value
        Task { await system.seek(groupID: group.id, seconds: Int(value.rounded())) }
    }

    func endSeek() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            seekDraft = nil
        }
    }

    func togglePlay() { perform { [id = selected?.id] in guard let id else { return }; try await self.system.togglePlay(groupID: id) } }
    func next() { perform { [id = selected?.id] in guard let id else { return }; try await self.system.next(groupID: id) } }
    func previous() { perform { [id = selected?.id] in guard let id else { return }; try await self.system.previous(groupID: id) } }

    func toggleMute() {
        guard let group = selected else { return }
        let muted = !group.groupMuted
        perform { try await self.system.setGroupMuted(groupID: group.id, muted: muted) }
    }

    func toggleShuffle() { perform { [id = selected?.id] in guard let id else { return }; try await self.system.toggleShuffle(groupID: id) } }
    func cycleRepeat() { perform { [id = selected?.id] in guard let id else { return }; try await self.system.cycleRepeat(groupID: id) } }

    func setCrossfade(_ enabled: Bool) {
        guard let id = selected?.id else { return }
        perform { try await self.system.setCrossfade(groupID: id, enabled: enabled) }
    }

    func setSleep(minutes: Int?) {
        guard let id = selected?.id else { return }
        perform { try await self.system.setSleep(groupID: id, minutes: minutes) }
    }

    func setMembership(_ ids: [String]) {
        guard let id = selected?.id else { return }
        perform { try await self.system.setMembership(groupID: id, memberUUIDs: ids) }
    }

    func playQueue(position: Int) {
        guard let id = selected?.id else { return }
        perform {
            try await self.system.playQueue(groupID: id, position: position)
            await self.reloadQueueIfNeeded()
        }
    }

    func removeQueue(_ item: QueueItem) {
        guard let id = selected?.id else { return }
        perform {
            try await self.system.removeFromQueue(groupID: id, itemID: item.id)
            await self.reloadQueueIfNeeded()
        }
    }

    func clearQueue() {
        guard let id = selected?.id else { return }
        perform {
            try await self.system.clearQueue(groupID: id)
            await self.reloadQueueIfNeeded()
        }
    }

    func moveQueue(from position: Int, to newPosition: Int) {
        guard let id = selected?.id else { return }
        perform {
            try await self.system.moveQueueItem(groupID: id, from: position, to: newPosition)
            await self.reloadQueueIfNeeded()
        }
    }

    func loadLibrary(_ tab: LibraryTab) async throws -> [MediaItem] {
        guard let id = selected?.id else { return [] }
        switch tab {
        case .favorites: return try await system.favorites(groupID: id)
        case .playlists: return try await system.playlists(groupID: id)
        case .inputs: return try await system.inputs(groupID: id)
        case .radio: return try await system.radioStations(groupID: id)
        }
    }

    func play(_ item: MediaItem) {
        guard let id = selected?.id else { return }
        perform { try await self.system.play(groupID: id, item: item) }
    }

    func enqueue(_ item: MediaItem, next: Bool) {
        guard let id = selected?.id else { return }
        perform { try await self.system.enqueue(groupID: id, item: item, next: next) }
    }

    func loadSettings(uuid: String) async throws -> RoomSettings {
        try await system.roomSettings(uuid: uuid)
    }

    func rename(uuid: String, name: String) {
        perform { try await self.system.renameRoom(uuid: uuid, name: name) }
    }

    func setBass(uuid: String, value: Int) { perform { try await self.system.setBass(uuid: uuid, value: value) } }
    func setTreble(uuid: String, value: Int) { perform { try await self.system.setTreble(uuid: uuid, value: value) } }
    func setLoudness(uuid: String, enabled: Bool) { perform { try await self.system.setLoudness(uuid: uuid, enabled: enabled) } }
    func setFixedOutput(uuid: String, enabled: Bool) { perform { try await self.system.setFixedOutput(uuid: uuid, enabled: enabled) } }
    func setTrueplay(uuid: String, enabled: Bool) { perform { try await self.system.setTrueplay(uuid: uuid, enabled: enabled) } }
    func setEQ(uuid: String, type: EQType, value: Int) { perform { try await self.system.setEQ(uuid: uuid, type: type, value: value) } }
    func setStatusLight(uuid: String, on: Bool) { perform { try await self.system.setStatusLight(uuid: uuid, on: on) } }
    func setButtonLock(uuid: String, locked: Bool) { perform { try await self.system.setButtonLock(uuid: uuid, locked: locked) } }
    func setMemberMuted(uuid: String, muted: Bool) { perform { try await self.system.setMemberMuted(uuid: uuid, muted: muted) } }
    func createAlarm(_ draft: AlarmDraft) { perform { try await self.system.createAlarm(draft) } }
    func updateAlarm(_ alarm: Alarm) { perform { try await self.system.updateAlarm(alarm) } }
    func deleteAlarm(id: Int, speakerUUID: String) { perform { try await self.system.deleteAlarm(id: id, speakerUUID: speakerUUID) } }

    func setMenuBarOnly(_ value: Bool) {
        menuBarOnly = value
        UserDefaults.standard.set(value, forKey: Self.menuBarOnlyKey)
        NotificationCenter.default.post(name: .sonosMenuBarOnly, object: nil, userInfo: ["value": value])
    }

    func openMainWindow() {
        NotificationCenter.default.post(name: .sonosOpenMainWindow, object: nil)
    }

    func reloadQueue() {
        queueTask?.cancel()
        guard showQueue, let id = selected?.id else { return }
        queueLoading = queue.isEmpty
        queueTask = Task { [weak self] in
            guard let self else { return }
            do {
                let items = try await system.queue(groupID: id)
                if Task.isCancelled { return }
                queue = items
                queueLoading = false
            } catch {
                if Task.isCancelled { return }
                queueLoading = false
                flash((error as? SonosError)?.message ?? error.localizedDescription)
            }
        }
    }

    func artworkURL(for itemArt: String?, group: GroupSnapshot) -> URL? {
        guard let host = group.coordinator?.host else { return nil }
        return ArtworkURL.resolve(artURI: itemArt, trackURI: nil, host: host, port: group.coordinator?.port ?? 1400)
    }

    func artworkFallbackURL(for itemArt: String?, group: GroupSnapshot) -> URL? {
        guard let host = group.coordinator?.host else { return nil }
        return ArtworkURL.httpsFallback(artURI: itemArt, host: host, port: group.coordinator?.port ?? 1400)
    }

    private func apply(_ snapshot: SystemSnapshot) {
        self.snapshot = snapshot
        if let preferredRoomUUID, let match = snapshot.groups.first(where: { $0.coordinatorUUID == preferredRoomUUID || $0.members.contains { $0.uuid == preferredRoomUUID } }) {
            selectedGroupID = match.id
        } else if selectedGroupID == nil || !snapshot.groups.contains(where: { $0.id == selectedGroupID }) {
            selectedGroupID = snapshot.groups.first?.id
            preferredRoomUUID = snapshot.groups.first?.coordinatorUUID
        }
        if let group = selected {
            if elapsedAnchor?.groupID != group.id || elapsedAnchor?.base != group.nowPlaying.elapsed {
                elapsedAnchor = (group.id, group.nowPlaying.elapsed, Date())
            }
        }
    }

    private func perform(_ work: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            do {
                try await work()
            } catch {
                flash((error as? SonosError)?.message ?? error.localizedDescription)
            }
        }
    }

    private func reloadQueueIfNeeded() async {
        guard showQueue, let id = selected?.id else { return }
        if let items = try? await system.queue(groupID: id) {
            queue = items
        }
    }

    private func flash(_ text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            if !Task.isCancelled { message = nil }
        }
    }
}

enum LibraryTab: String, CaseIterable, Identifiable {
    case favorites = "Favorites"
    case playlists = "Playlists"
    case inputs = "Inputs"
    case radio = "Radio"
    var id: String { rawValue }
}
