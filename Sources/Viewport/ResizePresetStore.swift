import Foundation

@MainActor
final class ResizePresetStore {
    static let didChangeNotification = Notification.Name("ResizePresetStoreDidChange")

    private let defaults: UserDefaults
    private let defaultsKey = "enabledResizePresetIDs"

    private(set) var enabledPresetIDs: Set<String>

    var enabledPresets: [ResizePreset] {
        ResizePreset.predefined.filter { enabledPresetIDs.contains($0.id) }
    }

    func enabledPresets(for orientation: ResizePresetOrientation) -> [ResizePreset] {
        enabledPresets.filter { $0.orientation == orientation }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.enabledPresetIDs = Self.loadEnabledPresetIDs(from: defaults, key: defaultsKey)
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

        save()
    }

    private func save() {
        defaults.set(Array(enabledPresetIDs).sorted(), forKey: defaultsKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private static func loadEnabledPresetIDs(from defaults: UserDefaults, key: String) -> Set<String> {
        guard let savedIDs = defaults.array(forKey: key) as? [String] else {
            return ResizePreset.defaultEnabledIDs
        }

        let validIDs = Set(ResizePreset.predefined.map(\.id))
        return Set(savedIDs).intersection(validIDs)
    }
}
