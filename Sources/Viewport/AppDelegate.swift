import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let presetStore = ResizePresetStore()
    private let resizer = WindowResizer()
    private lazy var hotKeyManager = GlobalHotKeyManager(store: presetStore)
    private let launchAtLoginManager = LaunchAtLoginManager()
    private var lastActiveApplication: NSRunningApplication?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        rebuildMenu()
        startTrackingActiveApplication()
        startObservingPresetChanges()
        startObservingWindowVisibility()
        startObservingGlobalHotKey()
        startObservingHotKeyManager()
        _ = hotKeyManager // force creation so registration happens at launch

        if !AccessibilityPermission.isTrusted {
            AccessibilityPermission.requestAccess()
        }
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            let baseImage = NSImage(systemSymbolName: "aspectratio", accessibilityDescription: "Viewport")
                ?? NSImage(systemSymbolName: "rectangle.inset.filled", accessibilityDescription: "Viewport")
                ?? NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Viewport")
            let configured = baseImage?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            ) ?? baseImage
            configured?.isTemplate = true
            button.image = configured
            button.imagePosition = .imageOnly
            button.toolTip = "Viewport"
        }

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        var needsSectionSpacing = false

        for orientation in ResizePresetOrientation.allCases {
            let presets = presetStore.enabledPresets(for: orientation)
            guard !presets.isEmpty else {
                continue
            }

            if needsSectionSpacing {
                menu.addItem(.separator())
            }

            menu.addItem(sectionHeaderItem(orientation.rawValue))
            presets.map(menuItem).forEach(menu.addItem)

            needsSectionSpacing = true
        }

        if !needsSectionSpacing {
            let emptyItem = NSMenuItem(title: "No Presets Enabled", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        if !AccessibilityPermission.isTrusted {
            menu.addItem(.separator())
            let permissionItem = NSMenuItem(
                title: "Grant Accessibility Permission\u{2026}",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            permissionItem.target = self
            menu.addItem(permissionItem)
        }

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About Viewport", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit Viewport", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        rememberCurrentFrontmostApplication()
        rebuildMenu()
    }

    @objc private func resizeToPreset(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? ResizePresetMenuValue else {
            return
        }

        apply(preset.preset, markLastUsed: true)
    }

    @objc private func applyLastUsedPresetFromShortcut(_ notification: Notification) {
        rememberCurrentFrontmostApplication()

        guard let preset = presetStore.lastUsedPreset else {
            NSSound.beep()
            return
        }

        apply(preset, markLastUsed: false)
    }

    private func apply(_ preset: ResizePreset, markLastUsed: Bool) {
        do {
            try resizer.resizeFocusedWindow(to: preset.size, preferredApplication: lastActiveApplication)
            if markLastUsed {
                presetStore.markLastUsed(preset)
            }
        } catch WindowResizeError.accessibilityPermissionMissing {
            AccessibilityPermission.requestAccess()
            showPermissionAlert()
        } catch {
            showError(error)
        }
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(store: presetStore, hotKeyManager: hotKeyManager, launchAtLoginManager: launchAtLoginManager)
        }

        promoteToRegular()
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityPermission.requestAccess()
        AccessibilityPermission.openSettings()
    }

    @objc private func showAbout() {
        promoteToRegular()

        let url = URL(string: "https://github.com/megaconfidence/viewport")!
        let linkText = "github.com/megaconfidence/viewport"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let credits = NSMutableAttributedString(
            string: linkText,
            attributes: [
                .link: url,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.linkColor,
                .paragraphStyle: paragraph
            ]
        )

        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func startTrackingActiveApplication() {
        rememberCurrentFrontmostApplication()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationDidChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func activeApplicationDidChange(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              application.processIdentifier != NSRunningApplication.current.processIdentifier else {
            return
        }

        lastActiveApplication = application
    }

    private func startObservingPresetChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(presetsDidChange(_:)),
            name: ResizePresetStore.didChangeNotification,
            object: presetStore
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutDidChange(_:)),
            name: ResizePresetStore.shortcutDidChangeNotification,
            object: presetStore
        )
    }

    @objc private func presetsDidChange(_ notification: Notification) {
        rebuildMenu()
        settingsWindowController?.refresh()
    }

    @objc private func shortcutDidChange(_ notification: Notification) {
        rebuildMenu()
    }

    @objc private func hotKeyManagerErrorChanged(_ notification: Notification) {
        rebuildMenu()
    }

    private func startObservingWindowVisibility() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    private func startObservingGlobalHotKey() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyLastUsedPresetFromShortcut(_:)),
            name: GlobalHotKey.didPressApplyLastPresetNotification,
            object: nil
        )
    }

    private func startObservingHotKeyManager() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotKeyManagerErrorChanged(_:)),
            name: GlobalHotKeyManager.errorDidChangeNotification,
            object: nil
        )
    }

    @objc private func windowWillClose(_ notification: Notification) {
        // isVisible is still true inside willClose; defer one runloop tick.
        DispatchQueue.main.async { [weak self] in
            self?.demoteIfNoVisibleWindows()
        }
    }

    private func promoteToRegular() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func demoteIfNoVisibleWindows() {
        let hasVisibleWindow = NSApp.windows.contains { window in
            window.isVisible && window.styleMask.contains(.titled)
        }
        if !hasVisibleWindow && NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func menuItem(for preset: ResizePreset) -> NSMenuItem {
        let item = NSMenuItem(title: preset.title, action: #selector(resizeToPreset(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = ResizePresetMenuValue(preset: preset)

        if presetStore.lastUsedPresetID == preset.id,
           hotKeyManager.registrationError == nil,
           let shortcut = presetStore.applyLastPresetShortcut,
           let keyEquivalent = shortcut.menuKeyEquivalent {
            item.keyEquivalent = keyEquivalent
            item.keyEquivalentModifierMask = shortcut.modifierFlags
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        ]
        item.attributedTitle = NSAttributedString(string: preset.title, attributes: attributes)
        return item
    }

    private func sectionHeaderItem(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) {
            return NSMenuItem.sectionHeader(title: title)
        }

        let item = NSMenuItem()
        item.isEnabled = false
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
            .kern: 0.4
        ]
        item.attributedTitle = NSAttributedString(string: title.uppercased(), attributes: attributes)
        return item
    }

    private func rememberCurrentFrontmostApplication() {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != NSRunningApplication.current.processIdentifier else {
            return
        }

        lastActiveApplication = application
    }

    private func showPermissionAlert() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Enable Viewport in System Settings \u{203A} Privacy & Security \u{203A} Accessibility, then choose a size again."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            AccessibilityPermission.openSettings()
        }
    }

    private func showError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert(error: error)
        alert.messageText = "Could Not Resize Window"
        alert.runModal()
    }
}

private final class ResizePresetMenuValue: NSObject {
    let preset: ResizePreset

    init(preset: ResizePreset) {
        self.preset = preset
    }
}
