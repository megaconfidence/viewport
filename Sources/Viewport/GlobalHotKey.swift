import Carbon
import Foundation

final class GlobalHotKey {
    static let didPressApplyLastPresetNotification = Notification.Name("GlobalHotKeyDidPressApplyLastPreset")

    private static let signature: OSType = 0x56505254 // VPRT
    private static let applyLastPresetID: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    deinit {
        unregister()
    }

    func registerShortcut(_ shortcut: Shortcut) throws {
        unregisterHotKey()
        try installEventHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: Self.applyLastPresetID
        )
        let status = RegisterEventHotKey(
            shortcut.carbonKeyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            hotKeyRef = nil
            throw GlobalHotKeyError.registrationFailed(status)
        }
    }

    func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    func unregister() {
        unregisterHotKey()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                guard let event else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                if parameterStatus == noErr,
                   hotKeyID.signature == GlobalHotKey.signature,
                   hotKeyID.id == GlobalHotKey.applyLastPresetID {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: GlobalHotKey.didPressApplyLastPresetNotification,
                            object: nil
                        )
                    }
                }

                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        guard status == noErr else {
            throw GlobalHotKeyError.handlerInstallFailed(status)
        }
    }
}

enum GlobalHotKeyError: LocalizedError {
    case handlerInstallFailed(OSStatus)
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .handlerInstallFailed(let status):
            "Could not install the global shortcut handler. Carbon returned \(status)."
        case .registrationFailed:
            "Could not register the shortcut. Another app may already be using it."
        }
    }
}
