import Foundation
import Testing
@testable import SonosKit

@Suite struct SpeakerCacheTests {
    @Test func roundTripAndUpsert() {
        let defaults = makeDefaults()
        let first = CachedSpeaker(
            uuid: "RINCON_AAA",
            name: "TV",
            host: "192.168.1.62",
            port: 1400,
            location: "http://192.168.1.62:1400/xml/device_description.xml",
            lastSeen: Date(timeIntervalSince1970: 1_700_000_000)
        )
        SpeakerCache.save(SpeakerCache.upsert(first, into: []), to: defaults)
        let moved = CachedSpeaker(
            uuid: "RINCON_AAA",
            name: "Salon",
            host: "192.168.1.70",
            port: 1400,
            location: "http://192.168.1.70:1400/xml/device_description.xml",
            lastSeen: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let other = CachedSpeaker(
            uuid: "RINCON_BBB",
            name: "Bureau",
            host: "192.168.1.71",
            port: 1400,
            location: "http://192.168.1.71:1400/xml/device_description.xml",
            lastSeen: Date(timeIntervalSince1970: 1_700_000_050)
        )
        let stored = SpeakerCache.upsert(moved, into: SpeakerCache.upsert(other, into: SpeakerCache.load(from: defaults, now: moved.lastSeen)))
        SpeakerCache.save(stored, to: defaults)
        let loaded = SpeakerCache.load(from: defaults, now: moved.lastSeen)
        #expect(loaded.count == 2)
        #expect(loaded.first { $0.uuid == "RINCON_AAA" }?.host == "192.168.1.70")
        #expect(loaded.first { $0.uuid == "RINCON_AAA" }?.name == "Salon")
        SpeakerCache.forget(in: defaults)
        #expect(SpeakerCache.load(from: defaults).isEmpty)
    }

    @Test func expiresSpeakersThatHaveNotBeenSeen() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fresh = CachedSpeaker(uuid: "A", name: "TV", host: "10.0.0.2", port: 1400, location: "http://10.0.0.2:1400/xml/device_description.xml", lastSeen: now)
        let stale = CachedSpeaker(uuid: "B", name: "Old", host: "10.0.0.3", port: 1400, location: "http://10.0.0.3:1400/xml/device_description.xml", lastSeen: now.addingTimeInterval(-(SpeakerCache.maxAge + 60)))
        let kept = SpeakerCache.pruned([fresh, stale], now: now)
        #expect(kept.map(\.uuid) == ["A"])
    }

    @Test func manualAddressBecomesDeviceDescriptionURL() {
        #expect(SpeakerCache.location(from: "192.168.1.62") == "http://192.168.1.62:1400/xml/device_description.xml")
        #expect(SpeakerCache.location(from: "192.168.1.62:1400") == "http://192.168.1.62:1400/xml/device_description.xml")
        #expect(SpeakerCache.location(from: "http://10.0.0.8:1400/xml/device_description.xml") == "http://10.0.0.8:1400/xml/device_description.xml")
        #expect(SpeakerCache.location(from: "8.8.8.8") == nil)
    }

    @Test func bonjourTXTLocation() {
        var record = Data()
        for item in ["location=http://192.168.1.62:1400/xml/device_description.xml", "info=RINCON_F0F6C1F0776101400"] {
            let bytes = Array(item.utf8)
            record.append(UInt8(bytes.count))
            record.append(contentsOf: bytes)
        }
        let fields = BonjourTXT.parse(record)
        #expect(BonjourTXT.location(in: fields) == "http://192.168.1.62:1400/xml/device_description.xml")
        #expect(BonjourTXT.location(in: ["info": "nope"]) == nil)
    }

    private func makeDefaults() -> UserDefaults {
        let name = "SonosLocalTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
