import AppKit
import Sparkle

/// Updates from the GitHub releases with Sparkle (feed and public key in Info.plist). Freewire checks on its own every
/// few hours, downloads a new version in the background and installs it right away, relaunching itself: a menu bar app
/// never quits on its own, so Sparkle's usual "install when you quit" would never come. "Check for Updates…" in the
/// menu runs a check now and shows Sparkle's window.
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!

    func start() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    nonisolated func updater(
        _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        log.info("update \(item.displayVersionString) downloaded: installing and relaunching")
        immediateInstallHandler()
        return true
    }
}
