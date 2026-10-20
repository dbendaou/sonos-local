import Foundation

public enum EQType: String, Sendable, CaseIterable {
    case dialogLevel = "DialogLevel"
    case nightMode = "NightMode"
    case subGain = "SubGain"
    case surroundEnable = "SurroundEnable"
    case surroundLevel = "SurroundLevel"
    case musicSurroundLevel = "MusicSurroundLevel"
    case surroundMode = "SurroundMode"
    case heightChannelLevel = "HeightChannelLevel"
    case audioDelay = "AudioDelay"
}

public struct AlarmDraft: Sendable, Equatable {
    public var startTime: String
    public var duration: String
    public var recurrence: String
    public var enabled: Bool
    public var roomUUID: String
    public var programURI: String
    public var programMetaData: String
    public var playMode: String
    public var volume: Int
    public var includeLinkedZones: Bool

    public init(
        startTime: String,
        duration: String = "02:00:00",
        recurrence: String = "DAILY",
        enabled: Bool = true,
        roomUUID: String,
        programURI: String = "x-rincon-buzzer:0",
        programMetaData: String = "",
        playMode: String = "NORMAL",
        volume: Int = 20,
        includeLinkedZones: Bool = false
    ) {
        self.startTime = startTime
        self.duration = duration
        self.recurrence = recurrence
        self.enabled = enabled
        self.roomUUID = roomUUID
        self.programURI = programURI
        self.programMetaData = programMetaData
        self.playMode = playMode
        self.volume = volume
        self.includeLinkedZones = includeLinkedZones
    }
}

public struct SpeakerClient: Sendable {
    public var host: String
    public var port: Int
    public var uuid: String
    private var soap: SOAPClient

    public init(host: String, port: Int = 1400, uuid: String, soap: SOAPClient = SOAPClient()) {
        self.host = host
        self.port = port
        self.uuid = uuid
        self.soap = soap
    }

    public func call(_ service: SonosService, _ action: String, _ arguments: [(String, String)] = []) async throws -> [String: String] {
        guard let url = URL(string: "http://\(host):\(port)\(service.controlPath)") else {
            throw SonosError(message: "Bad speaker address.")
        }
        return try await soap.call(url: url, service: service.rawValue, action: action, arguments: arguments)
    }

    private func instance(_ extra: [(String, String)] = []) -> [(String, String)] {
        [("InstanceID", "0")] + extra
    }

    private func flag(_ value: Bool) -> String { value ? "1" : "0" }

    // MARK: Transport

    public func play() async throws {
        _ = try await call(.avTransport, "Play", instance([("Speed", "1")]))
    }

    public func pause() async throws {
        _ = try await call(.avTransport, "Pause", instance())
    }

    public func stop() async throws {
        _ = try await call(.avTransport, "Stop", instance())
    }

    public func next() async throws {
        _ = try await call(.avTransport, "Next", instance())
    }

    public func previous() async throws {
        _ = try await call(.avTransport, "Previous", instance())
    }

    public func seek(seconds: Int) async throws {
        _ = try await call(.avTransport, "Seek", instance([
            ("Unit", "REL_TIME"),
            ("Target", SonosTime.clock(seconds)),
        ]))
    }

    public func seek(track: Int) async throws {
        _ = try await call(.avTransport, "Seek", instance([
            ("Unit", "TRACK_NR"),
            ("Target", String(max(1, track))),
        ]))
    }

    public func setAVTransportURI(_ uri: String, metadata: String) async throws {
        _ = try await call(.avTransport, "SetAVTransportURI", instance([
            ("CurrentURI", uri),
            ("CurrentURIMetaData", metadata),
        ]))
    }

    public func position() async throws -> [String: String] {
        try await call(.avTransport, "GetPositionInfo", instance())
    }

    public func transportInfo() async throws -> [String: String] {
        try await call(.avTransport, "GetTransportInfo", instance())
    }

    public func mediaInfo() async throws -> [String: String] {
        try await call(.avTransport, "GetMediaInfo", instance())
    }

    public func transportSettings() async throws -> [String: String] {
        try await call(.avTransport, "GetTransportSettings", instance())
    }

