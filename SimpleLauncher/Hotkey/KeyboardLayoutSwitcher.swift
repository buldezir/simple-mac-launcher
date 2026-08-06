import Carbon
import Foundation

/// Switches the system keyboard to an English layout while the launcher is open.
enum KeyboardLayoutSwitcher {
    private static let preferredEnglishIDs = [
        "com.apple.keylayout.ABC",
        "com.apple.keylayout.US",
        "com.apple.keylayout.British",
        "com.apple.keylayout.Australian",
        "com.apple.keylayout.Canadian",
        "com.apple.keylayout.Irish",
        "com.apple.keylayout.ABCExtended",
        "com.apple.keylayout.USInternational-PC",
    ]

    private static var sourceBeforeSwitch: TISInputSource?

    /// Select an English keyboard layout if the current one is not already English.
    static func activateEnglish() {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
        if isEnglishKeyboard(current) {
            sourceBeforeSwitch = nil
            return
        }
        guard let english = preferredEnglishSource() else { return }
        sourceBeforeSwitch = current
        TISSelectInputSource(english)
    }

    /// Restore the layout that was active before `activateEnglish()`, if any.
    static func restorePrevious() {
        guard let previous = sourceBeforeSwitch else { return }
        TISSelectInputSource(previous)
        sourceBeforeSwitch = nil
    }

    private static func preferredEnglishSource() -> TISInputSource? {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }
        let selectable = sources.filter { isSelectableKeyboardLayout($0) }

        for id in preferredEnglishIDs {
            if let match = selectable.first(where: { stringProperty($0, kTISPropertyInputSourceID) == id }) {
                return match
            }
        }

        return selectable.first(where: isEnglishKeyboard)
    }

    private static func isEnglishKeyboard(_ source: TISInputSource) -> Bool {
        guard let id = stringProperty(source, kTISPropertyInputSourceID) else { return false }
        if preferredEnglishIDs.contains(id) { return true }
        guard isKeyboardLayoutCategory(source) else { return false }
        guard let languages = stringArrayProperty(source, kTISPropertyInputSourceLanguages) else { return false }
        return languages.contains { $0 == "en" || $0.hasPrefix("en-") }
    }

    private static func isSelectableKeyboardLayout(_ source: TISInputSource) -> Bool {
        guard isKeyboardLayoutCategory(source) else { return false }
        guard let selectable = boolProperty(source, kTISPropertyInputSourceIsSelectCapable) else { return false }
        return selectable
    }

    private static func isKeyboardLayoutCategory(_ source: TISInputSource) -> Bool {
        stringProperty(source, kTISPropertyInputSourceCategory) == (kTISCategoryKeyboardInputSource as String)
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as? String
    }

    private static func stringArrayProperty(_ source: TISInputSource, _ key: CFString) -> [String]? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as? [String]
    }

    private static func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        let value = Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
        return (value as? NSNumber)?.boolValue
    }
}
