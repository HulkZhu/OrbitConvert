// Adapted from FileFlipper (MIT), copyright (c) 2026 FileFlipper contributors.
// See FILEFLIPPER_LICENSE.txt. OrbitConvert: private output paths and resource limits.
import Foundation


extension XMLElement {
    /// Direct children with this local name (namespace prefix ignored).
    func children(_ name: String) -> [XMLElement] {
        (children ?? []).compactMap { $0 as? XMLElement }.filter { $0.localName == name }
    }

    func child(_ name: String) -> XMLElement? {
        (children ?? []).lazy.compactMap { $0 as? XMLElement }.first { $0.localName == name }
    }

    /// First descendant with this local name, depth first.
    func descendant(_ name: String) -> XMLElement? {
        for case let element as XMLElement in children ?? [] {
            if element.localName == name { return element }
            if let found = element.descendant(name) { return found }
        }
        return nil
    }

    func descendants(_ name: String) -> [XMLElement] {
        var found: [XMLElement] = []
        for case let element as XMLElement in children ?? [] {
            if element.localName == name { found.append(element) }
            found += element.descendants(name)
        }
        return found
    }

    /// Attribute by local name (so "r:embed" is just "embed").
    func attr(_ name: String) -> String? {
        attributes?.first { $0.localName == name }?.stringValue
    }

    /// The relationship id ("r:id"), which can share its local name with a plain "id" attribute.
    var relationshipID: String? {
        attributes?.first { $0.localName == "id" && ($0.prefix == "r" || ($0.uri ?? "").contains("relationships")) }?.stringValue
    }
}

enum OfficePackage {
    static func xml(_ archive: ZipArchive, _ path: String) -> XMLElement? {
        guard let data = archive.data(at: path),
              data.count <= 16_000_000,
              XMLSafety.valid(data),
              let document = try? XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever]) else { return nil }
        return document.rootElement()
    }

    /// Relationship id → absolute package path, for the part at `path`.
    static func relationships(_ archive: ZipArchive, for path: String) -> [String: (target: String, type: String)] {
        let directory = (path as NSString).deletingLastPathComponent
        let relsPath = directory + "/_rels/" + (path as NSString).lastPathComponent + ".rels"
        guard let root = xml(archive, relsPath) else { return [:] }
        var result: [String: (String, String)] = [:]
        for relationship in root.children("Relationship") {
            guard let id = relationship.attr("Id"), let target = relationship.attr("Target") else { continue }
            guard relationship.attr("TargetMode") != "External", !target.contains(":"), !target.contains("\\") else { continue }
            result[id] = (resolve(target, from: directory), relationship.attr("Type") ?? "")
        }
        return result
    }

    /// Resolves "../media/image1.png" relative to a directory inside the package.
    static func resolve(_ target: String, from directory: String) -> String {
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        var parts = directory.split(separator: "/").map(String.init)
        for piece in target.split(separator: "/") {
            if piece == ".." { _ = parts.popLast() } else if piece != "." { parts.append(String(piece)) }
        }
        return parts.joined(separator: "/")
    }
}
