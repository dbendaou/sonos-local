import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum TransportState: String, Sendable, Equatable {
    case playing = "PLAYING"
    case paused = "PAUSED_PLAYBACK"
    case stopped = "STOPPED"
    case transitioning = "TRANSITIONING"
    case unknown = "UNKNOWN"

    public init(raw: String) {
        self = TransportState(rawValue: raw) ?? .unknown
    }

    public var isPlaying: Bool { self == .playing }
}

public struct NowPlaying: Sendable, Equatable {
    public var transport: TransportState
    public var title: String
    public var artist: String
    public var album: String
    public var source: String
    public var elapsed: Int
    public var duration: Int
    public var trackNumber: Int
    public var trackCount: Int
    public var shuffle: Bool
    public var repeatMode: RepeatMode
    public var crossfade: Bool
    public var sleepRemaining: String
    public var canSeek: Bool

    public var isPlaying: Bool { transport.isPlaying }

    public var artistLine: String {
        if !artist.isEmpty && !album.isEmpty { return "\(artist) — \(album)" }
        if !artist.isEmpty { return artist }
        return album
    }

    public var statusLine: String {
        switch transport {
        case .playing:
            return title.isEmpty ? "Playing" : title
        case .paused:
            return title.isEmpty ? "Paused" : "Paused · \(title)"
        case .transitioning:
            return "Connecting"
        case .stopped, .unknown:
            return "Not playing"
        }
    }

    public static let idle = NowPlaying(
        transport: .stopped,
        title: "",
        artist: "",
        album: "",
        source: "",
        elapsed: 0,
        duration: 0,
        trackNumber: 0,
        trackCount: 0,
        shuffle: false,
        repeatMode: .off,
        crossfade: false,
        sleepRemaining: "",
        canSeek: false
    )
}

public struct MemberSnapshot: Sendable, Equatable, Identifiable {
    public var id: String { uuid }
    public var uuid: String
    public var name: String
    public var host: String
    public var port: Int
    public var modelName: String
    public var modelNumber: String
    public var volume: Int
    public var isMuted: Bool
    public var isCoordinator: Bool
}

public struct GroupSnapshot: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var coordinatorUUID: String
    public var members: [MemberSnapshot]
    public var nowPlaying: NowPlaying
    public var groupVolume: Int
    public var groupMuted: Bool
    public var artworkURL: URL?
    /// https image from a streaming service, used only if `artworkURL` does not load.
    public var artworkFallbackURL: URL?

    public var coordinator: MemberSnapshot? {
        members.first { $0.uuid == coordinatorUUID } ?? members.first
    }
}

public struct SystemSnapshot: Sendable, Equatable {
    public var groups: [GroupSnapshot]
    public var isDiscovering: Bool
    public var hasCompletedDiscovery: Bool

    public static let empty = SystemSnapshot(groups: [], isDiscovering: true, hasCompletedDiscovery: false)
}

public struct RoomSettings: Sendable, Equatable {
    public var uuid: String
    public var name: String
    public var icon: String
    public var modelName: String
    public var modelNumber: String
    public var softwareVersion: String
    public var hardwareVersion: String
    public var serialNumber: String
    public var macAddress: String
    public var ipAddress: String
    public var householdID: String
    public var localTime: String
    public var timeZone: String
    public var volume: Int
    public var muted: Bool
    public var bass: Int?
    public var treble: Int?
    public var loudness: Bool?
    public var fixedOutput: Bool?
    public var trueplayAvailable: Bool?
    public var trueplayEnabled: Bool?
    public var nightMode: Bool?
    public var speechEnhancement: Bool?
    public var surroundEnabled: Bool?
    public var surroundLevel: Int?
    public var musicSurroundLevel: Int?
    public var surroundMode: Int?
    public var subGain: Int?
    public var heightLevel: Int?
    public var audioDelay: Int?
    public var statusLight: Bool?
    public var buttonsLocked: Bool?
    public var crossfade: Bool?
    public var playMode: PlayMode?
    public var sleepRemaining: String?
    public var alarms: [Alarm]
}

struct PlaybackStore: Equatable {
    var transport: TransportState = .stopped
    var title = ""
    var artist = ""
    var album = ""
    var artURI: String?
    var trackURI = ""
    var elapsed = 0
    var duration = 0
    var trackNumber = 0
    var trackCount = 0
    var playMode: PlayMode = .normal
    var crossfade = false
    var sleepRemaining = ""
    var actions: Set<String> = []

    var nowPlaying: NowPlaying {
        let canSeek: Bool
        if actions.isEmpty {
            canSeek = duration > 0
        } else {
            canSeek = actions.contains("Seek")
        }
        return NowPlaying(
            transport: transport,
            title: title,
            artist: artist,
            album: album,
            source: SourceLabel.describe(uri: trackURI),
            elapsed: elapsed,
            duration: max(duration, elapsed),
            trackNumber: trackNumber,
            trackCount: trackCount,
            shuffle: playMode.shuffle,
            repeatMode: playMode.repeatMode,
            crossfade: crossfade,
            sleepRemaining: sleepRemaining,
            canSeek: canSeek
        )
    }

