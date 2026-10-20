import Foundation

public struct XMLElement: Equatable, Sendable {
    public var name: String
    public var attributes: [String: String]
    public var children: [XMLElement]
    public var text: String
    /// Original markup for this element, including its tags.
    public var outerXML: String

    public var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func child(_ name: String) -> XMLElement? {
        children.first { $0.name == name }
    }

    public func children(named name: String) -> [XMLElement] {
        children.filter { $0.name == name }
    }

    public func firstDescendant(_ name: String) -> XMLElement? {
        for child in children {
            if child.name == name { return child }
            if let found = child.firstDescendant(name) { return found }
        }
        return nil
    }

    public func firstDescendant(where predicate: (XMLElement) -> Bool) -> XMLElement? {
        for child in children {
            if predicate(child) { return child }
            if let found = child.firstDescendant(where: predicate) { return found }
        }
        return nil
    }

    public func descendants(named name: String) -> [XMLElement] {
        var found: [XMLElement] = []
        for child in children {
            if child.name == name { found.append(child) }
            found.append(contentsOf: child.descendants(named: name))
        }
        return found
    }

    public func attribute(_ name: String) -> String? {
        attributes[name]
    }
}

public enum XMLError: Error, Equatable {
    case malformed
}

public enum XML {
    public static func parse(_ string: String) throws -> XMLElement {
        var parser = Parser(Array(string.utf8))
        try parser.skipPreamble()
        guard let element = try parser.parseElement() else {
            throw XMLError.malformed
        }
        return element
    }

    public static func escape(_ string: String) -> String {
        var out = ""
        out.reserveCapacity(string.count)
        for character in string {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(character)
            }
        }
        return out
    }
}

