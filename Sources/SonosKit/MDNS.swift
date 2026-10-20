import Foundation
#if canImport(Darwin)
import Darwin

final class MDNSDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate, @unchecked Sendable {
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    var onHost: (@Sendable (String) -> Void)?

    func start() {
        browser.delegate = self
        browser.searchForServices(ofType: "_sonos._tcp.", inDomain: "local.")
    }

    func stop() {
        browser.stop()
        services.removeAll()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        services.append(service)
        service.resolve(withTimeout: 5)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let addresses = sender.addresses else { return }
        for data in addresses {
            let host: String? = data.withUnsafeBytes { raw in
                guard raw.count >= MemoryLayout<sockaddr>.size else { return nil }
                let family = raw.load(as: sockaddr.self).sa_family
                guard family == sa_family_t(AF_INET) else { return nil }
                var addr = raw.load(as: sockaddr_in.self)
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
                return String(cString: buffer)
            }
            if let host, NetworkPolicy.isAllowedHost(host) {
                onHost?(host)
            }
        }
    }
}
#endif
