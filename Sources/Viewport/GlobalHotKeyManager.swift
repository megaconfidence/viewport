import AppKit

/// Owns the Carbon-backed `GlobalHotKey`, observes the store for shortcut
/// changes, and exposes the latest registration error so the UI can surface it.
@MainActor
final class GlobalHotKeyManager {
    static let errorDidChangeNotification = Notification.Name("GlobalHotKeyManagerErrorDidChange")

    private let store: ResizePresetStore
    private let hotKey = GlobalHotKey()
    private(set) var registrationError: Error?

    init(store: ResizePresetStore) {
        self.store = store
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refresh),
            name: ResizePresetStore.shortcutDidChangeNotification,
            object: store
        )
        refresh()
    }

    @objc func refresh() {
        guard let shortcut = store.applyLastPresetShortcut else {
            hotKey.unregisterHotKey()
            updateError(nil)
            return
        }

        do {
            try hotKey.registerShortcut(shortcut)
            updateError(nil)
        } catch {
            updateError(error)
        }
    }

    private func updateError(_ error: Error?) {
        let hadError = registrationError != nil
        registrationError = error
        let hasError = error != nil

        guard hadError || hasError else {
            return
        }

        NotificationCenter.default.post(
            name: Self.errorDidChangeNotification,
            object: self
        )
    }
}
