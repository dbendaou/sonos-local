import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct BatteryStatus: Equatable, Sendable {
    public var level: Int
    public var powerSource: String
    public var temperature: String

    public init(level: Int, powerSource: String, temperature: String) {
        self.level = level
        self.powerSource = powerSource
        self.temperature = temperature
    }

    /// External power (USB or a Sonos charging ring) means the pack is charging.
    public var isCharging: Bool {
        let source = powerSource.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return !source.isEmpty && source != "BATTERY" && source != "UNKNOWN"
    }

    /// SF Symbol that tracks the level in quarters, with a bolt while charging.
    public var symbolName: String {
        let bucket: String
        switch level {
        case ..<13: bucket = "0"
        case ..<38: bucket = "25"
        case ..<63: bucket = "50"
        case ..<88: bucket = "75"
        default: bucket = "100"
        }
        return isCharging ? "battery.\(bucket).bolt" : "battery.\(bucket)"
    }

    public var accessibilityLabel: String {
        isCharging ? "Battery \(level) percent, charging" : "Battery \(level) percent"
    }
}

public enum BatteryStatusParser {
    /// Parses `/status/batterystatus`. Speakers without a battery omit `Level`.
    public static func parse(_ xml: String) -> BatteryStatus? {
        let trimmed = xml.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let root = try? XML.parse(trimmed) else { return nil }
        let levelText = root.firstDescendant("Level")?.trimmedText ?? ""
        guard let level = Int(levelText) else { return nil }
        let source = root.firstDescendant("PowerSource")?.trimmedText ?? ""
        let temperature = root.firstDescendant("Temperature")?.trimmedText
            ?? root.firstDescendant("BatteryTemp")?.trimmedText
            ?? ""
        return BatteryStatus(
            level: min(100, max(0, level)),
            powerSource: source,
            temperature: temperature
        )
    }
}

public enum BatteryQuery {
    public enum Outcome: Equatable, Sendable {
        case reading(BatteryStatus)
        case unsupported
        case unavailable
    }

    public static let refreshInterval: TimeInterval = 60

    public static func fetch(host: String, port: Int, session: URLSession) async -> Outcome {
        guard let url = URL(string: "http://\(host):\(port)/status/batterystatus"),
              NetworkPolicy.isAllowedURL(url) else { return .unsupported }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unavailable }
            if http.statusCode == 404 || http.statusCode == 500 { return .unsupported }
            guard (200...299).contains(http.statusCode) else { return .unavailable }
            if let status = BatteryStatusParser.parse(String(decoding: data, as: UTF8.self)) {
                return .reading(status)
            }
            return .unsupported
        } catch {
            return .unavailable
        }
    }
}
