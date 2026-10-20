import Foundation

public struct DiscoveredSpeaker: Equatable, Sendable, Identifiable {
    public var id: String { uuid }
    public var uuid: String
    public var name: String
    public var modelName: String
    public var modelNumber: String
    public var softwareVersion: String
    public var serialNumber: String
    public var host: String
    public var port: Int
    public var isBridge: Bool
    public var isSub: Bool

    public init(
        uuid: String,
        name: String,
        modelName: String,
        modelNumber: String,
        softwareVersion: String,
        serialNumber: String,
        host: String,
        port: Int
    ) {
        self.uuid = uuid
        self.name = name
        self.modelName = modelName
        self.modelNumber = modelNumber
        self.softwareVersion = softwareVersion
        self.serialNumber = serialNumber
        self.host = host
        self.port = port
        let model = (modelName + " " + modelNumber).lowercased()
        self.isBridge = model.contains("bridge") || model.contains("boost")
        self.isSub = model.contains("sub")
    }
}

public enum DeviceDescriptionParser {
    public static func parse(
        _ xml: String,
        fallbackHost: String,
        fallbackPort: Int,
        advertisedName: String = ""
    ) throws -> DiscoveredSpeaker {
        let root = try XML.parse(xml)
        let devices = root.descendants(named: "device")
        let device = devices.first { ($0.child("deviceType")?.trimmedText ?? "").contains("ZonePlayer") }
            ?? root.child("device")
            ?? devices.first
        guard let device else {
            throw SonosError(message: "Device description did not include a player.")
        }
        let udn = device.child("UDN")?.trimmedText ?? ""
        let uuid = udn.replacingOccurrences(of: "uuid:", with: "")
        guard uuid.contains("RINCON_") || !uuid.isEmpty else {
            throw SonosError(message: "Device description did not include a UDN.")
        }
        let friendly = device.child("friendlyName")?.trimmedText ?? ""
        let room = device.child("roomName")?.trimmedText ?? ""
        let modelName = device.child("modelName")?.trimmedText ?? ""
        let name = RoomName.choose(
            zoneName: room,
            deviceName: friendly,
            modelName: modelName,
            advertisedName: advertisedName
        )
        return DiscoveredSpeaker(
            uuid: uuid,
            name: name,
            modelName: modelName,
            modelNumber: device.child("modelNumber")?.trimmedText ?? "",
            softwareVersion: device.child("softwareVersion")?.trimmedText ?? "",
            serialNumber: device.child("serialNum")?.trimmedText ?? "",
            host: fallbackHost,
            port: fallbackPort
        )
    }
}

public struct ZoneMember: Equatable, Sendable, Identifiable {
    public var id: String { uuid }
    public var uuid: String
    public var name: String
    public var host: String
    public var port: Int
    public var icon: String
    public var softwareVersion: String
    public var isInvisible: Bool
    public var isBridge: Bool
}

public struct ZoneGroup: Equatable, Sendable, Identifiable {
    public var id: String
    public var coordinatorUUID: String
    public var members: [ZoneMember]

    public var visibleMembers: [ZoneMember] {
        members.filter { !$0.isInvisible && !$0.isBridge }
    }

    public var displayName: String {
        let names = visibleMembers.map(\.name).filter { !$0.isEmpty }
        guard let first = names.first else { return "Room" }
        if names.count == 1 { return first }
        if names.count == 2 { return "\(first) + \(names[1])" }
        return "\(first) + \(names.count - 1)"
    }
}

public enum ZoneGroupParser {
    public static func parse(_ xml: String) throws -> [ZoneGroup] {
        let trimmed = xml.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        let root = try XML.parse(trimmed)
        let nodes = root.name == "ZoneGroup" ? [root] : root.descendants(named: "ZoneGroup")
        return nodes.map { group in
            let members = group.children(named: "ZoneGroupMember").map { member -> ZoneMember in
                let location = member.attribute("Location") ?? ""
                let endpoint = endpoint(from: location)
                return ZoneMember(
                    uuid: member.attribute("UUID") ?? "",
                    name: member.attribute("ZoneName") ?? "Room",
                    host: endpoint?.host ?? "",
                    port: endpoint?.port ?? 1400,
                    icon: member.attribute("Icon") ?? "",
                    softwareVersion: member.attribute("SoftwareVersion") ?? "",
                    isInvisible: (member.attribute("Invisible") ?? "0") == "1",
                    isBridge: (member.attribute("IsZoneBridge") ?? "0") == "1"
                )
            }
            return ZoneGroup(
                id: group.attribute("ID") ?? (group.attribute("Coordinator") ?? UUID().uuidString),
                coordinatorUUID: group.attribute("Coordinator") ?? members.first?.uuid ?? "",
                members: members
            )
        }
    }

    static func endpoint(from location: String) -> (host: String, port: Int)? {
        guard let url = URL(string: location), let host = url.host else { return nil }
        return (host, url.port ?? 1400)
    }
}

public struct MediaItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    public var uri: String
    public var artURI: String?
    public var itemClass: String
    public var metadata: String
    public var duration: Int

    public var subtitle: String {
        if !artist.isEmpty && !album.isEmpty { return "\(artist) · \(album)" }
        if !artist.isEmpty { return artist }
        if !album.isEmpty { return album }
        return ""
    }
}

public struct QueueItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var position: Int
    public var title: String
    public var artist: String
    public var album: String
    public var uri: String
    public var artURI: String?
    public var duration: Int
}

