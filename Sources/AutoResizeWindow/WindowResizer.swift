import ApplicationServices
import AppKit

enum WindowResizeError: LocalizedError {
    case accessibilityPermissionMissing
    case noTargetApplication
    case noFocusedWindow
    case cannotReadWindowFrame
    case cannotSetSize(AXError)
    case cannotSetPosition(AXError)
    case appleScriptFallbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            "Auto Resize Window needs Accessibility permission before it can resize other apps."
        case .noTargetApplication:
            "No target application was found. Switch to the app you want to resize and try again."
        case .noFocusedWindow:
            "No focused window was found for the active application."
        case .cannotReadWindowFrame:
            "The active window did not expose a readable position and size."
        case .cannotSetSize(let error):
            "macOS refused to resize this window. Accessibility returned \(error)."
        case .cannotSetPosition(let error):
            "macOS resized the window, but refused to move it. Accessibility returned \(error)."
        case .appleScriptFallbackFailed(let message):
            "Accessibility resizing did not work, and the AppleScript fallback also failed. \(message)"
        }
    }
}

struct WindowResizer {
    private let frameTolerance: CGFloat = 2
    private let messagingTimeout: Float = 2

    func resizeFocusedWindow(to requestedSize: CGSize, preferredApplication: NSRunningApplication?) throws {
        guard AccessibilityPermission.isTrusted else {
            throw WindowResizeError.accessibilityPermissionMissing
        }

        let target = try resolveTarget(preferredApplication: preferredApplication)
        focus(target)

        let window = targetWindow(for: target.application) ?? target.window
        AXUIElementSetMessagingTimeout(window, messagingTimeout)

        guard let screen = screenForWindow(window) ?? screenUnderMouse() ?? NSScreen.main else {
            throw WindowResizeError.cannotReadWindowFrame
        }

        let targetSize = fittedSize(requestedSize, inside: screen.visibleFrame)
        let targetFrame = centeredFrame(size: targetSize, in: screen.visibleFrame)
        let targetPosition = accessibilityPosition(for: targetFrame)

        let accessibilityResult = Result {
            try resizeWithAccessibility(
                window: window,
                application: target.application,
                size: targetSize,
                position: targetPosition
            )
        }

        let fallbackContext: String
        switch accessibilityResult {
        case .success(true):
            return
        case .success(false):
            fallbackContext = "Accessibility completed without changing the window frame."
        case .failure(let error):
            fallbackContext = "Accessibility failed: \(error.localizedDescription)"
        }

        do {
            try resizeWithAppleScript(
                application: target.application,
                size: targetSize,
                position: targetPosition
            )
        } catch {
            throw WindowResizeError.appleScriptFallbackFailed("\(error.localizedDescription) \(fallbackContext)")
        }
    }

    private struct WindowTarget {
        let application: NSRunningApplication
        let window: AXUIElement
    }

    private func resolveTarget(preferredApplication: NSRunningApplication?) throws -> WindowTarget {
        guard let application = targetApplication(preferredApplication) ?? targetApplication(NSWorkspace.shared.frontmostApplication) else {
            throw WindowResizeError.noTargetApplication
        }

        guard let window = targetWindow(for: application) else {
            throw WindowResizeError.noFocusedWindow
        }

        return WindowTarget(application: application, window: window)
    }

    private func targetApplication(_ application: NSRunningApplication?) -> NSRunningApplication? {
        guard let application,
              application.processIdentifier != NSRunningApplication.current.processIdentifier else {
            return nil
        }

        return application
    }

