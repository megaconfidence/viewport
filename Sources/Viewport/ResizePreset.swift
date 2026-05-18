import CoreGraphics

struct ResizePreset {
    let width: Int
    let height: Int

    var orientation: ResizePresetOrientation {
        width >= height ? .landscape : .vertical
    }

    var id: String {
        "\(width)x\(height)"
    }

    var title: String {
        "\(width) \u{00D7} \(height)"
    }

    var size: CGSize {
        CGSize(width: width, height: height)
    }

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

enum ResizePresetOrientation: String, CaseIterable {
    case landscape = "Horizontal"
    case vertical = "Vertical"
}

extension ResizePreset {
    static let predefined: [ResizePreset] = [
        ResizePreset(width: 2560, height: 1440),
        ResizePreset(width: 1920, height: 1080),
        ResizePreset(width: 1600, height: 900),
        ResizePreset(width: 1440, height: 900),
        ResizePreset(width: 1366, height: 768),
        ResizePreset(width: 1280, height: 720),
        ResizePreset(width: 1440, height: 2560),
        ResizePreset(width: 1080, height: 1920),
        ResizePreset(width: 900, height: 1600),
        ResizePreset(width: 900, height: 1440),
        ResizePreset(width: 768, height: 1366),
        ResizePreset(width: 720, height: 1280)
    ]

    static let defaultEnabledIDs: Set<String> = [
        "1920x1080",
        "1600x900",
        "1280x720",
        "1080x1920"
    ]

    static let defaultLastUsedID = "1920x1080"

    static func predefined(for orientation: ResizePresetOrientation) -> [ResizePreset] {
        predefined.filter { $0.orientation == orientation }
    }
}
