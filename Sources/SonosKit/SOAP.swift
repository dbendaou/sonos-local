import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum SonosService: String, Sendable, CaseIterable {
    case avTransport = "urn:schemas-upnp-org:service:AVTransport:1"
    case renderingControl = "urn:schemas-upnp-org:service:RenderingControl:1"
    case groupRenderingControl = "urn:schemas-upnp-org:service:GroupRenderingControl:1"
    case contentDirectory = "urn:schemas-upnp-org:service:ContentDirectory:1"
    case zoneGroupTopology = "urn:schemas-upnp-org:service:ZoneGroupTopology:1"
    case alarmClock = "urn:schemas-upnp-org:service:AlarmClock:1"
    case deviceProperties = "urn:schemas-upnp-org:service:DeviceProperties:1"

    public var controlPath: String {
        switch self {
        case .avTransport: return "/MediaRenderer/AVTransport/Control"
        case .renderingControl: return "/MediaRenderer/RenderingControl/Control"
        case .groupRenderingControl: return "/MediaRenderer/GroupRenderingControl/Control"
        case .contentDirectory: return "/MediaServer/ContentDirectory/Control"
        case .zoneGroupTopology: return "/ZoneGroupTopology/Control"
        case .alarmClock: return "/AlarmClock/Control"
        case .deviceProperties: return "/DeviceProperties/Control"
        }
    }

    public var eventPath: String {
        switch self {
        case .avTransport: return "/MediaRenderer/AVTransport/Event"
        case .renderingControl: return "/MediaRenderer/RenderingControl/Event"
        case .groupRenderingControl: return "/MediaRenderer/GroupRenderingControl/Event"
        case .contentDirectory: return "/MediaServer/ContentDirectory/Event"
        case .zoneGroupTopology: return "/ZoneGroupTopology/Event"
        case .alarmClock: return "/AlarmClock/Event"
        case .deviceProperties: return "/DeviceProperties/Event"
        }
    }
}

public enum SOAPEnvelope {
    public static func make(service: String, action: String, arguments: [(String, String)]) -> String {
        let body = arguments.map { name, value in
            "<\(name)>\(XML.escape(value))</\(name)>"
        }.joined()
        return "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
            + "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">"
            + "<s:Body>"
            + "<u:\(action) xmlns:u=\"\(service)\">"
            + body
            + "</u:\(action)>"
            + "</s:Body></s:Envelope>"
    }
}

public enum SOAPResponse {
    public static func values(in xml: String) throws -> [String: String] {
        let root: XMLElement
        do {
            root = try XML.parse(xml)
        } catch {
            throw SonosError(message: "The speaker returned something that was not SOAP.")
        }
        if root.firstDescendant("Fault") != nil || root.firstDescendant("errorCode") != nil {
            let code = Int(root.firstDescendant("errorCode")?.trimmedText ?? "")
            let message = root.firstDescendant("errorDescription")?.trimmedText
                ?? root.firstDescendant("faultstring")?.trimmedText
                ?? "The speaker rejected the command."
            throw SonosError(code: code, message: message)
        }
        let response = root.firstDescendant { $0.name.hasSuffix("Response") }
        let node = response ?? root.firstDescendant("Body") ?? root
        var result: [String: String] = [:]
        for child in node.children where !child.trimmedText.isEmpty || child.children.isEmpty {
            if result[child.name] == nil || !child.trimmedText.isEmpty {
                result[child.name] = child.trimmedText
            }
        }
        return result
    }
}

public struct SOAPClient: Sendable {
    public var session: URLSession
    public var timeout: TimeInterval

    public init(timeout: TimeInterval = 8) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpMaximumConnectionsPerHost = 4
        self.session = URLSession(configuration: configuration)
        self.timeout = timeout
    }

    public func call(url: URL, service: String, action: String, arguments: [(String, String)]) async throws -> [String: String] {
        guard NetworkPolicy.isAllowedURL(url) else {
            throw SonosError(message: "Refusing to contact \(url.host ?? "that host") because it is not on the local network.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(service)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        let payload = SOAPEnvelope.make(service: service, action: action, arguments: arguments)
        request.httpBody = Data(payload.utf8)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SonosError(message: "Couldn't reach the speaker.")
        }
        let text = String(decoding: data, as: UTF8.self)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode), text.isEmpty {
            throw SonosError(code: http.statusCode, message: "Speaker returned HTTP \(http.statusCode).")
        }
        return try SOAPResponse.values(in: text)
    }
}
