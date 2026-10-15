import AppKit
import SwiftUI

final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let defaults: UserDefaults
    @Published var hapticMode: Int { didSet { defaults.set(hapticMode, forKey: "hapticMode") } }
    @Published var wheelLayouts: [String: [String]] { didSet { defaults.set(wheelLayouts, forKey: "wheelLayouts") } }
    @Published var allowExternalApps: Bool { didSet { defaults.set(allowExternalApps, forKey: "allowExternalApps") } }
    @Published var centerTextScale: Double { didSet { defaults.set(centerTextScale, forKey: "centerTextScale") } }
    @Published var trimWhitespace: Bool { didSet { defaults.set(trimWhitespace, forKey: "trimWhitespace") } }
    @Published var shortcutMask: UInt64 { didSet { defaults.set(shortcutMask, forKey: "shortcutMask") } }
    @Published var shortcutKey: Int { didSet { defaults.set(shortcutKey, forKey: "shortcutKey") } }
    @Published var filenameTemplate: String { didSet { defaults.set(filenameTemplate, forKey: "filenameTemplate") } }
    @Published var diameter: Double { didSet { defaults.set(diameter, forKey: "wheelSize") } }
    @Published var density: Double { didSet { defaults.set(density, forKey: "glassDensity") } }
    @Published var clearGlass: Bool { didSet { defaults.set(clearGlass, forKey: "clearGlass") } }
    @Published var textScale: Double { didSet { defaults.set(textScale, forKey: "textScale") } }
    @Published var glassColor: NSColor {
        didSet {
            let rgb = glassColor.usingColorSpace(.sRGB) ?? .white
            defaults.set([Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent)], forKey: "glassColorRGB")
        }
    }
    @Published var showDock: Bool {
        didSet {
            defaults.set(showDock, forKey: "showDock")
            NSApp?.setActivationPolicy(showDock ? .regular : .accessory)
        }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hapticMode = min(3, max(0, defaults.object(forKey: "hapticMode") as? Int ?? 1))
        wheelLayouts = defaults.dictionary(forKey: "wheelLayouts") as? [String: [String]] ?? [:]
        // The per-source layout now controls AirDrop. Retire the old master
        // switch so previously disabled users can add it from the palette.
        allowExternalApps = defaults.bool(forKey: "allowExternalApps")
        centerTextScale = min(2, max(0.6, (defaults.object(forKey: "centerTextScale") as? Double) ?? 1))
        trimWhitespace = (defaults.object(forKey: "trimWhitespace") as? Bool) ?? false
        let savedMask = UInt64((defaults.object(forKey: "shortcutMask") as? NSNumber)?.uint64Value ?? (CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue))
        shortcutMask = savedMask == 0 ? CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue : savedMask
        shortcutKey = (defaults.object(forKey: "shortcutKey") as? Int) ?? -1
        filenameTemplate = defaults.string(forKey: "filenameTemplate") ?? "{name}-converted"
        defaults.register(defaults: ["wheelSize": 300.0, "glassDensity": 0.08, "clearGlass": true, "showDock": false])
        diameter = min(440, max(240, defaults.double(forKey: "wheelSize")))
        density = min(1, max(0, defaults.double(forKey: "glassDensity")))
        clearGlass = defaults.bool(forKey: "clearGlass")
        showDock = defaults.bool(forKey: "showDock")
        textScale = min(1.6, max(0.8, (defaults.object(forKey: "textScale") as? Double) ?? 1))
        if let rgb = defaults.array(forKey: "glassColorRGB") as? [Double], rgb.count == 3,
           rgb.allSatisfy({ $0.isFinite && (0...1).contains($0) }) {
            glassColor = NSColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
        } else { glassColor = .white }
    }
    func reset() { allowExternalApps = false; centerTextScale = 1; trimWhitespace = false; shortcutMask = CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue; shortcutKey = -1; filenameTemplate = "{name}-converted"; diameter = 300; density = 0.08; clearGlass = true; glassColor = .white; textScale = 1; showDock = false }
}

struct WheelPreview: NSViewRepresentable {
    @ObservedObject var preferences: Preferences
    func makeNSView(context: Context) -> NSView { NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 450)) }
    func updateNSView(_ container: NSView, context: Context) {
        container.subviews.forEach { $0.removeFromSuperview() }
        let ring = RingView(file: URL(fileURLWithPath: "/tmp/preview.jpg"), formats: WheelOptions.selected("jpg", preferences: preferences), original: "JPG", glassDensity: preferences.density, clearGlass: preferences.clearGlass, glassColor: preferences.glassColor, textScale: preferences.textScale, centerTextScale: preferences.centerTextScale) { _, _ in }
        let size = preferences.diameter
        ring.frame = NSRect(x: (460 - size) / 2, y: (450 - size) / 2, width: size, height: size)
        ring.bounds = NSRect(x: 0, y: 0, width: 440, height: 440)
        container.addSubview(ring)
    }
}

