import Foundation

/// One wired network interface, as System Settings › Network lists it.
public struct EthernetInterface: Sendable, Equatable, Identifiable {
    /// BSD name, such as `en15`.
    public var device: String
    /// Localized name, such as "USB 10/100/1G/2.5G LAN".
    public var name: String
    /// Controller model and vendor from the I/O Registry, when the driver publishes them.
    public var model: String?
    public var vendor: String?
    /// Uppercase, colon separated.
    public var macAddress: String?
    public var ipv4: [String]
    public var ipv6: [String]
    /// A cable is plugged in and the link is up.
    public var linkActive: Bool

    public var id: String { device }

    public init(
        device: String, name: String, model: String? = nil, vendor: String? = nil, macAddress: String? = nil,
        ipv4: [String] = [], ipv6: [String] = [], linkActive: Bool = false
    ) {
        self.device = device
        self.name = name
        self.model = model
        self.vendor = vendor
        self.macAddress = macAddress?.uppercased()
        self.ipv4 = ipv4
        self.ipv6 = IPAddress.sortedIPv6(ipv6)
        self.linkActive = linkActive
    }

    /// Thunderbolt ports report themselves as Ethernet; they only matter while a Thunderbolt network is plugged in.
    public var isIdleThunderboltPort: Bool { model == "ThunderboltIP" && !linkActive }

    /// Interfaces with a link first, then by device name in natural order (en6 before en15).
    static func displayOrder(_ a: EthernetInterface, _ b: EthernetInterface) -> Bool {
        if a.linkActive != b.linkActive { return a.linkActive }
        return a.device.localizedStandardCompare(b.device) == .orderedAscending
    }
}

/// The wired side of the network at one moment.
public struct NetworkSnapshot: Sendable, Equatable {
    public var interfaces: [EthernetInterface]
    /// The interface that carries the default route (`State:/Network/Global/IPv4`, or IPv6 when there is no IPv4).
    public var primaryInterface: String?

    public init(interfaces: [EthernetInterface], primaryInterface: String?) {
        self.interfaces = interfaces.filter { !$0.isIdleThunderboltPort }.sorted(by: EthernetInterface.displayOrder)
        self.primaryInterface = primaryInterface
    }

    public static let empty = NetworkSnapshot(interfaces: [], primaryInterface: nil)

    /// Some wired interface has a link.
    public var isConnected: Bool { interfaces.contains(where: \.linkActive) }

    /// Traffic goes out through a wired interface (it is the primary one, ahead of Wi-Fi).
    public var isActive: Bool { activeInterface != nil }

    public var activeInterface: EthernetInterface? {
        interfaces.first { $0.linkActive && $0.device == primaryInterface }
    }
}
