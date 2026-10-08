import Foundation
import SystemConfiguration

/// Watches the dynamic store for link, address and route changes and publishes a fresh snapshot after each burst.
@MainActor
public final class NetworkMonitor {
    public private(set) var snapshot: NetworkSnapshot = .empty
    public var onChange: ((NetworkSnapshot) -> Void)?

    private var store: SCDynamicStore?
    private var refreshTask: Task<Void, Never>?

    public init() {}

    public func start() {
        guard store == nil else { return }
        // The monitor lives as long as the app, so an unretained pointer is enough.
        var context = SCDynamicStoreContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        store = SCDynamicStoreCreate(nil, "Freewire" as CFString, { _, _, info in
            guard let info else { return }
            let monitor = Unmanaged<NetworkMonitor>.fromOpaque(info).takeUnretainedValue()
            // The run loop source is on the main run loop.
            MainActor.assumeIsolated { monitor.scheduleRefresh() }
        }, &context)
        guard let store else { return }

        let keys = ["State:/Network/Interface", "State:/Network/Global/IPv4", "State:/Network/Global/IPv6"]
        let patterns = ["State:/Network/Interface/[^/]+/(Link|IPv4|IPv6)"]
        SCDynamicStoreSetNotificationKeys(store, keys as CFArray, patterns as CFArray)
        if let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0) {
            // Common modes, so the icon still updates while the menu is open.
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        refresh()
    }

    public func refresh() {
        let next = InterfaceReader.snapshot(store: store)
        let changed = next != snapshot
        snapshot = next
        if changed { onChange?(next) }
    }

    /// One change (plugging a cable in) fires several keys within a few hundred milliseconds.
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