public enum DIDLParser {
    public static func items(in xml: String) throws -> [MediaItem] {
        let trimmed = xml.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        let root = try XML.parse(trimmed)
        let nodes = root.descendants(named: "item") + root.descendants(named: "container")
        return nodes.enumerated().map { offset, node in
            let res = node.child("res")
            let title = node.child("title")?.trimmedText ?? "Untitled"
            let artist = node.child("creator")?.trimmedText ?? ""
            let album = node.child("album")?.trimmedText ?? ""
            let art = node.children(named: "albumArtURI").compactMap { child -> String? in
                let text = child.trimmedText
                return text.isEmpty ? nil : text
            }.first
            let id = node.attribute("id") ?? "item-\(offset)"
            return MediaItem(
                id: id,
                title: title,
                artist: artist,
                album: album,
                uri: res?.trimmedText ?? "",
                artURI: art,
                itemClass: node.child("class")?.trimmedText ?? "",
                metadata: DIDL.envelope(node.outerXML),
                duration: SonosTime.parse(res?.attribute("duration") ?? "") ?? 0
            )
        }
    }

    public static func track(in xml: String) -> (title: String, artist: String, album: String, artURI: String?, duration: Int)? {
        guard let item = try? items(in: xml).first else { return nil }
        if item.title.isEmpty && item.uri.isEmpty { return nil }
        return (item.title, item.artist, item.album, item.artURI, item.duration)
    }
}

public struct SonosEvent: Equatable, Sendable {
    public var properties: [String: String]
    /// Instance 0 values that are not channel-specific.
    public var values: [String: String]
    /// Instance 0 values keyed by property then channel. Example: Volume / Master.
    public var channels: [String: [String: String]]
}

public enum EventParser {
    public static func parse(_ body: String) throws -> SonosEvent {
        let root = try XML.parse(body)
        var properties: [String: String] = [:]
        let propertyNodes = root.descendants(named: "property")
        let nodes = propertyNodes.isEmpty ? [root] : propertyNodes
        for property in nodes {
            for child in property.children {
                properties[child.name] = child.trimmedText
            }
        }
        var values: [String: String] = [:]
        var channels: [String: [String: String]] = [:]
        if let lastChange = properties["LastChange"], !lastChange.isEmpty, let event = try? XML.parse(lastChange) {
            let instances = event.descendants(named: "InstanceID")
            let instance = instances.first { ($0.attribute("val") ?? "0") == "0" } ?? instances.first
            if let instance {
                for child in instance.children {
                    let val = child.attribute("val") ?? child.trimmedText
                    if let channel = child.attribute("channel") {
                        var bucket = channels[child.name] ?? [:]
                        bucket[channel] = val
                        channels[child.name] = bucket
                    } else {
                        values[child.name] = val
                    }
                }
            }
        }
        return SonosEvent(properties: properties, values: values, channels: channels)
    }
}

public struct Alarm: Equatable, Sendable, Identifiable {
    public var id: Int
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

    public var recurrenceTitle: String {
        switch recurrence {
        case "ONCE": return "Once"
        case "WEEKDAYS": return "Weekdays"
        case "WEEKENDS": return "Weekends"
        case "DAILY": return "Daily"
        default: return recurrence.replacingOccurrences(of: "_", with: " ")
        }
    }
}

public enum AlarmParser {
    public static func parse(_ xml: String) throws -> [Alarm] {
        let trimmed = xml.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        let root = try XML.parse(trimmed)
        return root.descendants(named: "Alarm").compactMap { node in
            guard let id = Int(node.attribute("ID") ?? "") else { return nil }
            return Alarm(
                id: id,
                startTime: node.attribute("StartTime") ?? "07:00:00",
                duration: node.attribute("Duration") ?? "02:00:00",
                recurrence: node.attribute("Recurrence") ?? "DAILY",
                enabled: (node.attribute("Enabled") ?? "0") == "1",
                roomUUID: node.attribute("RoomUUID") ?? "",
                programURI: node.attribute("ProgramURI") ?? "x-rincon-buzzer:0",
                programMetaData: node.attribute("ProgramMetaData") ?? "",
                playMode: node.attribute("PlayMode") ?? "NORMAL",
                volume: Int(node.attribute("Volume") ?? "") ?? 20,
                includeLinkedZones: (node.attribute("IncludeLinkedZones") ?? "0") == "1"
            )
        }
    }
}

public struct SSDPResponse: Equatable, Sendable {
    public var location: String
    public var usn: String
    public var searchTarget: String
    public var server: String
    public var uuid: String?

    public static func parse(_ message: String) -> SSDPResponse? {
        let lines = message.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = lines.first else { return nil }
        let head = first.uppercased()
        guard head.contains("HTTP/1.1") || head.contains("NOTIFY") else { return nil }
        if head.hasPrefix("M-SEARCH") { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        guard let location = headers["location"], !location.isEmpty else { return nil }
        let usn = headers["usn"] ?? ""
        let server = headers["server"] ?? ""
        let target = headers["st"] ?? headers["nt"] ?? ""
        let interesting = usn.contains("ZonePlayer") || target.contains("ZonePlayer") || server.localizedCaseInsensitiveContains("Sonos") || usn.contains("RINCON_")
        guard interesting else { return nil }
        return SSDPResponse(
            location: location,
            usn: usn,
            searchTarget: target,
            server: server,
            uuid: uuid(from: usn)
        )
    }

    static func uuid(from usn: String) -> String? {
        guard let range = usn.range(of: "uuid:") else { return nil }
        let rest = usn[range.upperBound...]
        let id = rest.split(separator: ":").first.map(String.init) ?? ""
        return id.isEmpty ? nil : id
    }
}
