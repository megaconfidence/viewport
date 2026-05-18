import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    private let store: ResizePresetStore
    private let hotKeyManager: GlobalHotKeyManager
    private var presetCheckboxes: [(preset: ResizePreset, checkbox: NSButton)] = []
    private weak var shortcutRecorder: ShortcutRecorderView?
    private weak var shortcutErrorLabel: NSTextField?

    init(store: ResizePresetStore, hotKeyManager: GlobalHotKeyManager) {
        self.store = store
        self.hotKeyManager = hotKeyManager

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 340),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        buildContent()
        startObservingHotKeyManager()
        updateShortcutErrorLabel()
        resizeWindowToFit()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func refresh() {
        for item in presetCheckboxes {
            item.checkbox.state = store.isEnabled(item.preset) ? .on : .off
        }
        shortcutRecorder?.setShortcut(store.applyLastPresetShortcut)
        updateShortcutErrorLabel()
    }

    private func buildContent() {
        guard let window else {
            return
        }

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = contentView

        let presetStack = NSStackView()
        presetStack.orientation = .vertical
        presetStack.alignment = .leading
        presetStack.spacing = 14
        presetStack.translatesAutoresizingMaskIntoConstraints = false

        presetCheckboxes = []

        for orientation in ResizePresetOrientation.allCases {
            let section = sectionView(for: orientation)
            presetStack.addArrangedSubview(section)
        }

        let shortcutSection = buildShortcutSection()
        shortcutSection.translatesAutoresizingMaskIntoConstraints = false

        let resetButton = NSButton(title: "Reset", target: self, action: #selector(resetToDefaults))
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .small
        resetButton.translatesAutoresizingMaskIntoConstraints = false

        let doneButton = NSButton(title: "Done", target: self, action: #selector(closeWindow))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.controlSize = .small
        doneButton.translatesAutoresizingMaskIntoConstraints = false

        let footer = NSStackView(views: [resetButton, NSView(), doneButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.distribution = .fill
        footer.spacing = 8
        footer.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(presetStack)
        contentView.addSubview(shortcutSection)
        contentView.addSubview(footer)

        NSLayoutConstraint.activate([
            presetStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            presetStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            presetStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),

            shortcutSection.topAnchor.constraint(equalTo: presetStack.bottomAnchor, constant: 14),
            shortcutSection.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            shortcutSection.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),

            footer.topAnchor.constraint(equalTo: shortcutSection.bottomAnchor, constant: 14),
            footer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            footer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            footer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
        ])

        window.defaultButtonCell = doneButton.cell as? NSButtonCell
    }

    private func sectionView(for orientation: ResizePresetOrientation) -> NSView {
        let title = sectionTitleLabel(orientation.rawValue.uppercased())

        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 4
        grid.columnSpacing = 32
        grid.xPlacement = .leading
        grid.yPlacement = .top

        let presets = ResizePreset.predefined(for: orientation)
        for index in stride(from: 0, to: presets.count, by: 2) {
            let leftView: NSView = makeCheckbox(for: presets[index])
            let rightView: NSView = (index + 1 < presets.count)
                ? makeCheckbox(for: presets[index + 1])
                : NSGridCell.emptyContentView
            grid.addRow(with: [leftView, rightView])
        }

        let section = NSStackView(views: [title, grid])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 6

        return section
    }

    private func buildShortcutSection() -> NSView {
        let title = sectionTitleLabel("SHORTCUT")

        let descriptionLabel = NSTextField(labelWithString: "Apply last preset")
        descriptionLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        descriptionLabel.textColor = .labelColor

        let recorder = ShortcutRecorderView()
        recorder.setShortcut(store.applyLastPresetShortcut)
        recorder.onChange = { [weak self] newShortcut in
            self?.store.setApplyLastPresetShortcut(newShortcut)
        }
        shortcutRecorder = recorder

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [descriptionLabel, spacer, recorder])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        let errorLabel = NSTextField(labelWithString: "")
        errorLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        errorLabel.textColor = .systemRed
        errorLabel.maximumNumberOfLines = 0
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.isHidden = true
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutErrorLabel = errorLabel

        let section = NSStackView(views: [title, row, errorLabel])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 6

        row.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        errorLabel.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true

        return section
    }

    private func sectionTitleLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func makeCheckbox(for preset: ResizePreset) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: preset.title, target: self, action: #selector(togglePreset(_:)))
        checkbox.tag = presetCheckboxes.count
        checkbox.state = store.isEnabled(preset) ? .on : .off
        checkbox.translatesAutoresizingMaskIntoConstraints = false

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        ]
        checkbox.attributedTitle = NSAttributedString(string: preset.title, attributes: attributes)

        presetCheckboxes.append((preset, checkbox))
        return checkbox
    }

    private func startObservingHotKeyManager() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotKeyErrorChanged(_:)),
            name: GlobalHotKeyManager.errorDidChangeNotification,
            object: hotKeyManager
        )
    }

    @objc private func hotKeyErrorChanged(_ notification: Notification) {
        updateShortcutErrorLabel()
        resizeWindowToFit()
    }

    private func updateShortcutErrorLabel() {
        let error = hotKeyManager.registrationError
        let message = error?.localizedDescription
        shortcutErrorLabel?.stringValue = message ?? ""
        shortcutErrorLabel?.isHidden = message == nil
    }

    private func resizeWindowToFit() {
        guard let window, let contentView = window.contentView else {
            return
        }

        window.layoutIfNeeded()
        let fittingHeight = contentView.fittingSize.height
        let currentFrame = window.frame
        let newContentSize = NSSize(width: 380, height: fittingHeight)
        let newFrame = window.frameRect(forContentRect: NSRect(origin: currentFrame.origin, size: newContentSize))
        window.setFrame(NSRect(
            origin: NSPoint(x: currentFrame.minX, y: currentFrame.maxY - newFrame.height),
            size: newFrame.size
        ), display: true, animate: false)
    }

    @objc private func togglePreset(_ sender: NSButton) {
        guard presetCheckboxes.indices.contains(sender.tag) else {
            return
        }

        store.setEnabled(sender.state == .on, for: presetCheckboxes[sender.tag].preset)
    }

    @objc private func resetToDefaults() {
        store.resetToDefaults()
        store.setApplyLastPresetShortcut(.defaultApplyLastPreset)
    }

    @objc private func closeWindow() {
        close()
    }
}
