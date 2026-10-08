import Darwin
import Testing
@testable import FreewireCore

struct PublicIPTests {
    @Test func readsTheAddressLine() {
        let trace = "fl=12f34\nh=www.cloudflare.com\nip=165.1.200.27\nts=1791500000.1\nloc=CO\n"
        #expect(PublicIP.parseTrace(trace) == "165.1.200.27")
    }

    @Test func readsIPv6() {
        #expect(PublicIP.parseTrace("ip=2800:e2:1a80::1\r\n") == "2800:e2:1a80::1")
    }

    @Test func rejectsMissingOrBrokenAddresses() {
        #expect(PublicIP.parseTrace("fl=1\nloc=CO\n") == nil)
        #expect(PublicIP.parseTrace("ip=<html>\n") == nil)
        #expect(PublicIP.parseTrace("") == nil)
    }
}

struct IPAddressTests {
    private func ipv6(_ bytes: [UInt8]) -> in6_addr {
        var address = in6_addr()
        withUnsafeMutableBytes(of: &address) { $0.copyBytes(from: bytes) }
        return address
    }

    @Test func clearsTheEmbeddedScopeOfLinkLocal() {
        let kernel = ipv6([0xFE, 0x80, 0x00, 0x0F, 0, 0, 0, 0, 0x1C, 0x46, 0x58, 0xED, 0xBF, 0x5A, 0x59, 0xD6])
        #expect(IPAddress.string(kernel) == "fe80::1c46:58ed:bf5a:59d6")
    }

    @Test func leavesGlobalAddressesAlone() {
        let global = ipv6([0x28, 0x00, 0x00, 0xE2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x01])
        #expect(IPAddress.string(global) == "2800:e2::1")
    }

    @Test func formatsIPv4() {
        #expect(IPAddress.string(in_addr(s_addr: inet_addr("192.168.0.126"))) == "192.168.0.126")
    }

    @Test func putsLinkLocalLast() {
        #expect(IPAddress.sortedIPv6(["fe80::1", "2800:e2::5", "fd00::2"]) == ["2800:e2::5", "fd00::2", "fe80::1"])
    }
}

struct SnapshotTests {
    let usb = EthernetInterface(
        device: "en15", name: "USB 10/100/1G/2.5G LAN", model: "USB", vendor: "USB NCM",
        macAddress: "94:bd:be:84:c5:df", ipv4: ["192.168.0.126"], linkActive: true)
    let adapter6 = EthernetInterface(device: "en6", name: "Ethernet Adapter (en6)")
    let adapter8 = EthernetInterface(device: "en8", name: "Ethernet Adapter (en8)")
    let thunderbolt = EthernetInterface(device: "en2", name: "Thunderbolt 1", model: "ThunderboltIP", vendor: "Apple")

    @Test func ordersLinkedFirstThenNaturally() {
        let snapshot = NetworkSnapshot(interfaces: [adapter8, usb, adapter6], primaryInterface: "en15")
        #expect(snapshot.interfaces.map(\.device) == ["en15", "en6", "en8"])
    }

    @Test func hidesIdleThunderboltPortsOnly() {
        var linked = thunderbolt
        linked.linkActive = true
        #expect(NetworkSnapshot(interfaces: [thunderbolt, adapter6], primaryInterface: nil).interfaces.map(\.device) == ["en6"])
        #expect(NetworkSnapshot(interfaces: [linked], primaryInterface: nil).interfaces.map(\.device) == ["en2"])
    }

    @Test func connectedAndActive() {
        let wired = NetworkSnapshot(interfaces: [usb, adapter6], primaryInterface: "en15")
        #expect(wired.isConnected && wired.isActive)
        #expect(wired.activeInterface?.device == "en15")

        // Cable in, but Wi-Fi (en0) carries the traffic
        let wifiFirst = NetworkSnapshot(interfaces: [usb], primaryInterface: "en0")
        #expect(wifiFirst.isConnected && !wifiFirst.isActive)

        let unplugged = NetworkSnapshot(interfaces: [adapter6, adapter8], primaryInterface: "en0")
        #expect(!unplugged.isConnected && !unplugged.isActive)
        #expect(!NetworkSnapshot.empty.isConnected)
    }

    @Test func uppercasesTheMACAddress() {
        #expect(usb.macAddress == "94:BD:BE:84:C5:DF")
    }
}
