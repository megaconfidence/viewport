import Foundation

@MainActor
final class ResizePresetStore {
    static let didChangeNotification = Notification.Name("ResizePresetStoreDidChange")
    static let shortcutDidChangeNotification = Notification.Name("ResizePresetStoreShortcutDidChange")

    private let defaults: UserDefaults
    private let enabledIDsKey = "enabledResizePresetIDs"
    private let lastUsedPresetKey = "lastUsedResizePresetID"
    private let shortcutKey = "applyLastPresetShortcut"

    private(set) var enabledPresetIDs: Set<String>
    private(set) var lastUsedPresetID: String?
    private(set) var applyLastPresetShortcut: Shortcut?

    var enabledPresets: [ResizePreset] {
        ResizePreset.predefined.filter { enabledPresetIDs.contains($0.id) }
    }

    var lastUsedPreset: ResizePreset? {
        guard let lastUsedPresetID,
              enabledPresetIDs.contains(lastUsedPresetID) else {
            return nil
        }

        return ResizePreset.predefined.first { $0.id == lastUsedPresetID }
    }

    func enabledPresets(for orientation: ResizePresetOrientation) -> [ResizePreset] {
        enabledPresets.filter { $0.orientation == orientation }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.enabledPresetIDs = Self.loadEnabledPresetIDs(from: defaults, key: enabledIDsKey)
        self.lastUsedPresetID = Self.loadLastUsedPresetID(from: defaults, key: lastUsedPresetKey)
        self.applyLastPresetShortcut = Self.loadShortcut(from: defaults, key: shortcutKey)
    }

    func isEnabled(_ preset: ResizePreset) -> Bool {
        enabledPresetIDs.contains(preset.id)
    }

    func setEnabled(_ isEnabled: Bool, for preset: ResizePreset) {
        if isEnabled {
            enabledPresetIDs.insert(preset.id)
        } else {
            enabledPresetIDs.remove(preset.id)
        }

        saveEnabledIDs()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    func resetToDefaults() {
        enabledPresetIDs = ResizePreset.defaultEnabledIDs
        saveEnabledIDs()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    func markLastUsed(_ preset: ResizePreset) {
        guard lastUsedPresetID != preset.id else {
            return
        }

        lastUsedPresetID = preset.id
        defaults.set(preset.id, forKey: lastUsedPresetKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    func setApplyLastPresetShortcut(_ shortcut: Shortcut?) {
        applyLastPresetShortcut = shortcut

        if let shortcut, let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: shortcutKey)
        } else {
            defaults.removeObject(forKey: shortcutKey)
        }

        NotificationCenter.default.post(name: Self.shortcutDidChangeNotification, object: self)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func saveEnabledIDs() {
        defaults.set(Array(enabledPresetIDs).sorted(), forKey: enabledIDsKey)
    }

    private static func loadEnabledPresetIDs(from defaults: UserDefaults, key: String) -> Set<String> {
        guard let savedIDs = defaults.array(forKey: key) as? [String] else {
            return ResizePreset.defaultEnabledIDs
        }

        let validIDs = Set(ResizePreset.predefined.map(\.id))
        return Set(savedIDs).intersection(validIDs)
    }

    private static func loadLastUsedPresetID(from defaults: UserDefaults, key: String) -> String? {
        guard let id = defaults.string(forKey: key) else {
            return ResizePreset.defaultLastUsedID
        }

        guard ResizePreset.predefined.contains(where: { $0.id == id }) else {
            return ResizePreset.defaultLastUsedID
        }

        return id
    }

    private static func loadShortcut(from defaults: UserDefaults, key: String) -> Shortcut? {
        guard defaults.object(forKey: key) != nil else {
            return .defaultApplyLastPreset
        }

        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }
}