    public func setPlayMode(_ mode: PlayMode) async throws {
        _ = try await call(.avTransport, "SetPlayMode", instance([("NewPlayMode", mode.rawValue)]))
    }

    public func crossfade() async throws -> Bool {
        let values = try await call(.avTransport, "GetCrossfadeMode", instance())
        return values["CrossfadeMode"] == "1"
    }

    public func setCrossfade(_ enabled: Bool) async throws {
        _ = try await call(.avTransport, "SetCrossfadeMode", instance([("CrossfadeMode", flag(enabled))]))
    }

    public func sleepRemaining() async throws -> String {
        let values = try await call(.avTransport, "GetRemainingSleepTimerDuration", instance())
        return values["RemainingSleepTimerDuration"] ?? ""
    }

    public func setSleep(seconds: Int?) async throws {
        let value = seconds.map { SonosTime.clock($0) } ?? ""
        _ = try await call(.avTransport, "ConfigureSleepTimer", instance([("NewSleepTimerDuration", value)]))
    }

    public func becomeStandalone() async throws {
        _ = try await call(.avTransport, "BecomeCoordinatorOfStandaloneGroup", instance())
    }

    public func delegateCoordination(to uuid: String, rejoin: Bool) async throws {
        _ = try await call(.avTransport, "DelegateGroupCoordinationTo", instance([
            ("NewCoordinator", uuid),
            ("RejoinGroup", flag(rejoin)),
        ]))
    }

    public func addToQueue(uri: String, metadata: String, asNext: Bool) async throws {
        _ = try await call(.avTransport, "AddURIToQueue", instance([
            ("EnqueuedURI", uri),
            ("EnqueuedURIMetaData", metadata),
            ("DesiredFirstTrackNumberEnqueued", "0"),
            ("EnqueueAsNext", flag(asNext)),
        ]))
    }

    public func removeFromQueue(objectID: String) async throws {
        _ = try await call(.avTransport, "RemoveTrackFromQueue", instance([
            ("ObjectID", objectID),
            ("UpdateID", "0"),
        ]))
    }

    public func clearQueue() async throws {
        do {
            _ = try await call(.avTransport, "RemoveAllTracksFromQueue", instance())
        } catch let error as SonosError where error.code == 804 {
            return
        }
    }

    public func reorderQueue(startingIndex: Int, insertBefore: Int) async throws {
        _ = try await call(.avTransport, "ReorderTracksInQueue", instance([
            ("StartingIndex", String(startingIndex)),
            ("NumberOfTracks", "1"),
            ("InsertBefore", String(insertBefore)),
            ("UpdateID", "0"),
        ]))
    }

    // MARK: Volume

    public func volume() async throws -> Int {
        let values = try await call(.renderingControl, "GetVolume", instance([("Channel", "Master")]))
        return clamp(Int(values["CurrentVolume"] ?? "") ?? 0, 0, 100)
    }

    public func setVolume(_ value: Int) async throws {
        _ = try await call(.renderingControl, "SetVolume", instance([
            ("Channel", "Master"),
            ("DesiredVolume", String(clamp(value, 0, 100))),
        ]))
    }

    public func muted() async throws -> Bool {
        let values = try await call(.renderingControl, "GetMute", instance([("Channel", "Master")]))
        return values["CurrentMute"] == "1"
    }

    public func setMuted(_ muted: Bool) async throws {
        _ = try await call(.renderingControl, "SetMute", instance([
            ("Channel", "Master"),
            ("DesiredMute", flag(muted)),
        ]))
    }

    public func groupVolume() async throws -> Int {
        let values = try await call(.groupRenderingControl, "GetGroupVolume", instance())
        return clamp(Int(values["CurrentVolume"] ?? "") ?? 0, 0, 100)
    }

    public func setGroupVolume(_ value: Int) async throws {
        _ = try await call(.groupRenderingControl, "SetGroupVolume", instance([
            ("DesiredVolume", String(clamp(value, 0, 100))),
        ]))
    }

    public func groupMuted() async throws -> Bool {
        let values = try await call(.groupRenderingControl, "GetGroupMute", instance())
        return values["CurrentMute"] == "1"
    }