    mutating func apply(position: [String: String]) {
        if let track = Int(position["Track"] ?? "") { trackNumber = track }
        if let value = SonosTime.parse(position["TrackDuration"] ?? "") { duration = value }
        if let value = SonosTime.parse(position["RelTime"] ?? "") { elapsed = value }
        if let uri = position["TrackURI"], !uri.isEmpty { trackURI = uri }
        apply(metadata: position["TrackMetaData"] ?? "")
    }

    mutating func apply(media: [String: String]) {
        if trackURI.isEmpty, let uri = media["CurrentURI"] { trackURI = uri }
        if title.isEmpty { apply(metadata: media["CurrentURIMetaData"] ?? "") }
        if let count = Int(media["NrTracks"] ?? ""), count > 0 { trackCount = count }
    }

    mutating func apply(metadata: String) {
        guard let track = DIDLParser.track(in: metadata) else { return }
        if !track.title.isEmpty { title = track.title }
        if !track.artist.isEmpty { artist = track.artist }
        if !track.album.isEmpty { album = track.album }
        if let art = track.artURI, !art.isEmpty { artURI = art }
        if duration == 0, track.duration > 0 { duration = track.duration }
    }
}

struct VolumeStore: Equatable {
    var level = 0
    var muted = false
}

enum SnapshotBuilder {
    static func make(
        devices: [String: DiscoveredSpeaker],
        groups: [ZoneGroup],
        playback: [String: PlaybackStore],
        volumes: [String: VolumeStore],
        groupVolumes: [String: VolumeStore],
        discovering: Bool,
        hasCompletedDiscovery: Bool
    ) -> SystemSnapshot {
        var covered = Set<String>()
        var snapshots: [GroupSnapshot] = []
        let sourceGroups = groups.isEmpty ? provisional(devices) : groups
        for group in sourceGroups {
            let visible = group.visibleMembers.filter { !$0.uuid.isEmpty }
            let members = visible.isEmpty ? group.members.filter { !$0.isBridge && !$0.isInvisible } : visible
            if members.isEmpty { continue }
            covered.formUnion(group.members.map(\.uuid))
            snapshots.append(snapshot(group: group, members: members, devices: devices, playback: playback, volumes: volumes, groupVolumes: groupVolumes))
        }
        if !groups.isEmpty {
            for device in devices.values where !covered.contains(device.uuid) && !device.isBridge && !device.isSub {
                let solo = ZoneGroup(
                    id: "solo-\(device.uuid)",
                    coordinatorUUID: device.uuid,
                    members: [ZoneMember(uuid: device.uuid, name: device.name, host: device.host, port: device.port, icon: "", softwareVersion: device.softwareVersion, isInvisible: false, isBridge: false)]
                )
                snapshots.append(snapshot(group: solo, members: solo.members, devices: devices, playback: playback, volumes: volumes, groupVolumes: groupVolumes))
            }
        }
        snapshots.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return SystemSnapshot(groups: snapshots, isDiscovering: discovering, hasCompletedDiscovery: hasCompletedDiscovery)
    }

    private static func provisional(_ devices: [String: DiscoveredSpeaker]) -> [ZoneGroup] {
        devices.values.filter { !$0.isBridge && !$0.isSub }.map { device in
            ZoneGroup(
                id: "solo-\(device.uuid)",
                coordinatorUUID: device.uuid,
                members: [ZoneMember(uuid: device.uuid, name: device.name, host: device.host, port: device.port, icon: "", softwareVersion: device.softwareVersion, isInvisible: false, isBridge: false)]
            )
        }
    }

    private static func snapshot(
        group: ZoneGroup,
        members: [ZoneMember],
        devices: [String: DiscoveredSpeaker],
        playback: [String: PlaybackStore],
        volumes: [String: VolumeStore],
        groupVolumes: [String: VolumeStore]
    ) -> GroupSnapshot {
        let memberSnapshots = members.map { member -> MemberSnapshot in
            let device = devices[member.uuid]
            let volume = volumes[member.uuid] ?? VolumeStore()
            let host = member.host.isEmpty ? (device?.host ?? "") : member.host
            let port = member.port == 0 ? (device?.port ?? 1400) : member.port
            return MemberSnapshot(
                uuid: member.uuid,
                name: member.name.isEmpty ? (device?.name ?? "Room") : member.name,
                host: host,
                port: port,
                modelName: device?.modelName ?? "",
                modelNumber: device?.modelNumber ?? "",
                volume: volume.level,
                isMuted: volume.muted,
                isCoordinator: member.uuid == group.coordinatorUUID
            )
        }
        let coordinator = memberSnapshots.first { $0.isCoordinator } ?? memberSnapshots.first
        let playing = playback[group.coordinatorUUID]?.nowPlaying ?? .idle
        let groupVolume = groupVolumes[group.id] ?? VolumeStore(level: coordinator?.volume ?? 0, muted: coordinator?.isMuted ?? false)
        let artHost = coordinator?.host ?? ""
        let artPort = coordinator?.port ?? 1400
        let artURI = playback[group.coordinatorUUID]?.artURI
        let trackURI = playback[group.coordinatorUUID]?.trackURI
        let art = ArtworkURL.resolve(artURI: artURI, trackURI: trackURI, host: artHost, port: artPort)
        let artFallback = ArtworkURL.httpsFallback(artURI: artURI, host: artHost, port: artPort)
        let name = group.displayName == "Room" ? (coordinator?.name ?? "Room") : group.displayName
        return GroupSnapshot(
            id: group.id,
            name: name,
            coordinatorUUID: group.coordinatorUUID,
            members: memberSnapshots,
            nowPlaying: playing,
            groupVolume: groupVolume.level,
            groupMuted: groupVolume.muted,
            artworkURL: art,
            artworkFallbackURL: artFallback
        )
    }
}

