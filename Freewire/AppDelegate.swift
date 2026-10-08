import AppKit
import FreewireCore
import OSLog
import ServiceManagement
import SwiftUI

let log = Logger(subsystem: "io.github.sergioarojasm98.freewire", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let monitor = NetworkMonitor()
    private let preferences = Preferences()
    private let publicIP = PublicIPLookup()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var publicIPItem: NSMenuItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = StatusIcon.image
        statusItem.button?.setAccessibilityLabel("Freewire")
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        publicIP.onChange = { [weak self] in self?.publicIPItem?.title = self?.publicIP.title ?? "" }
        preferences.onChange = { [weak self] in self?.preferencesChanged() }
        monitor.onChange = { [weak self] snapshot in self?.networkChanged(snapshot) }
        monitor.start()
        if monitor.snapshot == .empty { networkChanged(.empty) }
        #if DEBUG
        preview(ProcessInfo.processInfo.arguments)
        #endif
    }

    #if DEBUG
    /// For screenshots: `--args -previewMenu`, `-previewDetails en0` or `-previewSettings`.
    private func preview(_ arguments: [String]) {
        guard arguments.contains(where: { $0.hasPrefix("-preview") }) else { return }
        if arguments.contains("-previewSettings") {
            openSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
                guard let view = settingsWindow?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/fw-settings.png"))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
            if arguments.contains("-previewMenu") { statusItem.button?.performClick(nil) }
            if let index = arguments.firstIndex(of: "-previewDetails"), index + 1 < arguments.count,
               let interface = monitor.snapshot.interfaces.first(where: { $0.device == arguments[index + 1] }) {
                details(of: interface).popUp(positioning: nil, at: NSPoint(x: 1300, y: 1050), in: nil)
            }
        }
    }
    #endif

    // MARK: - State changes

    private var lastConnected: Bool?

    private func networkChanged(_ snapshot: NetworkSnapshot) {
        statusItem.button?.appearsDisabled = !snapshot.isConnected
        statusItem.button?.toolTip = snapshot.isConnected ? "Ethernet: Connected" : "Ethernet: Disconnected"
        if let lastConnected, lastConnected != snapshot.isConnected, preferences.notifyOnChange {
            Notifier.post(connected: snapshot.isConnected, snapshot: snapshot)
        }
        lastConnected = snapshot.isConnected
        log.info("network: connected=\(snapshot.isConnected) active=\(snapshot.isActive) primary=\(snapshot.primaryInterface ?? "-")")
        // Give DHCP and the default route a moment to settle before asking for the public address
        if preferences.showPublicIP { publicIP.refresh(after: .seconds(2)) }
    }

    private func preferencesChanged() {
        if preferences.showPublicIP { publicIP.refreshIfStale() }
        if preferences.notifyOnChange { Notifier.requestPermission() }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        if preferences.showPublicIP { publicIP.refreshIfStale() }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let snapshot = monitor.snapshot
        menu.removeAllItems()

        menu.addItem(info("Ethernet: \(snapshot.isConnected ? "Connected" : "Disconnected")"))
        let active = info("Active: \(snapshot.isActive ? "Yes" : "No")")
        // The dot sits in the checkmark column, like the state of "Open at Login"
        active.state = .on
        active.onStateImage = StatusIcon.dot(snapshot.isActive ? .systemGreen : .systemGray)
        menu.addItem(active)
        publicIPItem = nil
        if preferences.showPublicIP {
            let item = info(publicIP.title)
            publicIPItem = item
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Interfaces"))
        let shown = preferences.showAdaptersWithoutLink ? snapshot.interfaces : snapshot.interfaces.filter(\.linkActive)
        if shown.isEmpty {
            menu.addItem(info(snapshot.interfaces.isEmpty ? "No Ethernet Adapters" : "No Cable Connected"))
        }
        for interface in shown {
            let item = NSMenuItem(title: interface.name, action: nil, keyEquivalent: "")
            item.submenu = details(of: interface)
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleOpenAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let about = NSMenuItem(title: "About Freewire", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func details(of interface: EthernetInterface) -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.addItem(info("Device: \(interface.device)"))
        var rows = [
            "Model: \(interface.model ?? "Unknown")",
            "Vendor: \(interface.vendor ?? "Unknown")",
            "MAC Address: \(interface.macAddress ?? "Unknown")",
            "Interface: \(interface.name)",
        ]
        rows += (interface.ipv4.isEmpty ? ["None"] : interface.ipv4).map { "IP Address (ipv4): \($0)" }
        rows += (interface.ipv6.isEmpty ? ["None"] : interface.ipv6).map { "IP Address (ipv6): \($0)" }
        for row in rows {
            let item = info(row)
            item.indentationLevel = 1
            submenu.addItem(item)
        }
        submenu.addItem(info("Status: \(interface.linkActive ? "Connected" : "Disconnected")"))
        return submenu
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    @objc private func toggleOpenAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            log.error("open at login: \(error.localizedDescription)")
            NSApp.activate()
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn’t change Open at Login"
            alert.runModal()
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(preferences: preferences)))
            window.title = "Freewire Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showAbout() {
        NSApp.activate()
        let link = "github.com/sergioarojasm98/freewire"
        let credits = NSAttributedString(string: link, attributes: [
            .link: URL(string: "https://\(link)")!,
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        ])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
