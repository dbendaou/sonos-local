import Foundation

/// Room labels come from the topology `ZoneName`. A model name is only a stand-in.
public enum RoomName {
    /// Uses `zoneName` as written. Falls back to `modelDisplayName` when the zone
    /// name is missing or is a raw `RINCON_` id.
    public static func display(zoneName: String, modelDisplayName: String = "") -> String {
        let zone = zoneName.trimmingCharacters(in: .whitespacesAndNewlines)
        if isUsable(zone) { return zone }
        let model = modelDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if isUsable(model) { return model }
        return "Speaker"
    }

    public static func choose(
        zoneName: String,
        deviceName: String = "",
        modelName: String = "",
        advertisedName: String = ""
    ) -> String {
        let model = modelName.isEmpty ? deviceName : modelName
        _ = advertisedName
        return display(zoneName: zoneName, modelDisplayName: model)
    }

    public static func groupTitle(_ names: [String]) -> String {
        let usable = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter(isUsable)
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

    /// Empty text and raw speaker ids are not room names. Product words such as "Play" are.
    public static func isPlaceholder(_ name: String) -> Bool {
        !isUsable(name)
    }

    public static func isUsable(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if SourceLabel.isHardwareIdentifier(trimmed) { return false }
        return true
    }

    private static func looksLikeHardware(_ name: String) -> Bool {
        SourceLabel.isHardwareIdentifier(name) || name.uppercased().contains("RINCON")
    }
}
