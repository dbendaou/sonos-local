import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum CSocket {
    static var datagram: Int32 {
        #if canImport(Glibc)
        Int32(SOCK_DGRAM.rawValue)
        #else
        SOCK_DGRAM
        #endif
    }

    static var stream: Int32 {
        #if canImport(Glibc)
        Int32(SOCK_STREAM.rawValue)
        #else
        SOCK_STREAM
        #endif
    }

    static func localIPv4() -> [String] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }
        var results: [String] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let flags = UInt32(current.pointee.ifa_flags)
            if flags & UInt32(IFF_UP) != 0, flags & UInt32(IFF_LOOPBACK) == 0, let address = current.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET) {
                var sin = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                if inet_ntop(AF_INET, &sin.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                    let host = String(cString: buffer)
                    if NetworkPolicy.isAllowedHost(host) {
                        results.append(host)
                    }
                }
            }
            cursor = current.pointee.ifa_next
        }
        return results
    }

    static func localAddress(reaching host: String) -> String? {
        let fd = socket(AF_INET, datagram, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = in_port_t(UInt16(9).bigEndian)
        guard inet_pton(AF_INET, host, &dest.sin_addr) == 1 else { return nil }
        let connected = withUnsafePointer(to: &dest) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
                connect(fd, sock, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return nil }
        var local = sockaddr_in()
        let named: Bool = withUnsafeMutablePointer(to: &local) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
                var length = socklen_t(MemoryLayout<sockaddr_in>.size)
                return getsockname(fd, sock, &length) == 0
            }
        }
        guard named else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &local.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
        return String(cString: buffer)
    }

    static func ssdpSearch(timeout: TimeInterval = 1.6) -> [SSDPResponse] {
        let fd = socket(AF_INET, datagram, 0)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        var reuse: Int32 = 1
        setsockopt(fd, Int32(SOL_SOCKET), Int32(SO_REUSEADDR), &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = in_addr_t(0)
        let bound = withUnsafePointer(to: &addr) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
                bind(fd, sock, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return [] }
        var ttl: UInt8 = 4
        setsockopt(fd, Int32(IPPROTO_IP), Int32(IP_MULTICAST_TTL), &ttl, socklen_t(MemoryLayout<UInt8>.size))
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | Int32(O_NONBLOCK))

        let interfaces = localIPv4()
        let targets = interfaces.isEmpty ? [nil as String?] : interfaces.map { Optional($0) }
        for iface in targets {
            if let iface {
                var ifaceAddr = in_addr()
                if inet_pton(AF_INET, iface, &ifaceAddr) == 1 {
                    setsockopt(fd, Int32(IPPROTO_IP), Int32(IP_MULTICAST_IF), &ifaceAddr, socklen_t(MemoryLayout<in_addr>.size))
                }
            }
            sendSearch(fd: fd)
        }
        if interfaces.isEmpty {
            sendSearch(fd: fd)
        }

        var found: [String: SSDPResponse] = [:]
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            var pollItem = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let remaining = Int32(max(0, deadline.timeIntervalSinceNow) * 1000)
            let ready = poll(&pollItem, 1, min(remaining, 250))
            if ready <= 0 { continue }
            while true {
                var storage = sockaddr_in()
                let count = withUnsafeMutablePointer(to: &storage) { pointer -> Int in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
                        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
                        return buffer.withUnsafeMutableBytes { raw in
                            guard let base = raw.baseAddress else { return 0 }
                            return recvfrom(fd, base, raw.count, 0, sock, &length)
                        }
                    }
                }
                if count <= 0 { break }
                let text = String(decoding: buffer.prefix(count), as: UTF8.self)
                if let response = SSDPResponse.parse(text) {
                    found[response.location] = response
                }
            }
        }
        return Array(found.values)
    }

    private static func sendSearch(fd: Int32) {
        let payload = """
        M-SEARCH * HTTP/1.1\r
        HOST: 239.255.255.250:1900\r
        MAN: \"ssdp:discover\"\r
        MX: 1\r
        ST: urn:schemas-upnp-org:device:ZonePlayer:1\r
        USER-AGENT: macOS/14 UPnP/1.1 SonosLocal/0.1\r
        \r

        """
        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = in_port_t(UInt16(1900).bigEndian)
        guard inet_pton(AF_INET, "239.255.255.250", &dest.sin_addr) == 1 else { return }
        let bytes = Array(payload.utf8)
        _ = bytes.withUnsafeBytes { raw in
            withUnsafePointer(to: &dest) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
                    sendto(fd, raw.baseAddress, raw.count, 0, sock, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}

public struct EventNotification: Equatable, Sendable {
    public var sid: String
    public var body: String
    public var path: String
}

public final class EventServer: @unchecked Sendable {
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var wakeRead: Int32 = -1
    private var wakeWrite: Int32 = -1
    private var started = false
    private var notes: [EventNotification] = []
    public private(set) var port: UInt16 = 0
    public var onNotify: (@Sendable (EventNotification) -> Void)?

    public init() {}

    public func start() throws {
        lock.lock()
        if started {
            lock.unlock()
            return
        }
        let fd = socket(AF_INET, CSocket.stream, 0)
        guard fd >= 0 else {
            lock.unlock()
            throw SonosError(message: "Couldn't open the event port.")
        }
        var reuse: Int32 = 1
        setsockopt(fd, Int32(SOL_SOCKET), Int32(SO_REUSEADDR), &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = in_addr_t(0)
        let bound = withUnsafePointer(to: &addr) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
                bind(fd, sock, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 32) == 0 else {
            close(fd)
            lock.unlock()
            throw SonosError(message: "Couldn't listen for speaker events.")
        }
        var local = sockaddr_in()
        withUnsafeMutablePointer(to: &local) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
                var length = socklen_t(MemoryLayout<sockaddr_in>.size)
                _ = getsockname(fd, sock, &length)
            }
        }
        let resolved = UInt16(bigEndian: local.sin_port)
        var pipes = [Int32](repeating: 0, count: 2)
        guard pipe(&pipes) == 0 else {
            close(fd)
            lock.unlock()
            throw SonosError(message: "Couldn't start the event server.")
        }
        listenFD = fd
        wakeRead = pipes[0]
        wakeWrite = pipes[1]
        port = resolved
        started = true
        lock.unlock()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.loop()
        }
    }

    public func stop() {
        lock.lock()
        let writeFD = wakeWrite
        let listen = listenFD
        started = false
        wakeWrite = -1
        lock.unlock()
        if writeFD >= 0 {
            var byte: UInt8 = 1
            _ = write(writeFD, &byte, 1)
            close(writeFD)
        }
        if listen >= 0 { close(listen) }
    }

    public func notifications() -> [EventNotification] {
        lock.lock()
        defer { lock.unlock() }
        return notes
    }

    private func loop() {
        while true {
            lock.lock()
            let listen = listenFD
            let wake = wakeRead
            let running = started
            lock.unlock()
            if !running || listen < 0 { break }
            var items = [
                pollfd(fd: listen, events: Int16(POLLIN), revents: 0),
                pollfd(fd: wake, events: Int16(POLLIN), revents: 0),
            ]
            let ready = poll(&items, nfds_t(items.count), 1000)
            if ready < 0 { continue }
            if items[1].revents != 0 { break }
            if items[0].revents & Int16(POLLIN) == 0 { continue }
            let client = accept(listen, nil, nil)
            if client >= 0 {
                handle(client)
                close(client)
            }
        }
        lock.lock()
        if wakeRead >= 0 { close(wakeRead) }
        if listenFD >= 0 { close(listenFD) }
        listenFD = -1
        wakeRead = -1
        started = false
        lock.unlock()
    }

    private func handle(_ client: Int32) {
        var collected = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            var item = pollfd(fd: client, events: Int16(POLLIN), revents: 0)
            let ready = poll(&item, 1, 200)
            if ready <= 0 { continue }
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return 0 }
                return recv(client, base, raw.count, 0)
            }
            if count <= 0 { break }
            collected.append(contentsOf: buffer.prefix(count))
            if let note = parse(collected) {
                lock.lock()
                notes.append(note)
                if notes.count > 40 { notes.removeFirst(notes.count - 40) }
                let callback = onNotify
                lock.unlock()
                callback?(note)
                let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                _ = response.withCString { send(client, $0, strlen($0), 0) }
                return
            }
            if collected.count > 1_000_000 { break }
        }
    }

    private func parse(_ data: Data) -> EventNotification? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data.subdata(in: 0..<headerEnd.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let request = lines.first else { return nil }
        let parts = request.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        let length = Int(headers["content-length"] ?? "") ?? 0
        let bodyStart = headerEnd.upperBound
        guard data.count >= bodyStart + length else { return nil }
        let body = String(data: data.subdata(in: bodyStart..<(bodyStart + length)), encoding: .utf8) ?? ""
        return EventNotification(sid: headers["sid"] ?? "", body: body, path: String(parts[1]))
    }
}
