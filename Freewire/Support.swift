import AppKit
import FreewireCore
import Observation
import UserNotifications

/// User settings, stored in UserDefaults.
@MainActor
@Observable
final class Preferences {
    var showPublicIP: Bool { didSet { save("showPublicIP", showPublicIP) } }
    var showAdaptersWithoutLink: Bool { didSet { save("showAdaptersWithoutLink", showAdaptersWithoutLink) } }
    var notifyOnChange: Bool { didSet { save("notifyOnChange", notifyOnChange) } }

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: ["showPublicIP": true, "showAdaptersWithoutLink": true, "notifyOnChange": false])
        showPublicIP = defaults.bool(forKey: "showPublicIP")
        showAdaptersWithoutLink = defaults.bool(forKey: "showAdaptersWithoutLink")
        notifyOnChange = defaults.bool(forKey: "notifyOnChange")
    }

    private func save(_ key: String, _ value: Bool) {
        defaults.set(value, forKey: key)
        onChange?()
    }
}

/// Keeps the last public address and refreshes it after network changes, or when the menu opens and it is old.
@MainActor
final class PublicIPLookup {
    private enum State {
        case unknown, checking, found(String), unavailable
    }

    private var state = State.unknown
    private var lastAttempt: Date?
    private var task: Task<Void, Never>?
    var onChange: (() -> Void)?

    var title: String {
        switch state {
        case .unknown, .checking: "Public IP Address: Checking…"
        case let .found(address): "Public IP Address: \(address)"
        case .unavailable: "Public IP Address: Unavailable"
        }
    }

    func refreshIfStale() {
        guard task == nil else { return }
        if let lastAttempt, Date.now.timeIntervalSince(lastAttempt) < 300 { return }
        refresh(after: .zero)
    }

    func refresh(after delay: Duration) {
        task?.cancel()
        task = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard let self, !Task.isCancelled else { return }
            lastAttempt = .now
            if case .found = state {} else { set(.checking) }
            do {
                let address = try await PublicIP.fetch()
                guard !Task.isCancelled else { return }
                set(.found(address))
            } catch {
                guard !Task.isCancelled else { return }
                log.info("public IP lookup failed: \(error.localizedDescription)")
                set(.unavailable)
            }
            task = nil
        }
    }

    private func set(_ new: State) {
        state = new
        onChange?()
    }
}

enum Notifier {
    static func requestPermission() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    @MainActor
    static func post(connected: Bool, snapshot: NetworkSnapshot) {
        let content = UNMutableNotificationContent()
        if connected, let interface = snapshot.interfaces.first(where: \.linkActive) {
            content.title = "Ethernet Connected"
            content.body = ([interface.name] + interface.ipv4.prefix(1)).joined(separator: " · ")
        } else {
            content.title = "Ethernet Disconnected"
            content.body = "No wired link."
        }
        let request = UNNotificationRequest(identifier: "link", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

enum StatusIcon {
    /// `<···>`, the Ethernet glyph of System Settings, as a template image so it follows the menu bar.
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            NSColor.black.set()
            for (outer, inner) in [(2.0, 5.8), (20.0, 16.2)] {
                let chevron = NSBezierPath()
                chevron.move(to: NSPoint(x: inner, y: 13.2))
                chevron.line(to: NSPoint(x: outer, y: 9))
                chevron.line(to: NSPoint(x: inner, y: 4.8))
                chevron.lineWidth = 1.6
                chevron.lineCapStyle = .round
                chevron.lineJoinStyle = .round
                chevron.stroke()
            }
            for x in [8.2, 11.0, 13.8] {
                NSBezierPath(ovalIn: NSRect(x: x - 1, y: 8, width: 2, height: 2)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()

    /// A colored dot as a plain bitmap, so a disabled menu item doesn't tint it gray.
    static func dot(_ color: NSColor) -> NSImage {
        let scale = 2, side = 12
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side * scale, pixelsHigh: side * scale, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
            bitsPerPixel: 0)
        else { return NSImage() }
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.usingColorSpace(.deviceRGB)?.set()
        NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 8, height: 8)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
