import XCTest
@testable import SonosKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class ProtocolTests: XCTestCase {
    func testXMLParsesElementsAttributesAndEntities() throws {
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
        let device = try XCTUnwrap(root.child("device"))
        XCTAssertEqual(device.attribute("id"), "1")
        XCTAssertEqual(device.child("friendlyName")?.trimmedText, "Living & Dining")
        XCTAssertEqual(device.child("note")?.trimmedText, "a<b>")
        XCTAssertEqual(device.child("flag")?.attribute("on"), "1")
        XCTAssertEqual(XML.escape("A&B<\"'>"), "A&amp;B&lt;&quot;&apos;&gt;")
    }

    func testXMLRejectsUnclosedInput() {
        XCTAssertThrowsError(try XML.parse("<a>"))
    }

    func testSOAPEnvelopeAndFault() throws {
        let body = SOAPEnvelope.make(
            service: "urn:schemas-upnp-org:service:RenderingControl:1",
            action: "SetVolume",
            arguments: [("InstanceID", "0"), ("Channel", "Master"), ("DesiredVolume", "Living & Dining")]
        )
        XCTAssertTrue(body.contains("<u:SetVolume xmlns:u=\"urn:schemas-upnp-org:service:RenderingControl:1\">"))
        XCTAssertTrue(body.contains("<DesiredVolume>Living &amp; Dining</DesiredVolume>"))

        let ok = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>
        <u:GetVolumeResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
          <CurrentVolume>22</CurrentVolume>
        </u:GetVolumeResponse>
        </s:Body></s:Envelope>
        """
        let values = try SOAPResponse.values(in: ok)
        XCTAssertEqual(values["CurrentVolume"], "22")

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
        XCTAssertThrowsError(try SOAPResponse.values(in: fault)) { error in
            let sonos = error as? SonosError
            XCTAssertEqual(sonos?.code, 701)
            XCTAssertEqual(sonos?.message, "Transition not available")
        }
    }

    func testDeviceDescription() throws {
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
        XCTAssertEqual(speaker.uuid, "RINCON_00112233445501400")
        XCTAssertEqual(speaker.name, "Living Room")
        XCTAssertEqual(speaker.modelName, "Sonos One")
        XCTAssertFalse(speaker.isBridge)
    }

    func testZoneGroupsHideSubAndNameAPair() throws {
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
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].displayName, "Living Room + Kitchen")
        XCTAssertEqual(groups[0].visibleMembers.count, 2)
        XCTAssertEqual(groups[0].members[0].host, "192.168.1.20")
        XCTAssertEqual(groups[0].members[0].port, 1400)
        XCTAssertTrue(groups[1].visibleMembers.isEmpty)
    }

    func testZoneGroupStateSurvivesSOAPEscaping() throws {
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
        XCTAssertEqual(groups.first?.displayName, "Office")
        XCTAssertEqual(groups.first?.coordinatorUUID, "RINCON_AAA")
    }

    func testDIDLPreservesMetadataAndFields() throws {
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
        let item = try XCTUnwrap(DIDLParser.items(in: xml).first)
        XCTAssertEqual(item.id, "Q:0/2")
        XCTAssertEqual(item.title, "Night Shift")
        XCTAssertEqual(item.artist, "The Band")
        XCTAssertEqual(item.album, "Late")
        XCTAssertEqual(item.uri, "x-sonos-http:track.mp3")
        XCTAssertEqual(item.artURI, "/getaa?u=track")
        XCTAssertEqual(item.duration, 202)
        XCTAssertTrue(item.metadata.contains("dc:title"))
        XCTAssertTrue(item.metadata.contains("DIDL-Lite"))
    }

    func testEventLastChange() throws {
        let inner = "&lt;Event xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/AVT/&quot;&gt;&lt;InstanceID val=&quot;0&quot;&gt;&lt;TransportState val=&quot;PLAYING&quot;/&gt;&lt;CurrentPlayMode val=&quot;SHUFFLE&quot;/&gt;&lt;Volume channel=&quot;Master&quot; val=&quot;15&quot;/&gt;&lt;CurrentTrackMetaData val=&quot;&amp;lt;DIDL-Lite xmlns:dc=&amp;quot;http://purl.org/dc/elements/1.1/&amp;quot;&amp;gt;&amp;lt;item&amp;gt;&amp;lt;dc:title&amp;gt;Song&amp;lt;/dc:title&amp;gt;&amp;lt;/item&amp;gt;&amp;lt;/DIDL-Lite&amp;gt;&quot;/&gt;&lt;/InstanceID&gt;&lt;/Event&gt;"
        let body = """
        <e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0">
          <e:property><LastChange>\(inner)</LastChange></e:property>
        </e:propertyset>
        """
        let event = try EventParser.parse(body)
        XCTAssertEqual(event.values["TransportState"], "PLAYING")
        XCTAssertEqual(event.values["CurrentPlayMode"], "SHUFFLE")
        XCTAssertEqual(event.channels["Volume"]?["Master"], "15")
        XCTAssertTrue(event.values["CurrentTrackMetaData"]?.contains("Song") == true)
    }

    func testTopologyEventProperty() throws {
        let body = """
        <e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0">
          <e:property><ZoneGroupState>&lt;ZoneGroups/&gt;</ZoneGroupState></e:property>
        </e:propertyset>
        """
        let event = try EventParser.parse(body)
        XCTAssertEqual(event.properties["ZoneGroupState"], "<ZoneGroups/>")
    }

    func testAlarms() throws {
        let xml = """
        <Alarms>
          <Alarm ID="14" StartTime="07:00:00" Duration="02:00:00" Recurrence="WEEKDAYS" Enabled="1" RoomUUID="RINCON_AAA" ProgramURI="x-rincon-buzzer:0" ProgramMetaData="" PlayMode="NORMAL" Volume="25" IncludeLinkedZones="0"/>
          <Alarm ID="15" StartTime="09:30:00" Duration="01:00:00" Recurrence="ONCE" Enabled="0" RoomUUID="RINCON_BBB" ProgramURI="x-rincon-buzzer:0" ProgramMetaData="" PlayMode="SHUFFLE" Volume="10" IncludeLinkedZones="1"/>
        </Alarms>
        """
        let alarms = try AlarmParser.parse(xml)
        XCTAssertEqual(alarms.count, 2)
        XCTAssertEqual(alarms[0].id, 14)
        XCTAssertTrue(alarms[0].enabled)
        XCTAssertEqual(alarms[0].recurrenceTitle, "Weekdays")
        XCTAssertFalse(alarms[1].enabled)
        XCTAssertTrue(alarms[1].includeLinkedZones)
        XCTAssertEqual(alarms[1].volume, 10)
    }

    func testSSDPResponse() {
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
        XCTAssertEqual(response?.location, "http://192.168.1.20:1400/xml/device_description.xml")
        XCTAssertEqual(response?.uuid, "RINCON_00112233445501400")
        XCTAssertNil(SSDPResponse.parse("M-SEARCH * HTTP/1.1\r\nST: ssdp:all\r\n"))
    }

    func testPlayModeRoundTrip() {
        let mode = PlayMode(shuffle: true, repeatMode: .all)
        XCTAssertEqual(mode, .shuffleRepeat)
        XCTAssertEqual(mode.togglingShuffle(), .repeatAll)
        XCTAssertEqual(PlayMode.normal.cyclingRepeat(), .repeatAll)
        XCTAssertEqual(PlayMode.repeatAll.cyclingRepeat(), .repeatOne)
        XCTAssertEqual(PlayMode.repeatOne.cyclingRepeat(), .normal)
        XCTAssertEqual(PlayMode(rawValue: "SHUFFLE_REPEAT_ONE")?.repeatMode, .one)
    }

    func testTimeAndQueueMath() {
        XCTAssertEqual(SonosTime.parse("0:03:22"), 202)
        XCTAssertEqual(SonosTime.parse("00:03:22"), 202)
        XCTAssertEqual(SonosTime.parse("3:02"), 182)
        XCTAssertNil(SonosTime.parse("NOT_IMPLEMENTED"))
        XCTAssertEqual(SonosTime.clock(202), "0:03:22")
        XCTAssertEqual(SonosTime.display(202), "3:22")
        XCTAssertEqual(SonosTime.display(3661), "1:01:01")
        XCTAssertEqual(QueueMath.reorder(start: 0, newPosition: 1, count: 4)?.startingIndex, 1)
        XCTAssertEqual(QueueMath.reorder(start: 0, newPosition: 1, count: 4)?.insertBefore, 3)
        XCTAssertEqual(QueueMath.reorder(start: 2, newPosition: 0, count: 4)?.insertBefore, 1)
        XCTAssertNil(QueueMath.reorder(start: 1, newPosition: 1, count: 4))
    }

    func testNetworkPolicyAndArtworkStayLocal() {
        XCTAssertTrue(NetworkPolicy.isAllowedHost("192.168.1.20"))
        XCTAssertTrue(NetworkPolicy.isAllowedHost("10.0.0.5"))
        XCTAssertTrue(NetworkPolicy.isAllowedHost("172.16.4.4"))
        XCTAssertFalse(NetworkPolicy.isAllowedHost("172.32.0.1"))
        XCTAssertFalse(NetworkPolicy.isAllowedHost("8.8.8.8"))
        XCTAssertTrue(NetworkPolicy.isAllowedHost("speaker.local"))
        let local = ArtworkURL.resolve(artURI: "/getaa?u=track", trackURI: nil, host: "192.168.1.20", port: 1400)
        XCTAssertEqual(local?.absoluteString, "http://192.168.1.20:1400/getaa?u=track")
        let proxied = ArtworkURL.resolve(artURI: "https://cdn.example.com/art.jpg", trackURI: "x-sonos-http:track", host: "10.0.0.8", port: 1400)
        XCTAssertEqual(proxied?.host, "10.0.0.8")
        XCTAssertTrue(proxied?.path == "/getaa")
        XCTAssertNil(ArtworkURL.resolve(artURI: "/getaa", trackURI: nil, host: "8.8.8.8", port: 1400))
    }

    func testSourceLabels() {
        XCTAssertEqual(SourceLabel.describe(uri: "x-sonos-htastream:RINCON_A:spdif"), "TV")
        XCTAssertEqual(SourceLabel.describe(uri: "x-rincon-stream:RINCON_A"), "Line-in")
        XCTAssertEqual(SourceLabel.describe(uri: "x-rincon-queue:RINCON_A#0"), "Queue")
        XCTAssertEqual(SourceLabel.describe(uri: "x-sonos-spotify:track"), "Spotify")
    }

    func testSnapshotNamesGroupsAndArtwork() throws {
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
        let room = try XCTUnwrap(snapshot.groups.first)
        XCTAssertEqual(room.name, "Living Room + Kitchen")
        XCTAssertEqual(room.nowPlaying.title, "Night Shift")
        XCTAssertEqual(room.nowPlaying.statusLine, "Night Shift")
        XCTAssertEqual(room.groupVolume, 22)
        XCTAssertEqual(room.members.first?.volume, 18)
        XCTAssertEqual(room.artworkURL?.host, "192.168.1.20")
        XCTAssertFalse(snapshot.isDiscovering)
    }

    func testEventServerAcceptsNotify() async throws {
        let server = EventServer()
        try server.start()
        defer { server.stop() }
        XCTAssertGreaterThan(server.port, 0)
        let body = "<e:propertyset><e:property><LastChange>ok</LastChange></e:property></e:propertyset>"
        let payload = """
        NOTIFY /event HTTP/1.1\r
        HOST: 127.0.0.1:\(server.port)\r
        SID: uuid:test-sid\r
        CONTENT-LENGTH: \(body.utf8.count)\r
        \r
        \(body)
        """
        try sendLocal(payload, port: server.port)
        let deadline = Date().addingTimeInterval(2)
        var found: EventNotification?
        while Date() < deadline {
            found = server.notifications().first
            if found != nil { break }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        let note = try XCTUnwrap(found)
        XCTAssertEqual(note.sid, "uuid:test-sid")
        XCTAssertEqual(note.path, "/event")
        XCTAssertTrue(note.body.contains("LastChange"))
    }

    private func sendLocal(_ text: String, port: UInt16) {
        rawSend(text, port)
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