    public func setGroupMuted(_ muted: Bool) async throws {
        _ = try await call(.groupRenderingControl, "SetGroupMute", instance([
            ("DesiredMute", flag(muted)),
        ]))
    }

    // MARK: Tone

    public func bass() async throws -> Int {
        let values = try await call(.renderingControl, "GetBass", instance())
        return Int(values["CurrentBass"] ?? "") ?? 0
    }

    public func setBass(_ value: Int) async throws {
        _ = try await call(.renderingControl, "SetBass", instance([("DesiredBass", String(clamp(value, -10, 10)))]))
    }

    public func treble() async throws -> Int {
        let values = try await call(.renderingControl, "GetTreble", instance())
        return Int(values["CurrentTreble"] ?? "") ?? 0
    }

    public func setTreble(_ value: Int) async throws {
        _ = try await call(.renderingControl, "SetTreble", instance([("DesiredTreble", String(clamp(value, -10, 10)))]))
    }

    public func loudness() async throws -> Bool {
        let values = try await call(.renderingControl, "GetLoudness", instance([("Channel", "Master")]))
        return values["CurrentLoudness"] == "1"
    }

    public func setLoudness(_ enabled: Bool) async throws {
        _ = try await call(.renderingControl, "SetLoudness", instance([
            ("Channel", "Master"),
            ("DesiredLoudness", flag(enabled)),
        ]))
    }

    public func eq(_ type: EQType) async throws -> Int {
        let values = try await call(.renderingControl, "GetEQ", instance([("EQType", type.rawValue)]))
        return Int(values["CurrentValue"] ?? "") ?? 0
    }

    public func setEQ(_ type: EQType, value: Int) async throws {
        _ = try await call(.renderingControl, "SetEQ", instance([
            ("EQType", type.rawValue),
            ("DesiredValue", String(value)),
        ]))
    }

    public func trueplay() async throws -> (available: Bool, enabled: Bool) {
        let values = try await call(.renderingControl, "GetRoomCalibrationStatus", instance())
        let available = (values["RoomCalibrationAvailable"] ?? "0") == "1"
        let enabled = (values["RoomCalibrationEnabled"] ?? "0") == "1"
        return (available, enabled)
    }

    public func setTrueplay(_ enabled: Bool) async throws {
        _ = try await call(.renderingControl, "SetRoomCalibrationStatus", instance([
            ("RoomCalibrationEnabled", flag(enabled)),
        ]))
    }

    public func outputFixed() async throws -> Bool {
        let values = try await call(.renderingControl, "GetOutputFixed", instance())
        return values["CurrentFixed"] == "1"
    }

    public func setOutputFixed(_ fixed: Bool) async throws {
        _ = try await call(.renderingControl, "SetOutputFixed", instance([
            ("DesiredFixed", flag(fixed)),
        ]))
    }

    // MARK: Browse

    public func browse(objectID: String, start: Int = 0, count: Int = 100) async throws -> [MediaItem] {
        var items: [MediaItem] = []
        var index = start
        var total = Int.max
        while index < total && items.count < 300 {
            let values = try await call(.contentDirectory, "Browse", [
                ("ObjectID", objectID),
                ("BrowseFlag", "BrowseDirectChildren"),
                ("Filter", "*"),
                ("StartingIndex", String(index)),
                ("RequestedCount", String(count)),
                ("SortCriteria", ""),
            ])
            let page = try DIDLParser.items(in: values["Result"] ?? "")
            items.append(contentsOf: page)
            let returned = Int(values["NumberReturned"] ?? "") ?? page.count
            total = Int(values["TotalMatches"] ?? "") ?? items.count
            if returned == 0 || page.isEmpty { break }
            index += returned
        }
        return items
    }

    public func zoneGroups() async throws -> [ZoneGroup] {
        let values = try await call(.zoneGroupTopology, "GetZoneGroupState")
        return try ZoneGroupParser.parse(values["ZoneGroupState"] ?? "")
    }

    // MARK: Device

    public func zoneAttributes() async throws -> [String: String] {
        try await call(.deviceProperties, "GetZoneAttributes")
    }