public actor SonosSystem {
    private var devices: [String: DiscoveredSpeaker] = [:]
    private var groups: [ZoneGroup] = []
    private var playback: [String: PlaybackStore] = [:]
    private var volumes: [String: VolumeStore] = [:]
    private var groupVolumes: [String: VolumeStore] = [:]
    private var discovering = true
    private var hasCompletedDiscovery = false
    private var continuations: [UUID: AsyncStream<SystemSnapshot>.Continuation] = [:]
    private var latest: SystemSnapshot = .empty
    private var loop: Task<Void, Never>?
    private var volumeJobs: [String: Task<Void, Never>] = [:]
    private var seekJobs: [String: Task<Void, Never>] = [:]
    private var subscriptions: [String: LiveSubscription] = [:]
    private var sidIndex: [String: String] = [:]
    private let eventServer = EventServer()
    private let soap = SOAPClient()
    private let defaults: UserDefaults
    #if canImport(Darwin)
    private var mdns: MDNSDiscovery?
    #endif

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func updates() -> AsyncStream<SystemSnapshot> {
        AsyncStream { continuation in
            let id = UUID()
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeContinuation(id) }
            }
            Task { await self.addContinuation(id, continuation) }
        }
    }

    public func start() {
        guard loop == nil else { return }
        try? eventServer.start()
        eventServer.onNotify = { [weak self] note in
            guard let self else { return }
            Task { await self.handle(note) }
        }
        loop = Task { [weak self] in
            await self?.run()
        }
        #if canImport(Darwin)
        let browser = MDNSDiscovery()
        browser.onLocation = { [weak self] location in
            guard let self else { return }
            Task { await self.ingest(locations: [location]) }
        }
        mdns = browser
        DispatchQueue.main.async {
            browser.start()
        }
        #endif
    }

    public func forgetSpeakers() async {
        SonosLog.discovery("Forgetting saved speakers")
        SpeakerCache.forget(in: defaults)
        devices.removeAll()
        groups.removeAll()
        playback.removeAll()
        volumes.removeAll()
        groupVolumes.removeAll()
        discovering = true
        hasCompletedDiscovery = false
        publish()
        await refresh()
    }

    public func addSpeaker(host: String) async throws {
        guard let location = SpeakerCache.location(from: host) else {
            throw SonosError(message: "Enter a speaker address on this network, such as 192.168.1.62.")
        }
        SonosLog.discovery("Manual add \(location)")
        let before = devices.count
        await ingest(locations: [location])
        await refreshTopology()
        discovering = groups.isEmpty
        publish()
        guard devices.count > before || devices.values.contains(where: { location.contains($0.host) }) else {
            throw SonosError(message: "No speaker answered at that address.")
        }
    }

    public func refresh() async {
        discovering = true
        hasCompletedDiscovery = false
        publish()
        // One SSDP pass often times out on a cold launch. Keep looking, and
        // leave the searching state up until a speaker actually answers.
        for attempt in 0..<4 {
            await discover()
            await refreshTopology()
            publish()
            if !groups.isEmpty { break }
            if attempt < 3 {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }
        discovering = groups.isEmpty
        hasCompletedDiscovery = !groups.isEmpty
        publish()
        await ensureSubscriptions()
    }

    // MARK: Playback

    public func togglePlay(groupID: String) async throws {
        let client = try coordinatorClient(groupID)
        let state = playback[client.uuid]?.transport ?? .unknown
        if state.isPlaying {
            try await client.pause()
        } else {
            try await client.play()
        }
        await pollCoordinator(client.uuid)
    }

    public func next(groupID: String) async throws {
        let client = try coordinatorClient(groupID)
        try await client.next()
        try await Task.sleep(nanoseconds: 250_000_000)
        await pollCoordinator(client.uuid)
    }

    public func previous(groupID: String) async throws {
        let client = try coordinatorClient(groupID)
        try await client.previous()
        try await Task.sleep(nanoseconds: 250_000_000)
        await pollCoordinator(client.uuid)
    }

    public func seek(groupID: String, seconds: Int) {
        guard let uuid = coordinatorUUID(groupID) else { return }
        updatePlayback(uuid) { $0.elapsed = seconds }
        publish()
        seekJobs[groupID]?.cancel()
        seekJobs[groupID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.sendSeek(groupID: groupID, seconds: seconds)
        }
    }

    public func setGroupVolume(groupID: String, volume: Int) {
        let level = min(100, max(0, volume))
        updateGroupVolume(groupID) { $0.level = level }
        publish()
        volumeJobs["group-\(groupID)"]?.cancel()
        volumeJobs["group-\(groupID)"] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.sendGroupVolume(groupID: groupID, volume: level)
        }
    }

    public func setGroupMuted(groupID: String, muted: Bool) async throws {
        updateGroupVolume(groupID) { $0.muted = muted }
        publish()
        try await coordinatorClient(groupID).setGroupMuted(muted)
    }

    public func setMemberVolume(uuid: String, volume: Int) {
        let level = min(100, max(0, volume))
        updateVolume(uuid) { $0.level = level }
        publish()
        volumeJobs["member-\(uuid)"]?.cancel()
        volumeJobs["member-\(uuid)"] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.sendMemberVolume(uuid: uuid, volume: level)
        }
    }

    public func setMemberMuted(uuid: String, muted: Bool) async throws {
        updateVolume(uuid) { $0.muted = muted }
        publish()
        try await tryClient(uuid).setMuted(muted)
    }

    public func cycleRepeat(groupID: String) async throws {
        let client = try coordinatorClient(groupID)
        let next = (playback[client.uuid]?.playMode ?? .normal).cyclingRepeat()
        try await client.setPlayMode(next)
        updatePlayback(client.uuid) { $0.playMode = next }
        publish()
    }

    public func toggleShuffle(groupID: String) async throws {
        let client = try coordinatorClient(groupID)
        let next = (playback[client.uuid]?.playMode ?? .normal).togglingShuffle()
        try await client.setPlayMode(next)
        updatePlayback(client.uuid) { $0.playMode = next }
        publish()
    }

    public func setCrossfade(groupID: String, enabled: Bool) async throws {
        let client = try coordinatorClient(groupID)
        try await client.setCrossfade(enabled)
        updatePlayback(client.uuid) { $0.crossfade = enabled }
        publish()
    }

    public func setSleep(groupID: String, minutes: Int?) async throws {
        let client = try coordinatorClient(groupID)
        try await client.setSleep(seconds: minutes.map { $0 * 60 })
        let label = minutes.map { "\($0):00" } ?? ""
        updatePlayback(client.uuid) { $0.sleepRemaining = label }
        publish()
    }

    public func setMembership(groupID: String, memberUUIDs: [String]) async throws {
        guard let group = groups.first(where: { $0.id == groupID }) else {
            throw SonosError(message: "That room is no longer available.")
        }
        let desired = Set(memberUUIDs)
        guard !desired.isEmpty else { return }
        let current = Set(group.visibleMembers.map(\.uuid))
        var coordinator = group.coordinatorUUID
        if !desired.contains(coordinator), let replacement = group.visibleMembers.map(\.uuid).first(where: { desired.contains($0) }) {
            try await tryClient(coordinator).delegateCoordination(to: replacement, rejoin: true)
            try await Task.sleep(nanoseconds: 300_000_000)
            try await tryClient(coordinator).becomeStandalone()
            coordinator = replacement
        }
        for uuid in desired.subtracting(current) where uuid != coordinator {
            try await tryClient(uuid).setAVTransportURI("x-rincon:\(coordinator)", metadata: "")
        }
        let staying = desired.union([coordinator])
        for uuid in current.subtracting(staying) {
            try await tryClient(uuid).becomeStandalone()
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        await refreshTopology()
        publish()
    }

    // MARK: Library

    public func queue(groupID: String) async throws -> [QueueItem] {
        let client = try coordinatorClient(groupID)
        let items = try await client.browse(objectID: "Q:0")
        return items.enumerated().map { index, item in
            QueueItem(
                id: item.id,
                position: index + 1,
                title: item.title,
                artist: item.artist,
                album: item.album,
                uri: item.uri,
                artURI: item.artURI,
                duration: item.duration
            )
        }
    }

    public func playQueue(groupID: String, position: Int) async throws {
        let client = try coordinatorClient(groupID)
        try await client.setAVTransportURI("x-rincon-queue:\(client.uuid)#0", metadata: "")
        try await client.seek(track: max(1, position))
        try await client.play()
        await pollCoordinator(client.uuid)
    }

    public func removeFromQueue(groupID: String, itemID: String) async throws {
        try await coordinatorClient(groupID).removeFromQueue(objectID: itemID)
    }

    public func clearQueue(groupID: String) async throws {
        try await coordinatorClient(groupID).clearQueue()
    }

    public func moveQueueItem(groupID: String, from position: Int, to newPosition: Int) async throws {
        let items = try await queue(groupID: groupID)
        guard let indexes = QueueMath.reorder(start: position - 1, newPosition: newPosition - 1, count: items.count) else { return }
        try await coordinatorClient(groupID).reorderQueue(startingIndex: indexes.startingIndex, insertBefore: indexes.insertBefore)
    }

    public func favorites(groupID: String) async throws -> [MediaItem] {
        try await coordinatorClient(groupID).browse(objectID: "FV:2")
    }

    public func playlists(groupID: String) async throws -> [MediaItem] {
        let client = try coordinatorClient(groupID)
        let saved = (try? await client.browse(objectID: "SQ:")) ?? []
        let imported = (try? await client.browse(objectID: "A:PLAYLISTS")) ?? []
        var seen = Set<String>()
        return (saved + imported).filter { seen.insert($0.id).inserted }
    }

    public func inputs(groupID: String) async throws -> [MediaItem] {
        try await coordinatorClient(groupID).browse(objectID: "AI:")
    }

    public func radioStations(groupID: String) async throws -> [MediaItem] {
        try await coordinatorClient(groupID).browse(objectID: "R:0/0")
    }

    public func play(groupID: String, item: MediaItem) async throws {
        guard !item.uri.isEmpty else {
            throw SonosError(message: "This item has no playable address on the speaker.")
        }
        let client = try coordinatorClient(groupID)
        try await client.setAVTransportURI(item.uri, metadata: item.metadata)
        try await client.play()
        await pollCoordinator(client.uuid)
    }

    public func enqueue(groupID: String, item: MediaItem, next: Bool) async throws {
        guard !item.uri.isEmpty else {
            throw SonosError(message: "This item can't be added to the queue.")
        }
        try await coordinatorClient(groupID).addToQueue(uri: item.uri, metadata: item.metadata, asNext: next)
    }

    // MARK: Settings

    public func roomSettings(uuid: String) async throws -> RoomSettings {
        let client = try tryClient(uuid)
        let attributes = try await client.zoneAttributes()
        let info = (try? await client.zoneInfo()) ?? [:]
        let device = devices[uuid]
        async let volume = client.volume()
        async let muted = client.muted()
        async let bass = optional { try await client.bass() }
        async let treble = optional { try await client.treble() }
        async let loudness = optional { try await client.loudness() }
        async let fixed = optional { try await client.outputFixed() }
        async let trueplay = optional { try await client.trueplay() }
        async let night = optional { try await client.eq(.nightMode) }
        async let dialog = optional { try await client.eq(.dialogLevel) }
        async let surroundOn = optional { try await client.eq(.surroundEnable) }
        async let surround = optional { try await client.eq(.surroundLevel) }
        async let musicSurround = optional { try await client.eq(.musicSurroundLevel) }
        async let surroundMode = optional { try await client.eq(.surroundMode) }
        async let sub = optional { try await client.eq(.subGain) }
        async let height = optional { try await client.eq(.heightChannelLevel) }
        async let delay = optional { try await client.eq(.audioDelay) }
        async let led = optional { try await client.ledOn() }
        async let locked = optional { try await client.buttonsLocked() }
        async let alarms = optional { try await client.alarms() }
        async let clock = optional { try await client.clock() }
        async let household = optional { try await client.householdID() }
        let coordinator = groups.first { $0.members.contains { $0.uuid == uuid } }?.coordinatorUUID ?? uuid
        let playbackClient = try? tryClient(coordinator)
        var crossfade: Bool?
        var sleep: String?
        if let playbackClient {
            crossfade = try? await playbackClient.crossfade()
            sleep = try? await playbackClient.sleepRemaining()
        }
        let mode = playback[coordinator]?.playMode
        let tuning = await trueplay
        return RoomSettings(
            uuid: uuid,
            name: attributes["CurrentZoneName"] ?? device?.name ?? "",
            icon: attributes["CurrentIcon"] ?? "",
            modelName: device?.modelName ?? "",
            modelNumber: device?.modelNumber ?? "",
            softwareVersion: info["DisplaySoftwareVersion"] ?? info["SoftwareVersion"] ?? device?.softwareVersion ?? "",
            hardwareVersion: info["HardwareVersion"] ?? "",
            serialNumber: info["SerialNumber"] ?? device?.serialNumber ?? "",
            macAddress: info["MACAddress"] ?? "",
            ipAddress: info["IPAddress"] ?? client.host,
            householdID: await household ?? "",
            localTime: (await clock)?.local ?? "",
            timeZone: (await clock)?.zone ?? "",
            volume: (try? await volume) ?? (volumes[uuid]?.level ?? 0),
            muted: (try? await muted) ?? (volumes[uuid]?.muted ?? false),
            bass: await bass,
            treble: await treble,
            loudness: await loudness,
            fixedOutput: await fixed,
            trueplayAvailable: tuning?.available,
            trueplayEnabled: tuning?.enabled,
            nightMode: (await night).map { $0 != 0 },
            speechEnhancement: (await dialog).map { $0 != 0 },
            surroundEnabled: (await surroundOn).map { $0 != 0 },
            surroundLevel: await surround,
            musicSurroundLevel: await musicSurround,
            surroundMode: await surroundMode,
            subGain: await sub,
            heightLevel: await height,
            audioDelay: await delay,
            statusLight: await led,
            buttonsLocked: await locked,
            crossfade: crossfade,
            playMode: mode,
            sleepRemaining: sleep,
            alarms: await alarms ?? []
        )
    }

    public func renameRoom(uuid: String, name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SonosError(message: "A room needs a name.") }
        let client = try tryClient(uuid)
        let attributes = (try? await client.zoneAttributes()) ?? [:]
        let icon = attributes["CurrentIcon"] ?? ""
        let configuration = attributes["CurrentConfiguration"] ?? ""
        try await client.setZoneAttributes(name: trimmed, icon: icon, configuration: configuration, targetRoom: trimmed)
        if var device = devices[uuid] {
            device.name = trimmed
            devices[uuid] = device
        }
        await refreshTopology()
        publish()
    }

    public func setBass(uuid: String, value: Int) async throws {
        try await tryClient(uuid).setBass(value)
    }

    public func setTreble(uuid: String, value: Int) async throws {
        try await tryClient(uuid).setTreble(value)
    }

    public func setLoudness(uuid: String, enabled: Bool) async throws {
        try await tryClient(uuid).setLoudness(enabled)
    }

    public func setFixedOutput(uuid: String, enabled: Bool) async throws {
        try await tryClient(uuid).setOutputFixed(enabled)
    }

    public func setTrueplay(uuid: String, enabled: Bool) async throws {
        try await tryClient(uuid).setTrueplay(enabled)
    }

    public func setEQ(uuid: String, type: EQType, value: Int) async throws {
        try await tryClient(uuid).setEQ(type, value: value)
    }

    public func setStatusLight(uuid: String, on: Bool) async throws {
        try await tryClient(uuid).setLED(on)
    }

    public func setButtonLock(uuid: String, locked: Bool) async throws {
        try await tryClient(uuid).setButtonsLocked(locked)
    }

    public func createAlarm(_ draft: AlarmDraft) async throws {
        _ = try await tryClient(draft.roomUUID).createAlarm(draft)
    }

    public func updateAlarm(_ alarm: Alarm) async throws {
        try await tryClient(alarm.roomUUID).updateAlarm(alarm)
    }

    public func deleteAlarm(id: Int, speakerUUID: String) async throws {
        try await tryClient(speakerUUID).destroyAlarm(id: id)
    }

    // MARK: Loop

    private func run() async {
        await connectCached()
        await refreshTopology()
        if !groups.isEmpty {
            discovering = false
            hasCompletedDiscovery = true
            publish()
        }
        await refresh()
        var tick = 0
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if Task.isCancelled { return }
            tick += 1
            if groups.isEmpty {
                discovering = true
                publish()
                await discover()
                await refreshTopology()
                discovering = groups.isEmpty
                if !groups.isEmpty {
                    hasCompletedDiscovery = true
                    await ensureSubscriptions()
                }
                publish()
                continue
            }
            await poll(includeVolumes: tick % 4 == 0)
            if tick % 8 == 0 {
                await discover()
                await refreshTopology()
                await ensureSubscriptions()
                await renewSubscriptions()
                publish()
            }
        }
    }

    private func connectCached() async {
        let cached = SpeakerCache.load(from: defaults)
        SonosLog.discovery("Saved speakers: \(cached.count)")
        await ingest(locations: cached.map(\.location))
    }

    private func discover() async {
        let responses = await Task.detached(priority: .userInitiated) {
            CSocket.ssdpSearch()
        }.value
        SonosLog.discovery("SSDP responses: \(responses.count)")
        if responses.isEmpty {
            SonosLog.discovery("SSDP saw nothing. Local Network permission may be blocking multicast, or no speaker answered this pass.")
        }
        for response in responses {
            SonosLog.discovery("SSDP \(response.location)")
        }
        await ingest(locations: responses.map(\.location))
    }

    private func ingest(locations: [String]) async {
        for location in locations {
            guard let url = URL(string: location), let host = url.host, NetworkPolicy.isAllowedHost(host) else {
                SonosLog.network("Skipping non-local location \(location)")
                continue
            }
            let port = url.port ?? 1400
            if devices.values.contains(where: { $0.host == host && $0.port == port }) {
                rememberSeen(host: host, port: port)
                continue
            }
            do {
                SonosLog.network("GET \(url.absoluteString)")
                var request = URLRequest(url: url)
                request.timeoutInterval = 4
                let (data, response) = try await soap.session.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    SonosLog.network("Speaker HTTP \(code) for \(url.absoluteString)")
                    continue
                }
                let xml = String(decoding: data, as: UTF8.self)
                let speaker = try DeviceDescriptionParser.parse(xml, fallbackHost: host, fallbackPort: port)
                guard NetworkPolicy.isAllowedHost(speaker.host) else { continue }
                devices[speaker.uuid] = speaker
                var saved = SpeakerCache.load(from: defaults)
                saved = SpeakerCache.upsert(
                    CachedSpeaker(
                        uuid: speaker.uuid,
                        name: speaker.name,
                        host: speaker.host,
                        port: speaker.port,
                        location: "http://\(speaker.host):\(speaker.port)/xml/device_description.xml",
                        lastSeen: Date()
                    ),
                    into: saved
                )
                SpeakerCache.save(saved, to: defaults)
                SonosLog.discovery("Speaker \(speaker.name) \(speaker.uuid) at \(speaker.host)")
            } catch {
                SonosLog.network("Could not read \(url.absoluteString): \(error.localizedDescription)")
            }
        }
    }

    private func rememberSeen(host: String, port: Int) {
        guard let speaker = devices.values.first(where: { $0.host == host && $0.port == port }) else { return }
        var saved = SpeakerCache.load(from: defaults)
        saved = SpeakerCache.upsert(
            CachedSpeaker(
                uuid: speaker.uuid,
                name: speaker.name,
                host: speaker.host,
                port: speaker.port,
                location: "http://\(speaker.host):\(speaker.port)/xml/device_description.xml",
                lastSeen: Date()
            ),
            into: saved
        )
        SpeakerCache.save(saved, to: defaults)
    }

    private func refreshTopology() async {
        let candidates = devices.values.filter { !$0.isBridge }
        for device in candidates {
            let client = SpeakerClient(host: device.host, port: device.port, uuid: device.uuid, soap: soap)
            if let groups = try? await client.zoneGroups(), !groups.isEmpty {
                self.groups = groups
                return
            }
        }
    }

    private func poll(includeVolumes: Bool) async {
        let coordinators = Set(groups.map(\.coordinatorUUID).filter { !$0.isEmpty })
        await withTaskGroup(of: Void.self) { group in
            for uuid in coordinators {
                group.addTask { await self.pollCoordinator(uuid) }
            }
        }
        if includeVolumes {
            let ids = Set(groups.flatMap { $0.visibleMembers.map(\.uuid) })
            for uuid in ids where !uuid.isEmpty {
                guard let client = try? tryClient(uuid) else { continue }
                if let level = try? await client.volume() {
                    updateVolume(uuid) { $0.level = level }
                }
                if let muted = try? await client.muted() {
                    updateVolume(uuid) { $0.muted = muted }
                }
            }
            for zone in groups {
                guard let client = try? coordinatorClient(zone.id) else { continue }
                if let level = try? await client.groupVolume() {
                    updateGroupVolume(zone.id) { $0.level = level }
                }
                if let muted = try? await client.groupMuted() {
                    updateGroupVolume(zone.id) { $0.muted = muted }
                }
            }
        }
        publish()
    }

    private func pollCoordinator(_ uuid: String) async {
        guard let client = try? tryClient(uuid) else { return }
        var store = playback[uuid] ?? PlaybackStore()
        if let position = try? await client.position() {
            store.apply(position: position)
        }
        if let info = try? await client.transportInfo(), let raw = info["CurrentTransportState"] {
            store.transport = TransportState(raw: raw)
        }
        if store.title.isEmpty, let media = try? await client.mediaInfo() {
            store.apply(media: media)
        }
        if let settings = try? await client.transportSettings(), let raw = settings["PlayMode"], let mode = PlayMode(rawValue: raw) {
            store.playMode = mode
        }
        playback[uuid] = store
        publish()
    }

    private func ensureSubscriptions() async {
        guard eventServer.port > 0 else { return }
        let players = devices.values.filter { !$0.isBridge }
        for device in players {
            await subscribe(device, .avTransport)
            await subscribe(device, .renderingControl)
        }
        if let first = players.first {
            await subscribe(first, .zoneGroupTopology)
        }
    }

    private func subscribe(_ device: DiscoveredSpeaker, _ service: SonosService) async {
        let key = "\(device.uuid)|\(service.rawValue)"
        if subscriptions[key] != nil { return }
        guard let local = CSocket.localAddress(reaching: device.host) else { return }
        let callback = "<http://\(local):\(eventServer.port)/event>"
        guard let result = try? await EventSubscription.subscribe(host: device.host, port: device.port, path: service.eventPath, callback: callback) else {
            return
        }
        let live = LiveSubscription(
            sid: result.sid,
            renewAfter: Date().addingTimeInterval(TimeInterval(max(60, result.seconds / 2))),
            host: device.host,
            port: device.port,
            path: service.eventPath,
            uuid: device.uuid,
            service: service
        )
        subscriptions[key] = live
        sidIndex[result.sid] = key
    }

    private func renewSubscriptions() async {
        for (key, subscription) in subscriptions where subscription.renewAfter < Date() {
            if let seconds = try? await EventSubscription.renew(host: subscription.host, port: subscription.port, path: subscription.path, sid: subscription.sid) {
                var updated = subscription
                updated.renewAfter = Date().addingTimeInterval(TimeInterval(max(60, seconds / 2)))
                subscriptions[key] = updated
            } else {
                subscriptions[key] = nil
                sidIndex[subscription.sid] = nil
            }
        }
    }

    private func handle(_ note: EventNotification) async {
        guard let key = sidIndex[note.sid], let subscription = subscriptions[key] else { return }
        guard let event = try? EventParser.parse(note.body) else { return }
        switch subscription.service {
        case .avTransport:
            var store = playback[subscription.uuid] ?? PlaybackStore()
            if let raw = event.values["TransportState"] { store.transport = TransportState(raw: raw) }
            if let raw = event.values["CurrentPlayMode"], let mode = PlayMode(rawValue: raw) { store.playMode = mode }
            if let raw = event.values["CurrentCrossfadeMode"] { store.crossfade = raw == "1" }
            if let raw = event.values["CurrentTrack"], let number = Int(raw) { store.trackNumber = number }
            if let raw = event.values["NumberOfTracks"], let number = Int(raw) { store.trackCount = number }
            if let raw = event.values["CurrentTrackDuration"], let seconds = SonosTime.parse(raw) { store.duration = seconds }
            if let raw = event.values["CurrentTrackURI"], !raw.isEmpty { store.trackURI = raw }
            if let raw = event.values["CurrentTrackMetaData"] { store.apply(metadata: raw) }
            if let raw = event.values["CurrentTransportActions"] {
                store.actions = Set(raw.split { $0 == "," || $0 == " " }.map { String($0) }.filter { !$0.isEmpty })
            }
            playback[subscription.uuid] = store
        case .renderingControl:
            if let level = event.channels["Volume"]?["Master"], let value = Int(level) {
                updateVolume(subscription.uuid) { $0.level = value }
            }
            if let muted = event.channels["Mute"]?["Master"] {
                let isMuted = muted == "1"
                updateVolume(subscription.uuid) { $0.muted = isMuted }
            }
        case .zoneGroupTopology:
            if let xml = event.properties["ZoneGroupState"], let parsed = try? ZoneGroupParser.parse(xml), !parsed.isEmpty {
                groups = parsed
            }
        default:
            break
        }
        publish()
    }

    private func sendSeek(groupID: String, seconds: Int) async {
        guard let client = try? coordinatorClient(groupID) else { return }
        try? await client.seek(seconds: seconds)
    }

    private func sendGroupVolume(groupID: String, volume: Int) async {
        guard let client = try? coordinatorClient(groupID) else { return }
        try? await client.setGroupVolume(volume)
    }

    private func sendMemberVolume(uuid: String, volume: Int) async {
        guard let client = try? tryClient(uuid) else { return }
        try? await client.setVolume(volume)
    }

    private func coordinatorUUID(_ groupID: String) -> String? {
        groups.first { $0.id == groupID }?.coordinatorUUID
            ?? (groupID.hasPrefix("solo-") ? String(groupID.dropFirst(5)) : nil)
    }

    private func coordinatorClient(_ groupID: String) throws -> SpeakerClient {
        guard let uuid = coordinatorUUID(groupID) else {
            throw SonosError(message: "That room is no longer available.")
        }
        return try tryClient(uuid)
    }

    private func tryClient(_ uuid: String) throws -> SpeakerClient {
        if let device = devices[uuid] {
            return SpeakerClient(host: device.host, port: device.port, uuid: uuid, soap: soap)
        }
        if let member = groups.flatMap(\.members).first(where: { $0.uuid == uuid }), !member.host.isEmpty {
            return SpeakerClient(host: member.host, port: member.port, uuid: uuid, soap: soap)
        }
        throw SonosError(message: "That speaker is not on the network.")
    }

    private func updatePlayback(_ uuid: String, _ body: (inout PlaybackStore) -> Void) {
        var store = playback[uuid] ?? PlaybackStore()
        body(&store)
        playback[uuid] = store
    }

    private func updateVolume(_ uuid: String, _ body: (inout VolumeStore) -> Void) {
        var store = volumes[uuid] ?? VolumeStore()
        body(&store)
        volumes[uuid] = store
    }

    private func updateGroupVolume(_ groupID: String, _ body: (inout VolumeStore) -> Void) {
        var store = groupVolumes[groupID] ?? VolumeStore()
        body(&store)
        groupVolumes[groupID] = store
    }

    private func optional<T>(_ work: () async throws -> T) async -> T? {
        try? await work()
    }

    private func publish() {
        latest = SnapshotBuilder.make(
            devices: devices,
            groups: groups,
            playback: playback,
            volumes: volumes,
            groupVolumes: groupVolumes,
            discovering: discovering,
            hasCompletedDiscovery: hasCompletedDiscovery
        )
        for continuation in continuations.values {
            continuation.yield(latest)
        }
    }

    private func addContinuation(_ id: UUID, _ continuation: AsyncStream<SystemSnapshot>.Continuation) {
        continuations[id] = continuation
        continuation.yield(latest)
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }
}

private struct LiveSubscription {
    var sid: String
    var renewAfter: Date
    var host: String
    var port: Int
    var path: String
    var uuid: String
    var service: SonosService
}