    private func focus(_ target: WindowTarget) {
        target.application.unhide()
        target.application.activate(options: [.activateIgnoringOtherApps])

        let applicationElement = AXUIElementCreateApplication(target.application.processIdentifier)
        AXUIElementSetMessagingTimeout(applicationElement, messagingTimeout)
        AXUIElementPerformAction(target.window, kAXRaiseAction as CFString)

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.12))
    }

    private func targetWindow(for application: NSRunningApplication) -> AXUIElement? {
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)

        if let focusedWindow = windowAttribute(kAXFocusedWindowAttribute as CFString, for: applicationElement) {
            return focusedWindow
        }

        if let mainWindow = windowAttribute(kAXMainWindowAttribute as CFString, for: applicationElement) {
            return mainWindow
        }

        return firstWindow(for: applicationElement)
    }

    private func windowAttribute(_ attribute: CFString, for applicationElement: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(applicationElement, attribute, &value)

        guard error == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        let window = value as! AXUIElement
        return isTargetableWindow(window) ? window : nil
    }

    private func firstWindow(for applicationElement: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(applicationElement, kAXWindowsAttribute as CFString, &value)

        guard error == .success, let windows = value as? [AXUIElement] else {
            return nil
        }

        return windows.first(where: isTargetableWindow)
    }

    private func isTargetableWindow(_ window: AXUIElement) -> Bool {
        guard readStringAttribute(kAXRoleAttribute as CFString, of: window) == kAXWindowRole,
              readBoolAttribute(kAXMinimizedAttribute as CFString, of: window) != true,
              let size = readSize(of: window),
              readPosition(of: window) != nil else {
            return false
        }

        return size.width > 0 && size.height > 0
    }

    private func screenForWindow(_ window: AXUIElement) -> NSScreen? {
        guard let position = readPosition(of: window), let size = readSize(of: window) else {
            return nil
        }

        let windowFrame = cocoaFrame(fromAccessibilityPosition: position, size: size)
        let windowCenter = CGPoint(x: windowFrame.midX, y: windowFrame.midY)

        return NSScreen.screens.first { screen in
            screen.frame.contains(windowCenter)
        }
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }

    private func fittedSize(_ size: CGSize, inside frame: CGRect) -> CGSize {
        let scale = min(1, frame.width / size.width, frame.height / size.height)
        return CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
    }

    private func centeredFrame(size: CGSize, in frame: CGRect) -> CGRect {
        CGRect(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func resizeWithAccessibility(
        window: AXUIElement,
        application: NSRunningApplication,
        size: CGSize,
        position: CGPoint
    ) throws -> Bool {
        try withEnhancedUserInterfaceDisabled(for: application) {
            try setFrame(size: size, position: position, for: window)
        }

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        return accessibilityFrameMatches(window, size: size, position: position)
    }

    private func withEnhancedUserInterfaceDisabled<T>(
        for application: NSRunningApplication,
        _ body: () throws -> T
    ) rethrows -> T {
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface" as CFString
        let shouldRestoreEnhancedUserInterface = readBoolAttribute(enhancedUserInterfaceAttribute, of: applicationElement) == true

        if shouldRestoreEnhancedUserInterface {
            setBoolAttribute(enhancedUserInterfaceAttribute, of: applicationElement, to: false)
        }

        defer {
            if shouldRestoreEnhancedUserInterface {
                setBoolAttribute(enhancedUserInterfaceAttribute, of: applicationElement, to: true)
            }
        }

        return try body()
    }

    private func resizeWithAppleScript(
        application: NSRunningApplication,
        size: CGSize,
        position: CGPoint
    ) throws {
        guard let applicationName = appleScriptApplicationName(for: application) else {
            throw WindowResizeError.appleScriptFallbackFailed("Could not resolve the target app name.")
        }

        let left = Int(round(position.x))
        let top = Int(round(position.y))
        let right = Int(round(position.x + size.width))
        let bottom = Int(round(position.y + size.height))
        let escapedApplicationName = appleScriptStringLiteral(applicationName)
        let source = """
        tell application "\(escapedApplicationName)"
            if (count of windows) is 0 then error "No open windows"
            set bounds of front window to {\(left), \(top), \(right), \(bottom)}
        end tell
        """

        guard let script = NSAppleScript(source: source) else {
            throw WindowResizeError.appleScriptFallbackFailed("Could not create the AppleScript fallback.")
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            throw WindowResizeError.appleScriptFallbackFailed(appleScriptErrorMessage(errorInfo))
        }

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        if let verifiedWindow = targetWindow(for: application),
           !accessibilityFrameMatches(verifiedWindow, size: size, position: position) {
            throw WindowResizeError.appleScriptFallbackFailed("AppleScript ran, but the window still did not match the requested frame.")
        }
    }

    private func appleScriptApplicationName(for application: NSRunningApplication) -> String? {
        if let localizedName = application.localizedName, !localizedName.isEmpty {
            return localizedName
        }

        return application.bundleURL?.deletingPathExtension().lastPathComponent
    }

    private func appleScriptStringLiteral(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func appleScriptErrorMessage(_ errorInfo: NSDictionary) -> String {
        let message = errorInfo[NSAppleScript.errorMessage] as? String
        let number = errorInfo[NSAppleScript.errorNumber] as? NSNumber

        switch (message, number) {
        case let (message?, number?):
            return "AppleScript returned \(number): \(message)"
        case let (message?, nil):
            return "AppleScript returned: \(message)"
        case let (nil, number?):
            return "AppleScript returned error \(number)."
        case (nil, nil):
            return "AppleScript returned an unknown error."
        }
    }

    private func accessibilityFrameMatches(_ window: AXUIElement, size: CGSize, position: CGPoint) -> Bool {
        guard let actualSize = readSize(of: window), let actualPosition = readPosition(of: window) else {
            return false
        }

        return isClose(actualSize.width, size.width)
            && isClose(actualSize.height, size.height)
            && isClose(actualPosition.x, position.x)
            && isClose(actualPosition.y, position.y)
    }

    private func isClose(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) <= frameTolerance
    }

    private func setFrame(size: CGSize, position: CGPoint, for window: AXUIElement) throws {
        try setSize(size, for: window)
        try setPosition(position, for: window)
        try setSize(size, for: window)
    }

    private func setSize(_ size: CGSize, for window: AXUIElement) throws {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else {
            throw WindowResizeError.cannotReadWindowFrame
        }

        let error = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        guard error == .success else {
            throw WindowResizeError.cannotSetSize(error)
        }
    }

    private func setPosition(_ position: CGPoint, for window: AXUIElement) throws {
        var position = position
        guard let value = AXValueCreate(.cgPoint, &position) else {
            throw WindowResizeError.cannotReadWindowFrame
        }

        let error = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        guard error == .success else {
            throw WindowResizeError.cannotSetPosition(error)
        }
    }

    private func readPosition(of window: AXUIElement) -> CGPoint? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value)
        guard error == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        var point = CGPoint.zero
        guard AXValueGetType(axValue) == .cgPoint, AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func readSize(of window: AXUIElement) -> CGSize? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value)
        guard error == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        var size = CGSize.zero
        guard AXValueGetType(axValue) == .cgSize, AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return size
    }

    private func readStringAttribute(_ attribute: CFString, of element: AXUIElement) -> String? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else {
            return nil
        }

        return value as? String
    }

    private func readBoolAttribute(_ attribute: CFString, of element: AXUIElement) -> Bool? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else {
            return nil
        }

        return value as? Bool
    }

    @discardableResult
    private func setBoolAttribute(_ attribute: CFString, of element: AXUIElement, to value: Bool) -> Bool {
        AXUIElementSetAttributeValue(
            element,
            attribute,
            value ? kCFBooleanTrue : kCFBooleanFalse
        ) == .success
    }

    private func accessibilityPosition(for cocoaFrame: CGRect) -> CGPoint {
        CGPoint(x: cocoaFrame.minX, y: accessibilityBaseMaxY - cocoaFrame.maxY)
    }

    private func cocoaFrame(fromAccessibilityPosition position: CGPoint, size: CGSize) -> CGRect {
        CGRect(
            x: position.x,
            y: accessibilityBaseMaxY - position.y - size.height,
            width: size.width,
            height: size.height
        )
    }

    private var accessibilityBaseMaxY: CGFloat {
        NSScreen.screens.first { screen in
            screen.frame.origin == .zero
        }?.frame.maxY ?? NSScreen.main?.frame.maxY ?? 0
    }
}
