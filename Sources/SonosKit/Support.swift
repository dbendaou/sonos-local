import Foundation

public struct SonosError: Error, Equatable, Sendable, CustomStringConvertible {
    public var code: Int?
    public var message: String

    public init(code: Int? = nil, message: String) {
        self.code = code
        self.message = message
    }

    public var description: String { message }
}

public enum SonosTime {
    /// Parses Sonos durations such as `0:03:22` or `00:03:22`.
    public static func parse(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "NOT_IMPLEMENTED" { return nil }
        let parts = trimmed.split(separator: ":").map { Int($0) }
        guard parts.count >= 2, parts.allSatisfy({ $0 != nil }) else { return nil }
        let numbers = parts.compactMap { $0 }
        if numbers.count == 2 {
            return numbers[0] * 60 + numbers[1]
        }
        let tail = numbers.suffix(3)
        let values = Array(tail)
        guard values.count == 3 else { return nil }
        return values[0] * 3600 + values[1] * 60 + values[2]
    }

    /// Protocol form `H:MM:SS`, which is what Seek and alarms expect.
    public static func clock(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let secs = safe % 60
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }

    /// Compact form for the scrubber: `3:22` or `1:03:22`.
    public static func display(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let secs = safe % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

public enum RepeatMode: String, Sendable, Equatable, CaseIterable {
    case off
    case all
    case one

    public var title: String {
        switch self {
        case .off: return "Off"
        case .all: return "All"
        case .one: return "One"
        }
    }
}

public enum PlayMode: String, Sendable, Equatable, CaseIterable {
    case normal = "NORMAL"
    case repeatAll = "REPEAT_ALL"
    case repeatOne = "REPEAT_ONE"
    case shuffle = "SHUFFLE_NOREPEAT"
    case shuffleRepeat = "SHUFFLE"
    case shuffleRepeatOne = "SHUFFLE_REPEAT_ONE"

    public var shuffle: Bool {
        switch self {
        case .shuffle, .shuffleRepeat, .shuffleRepeatOne: return true
        default: return false
        }
    }

    public var repeatMode: RepeatMode {
        switch self {
        case .repeatAll, .shuffleRepeat: return .all
        case .repeatOne, .shuffleRepeatOne: return .one
        default: return .off
        }
    }

    public init(shuffle: Bool, repeatMode: RepeatMode) {
        switch (shuffle, repeatMode) {
        case (false, .off): self = .normal
        case (false, .all): self = .repeatAll
        case (false, .one): self = .repeatOne
        case (true, .off): self = .shuffle
        case (true, .all): self = .shuffleRepeat
        case (true, .one): self = .shuffleRepeatOne
        }
    }

    public func togglingShuffle() -> PlayMode {
        PlayMode(shuffle: !shuffle, repeatMode: repeatMode)
    }

    public func cyclingRepeat() -> PlayMode {
        let next: RepeatMode
        switch repeatMode {
        case .off: next = .all
        case .all: next = .one
        case .one: next = .off
        }
        return PlayMode(shuffle: shuffle, repeatMode: next)
    }
}

public enum NetworkPolicy {
    public static func isAllowedHost(_ host: String) -> Bool {
        let value = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.isEmpty { return false }
        if value == "localhost" || value.hasSuffix(".local") { return true }
        let parts = value.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        let a = parts[0]
        let b = parts[1]
        if a == 10 || a == 127 { return true }
        if a == 192 && b == 168 { return true }
        if a == 172 && (16...31).contains(b) { return true }
        if a == 169 && b == 254 { return true }
        return false
    }

    public static func isAllowedURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        guard let host = url.host else { return false }
        return isAllowedHost(host)
    }
}

public enum ArtworkURL {
    /// Speaker-local art when possible. Relative `/getaa` paths are prefixed with
    /// `http://host:port`, and XML `&amp;` sequences are decoded first.
    /// An https image from a streaming service is proxied through the speaker's
    /// `/getaa` endpoint. `httpsFallback` is that same https URL, for when the
    /// proxy has no copy.
    public static func resolve(artURI: String?, trackURI: String?, host: String, port: Int) -> URL? {
        guard NetworkPolicy.isAllowedHost(host), (1...65535).contains(port) else { return nil }
        let art = xmlUnescape(artURI ?? "")
        let track = xmlUnescape(trackURI ?? "")
        let base = "http://\(host):\(port)"
        if let local = speakerURL(art, base: base) {
            return local
        }
        let source = track.isEmpty ? art : track
        return getaa(source, base: base)
    }

    /// Direct https artwork. Nil when the art is already on the speaker.
    public static func httpsFallback(artURI: String?, host: String, port: Int) -> URL? {
        guard NetworkPolicy.isAllowedHost(host) else { return nil }
        let art = xmlUnescape(artURI ?? "")
        guard let url = URL(string: art), url.scheme?.lowercased() == "https", let artHost = url.host, !artHost.isEmpty else {
            return nil
        }
        if NetworkPolicy.isAllowedHost(artHost) { return nil }
        return url
    }

    static func xmlUnescape(_ raw: String) -> String {
        var current = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for _ in 0..<4 {
            let next = current
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&apos;", with: "'")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
            if next == current { break }
            current = next
        }
        return current
    }

