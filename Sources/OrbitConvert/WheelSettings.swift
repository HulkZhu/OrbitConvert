import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum WheelOptions {
    static let groups: [(name: String, sources: [String])] = [
        ("照片", ["png", "jpg", "webp", "heic", "gif", "bmp", "tiff", "svg"]),
        ("文档", ["pdf", "docx", "txt", "pptx", "xlsx", "pages", "numbers", "key"]),
        ("RAW", RAWDecoder.extensions),
        ("音频", ["wav", "mp3", "flac", "m4a", "aiff"]),
        ("视频", ["mov", "mp4", "m4v"]), ("压缩包", ["rar"])
    ]
    static let sources = groups.flatMap(\.sources)
    static let extract = Format(name: "解压", ext: "extract", type: .data)
    static let airDrop = Format(name: "AirDrop", ext: "airdrop", type: .data)
    static func key(_ source: String) -> String { BatchConverter.kind(URL(fileURLWithPath: "/source." + source)) }
    static func candidates(_ source: String) -> [Format] {
        Converter.formats(for: URL(fileURLWithPath: "/source." + key(source))) + [airDrop]
    }
    static func selected(_ source: String, preferences: Preferences) -> [Format] {
        let available = candidates(source)
        let saved = preferences.wheelLayouts[key(source)] ?? (Converter.defaultFormats(for: URL(fileURLWithPath: "/source." + key(source))).map(\.ext) + ["airdrop"])
        var seen = Set<String>()
        return saved.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return available.first { $0.ext == id }
        }
    }
    static func move(_ id: String, source: String, index: Int, preferences: Preferences) {
        guard candidates(source).contains(where: { $0.ext == id }) else { return }
        var ids = selected(source, preferences: preferences).map(\.ext)
        ids.removeAll { $0 == id }
        ids.insert(id, at: min(max(0, index), ids.count))
        preferences.wheelLayouts[key(source)] = ids
    }
    static func group(for source: String) -> String? { groups.first { $0.sources.contains(key(source)) }?.name }
    static func setEverywhere(_ id: String, included: Bool, preferences: Preferences, group: String? = nil) {
        SettingsNavigation.shared.clearDrag()
        var layouts = preferences.wheelLayouts
        let scopedSources = group.map { name in groups.first { $0.name == name }?.sources ?? [] } ?? sources
        for source in scopedSources where candidates(source).contains(where: { $0.ext == id }) {
            var ids = selected(source, preferences: preferences).map(\.ext)
            if included { if !ids.contains(id) { ids.append(id) } }
            else { ids.removeAll { $0 == id } }
            layouts[key(source)] = ids
        }
        preferences.wheelLayouts = layouts
    }
}

