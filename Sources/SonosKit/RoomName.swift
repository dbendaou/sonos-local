import Foundation

/// Picks a room name a person set, and drops product names, hardware ids, and addresses.
public enum RoomName {
    /// `zoneName` is the topology name. `deviceName` is the description's room or friendly name.
    /// `advertisedName` is the Bonjour instance name when discovery had one.
    public static func choose(
        zoneName: String,
        deviceName: String,
        modelName: String = "",
        advertisedName: String = ""
    ) -> String {
        let candidates = [zoneName, advertisedName, deviceName]
        for candidate in candidates {
            if let room = cleaned(candidate, modelName: modelName) {
                return room
            }
        }
        return "Speaker"
    }

    public static func groupTitle(_ names: [String]) -> String {
        let trimmed = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let real = trimmed.filter { !isPlaceholder($0) }
        let usable = real.isEmpty ? trimmed : real
        switch usable.count {
        case 0: return "Speaker"
        case 1: return usable[0]
        case 2: return "\(usable[0]) + \(usable[1])"
        default: return "\(usable[0]) + \(usable.count - 1)"
        }
    }

    /// Bonjour instance names look like `RINCON_…@Salon` or `Bureau`.
    public static func fromServiceName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = name.range(of: "._sonos", options: .caseInsensitive) {
            name = String(name[..<range.lowerBound])
        }
        let parts = name.split(separator: "@", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard parts.count == 2 else { return name }
        let left = parts[0]
        let right = parts[1]
        if looksLikeHardware(left) { return right }
        if looksLikeHardware(right) { return left }
        return right.isEmpty ? left : right
    }

    public static func isPlaceholder(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if trimmed.contains("://") { return true }
        if SourceLabel.isHardwareIdentifier(trimmed) { return true }
        if isIPAddress(trimmed) { return true }
        let key = normalizeKey(trimmed)
        if key.isEmpty { return true }
        if generic.contains(key) || products.contains(key) { return true }
        if key.hasPrefix("sonos ") { return true }
        let compact = key.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ":", with: "")
        if compactProducts.contains(compact) { return true }
        return false
    }

    private static func cleaned(_ raw: String, modelName: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let side = roomSide(of: trimmed), let room = accept(side, modelName: modelName) {
            return room
        }
        if isAddressAndProduct(trimmed) { return nil }
        return accept(trimmed, modelName: modelName)
    }

    /// `192.168.1.62 - Sonos Playbar` has no room in it.
    private static func isAddressAndProduct(_ name: String) -> Bool {
        let separators = [" - ", " — ", " – ", " @ "]
        for separator in separators {
            guard let range = name.range(of: separator) else { continue }
            let left = String(name[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(name[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let leftIsRaw = isIPAddress(left) || isPlaceholder(left) || looksLikeHardware(left)
            let rightIsProduct = isPlaceholder(right) || right.lowercased().hasPrefix("sonos") || isIPAddress(right)
            if leftIsRaw && rightIsProduct { return true }
        }
        return false
    }

    private static func accept(_ name: String, modelName: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || isPlaceholder(trimmed) || matchesModel(trimmed, modelName: modelName) {
            return nil
        }
        return trimmed
    }

    /// Sonos friendly names are `Room - Sonos Playbar` or `192.168.1.62 - Sonos One`.
    private static func roomSide(of name: String) -> String? {
        let separators = [" - ", " — ", " – ", " @ "]
        for separator in separators {
            guard let range = name.range(of: separator) else { continue }
            let left = String(name[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(name[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !left.isEmpty, !right.isEmpty else { continue }
            let rightIsProduct = isPlaceholder(right) || right.lowercased().hasPrefix("sonos")
            if rightIsProduct, !isPlaceholder(left), !isIPAddress(left) {
                return left
            }
        }
        return nil
    }

    private static func matchesModel(_ name: String, modelName: String) -> Bool {
        let model = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return false }
        let nameKey = normalizeKey(name)
        let modelKey = normalizeKey(model)
        if nameKey == modelKey { return true }
        let bare = modelKey.hasPrefix("sonos ") ? String(modelKey.dropFirst(6)) : modelKey
        return nameKey == bare || nameKey == "sonos \(bare)"
    }

    private static func looksLikeHardware(_ name: String) -> Bool {
        SourceLabel.isHardwareIdentifier(name) || name.uppercased().contains("RINCON")
    }

    private static func isIPAddress(_ name: String) -> Bool {
        let parts = name.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { UInt8($0) != nil }
    }

    private static func normalizeKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static let generic: Set<String> = [
        "room", "rooms", "speaker", "speakers", "sonos", "player", "play", "zone", "unknown", "unnamed",
    ]

    private static let products: Set<String> = [
        "playbar", "playbase", "play:1", "play:3", "play:5", "play 1", "play 3", "play 5",
        "beam", "arc", "arc ultra", "ray", "roam", "roam 2", "move", "move 2", "five", "amp", "port",
        "sub", "sub mini", "boost", "bridge", "connect", "connect:amp", "era 100", "era 300",
        "one sl", "symfonisk",
    ]

    private static let compactProducts: Set<String> = [
        "play", "playbar", "playbase", "play1", "play3", "play5", "beam", "arc", "arcultra", "ray",
        "roam", "roam2", "move", "move2", "five", "amp", "port", "sub", "submini", "boost", "bridge",
        "connect", "connectamp", "era100", "era300", "onesl", "symfonisk",
    ]
}