    private static func speakerURL(_ art: String, base: String) -> URL? {
        guard !art.isEmpty else { return nil }
        if art.hasPrefix("http://") || art.hasPrefix("https://") {
            guard let url = URL(string: art), let artHost = url.host, NetworkPolicy.isAllowedHost(artHost) else { return nil }
            return url
        }
        if art.hasPrefix("//") {
            return speakerURL("http:" + art, base: base)
        }
        let path = art.hasPrefix("/") ? art : "/" + art
        if let url = URL(string: base + path) { return url }
        var allowed = CharacterSet.urlPathAllowed
        allowed.formUnion(.urlQueryAllowed)
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: base + encoded)
    }

    private static func getaa(_ source: String, base: String) -> URL? {
        guard !source.isEmpty else { return nil }
        let encoded = source.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? source
        return URL(string: "\(base)/getaa?s=1&u=\(encoded)")
    }
}

public enum PlaybackKind: String, Sendable, Equatable {
    case music
    case tv
    case lineIn
    case radio
    case stream
}

public enum SourceLabel {
    public static func kind(for uri: String) -> PlaybackKind {
        let value = uri.lowercased()
        if value.hasPrefix("x-sonos-htastream") { return .tv }
        if value.hasPrefix("x-rincon-stream") { return .lineIn }
        if value.hasPrefix("x-rincon-mp3radio")
            || value.hasPrefix("x-sonosapi-stream")
            || value.hasPrefix("x-sonosapi-radio")
            || value.hasPrefix("x-sonosapi-hls")
            || value.contains("tunein")
            || value.contains("radiotime") {
            return .radio
        }
        if value.hasPrefix("http://") || value.hasPrefix("https://") || value.hasPrefix("x-rincon-http") {
            return .stream
        }
        return .music
    }

    public static func isLive(kind: PlaybackKind, duration: Int) -> Bool {
        switch kind {
        case .tv, .lineIn:
            return true
        case .radio, .stream:
            return duration <= 0
        case .music:
            return false
        }
    }

    public static func allowsSkip(_ kind: PlaybackKind) -> Bool {
        kind == .music
    }

    public static func allowsModes(_ kind: PlaybackKind) -> Bool {
        kind == .music
    }

    public static func symbol(for kind: PlaybackKind) -> String {
        switch kind {
        case .tv: return "tv"
        case .lineIn: return "cable.connector"
        case .radio: return "antenna.radiowaves.left.and.right"
        case .stream: return "dot.radiowaves.left.and.right"
        case .music: return "music.note"
        }
    }

    /// Speaker ids and transport URIs are not titles.
    public static func isHardwareIdentifier(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let upper = trimmed.uppercased()
        if upper.hasPrefix("RINCON_") { return true }
        if upper.range(of: #"RINCON_[0-9A-F]{6,}"#, options: .regularExpression) != nil { return true }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("x-sonos") || lower.hasPrefix("x-rincon") { return true }
        return false
    }

    public static func scrub(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return isHardwareIdentifier(trimmed) ? "" : trimmed
    }

    public static func displayTitle(_ metadataTitle: String, uri: String) -> String {
        let cleaned = scrub(metadataTitle)
        if !cleaned.isEmpty { return cleaned }
        switch kind(for: uri) {
        case .tv: return "TV"
        case .lineIn: return "Line-In"
        case .radio: return "Radio"
        case .stream: return "Stream"
        case .music: return ""
        }
    }

    public static func describe(uri: String) -> String {
        switch kind(for: uri) {
        case .tv: return "TV"
        case .lineIn: return "Line-In"
        case .radio: return "Radio"
        case .stream: return "Stream"
        case .music:
            let value = uri.lowercased()
            if value.isEmpty { return "" }
            if value.hasPrefix("x-rincon-queue") { return "Queue" }
            if value.hasPrefix("x-rincon-playlist") || value.contains("savedqueues") { return "Playlist" }
            if value.hasPrefix("x-rincon-buzzer") { return "Alarm" }
            if value.hasPrefix("x-rincon:") { return "Group" }
            if value.contains("spotify") { return "Spotify" }
            if value.contains("apple") || value.contains("itun") { return "Apple Music" }
            if value.hasPrefix("x-file-cifs") { return "Library" }
            return ""
        }
    }
}

public enum QueueMath {
    /// Converts a 0-based move into the 1-based indexes Sonos `ReorderTracksInQueue` expects.
    /// `newPosition` is where the track should land after the move.
    public static func reorder(start: Int, newPosition: Int, count: Int) -> (startingIndex: Int, insertBefore: Int)? {
        guard count > 0, start >= 0, newPosition >= 0, start < count, newPosition < count, start != newPosition else {
            return nil
        }
        let insertBefore = newPosition > start ? newPosition + 1 : newPosition
        return (start + 1, insertBefore + 1)
    }
}

public enum DIDL {
    public static func envelope(_ fragment: String) -> String {
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("DIDL-Lite") { return trimmed }
        return "<DIDL-Lite xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\" xmlns:r=\"urn:schemas-rinconnetworks-com:metadata-1-0/\" xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\">\(trimmed)</DIDL-Lite>"
    }
}
