import AppKit
import Carbon
import Combine
import Foundation

/// Global activation shortcut. Modifiers are Carbon flags (`cmdKey`, `optionKey`, …).
struct ActivationHotkey: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = ActivationHotkey(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey)
    )

    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.keyLabel(keyCode))
        return parts.joined(separator: " ")
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        let relevant = flags.intersection(.deviceIndependentFlagsMask)
        if relevant.contains(.control) { mods |= UInt32(controlKey) }
        if relevant.contains(.option) { mods |= UInt32(optionKey) }
        if relevant.contains(.shift) { mods |= UInt32(shiftKey) }
        if relevant.contains(.command) { mods |= UInt32(cmdKey) }
        return mods
    }

    enum RecordResult {
        case cancel
        case reset
        case invalid
        case recorded(ActivationHotkey)
    }

    static func interpret(_ event: NSEvent) -> RecordResult {
        let keyCode = event.keyCode
        if keyCode == UInt16(kVK_Escape) { return .cancel }
        if keyCode == UInt16(kVK_Delete) || keyCode == UInt16(kVK_ForwardDelete) { return .reset }
        if isModifierKey(keyCode) { return .invalid }
        let mods = carbonModifiers(from: event.modifierFlags)
        guard mods != 0 else { return .invalid }
        return .recorded(ActivationHotkey(keyCode: UInt32(keyCode), modifiers: mods))
    }

    private static func isModifierKey(_ keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_Command, kVK_Shift, kVK_CapsLock, kVK_Option, kVK_Control,
             kVK_RightShift, kVK_RightOption, kVK_RightControl, kVK_Function:
            return true
        default:
            return false
        }
    }

    private static func keyLabel(_ keyCode: UInt32) -> String {
        let special: [Int: String] = [
            kVK_Return: "Return",
            kVK_Tab: "Tab",
            kVK_Space: "Space",
            kVK_Delete: "Delete",
            kVK_Escape: "Esc",
            kVK_ForwardDelete: "Fwd Delete",
            kVK_Home: "Home",
            kVK_End: "End",
            kVK_PageUp: "Page Up",
            kVK_PageDown: "Page Down",
            kVK_LeftArrow: "←",
            kVK_RightArrow: "→",
            kVK_DownArrow: "↓",
            kVK_UpArrow: "↑",
            kVK_F1: "F1",
            kVK_F2: "F2",
            kVK_F3: "F3",
            kVK_F4: "F4",
            kVK_F5: "F5",
            kVK_F6: "F6",
            kVK_F7: "F7",
            kVK_F8: "F8",
            kVK_F9: "F9",
            kVK_F10: "F10",
            kVK_F11: "F11",
            kVK_F12: "F12",
            kVK_F13: "F13",
            kVK_F14: "F14",
            kVK_F15: "F15",
            kVK_F16: "F16",
            kVK_F17: "F17",
            kVK_F18: "F18",
            kVK_F19: "F19",
            kVK_F20: "F20",
        ]
        if let label = special[Int(keyCode)] { return label }
        if let character = translatedKey(keyCode), !character.isEmpty {
            return character.uppercased()
        }
        return "Key \(keyCode)"
    }

    private static func translatedKey(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length: Int = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return OSStatus(-1)
            }
            return UCKeyTranslate(
                base,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let label = String(utf16CodeUnits: chars, count: length)
        if label == " " { return "Space" }
        return label
    }
}

final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    var onToggle: (() -> Void)?

    /// Set when the system rejects the shortcut, usually because another app owns it.
    @Published private(set) var registrationError: String?

    private let hotKeyID = EventHotKeyID(signature: OSType(0x534C4E43), id: 1) // 'SLNC'

    func register(_ hotkey: ActivationHotkey) {
        installHandlerIfNeeded()

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            hotKeyRef = nil
            registrationError = "Couldn’t register \(hotkey.displayString). Another app may be using it."
            NSLog("SimpleLauncher: failed to register hotkey \(hotkey.displayString) (\(status))")
        } else {
            registrationError = nil
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                if hkID.id == manager.hotKeyID.id {
                    DispatchQueue.main.async {
                        manager.onToggle?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )
    }
}
