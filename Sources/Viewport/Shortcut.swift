import AppKit
import Carbon

/// A keyboard shortcut captured from the user (modifiers + a non-modifier key).
/// Stored in `UserDefaults` via `Codable`, converted to Carbon parameters for
/// `RegisterEventHotKey`, and rendered with macOS modifier glyphs for display.
struct Shortcut: Codable, Equatable {
    let keyCode: Int
    let modifierFlagsRawValue: UInt
    let characterDisplay: String

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue)
    }

    var carbonKeyCode: UInt32 {
        UInt32(keyCode)
    }

    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        let mods = modifierFlags
        if mods.contains(.control) { flags |= UInt32(controlKey) }
        if mods.contains(.option) { flags |= UInt32(optionKey) }
        if mods.contains(.shift) { flags |= UInt32(shiftKey) }
        if mods.contains(.command) { flags |= UInt32(cmdKey) }
        return flags
    }

    var displayString: String {
        var glyphs = ""
        let mods = modifierFlags
        if mods.contains(.control) { glyphs += "\u{2303}" }
        if mods.contains(.option) { glyphs += "\u{2325}" }
        if mods.contains(.shift) { glyphs += "\u{21E7}" }
        if mods.contains(.command) { glyphs += "\u{2318}" }
        return glyphs + characterDisplay
    }

    /// The single-character keyEquivalent to display on an `NSMenuItem`.
    /// Returns `nil` for special keys (arrows, function keys, etc.) so the
    /// menu hint is suppressed when the printable form is ambiguous.
    var menuKeyEquivalent: String? {
        guard characterDisplay.count == 1,
              let scalar = characterDisplay.unicodeScalars.first,
              scalar.value < 128,
              scalar.properties.isAlphabetic || CharacterSet.alphanumerics.contains(scalar) || scalar.value > 32 else {
            return nil
        }
        return characterDisplay.lowercased()
    }

    static let defaultApplyLastPreset = Shortcut(
        keyCode: kVK_ANSI_V,
        modifierFlagsRawValue: NSEvent.ModifierFlags([.command, .option, .control]).rawValue,
        characterDisplay: "V"
    )
}
