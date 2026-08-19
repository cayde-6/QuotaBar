import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: QuotaStore?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = QuotaStore()
        self.store = store
        self.statusBarController = StatusBarController(store: store)

        // Kicks off the first fetch plus the recurring 5-minute auto-refresh loop.
        store.start()
    }
}
