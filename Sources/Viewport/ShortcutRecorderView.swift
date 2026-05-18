import AppKit
import Carbon

/// A click-to-record control that captures a keyboard shortcut.
/// - Click the view to enter recording mode.
/// - Press Modifier(s) + a non-modifier key to capture.
/// - Press Escape to cancel.
/// - Press Delete (no modifiers) to clear the existing shortcut.
@MainActor
final class ShortcutRecorderView: NSView {
    var onChange: ((Shortcut?) -> Void)?

    private(set) var shortcut: Shortcut? {
        didSet {
            updateAppearance()
        }
    }

    private var isRecording = false {
        didSet { updateAppearance() }
    }

    private let label = NSTextField(labelWithString: "")
    private let clearButton = NSButton()

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        label.alignment = .center
        label.isSelectable = false
        addSubview(label)

        clearButton.isBordered = false
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear shortcut")
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.imageScaling = .scaleProportionallyDown
        clearButton.target = self
        clearButton.action = #selector(handleClear)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.isHidden = true
        addSubview(clearButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 110),

            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -4),

            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            clearButton.widthAnchor.constraint(equalToConstant: 14),
            clearButton.heightAnchor.constraint(equalToConstant: 14)
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setShortcut(_ shortcut: Shortcut?) {
        self.shortcut = shortcut
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            return
        }
        window?.makeFirstResponder(self)
        isRecording = true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else {
            return super.performKeyEquivalent(with: event)
        }
        return capture(event: event)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        _ = capture(event: event)
    }

    @discardableResult
    private func capture(event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let keyCode = Int(event.keyCode)

        if keyCode == kVK_Escape, modifiers.isEmpty {
            window?.makeFirstResponder(nil)
            return true
        }

        if (keyCode == kVK_Delete || keyCode == kVK_ForwardDelete), modifiers.isEmpty {
            commit(nil)
            return true
        }

        guard !modifiers.isEmpty else {
            return false
        }

        if isModifierKeyCode(keyCode) {
            return false
        }

        let display = displayName(for: keyCode, event: event)
        guard !display.isEmpty else {
            return false
        }

        let new = Shortcut(
            keyCode: keyCode,
            modifierFlagsRawValue: modifiers.rawValue,
            characterDisplay: display
        )
        commit(new)
        return true
    }

    private func commit(_ new: Shortcut?) {
        shortcut = new
        window?.makeFirstResponder(nil)
        onChange?(new)
    }

    @objc private func handleClear() {
        commit(nil)
    }

    private func isModifierKeyCode(_ keyCode: Int) -> Bool {
        switch keyCode {
        case kVK_Command, kVK_RightCommand,
             kVK_Shift, kVK_RightShift,
             kVK_Option, kVK_RightOption,
             kVK_Control, kVK_RightControl,
             kVK_CapsLock, kVK_Function:
            return true
        default:
            return false
        }
    }

    private func displayName(for keyCode: Int, event: NSEvent) -> String {
        switch keyCode {
        case kVK_Space: return "Space"
        case kVK_Return, kVK_ANSI_KeypadEnter: return "\u{21A9}"
        case kVK_Tab: return "\u{21E5}"
        case kVK_Delete: return "\u{232B}"
        case kVK_ForwardDelete: return "\u{2326}"
        case kVK_Escape: return "\u{238B}"
        case kVK_LeftArrow: return "\u{2190}"
        case kVK_RightArrow: return "\u{2192}"
        case kVK_UpArrow: return "\u{2191}"
        case kVK_DownArrow: return "\u{2193}"
        case kVK_Home: return "\u{2196}"
        case kVK_End: return "\u{2198}"
        case kVK_PageUp: return "\u{21DE}"
        case kVK_PageDown: return "\u{21DF}"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            let characters = event.charactersIgnoringModifiers ?? ""
            return characters.uppercased()
        }
    }

    private func updateAppearance() {
        if isRecording {
            label.stringValue = "Press shortcut\u{2026}"
            label.textColor = .tertiaryLabelColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.borderWidth = 2
            clearButton.isHidden = true
        } else if let shortcut {
            label.stringValue = shortcut.displayString
            label.textColor = .labelColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.borderWidth = 1
            clearButton.isHidden = false
        } else {
            label.stringValue = "Click to record"
            label.textColor = .tertiaryLabelColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.borderWidth = 1
            clearButton.isHidden = true
        }
    }
}
