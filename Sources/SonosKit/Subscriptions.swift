import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum EventSubscription {
    static func subscribe(host: String, port: Int, path: String, callback: String, timeout: TimeInterval = 8) async throws -> (sid: String, seconds: Int) {
        let response = try await request(
            host: host,
            port: port,
            path: path,
            method: "SUBSCRIBE",
            headers: [
                "CALLBACK": callback,
                "NT": "upnp:event",
                "TIMEOUT": "Second-600",
            ],
            timeout: timeout
        )
        guard let sid = header(response, "sid"), !sid.isEmpty else {
            throw SonosError(message: "The speaker did not start an event subscription.")
        }
        return (sid, seconds(header(response, "timeout")) ?? 600)
    }

    static func renew(host: String, port: Int, path: String, sid: String, timeout: TimeInterval = 8) async throws -> Int {
        let response = try await request(
            host: host,
            port: port,
            path: path,
            method: "SUBSCRIBE",
            headers: [
                "SID": sid,
                "TIMEOUT": "Second-600",
            ],
            timeout: timeout
        )
        return seconds(header(response, "timeout")) ?? 600
    }

    static func unsubscribe(host: String, port: Int, path: String, sid: String) async {
        _ = try? await request(
            host: host,
            port: port,
            path: path,
            method: "UNSUBSCRIBE",
            headers: ["SID": sid],
            timeout: 3
        )
    }

    private static func request(
        host: String,
        port: Int,
        path: String,
        method: String,
        headers: [String: String],
        timeout: TimeInterval
    ) async throws -> HTTPURLResponse {
        guard NetworkPolicy.isAllowedHost(host), let url = URL(string: "http://\(host):\(port)\(path)") else {
            throw SonosError(message: "Refusing a subscription off the local network.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw SonosError(code: code, message: "Event subscription failed.")
        }
        return http
    }

    private static func header(_ response: HTTPURLResponse, _ name: String) -> String? {
        for (key, value) in response.allHeaderFields {
            if String(describing: key).caseInsensitiveCompare(name) == .orderedSame {
                return String(describing: value)
            }
        }
        return nil
    }

    private static func seconds(_ header: String?) -> Int? {
        guard let header else { return nil }
        let digits = header.filter(\.isNumber)
        return Int(digits)
    }
}