enum WheelReorder {
    // Slot zero is just another circular slot. Only items on the travelled
    // arc shift into the vacancy; the rest of the wheel remains anchored.
    static func move(_ ids: [String], id: String, angle: Double) -> [String] {
        guard ids.count > 1, let origin = ids.firstIndex(of: id) else { return ids }
        let n = ids.count, step = 2 * Double.pi / Double(ids.count)
        let normalized = (angle.truncatingRemainder(dividingBy: 2 * .pi) + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
        let destination = Int(floor(normalized / step + 0.5 - 0.000001)) % n
        let forward = (destination - origin + n) % n
        let distance = forward <= n / 2 ? forward : forward - n
        guard distance != 0 else { return ids }
        var result = ids
        let direction = distance > 0 ? 1 : -1
        var slot = origin
        for _ in 0..<abs(distance) {
            let next = (slot + direction + n) % n
            result[slot] = result[next]
            slot = next
        }
        result[slot] = id
        return result
    }
}

final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var tab = "通用" { didSet { clearDrag() } }
    @Published var source = "png" { didSet { clearDrag() } }
    @Published var previewIDs: [String]?
    @Published var expandedGroups: Set<String> = ["照片"]
    var draggedID: String?
    var dragSource: String?
    var cardVisibility: ((Bool) -> Void)?
    var morphImage: ((NSImage, NSRect) -> Void)?
    var entryPoint = CGPoint(x: 170, y: 170)
    weak var editorRing: RingView?
    var exitOverlay: ExitMorphOverlay?
    var dragFromPalette = false
    func leaveRing() {
        guard !dragFromPalette || previewIDs != nil else { return }
        guard exitOverlay == nil, let id = draggedID, let ring = editorRing else { return }
        exitOverlay = ExitMorphOverlay.show(ring: ring, id: id)
        cardVisibility?(false)
        previewIDs = ring.formats.filter { $0.ext != id }.map(\.ext)
    }
    func beginDrag(_ id: String, fromPalette: Bool = false) {
        exitOverlay?.stop(); exitOverlay = nil
        previewIDs = nil; draggedID = id; dragSource = source; dragFromPalette = fromPalette
    }
    func clearDrag() { exitOverlay?.stop(); exitOverlay = nil; previewIDs = nil; draggedID = nil; dragSource = nil; cardVisibility = nil; morphImage = nil }
    func preview(_ location: CGPoint, preferences: Preferences) {
        if exitOverlay != nil { exitOverlay?.stop(); exitOverlay = nil; previewIDs = nil }
        guard dragSource == source, let id = draggedID else { return }
        let chosen = WheelOptions.selected(source, preferences: preferences).map(\.ext)
        guard WheelOptions.candidates(source).contains(where: { $0.ext == id }) else { return }
        var ids = chosen.filter { $0 != id }
        let count = max(1, chosen.count)
        var angle = atan2(170 - location.y, location.x - 170) - .pi / 2
        if angle < 0 { angle += 2 * .pi }
        let step = 2 * Double.pi / Double(count)
        let origin = chosen.firstIndex(of: id)
        if origin != nil {
            ids = WheelReorder.move(previewIDs ?? chosen, id: id, angle: angle)
        } else {
            let boundary = min(chosen.count, Int(floor(angle / step)) + 1)
            ids.insert(id, at: min(boundary, ids.count))
        }
        if previewIDs == nil { entryPoint = location }
        // New palette cards retain their native drag image until RingView takes
        // over its actual pixels; never hide it before the first morph frame.
        if origin != nil { cardVisibility?(false) }
        if previewIDs != ids { previewIDs = ids }
    }
    let licenses = LicenseSelection()
}

