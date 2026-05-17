import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let presetStore = ResizePresetStore()
    private let resizer = WindowResizer()
    private var lastActiveApplication: NSRunningApplication?
    private var presetEditorWindowController: PresetEditorWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        rebuildMenu()
        startTrackingActiveApplication()
        startObservingPresetChanges()

        if !AccessibilityPermission.isTrusted {
            AccessibilityPermission.requestAccess()
        }
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "arrow.up.left.and.arrow.down.right",
                accessibilityDescription: "Viewport"
            )
            button.imagePosition = .imageOnly
        }

        menu.delegate = self
        statusItem.menu = menu
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let titleItem = NSMenuItem(title: "Viewport", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        var needsSectionSeparator = false

        for orientation in ResizePresetOrientation.allCases {
            let presets = presetStore.enabledPresets(for: orientation)
            guard !presets.isEmpty else {
                continue
            }

            if needsSectionSeparator {
                menu.addItem(.separator())
            }

            menu.addItem(sectionTitleItem(orientation.rawValue))
            presets.map(menuItem).forEach(menu.addItem)

            needsSectionSeparator = true
        }

        if !needsSectionSeparator {
            let emptyItem = NSMenuItem(title: "No Presets Enabled", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        }

        menu.addItem(.separator())

        let editPresetsItem = NSMenuItem(title: "Choose Presets...", action: #selector(openPresetEditor), keyEquivalent: ",")
        editPresetsItem.target = self
        menu.addItem(editPresetsItem)

        menu.addItem(.separator())

        let permissionTitle = AccessibilityPermission.isTrusted ? "Accessibility Permission Granted" : "Grant Accessibility Permission..."
        let permissionItem = NSMenuItem(title: permissionTitle, action: #selector(openAccessibilitySettings), keyEquivalent: "")
        permissionItem.target = self
        permissionItem.isEnabled = !AccessibilityPermission.isTrusted
        menu.addItem(permissionItem)

        menu.addItem(.separator())

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

        do {
            try resizer.resizeFocusedWindow(to: preset.preset.size, preferredApplication: lastActiveApplication)
        } catch WindowResizeError.accessibilityPermissionMissing {
            AccessibilityPermission.requestAccess()
            showPermissionAlert()
        } catch {
            showError(error)
        }
    }

    @objc private func openPresetEditor() {
        if presetEditorWindowController == nil {
            presetEditorWindowController = PresetEditorWindowController(store: presetStore)
        }

        NSApp.activate(ignoringOtherApps: true)
        presetEditorWindowController?.showWindow(nil)
        presetEditorWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityPermission.requestAccess()
        AccessibilityPermission.openSettings()
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
    }

    @objc private func presetsDidChange(_ notification: Notification) {
        rebuildMenu()
        presetEditorWindowController?.refresh()
    }

    private func menuItem(for preset: ResizePreset) -> NSMenuItem {
        let item = NSMenuItem(title: preset.title, action: #selector(resizeToPreset(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = ResizePresetMenuValue(preset: preset)
        return item
    }

    private func sectionTitleItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
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
        alert.informativeText = "Enable Viewport in System Settings > Privacy & Security > Accessibility, then choose a size again."
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