private struct Parser {
    let bytes: [UInt8]
    var index: Int = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func skipPreamble() throws {
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            index = 3
        }
        while index < bytes.count {
            skipSpace()
            guard index < bytes.count else { return }
            guard bytes[index] == UInt8(ascii: "<") else { throw XMLError.malformed }
            if peek("<?") {
                try skipPast("?>")
                continue
            }
            if peek("<!--") {
                try skipPast("-->")
                continue
            }
            if peek("<!") {
                try skipPast(">")
                continue
            }
            return
        }
    }

    mutating func parseElement() throws -> XMLElement? {
        guard index < bytes.count, bytes[index] == UInt8(ascii: "<") else { return nil }
        if peek("</") || peek("<!--") || peek("<?") || peek("<!") { return nil }
        let start = index
        index += 1
        let rawName = try readName()
        let attributes = try readAttributes()
        let selfClosing = consumeSelfClosing()
        if selfClosing {
            return XMLElement(
                name: localName(rawName),
                attributes: attributes,
                children: [],
                text: "",
                outerXML: slice(start, index)
            )
        }
        var children: [XMLElement] = []
        var text = ""
        while index < bytes.count {
            if peek("</") {
                try skipPast(">")
                return XMLElement(
                    name: localName(rawName),
                    attributes: attributes,
                    children: children,
                    text: text,
                    outerXML: slice(start, index)
                )
            }
            if peek("<!--") {
                try skipPast("-->")
                continue
            }
            if peek("<?") {
                try skipPast("?>")
                continue
            }
            if peek("<![CDATA[") {
                index += "<![CDATA[".utf8.count
                let cdataStart = index
                try skipPast("]]>")
                let cdataEnd = index - "]]>".utf8.count
                text += slice(cdataStart, cdataEnd)
                continue
            }
            if bytes[index] == UInt8(ascii: "<") {
                if let child = try parseElement() {
                    children.append(child)
                } else {
                    throw XMLError.malformed
                }
                continue
            }
            text += readText()
        }
        throw XMLError.malformed
    }

    mutating func readAttributes() throws -> [String: String] {
        var attributes: [String: String] = [:]
        while index < bytes.count {
            skipSpace()
            guard index < bytes.count else { throw XMLError.malformed }
            let byte = bytes[index]
            if byte == UInt8(ascii: ">") || byte == UInt8(ascii: "/") { break }
            let name = try readName()
            skipSpace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: "=") else { throw XMLError.malformed }
            index += 1
            skipSpace()
            let value = try readQuoted()
            attributes[localName(name)] = decode(value)
        }
        return attributes
    }

    mutating func consumeSelfClosing() -> Bool {
        skipSpace()
        if peek("/>") {
            index += 2
            return true
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: ">") {
            index += 1
        }
        return false
    }

    mutating func readName() throws -> String {
        let start = index
        while index < bytes.count {
            let byte = bytes[index]
            let isName = (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
                || (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
                || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
                || byte == UInt8(ascii: ":")
                || byte == UInt8(ascii: "_")
                || byte == UInt8(ascii: "-")
                || byte == UInt8(ascii: ".")
            if !isName { break }
            index += 1
        }
        if start == index { throw XMLError.malformed }
        return slice(start, index)
    }

    mutating func readQuoted() throws -> String {
        guard index < bytes.count else { throw XMLError.malformed }
        let quote = bytes[index]
        guard quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'") else { throw XMLError.malformed }
        index += 1
        let start = index
        while index < bytes.count, bytes[index] != quote {
            index += 1
        }
        guard index < bytes.count else { throw XMLError.malformed }
        let value = slice(start, index)
        index += 1
        return value
    }

    mutating func readText() -> String {
        var raw = ""
        while index < bytes.count, bytes[index] != UInt8(ascii: "<") {
            if bytes[index] == UInt8(ascii: "&") {
                raw += readEntity()
            } else {
                let start = index
                while index < bytes.count, bytes[index] != UInt8(ascii: "<"), bytes[index] != UInt8(ascii: "&") {
                    index += 1
                }
                raw += slice(start, index)
            }
        }
        return raw
    }

    mutating func readEntity() -> String {
        let start = index
        index += 1
        let entityStart = index
        var scanned = 0
        while index < bytes.count, bytes[index] != UInt8(ascii: ";"), bytes[index] != UInt8(ascii: "<"), scanned < 16 {
            index += 1
            scanned += 1
        }
        guard index < bytes.count, bytes[index] == UInt8(ascii: ";") else {
            index = start + 1
            return "&"
        }
        let token = slice(entityStart, index)
        index += 1
        if let decoded = decodeEntityToken(token) {
            return decoded
        }
        return slice(start, index)
    }

    func decodeEntityToken(_ token: String) -> String? {
        switch token {
        case "lt": return "<"
        case "gt": return ">"
        case "amp": return "&"
        case "quot": return "\""
        case "apos": return "'"
        default: break
        }
        if token.hasPrefix("#x"), let value = UInt32(token.dropFirst(2), radix: 16), let scalar = UnicodeScalar(value) {
            return String(scalar)
        }
        if token.hasPrefix("#"), let value = UInt32(token.dropFirst(), radix: 10), let scalar = UnicodeScalar(value) {
            return String(scalar)
        }
        return nil
    }

    func decode(_ string: String) -> String {
        guard string.contains("&") else { return string }
        var parser = Parser(Array(string.utf8))
        return parser.readText()
    }

    mutating func skipSpace() {
        while index < bytes.count, isSpace(bytes[index]) {
            index += 1
        }
    }

    func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    func peek(_ string: String) -> Bool {
        let needle = Array(string.utf8)
        guard index + needle.count <= bytes.count else { return false }
        return Array(bytes[index..<(index + needle.count)]) == needle
    }

    mutating func skipPast(_ marker: String) throws {
        let needle = Array(marker.utf8)
        while index + needle.count <= bytes.count {
            if Array(bytes[index..<(index + needle.count)]) == needle {
                index += needle.count
                return
            }
            index += 1
        }
        throw XMLError.malformed
    }

    func slice(_ start: Int, _ end: Int) -> String {
        guard start >= 0, end >= start, end <= bytes.count else { return "" }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    func localName(_ raw: String) -> String {
        guard let colon = raw.lastIndex(of: ":") else { return raw }
        return String(raw[raw.index(after: colon)...])
    }
}
