import AppKit

@main
enum FreewireMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate // weak, so keep it alive for the life of the run loop
        withExtendedLifetime(delegate) { app.run() }
    }
}