    public func setZoneAttributes(name: String, icon: String, configuration: String, targetRoom: String) async throws {
        _ = try await call(.deviceProperties, "SetZoneAttributes", [
            ("DesiredZoneName", name),
            ("DesiredIcon", icon),
            ("DesiredConfiguration", configuration),
            ("DesiredTargetRoomName", targetRoom),
        ])
    }

    public func zoneInfo() async throws -> [String: String] {
        try await call(.deviceProperties, "GetZoneInfo")
    }

    public func householdID() async throws -> String {
        let values = try await call(.deviceProperties, "GetHouseholdID")
        return values["CurrentHouseholdID"] ?? ""
    }

    public func ledOn() async throws -> Bool {
        let values = try await call(.deviceProperties, "GetLEDState")
        return (values["CurrentLEDState"] ?? "").caseInsensitiveCompare("On") == .orderedSame
    }

    public func setLED(_ on: Bool) async throws {
        _ = try await call(.deviceProperties, "SetLEDState", [("DesiredLEDState", on ? "On" : "Off")])
    }

    public func buttonsLocked() async throws -> Bool {
        let values = try await call(.deviceProperties, "GetButtonLockState")
        return (values["CurrentButtonLockState"] ?? "").caseInsensitiveCompare("On") == .orderedSame
    }

    public func setButtonsLocked(_ locked: Bool) async throws {
        _ = try await call(.deviceProperties, "SetButtonLockState", [("DesiredButtonLockState", locked ? "On" : "Off")])
    }

    // MARK: Alarms

    public func alarms() async throws -> [Alarm] {
        let values = try await call(.alarmClock, "ListAlarms")
        return try AlarmParser.parse(values["CurrentAlarmList"] ?? "")
    }

    public func createAlarm(_ draft: AlarmDraft) async throws -> Int {
        let values = try await call(.alarmClock, "CreateAlarm", alarmArguments(draft, id: nil))
        return Int(values["AssignedID"] ?? "") ?? 0
    }

    public func updateAlarm(_ alarm: Alarm) async throws {
        _ = try await call(.alarmClock, "UpdateAlarm", alarmArguments(alarm))
    }

    public func destroyAlarm(id: Int) async throws {
        _ = try await call(.alarmClock, "DestroyAlarm", [("ID", String(id))])
    }

    public func clock() async throws -> (local: String, zone: String) {
        let values = try await call(.alarmClock, "GetTimeNow")
        return (values["CurrentLocalTime"] ?? "", values["CurrentTimeZone"] ?? "")
    }

    private func alarmArguments(_ draft: AlarmDraft, id: Int?) -> [(String, String)] {
        var args: [(String, String)] = []
        if let id { args.append(("ID", String(id))) }
        args.append(contentsOf: [
            ("StartLocalTime", draft.startTime),
            ("Duration", draft.duration),
            ("Recurrence", draft.recurrence),
            ("Enabled", flag(draft.enabled)),
            ("RoomUUID", draft.roomUUID),
            ("ProgramURI", draft.programURI),
            ("ProgramMetaData", draft.programMetaData),
            ("PlayMode", draft.playMode),
            ("Volume", String(clamp(draft.volume, 0, 100))),
            ("IncludeLinkedZones", flag(draft.includeLinkedZones)),
        ])
        return args
    }

    private func alarmArguments(_ alarm: Alarm) -> [(String, String)] {
        [
            ("ID", String(alarm.id)),
            ("StartLocalTime", alarm.startTime),
            ("Duration", alarm.duration),
            ("Recurrence", alarm.recurrence),
            ("Enabled", flag(alarm.enabled)),
            ("RoomUUID", alarm.roomUUID),
            ("ProgramURI", alarm.programURI),
            ("ProgramMetaData", alarm.programMetaData),
            ("PlayMode", alarm.playMode),
            ("Volume", String(clamp(alarm.volume, 0, 100))),
            ("IncludeLinkedZones", flag(alarm.includeLinkedZones)),
        ]
    }

    private func clamp(_ value: Int, _ lower: Int, _ upper: Int) -> Int {
        min(max(value, lower), upper)
    }
}
