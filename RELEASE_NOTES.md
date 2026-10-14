- **Works behind a VPN.** With a VPN connected (GlobalProtect, IPsec, WireGuard…) the system's default route goes into a tunnel such as `utun0`, so Freewire said "Active: No" and no interface was bold. Now it follows the tunnel down to the interface its traffic really leaves through: the first service with an address in the network service order, like `scutil --nwi` shows.

Signed with Developer ID, notarized and stapled. macOS 14 or later, Apple silicon. Installs itself on Freewire 1.2.0 or later.