struct PreferencesView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var navigation = SettingsNavigation.shared
    var body: some View {
        VStack(spacing: 0) {
            Picker("设置分类", selection: $navigation.tab) {
                ForEach(["通用", "功能", "高级", "开源许可"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented).frame(width: 360).padding(16)
            Divider()
            if navigation.tab == "通用" { GeneralPreferencesView(preferences: preferences) }
            else if navigation.tab == "功能" { FunctionSettings(preferences: preferences, navigation: navigation).frame(width: 776, height: 620).padding(24) }
            else if navigation.tab == "高级" { AdvancedPreferencesView(preferences: preferences).frame(width: 776, height: 620).padding(24) }
            else { LicensesView(selection: navigation.licenses).frame(width: 776, height: 620).padding(24) }
        }.background(Color(nsColor: .windowBackgroundColor))
    }
}

struct FunctionSettings: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var navigation: SettingsNavigation
    var chosen: [Format] { WheelOptions.selected(navigation.source, preferences: preferences) }
    var displayed: [Format] {
        guard let ids = navigation.previewIDs else { return chosen }
        let all = WheelOptions.candidates(navigation.source)
        return ids.compactMap { id in all.first { $0.ext == id } }
    }
    var candidateRows: [[Format]] {
        let items = WheelOptions.candidates(navigation.source)
        return stride(from: 0, to: items.count, by: 5).map { Array(items[$0..<min($0 + 5, items.count)]) }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading) {
                Text("源文件格式").font(.headline)
                ScrollView {
                  VStack(alignment: .leading, spacing: 6) {
                    ForEach(WheelOptions.groups, id: \.name) { group in
                        Button {
                            if navigation.expandedGroups.contains(group.name) { navigation.expandedGroups.remove(group.name) }
                            else { navigation.expandedGroups.insert(group.name) }
                        } label: {
                            HStack {
                                Image(systemName: navigation.expandedGroups.contains(group.name) ? "chevron.down" : "chevron.right").frame(width: 12)
                                Text(group.name).font(.headline)
                                Spacer()
                            }.padding(.vertical, 6).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if navigation.expandedGroups.contains(group.name) {
                            ForEach(group.sources, id: \.self) { source in
                                Button { navigation.source = source } label: {
                                    Text(sourceLabel(source)).frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.leading, 18).padding(.vertical, 5)
                                        .foregroundStyle(navigation.source == source ? Color.white : Color.primary)
                                        .background(RoundedRectangle(cornerRadius: 7).fill(navigation.source == source ? Color.accentColor : Color.clear))
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                  }.padding(6)
                }
            }.frame(width: 145)
            ScrollView {
            VStack(spacing: 12) {
                Text("自定义 \(navigation.source.uppercased()) 圆盘").font(.title2.bold())
                Text("将上方格式拖入圆盘；拖动扇区排序，拖出圆盘到下方移除区即可移除。")
                    .font(.caption).foregroundStyle(.secondary)
                VStack(spacing: 12) {
                    ForEach(candidateRows.indices, id: \.self) { row in
                    HStack(spacing: 10) {
                    ForEach(candidateRows[row]) { format in
                        Button { WheelOptions.move(format.ext, source: navigation.source, index: chosen.count, preferences: preferences) } label: {
                            Text(format.name).font(.system(size: 22, weight: .medium)).frame(width: 104, height: 48)
                                .background(ClearOptionGlass().allowsHitTesting(false))
                                .overlay(alignment: .topTrailing) {
                                    if chosen.contains(where: { $0.ext == format.ext }) { Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).padding(4) }
                                }
                        }.buttonStyle(.plain)
                            .overlay(PaletteDragHandle(format: format, navigation: navigation, preferences: preferences) {
                                WheelOptions.move(format.ext, source: navigation.source, index: chosen.count, preferences: preferences)
                            })
                    }
                    }.frame(maxWidth: .infinity, alignment: .center)
                    }
                }.frame(maxWidth: .infinity, alignment: .center)
                ZStack {
                    EditorRing(preferences: preferences, source: navigation.source, formats: displayed).allowsHitTesting(false)
                    if displayed.isEmpty {
                        Text("拖入格式开始配置").foregroundStyle(.secondary)
                    }
                    ForEach(Array(displayed.enumerated()), id: \.element.ext) { index, format in
                        SectorDropShape(index: index, count: displayed.count).fill(Color.white.opacity(0.001))
                            .contentShape(SectorDropShape(index: index, count: displayed.count))
                            .onDrag {
                                navigation.beginDrag(format.ext)
                                return NSItemProvider(object: ("orbit-sector:" + navigation.source + ":" + format.ext) as NSString)
                            } preview: {
                                Color.clear.frame(width: 1, height: 1)
                            }
                            .contextMenu {
                                Button("移除 \(format.name)") {
                                    preferences.wheelLayouts[WheelOptions.key(navigation.source)] = chosen.filter { $0.ext != format.ext }.map(\.ext)
                                }
                                Divider()
                                Button("从所有圆盘移除 \(format.name)") { WheelOptions.setEverywhere(format.ext, included: false, preferences: preferences) }
                                Button("添加到所有支持的圆盘") { WheelOptions.setEverywhere(format.ext, included: true, preferences: preferences) }
                                if let group = WheelOptions.group(for: navigation.source) {
                                    Divider()
                                    Button("从所有“\(group)”圆盘移除 \(format.name)") { WheelOptions.setEverywhere(format.ext, included: false, preferences: preferences, group: group) }
                                    Button("添加到所有支持的“\(group)”圆盘") { WheelOptions.setEverywhere(format.ext, included: true, preferences: preferences, group: group) }
                                }
                            }
                    }
                }.frame(width: 340, height: 340)
                    .onDrop(of: [UTType.utf8PlainText], delegate: WheelDrop(preferences: preferences, navigation: navigation, source: navigation.source, index: chosen.count))
                Text("拖到这里移除 · 原文件不受影响")
                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5])))
                    .onDrop(of: [UTType.utf8PlainText], delegate: WheelRemoveDrop(preferences: preferences, source: navigation.source))
                HStack {
                    Text("从顶部开始，按逆时针排列 · 自动保存").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("恢复此格式默认值") { preferences.wheelLayouts.removeValue(forKey: WheelOptions.key(navigation.source)) }
                }
                Divider()
                Text("拖到 AirDrop 扇区并松手后，选择附近接收人。发送的是原文件，不转换、不创建副本。需系统支持 AirDrop；蓝牙、Wi-Fi 与接收方可见性由系统管理。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("右键点击候选格式或圆盘扇区，可一键添加或移除；可作用于所有圆盘，也可仅作用于当前分类（如文档）。添加仅应用于支持该目标的源格式。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity)
                .onDrop(of: [UTType.utf8PlainText], delegate: WheelRemoveDrop(preferences: preferences, source: navigation.source))
            }
        }
    }
    func provider(_ id: String) -> NSItemProvider {
        navigation.beginDrag(id)
        return NSItemProvider(object: ("orbit-wheel:" + navigation.source + ":" + id) as NSString)
    }
    func sourceLabel(_ source: String) -> String {
        switch source { case "jpg": return "JPG / JPEG"; case "heic": return "HEIC / HEIF"; case "tiff": return "TIFF / TIF"; default: return source.uppercased() }
    }
}

