import AppKit

@MainActor
final class PresetEditorWindowController: NSWindowController {
    private let store: ResizePresetStore
    private var presetCheckboxes: [(preset: ResizePreset, checkbox: NSButton)] = []

    init(store: ResizePresetStore) {
        self.store = store

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Choose Presets"
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

        let descriptionLabel = NSTextField(labelWithString: "Choose which landscape and vertical sizes appear in the menu.")
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 8
        stackView.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        presetCheckboxes = []

        for orientation in ResizePresetOrientation.allCases {
            stackView.addArrangedSubview(sectionLabel(orientation.rawValue))

            for preset in ResizePreset.predefined(for: orientation) {
                let checkbox = NSButton(checkboxWithTitle: preset.title, target: self, action: #selector(togglePreset(_:)))
                checkbox.tag = presetCheckboxes.count
                checkbox.state = store.isEnabled(preset) ? .on : .off
                checkbox.translatesAutoresizingMaskIntoConstraints = false
                stackView.addArrangedSubview(checkbox)
                presetCheckboxes.append((preset, checkbox))
            }
        }

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.documentView = stackView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let doneButton = NSButton(title: "Done", target: self, action: #selector(closeWindow))
        doneButton.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(descriptionLabel)
        contentView.addSubview(scrollView)
        contentView.addSubview(doneButton)

        NSLayoutConstraint.activate([
            descriptionLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            descriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            descriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 14),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: doneButton.topAnchor, constant: -16),

            stackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            doneButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            doneButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
    }

    @objc private func togglePreset(_ sender: NSButton) {
        guard presetCheckboxes.indices.contains(sender.tag) else {
            return
        }

        store.setEnabled(sender.state == .on, for: presetCheckboxes[sender.tag].preset)
    }

    @objc private func closeWindow() {
        close()
    }

    private func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .secondaryLabelColor
        return label
    }
}