struct GeneralPreferencesView: View {
    @ObservedObject var preferences: Preferences
    var body: some View {
        HStack(spacing: 8) {
            ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("外观与行为").font(.title2.bold())
                VStack(alignment: .leading) {
                    Text("圆盘大小 · \(Int(preferences.diameter)) pt")
                    Slider(value: $preferences.diameter, in: 240...440, step: 10)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Liquid Glass")
                    Picker("样式", selection: $preferences.clearGlass) {
                        Text("清透").tag(true)
                        Text("标准").tag(false)
                    }.pickerStyle(.segmented)
                    ColorPicker("玻璃颜色", selection: Binding(
                        get: { Color(nsColor: preferences.glassColor) },
                        set: { preferences.glassColor = NSColor($0) }
                    ), supportsOpacity: false)
                    Text("玻璃浓度 · \(Int(preferences.density * 100))%")
                    Slider(value: $preferences.density, in: 0...1)
                    Text("浓度越高，所选颜色越明显；为 0 时不染色。系统不提供独立模糊半径。").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("在程序坞显示图标", isOn: $preferences.showDock)
                VStack(alignment: .leading) {
                    Text("文字大小 · \(Int((preferences.textScale * 100).rounded()))%")
                    Slider(value: $preferences.textScale, in: 0.8...1.6, step: 0.05)
                }
                VStack(alignment: .leading) {
                    Text("中央原格式字号 · \(Int((preferences.centerTextScale * 100).rounded()))%")
                    Slider(value: $preferences.centerTextScale, in: 0.6...2, step: 0.05)
                }
                ShortcutSettings(preferences: preferences)
                Picker("震动反馈强度（模式）", selection: $preferences.hapticMode) {
                    Text("关闭").tag(0); Text("轻提示").tag(1); Text("标准").tag(2); Text("双脉冲").tag(3)
                }
                Button("体验触感") { WheelHaptics.play(preferences.hapticMode) }
                Text("系统不提供连续震幅调节，档位改变触感模式。需支持触感的触摸板；实际力度由系统和硬件决定。").font(.caption).foregroundStyle(.secondary)
                Text("自动保存。程序坞立即生效；圆盘设置在下次唤出时应用。").font(.caption).foregroundStyle(.secondary)
                Button("恢复通用设置默认值") {
                    let advanced = (preferences.allowExternalApps, preferences.trimWhitespace, preferences.filenameTemplate)
                    preferences.reset()
                    preferences.hapticMode = 1
                    (preferences.allowExternalApps, preferences.trimWhitespace, preferences.filenameTemplate) = advanced
                }
            }.padding(.trailing, 8)
            }.frame(width: 260)
            WheelPreview(preferences: preferences).frame(width: 460, height: 450)
        }.padding(24).frame(width: 776, height: 620).background(Color(nsColor: .windowBackgroundColor))
    }
}

struct AdvancedPreferencesView: View {
    @ObservedObject var preferences: Preferences
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("高级").font(.title2.bold())
                Toggle("允许已安装的 Apple 应用辅助转换", isOn: $preferences.allowExternalApps)
                Text("仅 Pages／Numbers／Keynote 原生文件需要对应 Apple 应用。DOCX／PPTX／XLSX 在 App 内转换；复杂排版、图表可能有差异，Excel 使用已有公式结果，不重新计算。")
                    .foregroundStyle(.secondary)
                Divider()
                Toggle("文档转图片时裁掉外围白边", isOn: $preferences.trimWhitespace)
                Text("只裁外围空白，不拉伸内容；关闭可保留原始整页尺寸。").foregroundStyle(.secondary)
                Divider()
                Text("默认输出文件名").font(.headline)
                TextField("{name}-converted", text: $preferences.filenameTemplate).textFieldStyle(.roundedBorder)
                Text("示例：" + Converter.outputStem(URL(fileURLWithPath: "/照片.jpg"), format: Format.all[0], naming: preferences.filenameTemplate) + ".png").foregroundStyle(.secondary)
                Text("可用：{name} 原名、{format} 格式、{date} 日期。扩展名自动添加；重名自动编号。多页图片保存至同名新文件夹。")
                    .foregroundStyle(.secondary)
                Text("自动保存，下一次转换生效。").font(.caption).foregroundStyle(.secondary)
                Button("恢复高级设置默认值") {
                    preferences.allowExternalApps = false; preferences.trimWhitespace = false; preferences.filenameTemplate = "{name}-converted"
                }
            }.padding(24).frame(maxWidth: 620, alignment: .leading)
        }.frame(maxWidth: .infinity)
    }
}
