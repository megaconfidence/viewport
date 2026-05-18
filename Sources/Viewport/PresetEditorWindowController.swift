import AppKit

@MainActor
final class PresetEditorWindowController: NSWindowController {
    private let store: ResizePresetStore
    private var presetCheckboxes: [(preset: ResizePreset, checkbox: NSButton)] = []

    init(store: ResizePresetStore) {
        self.store = store

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Choose Presets"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        buildContent()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func refresh() {
        for item in presetCheckboxes {
            item.checkbox.state = store.isEnabled(item.preset) ? .on : .off
        }
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
        contentView.addSubview(footer)

        NSLayoutConstraint.activate([
            presetStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            presetStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            presetStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),

            footer.topAnchor.constraint(greaterThanOrEqualTo: presetStack.bottomAnchor, constant: 14),
            footer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            footer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            footer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
        ])

        window.defaultButtonCell = doneButton.cell as? NSButtonCell
    }

    private func sectionView(for orientation: ResizePresetOrientation) -> NSView {
        let title = NSTextField(labelWithString: orientation.rawValue.uppercased())
        title.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.translatesAutoresizingMaskIntoConstraints = false

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

    @objc private func togglePreset(_ sender: NSButton) {
        guard presetCheckboxes.indices.contains(sender.tag) else {
            return
        }

        store.setEnabled(sender.state == .on, for: presetCheckboxes[sender.tag].preset)
    }

    @objc private func resetToDefaults() {
        store.resetToDefaults()
    }

    @objc private func closeWindow() {
        close()
    }
}
