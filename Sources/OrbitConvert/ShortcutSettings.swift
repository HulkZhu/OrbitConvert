import AppKit
import SwiftUI

extension Preferences {
    static let modifiers: [(String, CGEventFlags)] = [("⌃ Control", .maskControl), ("⌥ Option", .maskAlternate), ("⇧ Shift", .maskShift), ("⌘ Command", .maskCommand)]
    static let keys: [(String, Int)] = [("无附加键（只按修饰键）", -1), ("空格", 49), ("A",0),("B",11),("C",8),("D",2),("E",14),("F",3),("G",5),("H",4),("I",34),("J",38),("K",40),("L",37),("M",46),("N",45),("O",31),("P",35),("Q",12),("R",15),("S",1),("T",17),("U",32),("V",9),("W",13),("X",7),("Y",16),("Z",6),("F1",122),("F2",120),("F3",99),("F4",118),("F5",96),("F6",97),("F7",98),("F8",100),("F9",101),("F10",109),("F11",103),("F12",111)]
    func matchesShortcut(_ flags: CGEventFlags) -> Bool {
        let relevant = Self.modifiers.reduce(UInt64(0)) { $0 | $1.1.rawValue }
        guard shortcutMask != 0, flags.rawValue & relevant == shortcutMask & relevant else { return false }
        return shortcutKey == -1 || (shortcutKey >= 0 && shortcutKey <= 127 && CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(shortcutKey)))
    }
}

struct ShortcutSettings: View {
    @ObservedObject var preferences: Preferences
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("转换快捷键").font(.headline)
            ForEach(Preferences.modifiers, id: \.0) { label, flag in
                Toggle(label, isOn: Binding(get: { preferences.shortcutMask & flag.rawValue != 0 }, set: { enabled in
                    let mask = enabled ? preferences.shortcutMask | flag.rawValue : preferences.shortcutMask & ~flag.rawValue
                    if mask != 0 { preferences.shortcutMask = mask }
                }))
            }
            Picker("附加键", selection: $preferences.shortcutKey) {
                ForEach(Preferences.keys, id: \.1) { name, key in Text(name).tag(key) }
            }
            Text("至少保留一个修饰键。按住组合键，再按下鼠标拖动文件；设置立即生效。请避开系统已有快捷键。").font(.caption).foregroundStyle(.secondary)
        }
    }
}
