import Darwin
import Foundation
import IOKit
import SystemConfiguration

/// Reads the wired interfaces from SystemConfiguration (names, MAC, link), the I/O Registry (model, vendor) and
/// getifaddrs (addresses).
public enum InterfaceReader {
    public static func snapshot(store: SCDynamicStore?) -> NetworkSnapshot {
        let addresses = addressesByDevice()
        let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        let interfaces = all.compactMap { interface -> EthernetInterface? in
            guard SCNetworkInterfaceGetInterfaceType(interface) as String? == kSCNetworkInterfaceTypeEthernet as String,
                  let device = SCNetworkInterfaceGetBSDName(interface) as String?
            else { return nil }
            let registry = registryInfo(device: device)
            return EthernetInterface(
                device: device,
                name: SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? device,
                model: registry.model,
                vendor: registry.vendor,
                macAddress: SCNetworkInterfaceGetHardwareAddressString(interface) as String?,
                ipv4: addresses[device]?.ipv4 ?? [],
                ipv6: addresses[device]?.ipv6 ?? [],
                linkActive: linkActive(device: device, store: store)
            )
        }
        return NetworkSnapshot(interfaces: interfaces, primaryInterface: primaryInterface(store: store))
    }

    static func linkActive(device: String, store: SCDynamicStore?) -> Bool {
        let link = SCDynamicStoreCopyValue(store, "State:/Network/Interface/\(device)/Link" as CFString) as? [String: Any]
        return link?["Active"] as? Bool ?? false
    }

    static func primaryInterface(store: SCDynamicStore?) -> String? {
        for key in ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] {
            let global = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
            if let device = global?["PrimaryInterface"] as? String { return device }
        }
        return nil
    }

    /// IOModel / IOVendor live on the network controller, a parent of the interface's I/O Registry entry.
    static func registryInfo(device: String) -> (model: String?, vendor: String?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOBSDNameMatching(kIOMainPortDefault, 0, device))
        guard service != IO_OBJECT_NULL else { return (nil, nil) }
        defer { IOObjectRelease(service) }
        let options = IOOptionBits(kIORegistryIterateParents | kIORegistryIterateRecursively)
        func property(_ key: String) -> String? {
            let value = IORegistryEntrySearchCFProperty(service, kIOServicePlane, key as CFString, kCFAllocatorDefault, options)
            guard let text = (value as? String)?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
            return text
        }
        return (property("IOModel"), property("IOVendor"))
    }

    struct Addresses {
        var ipv4: [String] = []
        var ipv6: [String] = []
    }

    static func addressesByDevice() -> [String: Addresses] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [:] }
        defer { freeifaddrs(head) }
        var result: [String: Addresses] = [:]
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let socketAddress = entry.pointee.ifa_addr else { continue }
            let device = String(cString: entry.pointee.ifa_name)
            switch Int32(socketAddress.pointee.sa_family) {
            case AF_INET:
                let address = socketAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                result[device, default: Addresses()].ipv4.append(IPAddress.string(address))
            case AF_INET6:
                let address = socketAddress.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                result[device, default: Addresses()].ipv6.append(IPAddress.string(address))
            default:
                continue
            }
        }
        return result
    }
}