struct SectorDropShape: Shape {
    var index: Int
    var count: Int
    func path(in rect: CGRect) -> Path {
        var transform = CGAffineTransform(a: rect.width / 440, b: 0, c: 0, d: -rect.height / 440, tx: 0, ty: rect.height)
        return Path(SectorGeometry.sector(index, count: count).copy(using: &transform)!)
    }
}

struct EditorRing: NSViewRepresentable {
    @ObservedObject var preferences: Preferences
    let source: String
    let formats: [Format]
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ container: NSView, context: Context) {
        if let ring = container.subviews.first as? RingView, ring.original == source.uppercased(),
           ring.glassDensity == preferences.density, ring.clearGlass == preferences.clearGlass,
           ring.glassColor == preferences.glassColor, ring.textScale == preferences.textScale,
           ring.centerTextScale == preferences.centerTextScale {
            let point = SettingsNavigation.shared.entryPoint
            SettingsNavigation.shared.editorRing = ring
            ring.setFormats(formats, insertionPoint: CGPoint(x: point.x * 440 / 340, y: (340 - point.y) * 440 / 340))
            return
        }
        container.subviews.forEach { $0.removeFromSuperview() }
        let ring = RingView(file: URL(fileURLWithPath: "/preview." + source), formats: formats, original: source.uppercased(), glassDensity: preferences.density, clearGlass: preferences.clearGlass, glassColor: preferences.glassColor, textScale: preferences.textScale, centerTextScale: preferences.centerTextScale) { _, _ in }
        ring.frame = NSRect(x: 0, y: 0, width: 340, height: 340)
        ring.bounds = NSRect(x: 0, y: 0, width: 440, height: 440)
        container.addSubview(ring)
        SettingsNavigation.shared.editorRing = ring
    }
}

struct WheelDrop: DropDelegate {
    let preferences: Preferences
    let navigation: SettingsNavigation
    let source: String
    let index: Int
    func dropEntered(info: DropInfo) { navigation.preview(info.location, preferences: preferences) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        navigation.preview(info.location, preferences: preferences)
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { navigation.leaveRing() }
    func performDrop(info: DropInfo) -> Bool {
        let preview = navigation.previewIDs
        guard let provider = info.itemProviders(for: [UTType.utf8PlainText]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String else { return }
            guard let prefix = ["orbit-wheel:", "orbit-sector:"].map({ $0 + source + ":" }).first(where: { text.hasPrefix($0) }) else { return }
            let id = String(text.dropFirst(prefix.count))
            DispatchQueue.main.async {
                guard navigation.source == source else { return }
                if let preview, preview.contains(id) {
                    let valid = Set(WheelOptions.candidates(source).map(\.ext))
                    preferences.wheelLayouts[WheelOptions.key(source)] = preview.filter { valid.contains($0) }
                } else { WheelOptions.move(id, source: source, index: index, preferences: preferences) }
                navigation.clearDrag()
            }
        }
        return true
    }
}

struct WheelRemoveDrop: DropDelegate {
    let preferences: Preferences
    let source: String
    func dropEntered(info: DropInfo) { SettingsNavigation.shared.leaveRing() }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.utf8PlainText]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let text = value as? String else { return }
            let prefix = "orbit-sector:" + source + ":"
            guard text.hasPrefix(prefix) else { return }
            let id = String(text.dropFirst(prefix.count))
            DispatchQueue.main.async {
                preferences.wheelLayouts[WheelOptions.key(source)] = WheelOptions.selected(source, preferences: preferences).filter { $0.ext != id }.map(\.ext)
                SettingsNavigation.shared.clearDrag()
            }
        }
        return true
    }
}

struct ClearOptionGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .clear; glass.tintColor = nil; glass.cornerRadius = SectorGeometry.cornerRadius * 340 / 440
            return glass
        }
        let view = NSVisualEffectView()
        view.material = .hudWindow; view.state = .active; view.wantsLayer = true
        view.layer?.cornerRadius = SectorGeometry.cornerRadius * 340 / 440; view.layer?.masksToBounds = true
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}
