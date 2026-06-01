import Carbon.HIToolbox
import Foundation

struct KeyCombo: Codable, Equatable, Hashable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let cmd: UInt32 = UInt32(cmdKey)
    static let shift: UInt32 = UInt32(shiftKey)
    static let option: UInt32 = UInt32(optionKey)
    static let control: UInt32 = UInt32(controlKey)

    static let defaultStart = KeyCombo(keyCode: 15, modifiers: cmd | shift)   // ⌘⇧R
    static let defaultStop = KeyCombo(keyCode: 1, modifiers: cmd | shift)     // ⌘⇧S
    static let defaultAdHoc = KeyCombo(keyCode: 0, modifiers: cmd | shift)    // ⌘⇧A

    var hasRequiredModifier: Bool {
        modifiers & (Self.cmd | Self.option | Self.control) != 0
    }

    var displayString: String {
        var s = ""
        if modifiers & Self.control != 0 { s += "⌃" }
        if modifiers & Self.option != 0 { s += "⌥" }
        if modifiers & Self.shift != 0 { s += "⇧" }
        if modifiers & Self.cmd != 0 { s += "⌘" }
        s += Self.keyName(forKeyCode: keyCode)
        return s
    }

    private static func keyName(forKeyCode code: UInt32) -> String {
        switch Int(code) {
        case kVK_ANSI_A: return "A"; case kVK_ANSI_B: return "B"; case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"; case kVK_ANSI_E: return "E"; case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"; case kVK_ANSI_H: return "H"; case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"; case kVK_ANSI_K: return "K"; case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"; case kVK_ANSI_N: return "N"; case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"; case kVK_ANSI_Q: return "Q"; case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"; case kVK_ANSI_T: return "T"; case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"; case kVK_ANSI_W: return "W"; case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"; case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"; case kVK_ANSI_1: return "1"; case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"; case kVK_ANSI_4: return "4"; case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"; case kVK_ANSI_7: return "7"; case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Escape: return "⎋"
        default: return "·"
        }
    }
}
