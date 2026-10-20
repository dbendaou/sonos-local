import Foundation
#if canImport(Darwin)
import Darwin

final class MDNSDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate, @unchecked Sendable {
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    /// Device-description URL from the Bonjour TXT `location` record, or built from a resolved address.
    var onLocation: (@Sendable (String) -> Void)?

    func start() {
        browser.delegate = self
        browser.includesPeerToPeer = false
        SonosLog.discovery("Bonjour browse _sonos._tcp")
        browser.searchForServices(ofType: "_sonos._tcp.", inDomain: "local.")
    }

    func stop() {
        browser.stop()
        services.removeAll()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        SonosLog.discovery("Bonjour found \(service.name)")
        service.delegate = self
        services.append(service)
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        SonosLog.discovery("Bonjour search failed \(errorDict)")
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        if let data = sender.txtRecordData() {
            let fields = BonjourTXT.parse(data)
            if let location = BonjourTXT.location(in: fields) {
                SonosLog.discovery("Bonjour TXT location \(location)")
                onLocation?(location)
                return
            }
            SonosLog.discovery("Bonjour \(sender.name) resolved without a location TXT")
        }
        guard let addresses = sender.addresses else { return }
        for data in addresses {
            let host: String? = data.withUnsafeBytes { raw in
                guard raw.count >= MemoryLayout<sockaddr_in>.size else { return nil }
                let family = raw.load(as: sockaddr.self).sa_family
                guard family == sa_family_t(AF_INET) else { return nil }
                var addr = raw.load(as: sockaddr_in.self)
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
                return String(cString: buffer)
            }
            if let host, NetworkPolicy.isAllowedHost(host) {
                let location = "http://\(host):1400/xml/device_description.xml"
                SonosLog.discovery("Bonjour address \(location)")
                onLocation?(location)
            }
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        SonosLog.discovery("Bonjour resolve failed for \(sender.name): \(errorDict)")
    }
}
#endif
