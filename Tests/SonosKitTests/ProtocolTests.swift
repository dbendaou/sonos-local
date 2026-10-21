import Foundation
import Testing
@testable import SonosKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite struct ProtocolTests {
    @Test func xmlParsesElementsAttributesAndEntities() throws {
        let xml = """
        <?xml version="1.0"?>
        <root xmlns="urn:schemas-upnp-org:device-1-0">
          <!-- comment -->
          <device id="1">
            <friendlyName>Living &amp; Dining</friendlyName>
            <note><![CDATA[a<b>]]></note>
            <flag on="1"/>
          </device>
        </root>
        """
        let root = try XML.parse(xml)
        let device = try #require(root.child("device"))
        #expect(device.attribute("id") == "1")
        #expect(device.child("friendlyName")?.trimmedText == "Living & Dining")
        #expect(device.child("note")?.trimmedText == "a<b>")
        #expect(device.child("flag")?.attribute("on") == "1")
        #expect(XML.escape("A&B<\"'>") == "A&amp;B&lt;&quot;&apos;&gt;")
    }

    @Test func xmlRejectsUnclosedInput() {
        #expect(throws: XMLError.malformed) {
            try XML.parse("<a>")
        }
    }

    @Test func soapEnvelopeAndFault() throws {
        let body = SOAPEnvelope.make(
            service: "urn:schemas-upnp-org:service:RenderingControl:1",
            action: "SetVolume",
            arguments: [("InstanceID", "0"), ("Channel", "Master"), ("DesiredVolume", "Living & Dining")]
        )
        #expect(body.contains("<u:SetVolume xmlns:u=\"urn:schemas-upnp-org:service:RenderingControl:1\">"))
        #expect(body.contains("<DesiredVolume>Living &amp; Dining</DesiredVolume>"))

        let ok = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>
        <u:GetVolumeResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
          <CurrentVolume>22</CurrentVolume>
        </u:GetVolumeResponse>
        </s:Body></s:Envelope>
        """
        let values = try SOAPResponse.values(in: ok)
        #expect(values["CurrentVolume"] == "22")

        let fault = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>
          <s:Fault>
            <faultcode>s:Client</faultcode>
            <faultstring>UPnPError</faultstring>
            <detail><UPnPError xmlns="urn:schemas-upnp-org:control-1-0">
              <errorCode>701</errorCode>
              <errorDescription>Transition not available</errorDescription>
            </UPnPError></detail>
          </s:Fault>
        </s:Body></s:Envelope>
        """
        #expect(throws: SonosError(code: 701, message: "Transition not available")) {
            try SOAPResponse.values(in: fault)
        }
    }

    @Test func deviceDescription() throws {
        let xml = """
        <root>
          <device>
            <deviceType>urn:schemas-upnp-org:device:ZonePlayer:1</deviceType>
            <friendlyName>192.168.1.20 - Sonos One</friendlyName>
            <roomName>Living Room</roomName>
            <modelName>Sonos One</modelName>
            <modelNumber>S18</modelNumber>
            <serialNum>00-11-22-33-44-55:A</serialNum>
            <UDN>uuid:RINCON_00112233445501400</UDN>
            <softwareVersion>80.0-50000</softwareVersion>
          </device>
        </root>
        """
        let speaker = try DeviceDescriptionParser.parse(xml, fallbackHost: "192.168.1.20", fallbackPort: 1400)
        #expect(speaker.uuid == "RINCON_00112233445501400")
        #expect(speaker.name == "Living Room")
        #expect(speaker.modelName == "Sonos One")
        #expect(speaker.isBridge == false)
    }

    @Test func zoneGroupsHideSubAndNameAPair() throws {
        let xml = """
        <ZoneGroupState>
          <ZoneGroups>
            <ZoneGroup Coordinator="RINCON_AAA" ID="RINCON_AAA:10">
              <ZoneGroupMember UUID="RINCON_AAA" Location="http://192.168.1.20:1400/xml/device_description.xml" ZoneName="Living Room" Invisible="0" IsZoneBridge="0"/>
              <ZoneGroupMember UUID="RINCON_BBB" Location="http://192.168.1.21:1400/xml/device_description.xml" ZoneName="Kitchen" Invisible="0"/>
              <ZoneGroupMember UUID="RINCON_SUB" Location="http://192.168.1.22:1400/xml/device_description.xml" ZoneName="Sub" Invisible="1"/>
            </ZoneGroup>
            <ZoneGroup Coordinator="RINCON_BRIDGE" ID="RINCON_BRIDGE:1">
              <ZoneGroupMember UUID="RINCON_BRIDGE" Location="http://192.168.1.2:1400/xml/device_description.xml" ZoneName="Boost" Invisible="0" IsZoneBridge="1"/>
            </ZoneGroup>
          </ZoneGroups>
        </ZoneGroupState>
        """
        let groups = try ZoneGroupParser.parse(xml)
        #expect(groups.count == 2)
        #expect(groups[0].displayName == "Living Room + Kitchen")
        #expect(groups[0].visibleMembers.count == 2)
        #expect(groups[0].members[0].host == "192.168.1.20")
        #expect(groups[0].members[0].port == 1400)
        #expect(groups[1].visibleMembers.isEmpty)
    }

    @Test func zoneGroupStateSurvivesSOAPEscaping() throws {
        let inner = "&lt;ZoneGroupState&gt;&lt;ZoneGroups&gt;&lt;ZoneGroup Coordinator=&quot;RINCON_AAA&quot; ID=&quot;G1&quot;&gt;&lt;ZoneGroupMember UUID=&quot;RINCON_AAA&quot; Location=&quot;http://10.0.0.8:1400/xml/device_description.xml&quot; ZoneName=&quot;Office&quot; Invisible=&quot;0&quot;/&gt;&lt;/ZoneGroup&gt;&lt;/ZoneGroups&gt;&lt;/ZoneGroupState&gt;"
        let soap = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>
          <u:GetZoneGroupStateResponse xmlns:u="urn:schemas-upnp-org:service:ZoneGroupTopology:1">
            <ZoneGroupState>\(inner)</ZoneGroupState>
          </u:GetZoneGroupStateResponse>
        </s:Body></s:Envelope>
        """
        let values = try SOAPResponse.values(in: soap)
        let groups = try ZoneGroupParser.parse(values["ZoneGroupState"] ?? "")
        #expect(groups.first?.displayName == "Office")
        #expect(groups.first?.coordinatorUUID == "RINCON_AAA")
    }

    @Test func didlPreservesMetadataAndFields() throws {
        let xml = """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">
          <item id="Q:0/2" parentID="Q:0" restricted="true">
            <res protocolInfo="sonos.com-http:*:audio/mpeg:*" duration="0:03:22">x-sonos-http:track.mp3</res>
            <upnp:albumArtURI>/getaa?u=track</upnp:albumArtURI>
            <dc:title>Night Shift</dc:title>
            <upnp:class>object.item.audioItem.musicTrack</upnp:class>
            <dc:creator>The Band</dc:creator>
            <upnp:album>Late</upnp:album>
          </item>
        </DIDL-Lite>
        """
        let item = try #require(DIDLParser.items(in: xml).first)
        #expect(item.id == "Q:0/2")
        #expect(item.title == "Night Shift")
        #expect(item.artist == "The Band")
        #expect(item.album == "Late")
        #expect(item.uri == "x-sonos-http:track.mp3")
        #expect(item.artURI == "/getaa?u=track")
        #expect(item.duration == 202)
        #expect(item.metadata.contains("dc:title"))
        #expect(item.metadata.contains("DIDL-Lite"))
    }

    @Test func eventLastChange() throws {
        let inner = "&lt;Event xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/AVT/&quot;&gt;&lt;InstanceID val=&quot;0&quot;&gt;&lt;TransportState val=&quot;PLAYING&quot;/&gt;&lt;CurrentPlayMode val=&quot;SHUFFLE&quot;/&gt;&lt;Volume channel=&quot;Master&quot; val=&quot;15&quot;/&gt;&lt;CurrentTrackMetaData val=&quot;&amp;lt;DIDL-Lite xmlns:dc=&amp;quot;http://purl.org/dc/elements/1.1/&amp;quot;&amp;gt;&amp;lt;item&amp;gt;&amp;lt;dc:title&amp;gt;Song&amp;lt;/dc:title&amp;gt;&amp;lt;/item&amp;gt;&amp;lt;/DIDL-Lite&amp;gt;&quot;/&gt;&lt;/InstanceID&gt;&lt;/Event&gt;"
        let body = """
        <e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0">
          <e:property><LastChange>\(inner)</LastChange></e:property>
        </e:propertyset>
        """
        let event = try EventParser.parse(body)
        #expect(event.values["TransportState"] == "PLAYING")
        #expect(event.values["CurrentPlayMode"] == "SHUFFLE")
        #expect(event.channels["Volume"]?["Master"] == "15")
        #expect(event.values["CurrentTrackMetaData"]?.contains("Song") == true)
    }

    @Test func topologyEventProperty() throws {
        let body = """
        <e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0">
          <e:property><ZoneGroupState>&lt;ZoneGroups/&gt;</ZoneGroupState></e:property>
        </e:propertyset>
        """
        let event = try EventParser.parse(body)
        #expect(event.properties["ZoneGroupState"] == "<ZoneGroups/>")
    }

    @Test func alarms() throws {
        let xml = """
        <Alarms>
          <Alarm ID="14" StartTime="07:00:00" Duration="02:00:00" Recurrence="WEEKDAYS" Enabled="1" RoomUUID="RINCON_AAA" ProgramURI="x-rincon-buzzer:0" ProgramMetaData="" PlayMode="NORMAL" Volume="25" IncludeLinkedZones="0"/>
          <Alarm ID="15" StartTime="09:30:00" Duration="01:00:00" Recurrence="ONCE" Enabled="0" RoomUUID="RINCON_BBB" ProgramURI="x-rincon-buzzer:0" ProgramMetaData="" PlayMode="SHUFFLE" Volume="10" IncludeLinkedZones="1"/>
        </Alarms>
        """
        let alarms = try AlarmParser.parse(xml)
        #expect(alarms.count == 2)
        #expect(alarms[0].id == 14)
        #expect(alarms[0].enabled)
        #expect(alarms[0].recurrenceTitle == "Weekdays")
        #expect(alarms[1].enabled == false)
        #expect(alarms[1].includeLinkedZones)
        #expect(alarms[1].volume == 10)
    }

    @Test func ssdpResponse() {
        let message = """
        HTTP/1.1 200 OK\r
        CACHE-CONTROL: max-age=1800\r
        LOCATION: http://192.168.1.20:1400/xml/device_description.xml\r
        SERVER: Linux UPnP/1.0 Sonos/80.0-50000 (ZPS18)\r
        ST: urn:schemas-upnp-org:device:ZonePlayer:1\r
        USN: uuid:RINCON_00112233445501400::urn:schemas-upnp-org:device:ZonePlayer:1\r
        \r

        """
        let response = SSDPResponse.parse(message)
        #expect(response?.location == "http://192.168.1.20:1400/xml/device_description.xml")
        #expect(response?.uuid == "RINCON_00112233445501400")
        #expect(SSDPResponse.parse("M-SEARCH * HTTP/1.1\r\nST: ssdp:all\r\n") == nil)
    }

    @Test func playModeRoundTrip() {
        let mode = PlayMode(shuffle: true, repeatMode: .all)
        #expect(mode == .shuffleRepeat)
        #expect(mode.togglingShuffle() == .repeatAll)
        #expect(PlayMode.normal.cyclingRepeat() == .repeatAll)
        #expect(PlayMode.repeatAll.cyclingRepeat() == .repeatOne)
        #expect(PlayMode.repeatOne.cyclingRepeat() == .normal)
        #expect(PlayMode(rawValue: "SHUFFLE_REPEAT_ONE")?.repeatMode == .one)
    }

    @Test func timeAndQueueMath() {
        #expect(SonosTime.parse("0:03:22") == 202)
        #expect(SonosTime.parse("00:03:22") == 202)
        #expect(SonosTime.parse("3:02") == 182)
        #expect(SonosTime.parse("NOT_IMPLEMENTED") == nil)
        #expect(SonosTime.clock(202) == "0:03:22")
        #expect(SonosTime.display(202) == "3:22")
        #expect(SonosTime.display(3661) == "1:01:01")
        #expect(QueueMath.reorder(start: 0, newPosition: 1, count: 4)?.startingIndex == 1)
        #expect(QueueMath.reorder(start: 0, newPosition: 1, count: 4)?.insertBefore == 3)
        #expect(QueueMath.reorder(start: 2, newPosition: 0, count: 4)?.insertBefore == 1)
        #expect(QueueMath.reorder(start: 1, newPosition: 1, count: 4) == nil)
    }

    @Test func networkPolicyAndArtworkStayLocal() {
        #expect(NetworkPolicy.isAllowedHost("192.168.1.20"))
        #expect(NetworkPolicy.isAllowedHost("10.0.0.5"))
        #expect(NetworkPolicy.isAllowedHost("172.16.4.4"))
        #expect(NetworkPolicy.isAllowedHost("172.32.0.1") == false)
        #expect(NetworkPolicy.isAllowedHost("8.8.8.8") == false)
        #expect(NetworkPolicy.isAllowedHost("speaker.local"))
        let local = ArtworkURL.resolve(artURI: "/getaa?u=track", trackURI: nil, host: "192.168.1.20", port: 1400)
        #expect(local?.absoluteString == "http://192.168.1.20:1400/getaa?u=track")
        let proxied = ArtworkURL.resolve(artURI: "https://cdn.example.com/art.jpg", trackURI: "x-sonos-http:track", host: "10.0.0.8", port: 1400)
        #expect(proxied?.host == "10.0.0.8")
        #expect(proxied?.path == "/getaa")
        #expect(ArtworkURL.resolve(artURI: "/getaa", trackURI: nil, host: "8.8.8.8", port: 1400) == nil)
        #expect(ArtworkURL.httpsFallback(artURI: "https://cdn.example.com/art.jpg", host: "10.0.0.8", port: 1400)?.host == "cdn.example.com")
    }

    @Test func artworkURIResolution() {
        let escaped = ArtworkURL.resolve(
            artURI: "/getaa?s=1&amp;u=track%3A1",
            trackURI: nil,
            host: "192.168.1.20",
            port: 1400
        )
        #expect(escaped?.host == "192.168.1.20")
        #expect(escaped?.path == "/getaa")
        #expect(escaped?.absoluteString.contains("amp;") == false)
        #expect(escaped?.absoluteString.contains("s=1") == true)
        #expect(escaped?.absoluteString.contains("u=track%3A1") == true || escaped?.absoluteString.contains("u=track:1") == true)

        let relative = ArtworkURL.resolve(artURI: "getaa?u=abc", trackURI: nil, host: "192.168.1.20", port: 1400)
        #expect(relative?.absoluteString == "http://192.168.1.20:1400/getaa?u=abc")

        let streamed = ArtworkURL.resolve(
            artURI: "https://i.scdn.co/image/abc",
            trackURI: nil,
            host: "192.168.1.10",
            port: 1400
        )
        #expect(streamed?.scheme == "http")
        #expect(streamed?.host == "192.168.1.10")
        #expect(streamed?.path == "/getaa")
        let direct = ArtworkURL.httpsFallback(artURI: "https://i.scdn.co/image/abc&amp;v=1", host: "192.168.1.10", port: 1400)
        #expect(direct?.scheme == "https")
        #expect(direct?.host == "i.scdn.co")
        #expect(direct?.absoluteString.contains("amp;") == false)
    }

    @Test func sourceLabels() {
        #expect(SourceLabel.describe(uri: "x-sonos-htastream:RINCON_A:spdif") == "TV")
        #expect(SourceLabel.describe(uri: "x-rincon-stream:RINCON_A") == "Line-In")
        #expect(SourceLabel.describe(uri: "x-rincon-queue:RINCON_A#0") == "Queue")
        #expect(SourceLabel.describe(uri: "x-sonos-spotify:track") == "Spotify")
    }

    @Test func classifiesTVLineInAndLiveRadio() {
        let tv = "x-sonos-htastream:RINCON_F0F6C1F0776101400:spdif"
        #expect(SourceLabel.kind(for: tv) == .tv)
        #expect(SourceLabel.isLive(kind: .tv, duration: 0))
        #expect(SourceLabel.allowsSkip(.tv) == false)
        #expect(SourceLabel.allowsModes(.tv) == false)
        #expect(SourceLabel.symbol(for: .tv) == "tv")
        #expect(SourceLabel.isHardwareIdentifier("RINCON_F0F6C1F0776101400"))
        #expect(SourceLabel.displayTitle("RINCON_F0F6C1F0776101400", uri: tv) == "TV")
        #expect(SourceLabel.scrub("RINCON_F0F6C1F0776101400") == "")

        let line = "x-rincon-stream:RINCON_804AF2C882CA01400"
        #expect(SourceLabel.kind(for: line) == .lineIn)
        #expect(SourceLabel.displayTitle("RINCON_804AF2C882CA01400", uri: line) == "Line-In")
        #expect(SourceLabel.allowsSkip(.lineIn) == false)

        let radio = "x-sonosapi-stream:s123?sid=254"
        #expect(SourceLabel.kind(for: radio) == .radio)
        #expect(SourceLabel.isLive(kind: .radio, duration: 0))
        #expect(SourceLabel.isLive(kind: .radio, duration: 180) == false)
        #expect(SourceLabel.displayTitle("BBC Radio 4", uri: radio) == "BBC Radio 4")
        #expect(SourceLabel.allowsModes(.radio) == false)

        let track = "x-sonos-spotify:spotify%3atrack%3a123"
        #expect(SourceLabel.kind(for: track) == .music)
        #expect(SourceLabel.allowsSkip(.music))
        #expect(SourceLabel.allowsModes(.music))
        #expect(SourceLabel.isLive(kind: .music, duration: 0) == false)
        #expect(SourceLabel.displayTitle("Night Shift", uri: track) == "Night Shift")
    }

    @Test func snapshotNamesGroupsAndArtwork() throws {
        let device = DiscoveredSpeaker(uuid: "RINCON_AAA", name: "Living Room", modelName: "Sonos One", modelNumber: "S18", softwareVersion: "80", serialNumber: "S", host: "192.168.1.20", port: 1400)
        var playback = PlaybackStore()
        playback.title = "Night Shift"
        playback.artist = "The Band"
        playback.transport = .playing
        playback.artURI = "/getaa?u=1"
        playback.trackURI = "x-sonos-http:track"
        playback.duration = 200
        playback.elapsed = 10
        let group = ZoneGroup(
            id: "G1",
            coordinatorUUID: "RINCON_AAA",
            members: [
                ZoneMember(uuid: "RINCON_AAA", name: "Living Room", host: "192.168.1.20", port: 1400, icon: "", softwareVersion: "", isInvisible: false, isBridge: false),
                ZoneMember(uuid: "RINCON_BBB", name: "Kitchen", host: "192.168.1.21", port: 1400, icon: "", softwareVersion: "", isInvisible: false, isBridge: false),
            ]
        )
        let snapshot = SnapshotBuilder.make(
            devices: ["RINCON_AAA": device],
            groups: [group],
            playback: ["RINCON_AAA": playback],
            volumes: ["RINCON_AAA": VolumeStore(level: 18, muted: false)],
            groupVolumes: ["G1": VolumeStore(level: 22, muted: false)],
            discovering: false,
            hasCompletedDiscovery: true
        )
        let room = try #require(snapshot.groups.first)
        #expect(room.name == "Living Room + Kitchen")
        #expect(room.nowPlaying.title == "Night Shift")
        #expect(room.nowPlaying.statusLine == "Night Shift")
        #expect(room.groupVolume == 22)
        #expect(room.members.first?.volume == 18)
        #expect(room.artworkURL?.host == "192.168.1.20")
        #expect(snapshot.isDiscovering == false)
    }

    @Test func eventServerAcceptsNotify() async throws {
        let server = EventServer()
        try server.start()
        defer { server.stop() }
        #expect(server.port > 0)
        let body = "<e:propertyset><e:property><LastChange>ok</LastChange></e:property></e:propertyset>"
        let payload = """
        NOTIFY /event HTTP/1.1\r
        HOST: 127.0.0.1:\(server.port)\r
        SID: uuid:test-sid\r
        CONTENT-LENGTH: \(body.utf8.count)\r
        \r
        \(body)
        """
        rawSend(payload, server.port)
        let deadline = Date().addingTimeInterval(2)
        var found: EventNotification?
        while Date() < deadline {
            found = server.notifications().first
            if found != nil { break }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        let note = try #require(found)
        #expect(note.sid == "uuid:test-sid")
        #expect(note.path == "/event")
        #expect(note.body.contains("LastChange"))
    }

    @Test func roomNamesIgnoreProductPlaceholders() {
        #expect(RoomName.isPlaceholder("Play"))
        #expect(RoomName.isPlaceholder("Play:1"))
        #expect(RoomName.isPlaceholder("Playbar"))
        #expect(RoomName.isPlaceholder("Sonos Playbar"))
        #expect(RoomName.isPlaceholder("RINCON_000E5812345601400"))
        #expect(RoomName.isPlaceholder("192.168.1.62"))
        #expect(!RoomName.isPlaceholder("Salon"))
        #expect(!RoomName.isPlaceholder("Playroom"))
        #expect(RoomName.choose(zoneName: "Play", deviceName: "TV - Sonos Playbar", modelName: "Sonos Playbar") == "TV")
        #expect(RoomName.choose(zoneName: "Playbar", deviceName: "192.168.1.62 - Sonos Playbar", modelName: "Sonos Playbar") == "Speaker")
        #expect(RoomName.choose(zoneName: "Office", deviceName: "Play:1", modelName: "Sonos Play:1") == "Office")
        #expect(RoomName.choose(zoneName: "Playroom", deviceName: "Sonos One", modelName: "Sonos One") == "Playroom")
        #expect(RoomName.choose(zoneName: "Play", deviceName: "Play", modelName: "Playbar", advertisedName: "Bureau") == "Bureau")
        #expect(RoomName.fromServiceName("RINCON_000E5812345601400@Salon") == "Salon")
        #expect(RoomName.fromServiceName("Bureau@RINCON_000E5812345601400") == "Bureau")
        #expect(RoomName.groupTitle(["TV"]) == "TV")
        #expect(RoomName.groupTitle(["Salon", "Bureau"]) == "Salon + Bureau")
    }

    @Test func deviceDescriptionPrefersRoomOverProductName() throws {
        let xml = """
        <root>
          <device>
            <deviceType>urn:schemas-upnp-org:device:ZonePlayer:1</deviceType>
            <friendlyName>TV - Sonos Playbar</friendlyName>
            <roomName>Play</roomName>
            <modelName>Sonos Playbar</modelName>
            <UDN>uuid:RINCON_AABBCCDDEEFF01400</UDN>
          </device>
        </root>
        """
        let speaker = try DeviceDescriptionParser.parse(xml, fallbackHost: "192.168.1.62", fallbackPort: 1400)
        #expect(speaker.name == "TV")
    }

    @Test func snapshotReplacesPlaceholderRoomAndDropsDuplicateHost() {
        let playbar = DiscoveredSpeaker(
            uuid: "RINCON_AAA",
            name: "TV",
            modelName: "Sonos Playbar",
            modelNumber: "S9",
            softwareVersion: "",
            serialNumber: "",
            host: "192.168.1.62",
            port: 1400
        )
        let ghost = DiscoveredSpeaker(
            uuid: "RINCON_GHOST",
            name: "Play",
            modelName: "Sonos Playbar",
            modelNumber: "S9",
            softwareVersion: "",
            serialNumber: "",
            host: "192.168.1.62",
            port: 1400
        )
        let group = ZoneGroup(
            id: "G1",
            coordinatorUUID: "RINCON_AAA",
            members: [
                ZoneMember(
                    uuid: "RINCON_AAA",
                    name: "Play",
                    host: "192.168.1.62",
                    port: 1400,
                    icon: "",
                    softwareVersion: "",
                    isInvisible: false,
                    isBridge: false
                ),
            ]
        )
        let snapshot = SnapshotBuilder.make(
            devices: ["RINCON_AAA": playbar, "RINCON_GHOST": ghost],
            groups: [group],
            playback: [:],
            volumes: [:],
            groupVolumes: [:],
            discovering: false,
            hasCompletedDiscovery: true,
            advertisedNames: [:]
        )
        #expect(snapshot.groups.count == 1)
        #expect(snapshot.groups[0].name == "TV")
        #expect(snapshot.groups[0].members.map(\.name) == ["TV"])
    }

    @Test func debounceKeepsOnlyTheLatestSliderSample() {
        var ledger = DebounceLedger()
        let first = ledger.push(key: "group-volume")
        let second = ledger.push(key: "group-volume")
        let third = ledger.push(key: "group-volume")
        let other = ledger.push(key: "seek")
        #expect(first == 1)
        #expect(second == 2)
        #expect(third == 3)
        #expect(ledger.isLatest(key: "group-volume", generation: third))
        #expect(!ledger.isLatest(key: "group-volume", generation: first))
        #expect(!ledger.isLatest(key: "group-volume", generation: second))
        #expect(ledger.isLatest(key: "seek", generation: other))
        #expect(DebounceLedger.delayNanoseconds >= 100_000_000)
    }

    @Test func playPauseFlipsBeforeTheSpeakerAnswers() {
        #expect(TransportState.playing.toggled == .paused)
        #expect(TransportState.paused.toggled == .playing)
        #expect(TransportState.stopped.toggled == .playing)
        #expect(TransportState.unknown.toggled == .playing)
    }

    @Test func batteryStatusParsesLevelAndCharging() {
        let roaming = """
        <?xml version="1.0" encoding="UTF-8"?>
        <BatteryStatus>
          <Level>67</Level>
          <PowerSource>BATTERY</PowerSource>
          <Temperature>NORMAL</Temperature>
          <BatteryTemp>32</BatteryTemp>
        </BatteryStatus>
        """
        let onBattery = BatteryStatusParser.parse(roaming)
        #expect(onBattery?.level == 67)
        #expect(onBattery?.isCharging == false)
        #expect(onBattery?.symbolName == "battery.75")
        #expect(onBattery?.temperature == "NORMAL")

        let docked = """
        <BatteryStatus>
          <Level>67</Level>
          <PowerSource>SONOS_CHARGING_RING</PowerSource>
        </BatteryStatus>
        """
        let charging = BatteryStatusParser.parse(docked)
        #expect(charging?.isCharging == true)
        #expect(charging?.symbolName == "battery.75.bolt")

        let low = BatteryStatusParser.parse("<BatteryStatus><Level>10</Level><PowerSource>USB_POWER</PowerSource></BatteryStatus>")
        #expect(low?.symbolName == "battery.0.bolt")
        #expect(BatteryStatusParser.parse("<BatteryStatus><Level>100</Level><PowerSource>BATTERY</PowerSource></BatteryStatus>")?.symbolName == "battery.100")
        #expect(BatteryStatusParser.parse("<BatteryStatus><Level>12</Level><PowerSource>BATTERY</PowerSource></BatteryStatus>")?.symbolName == "battery.0")
        #expect(BatteryStatusParser.parse("<BatteryStatus><Level>13</Level><PowerSource>BATTERY</PowerSource></BatteryStatus>")?.symbolName == "battery.25")
        #expect(BatteryStatusParser.parse("<BatteryStatus><PowerSource>BATTERY</PowerSource></BatteryStatus>") == nil)
        #expect(BatteryStatusParser.parse("<html>not a speaker</html>") == nil)
        #expect(BatteryStatusParser.parse("") == nil)
        #expect(BatteryQuery.refreshInterval == 60)
    }

    @Test func nowPlayingColumnMatchesTheArtwork() {
        let roomy = PlayerFit.metrics(width: 1400, height: 1100, showsModes: false)
        #expect(roomy.column == roomy.artwork)
        #expect(roomy.artwork <= 420)
        #expect(roomy.artwork + roomy.chrome <= 1100.5)
        #expect(roomy.transport <= 72)
        #expect(roomy.transport >= 46)

        let narrow = PlayerFit.metrics(width: 360, height: 900, showsModes: true)
        #expect(narrow.column == narrow.artwork)
        #expect(narrow.artwork < roomy.artwork)
        #expect(narrow.transport < roomy.transport)
        #expect(narrow.titleSize < roomy.titleSize)

        let short = PlayerFit.metrics(width: 1100, height: 560, showsModes: true)
        #expect(short.column == short.artwork)
        #expect(short.artwork + short.chrome <= 560.5)
        #expect(short.artwork < roomy.artwork)
    }
}

private func rawSend(_ text: String, _ port: UInt16) {
    let fd = socket(AF_INET, CSocket.stream, 0)
    guard fd >= 0 else { return }
    defer { close(fd) }
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = in_port_t(port.bigEndian)
    _ = inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)
    let connected = withUnsafePointer(to: &addr) { pointer -> Int32 in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
            connect(fd, sock, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard connected == 0 else { return }
    _ = text.withCString { send(fd, $0, strlen($0), 0) }
}
