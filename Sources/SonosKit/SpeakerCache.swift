import Foundation

public struct CachedSpeaker: Codable, Equatable, Sendable, Identifiable {
    public var id: String { uuid }
    public var uuid: String
    public var name: String
    public var host: String
    public var port: Int
    public var location: String
    public var lastSeen: Date

    public init(uuid: String, name: String, host: String, port: Int, location: String, lastSeen: Date) {
        self.uuid = uuid
        self.name = name
        self.host = host
        self.port = port
        self.location = location
        self.lastSeen = lastSeen
    }
}

public enum SpeakerCache {
    public static let defaultsKey = "sonos.cachedSpeakers"
    /// Drop a saved speaker that has not answered for this long.
    public static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    public static func load(from defaults: UserDefaults, now: Date = Date(), maxAge: TimeInterval = maxAge) -> [CachedSpeaker] {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([CachedSpeaker].self, from: data) else {
            return []
        }
        return pruned(decoded, now: now, maxAge: maxAge)
    }

    public static func save(_ speakers: [CachedSpeaker], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(speakers) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    public static func upsert(_ speaker: CachedSpeaker, into speakers: [CachedSpeaker]) -> [CachedSpeaker] {
        var next = speakers.filter { $0.uuid != speaker.uuid }
        next.append(speaker)
        return next.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func pruned(_ speakers: [CachedSpeaker], now: Date, maxAge: TimeInterval = maxAge) -> [CachedSpeaker] {
        speakers.filter { now.timeIntervalSince($0.lastSeen) <= maxAge }
    }

    public static func forget(in defaults: UserDefaults) {
        defaults.removeObject(forKey: defaultsKey)
    }

    /// Accepts `192.168.1.62`, `192.168.1.62:1400`, or a full device-description URL.
    public static func location(from userInput: String) -> String? {
        let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), let host = url.host, NetworkPolicy.isAllowedHost(host) {
            let port = url.port ?? 1400
            return "http://\(host):\(port)/xml/device_description.xml"
        }
        let pieces = trimmed.split(separator: ":").map(String.init)
        let host = pieces.first ?? trimmed
        guard NetworkPolicy.isAllowedHost(host) else { return nil }
        let port = pieces.count > 1 ? Int(pieces[1]) ?? 1400 : 1400
        return "http://\(host):\(port)/xml/device_description.xml"
    }
}

public enum BonjourTXT {
    /// DNS-SD TXT record: a sequence of length-prefixed `key=value` strings.
    public static func parse(_ data: Data) -> [String: String] {
        var fields: [String: String] = [:]
        var index = 0
        let bytes = [UInt8](data)
        while index < bytes.count {
            let length = Int(bytes[index])
            index += 1
            guard length > 0, index + length <= bytes.count else { break }
            let text = String(decoding: bytes[index..<(index + length)], as: UTF8.self)
            index += length
            if let equals = text.firstIndex(of: "=") {
                let key = String(text[..<equals])
                let value = String(text[text.index(after: equals)...])
                fields[key] = value
            } else if !text.isEmpty {
                fields[text] = ""
            }
        }
        return fields
    }

    public static func location(in fields: [String: String]) -> String? {
        let value = fields["location"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard value.hasPrefix("http://") || value.hasPrefix("https://") else { return nil }
        return value
    }
}
