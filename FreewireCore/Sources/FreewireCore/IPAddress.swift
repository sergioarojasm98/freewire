import Darwin

public enum IPAddress {
    public static func string(_ address: in_addr) -> String {
        var address = address
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count)) != nil else { return "" }
        return text(buffer)
    }

    /// The kernel hands out link-local addresses with the scope id embedded in bytes 2–3 (KAME), so getifaddrs
    /// returns `fe80:f::…` for en15; clear it to get the address System Settings shows.
    public static func string(_ address: in6_addr) -> String {
        var address = address
        withUnsafeMutableBytes(of: &address) { bytes in
            if bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80 {
                bytes[2] = 0
                bytes[3] = 0
            }
        }
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count)) != nil else { return "" }
        return text(buffer)
    }

    private static func text(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    public static func isLinkLocal(_ ipv6: String) -> Bool { ipv6.lowercased().hasPrefix("fe80:") }

    /// Routable addresses first, link-local last; otherwise the order the kernel gave.
    public static func sortedIPv6(_ addresses: [String]) -> [String] {
        addresses.filter { !isLinkLocal($0) } + addresses.filter(isLinkLocal)
    }

    public static func isValid(_ text: String) -> Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return inet_pton(AF_INET, text, &v4) == 1 || inet_pton(AF_INET6, text, &v6) == 1
    }
}
