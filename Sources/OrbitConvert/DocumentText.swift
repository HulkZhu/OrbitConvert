import Foundation

/// Read only the necessary ZIP members; never extract caller-controlled paths.
enum DocumentText {
    static func member(_ name: String, in input: URL) throws -> Data {
        let archive = try ZipArchive(url: input)
        guard let data = archive.data(at: name), XMLSafety.valid(data) else { throw OfficeEngine.error("无法读取文档内容：\(name)。") }
        return data
    }
    static func parse(_ data: Data) throws -> Reader {
        guard XMLSafety.valid(data) else { throw OfficeEngine.error("文档 XML 无效。") }
        let parser = XMLParser(data: data), reader = Reader()
        parser.shouldResolveExternalEntities = false; parser.delegate = reader
        guard parser.parse() else { throw OfficeEngine.error("文档 XML 内容损坏。") }
        return reader
    }
    static func read(_ input: URL) throws -> String {
        let archive = try ZipArchive(url: input)
        func member(_ name: String, in input: URL) throws -> Data {
            guard let data = archive.data(at: name) else { throw OfficeEngine.error("文档缺少：\(name)") }
            return data
        }
        if input.pathExtension.lowercased() == "docx" {
            return try parse(member("word/document.xml", in: input)).text
        }
        let presentation = try parse(member("ppt/presentation.xml", in: input))
        let relationships = try parse(member("ppt/_rels/presentation.xml.rels", in: input))
        guard presentation.slideIDs.count <= 1000 else { throw OfficeEngine.error("最多处理 1000 张幻灯片。") }
        var slides: [String] = []
        for id in presentation.slideIDs {
            guard let target = relationships.targets[id], !target.contains(".."), !target.contains(":") else { throw OfficeEngine.error("演示文稿的页面引用无效。") }
            let part = target.hasPrefix("/ppt/") ? String(target.dropFirst()) : "ppt/" + target
            guard part.hasPrefix("ppt/slides/"), part.hasSuffix(".xml") else { throw OfficeEngine.error("演示文稿页面路径无效。") }
            slides.append(try parse(member(part, in: input)).text)
        }
        guard !slides.isEmpty else { throw OfficeEngine.error("演示文稿没有可读取的幻灯片。") }
        return slides.joined(separator: "\n\u{000c}\n")
    }
    final class Reader: NSObject, XMLParserDelegate {
        var text = "", inText = false
        var slideIDs: [String] = [], targets: [String: String] = [:]
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            let local = name.split(separator: ":").last.map(String.init) ?? name
            if local == "t" { inText = true }
            if local == "tab" { text += "\t" }
            if local == "br" { text += attributes["w:type"] == "page" ? "\u{000c}" : "\n" }
            if local == "sldId", let id = attributes["r:id"] { slideIDs.append(id) }
            if local == "Relationship", attributes["TargetMode"] != "External", let id = attributes["Id"], let target = attributes["Target"] { targets[id] = target }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { if inText { text += string } }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let local = name.split(separator: ":").last.map(String.init) ?? name
            if local == "t" { inText = false }; if local == "p" { text += "\n" }
        }
    }
}
