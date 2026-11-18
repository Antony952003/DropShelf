import AppKit
import UniformTypeIdentifiers

/// A single thing sitting on a shelf.
///
/// Dropover's shelves accept the pasteboard types declared in its `NSServices`
/// entry (string, file contents, RTF, RTFD, URL) plus file promises; this model
/// covers the same ground.
final class ShelfItem: Codable, Equatable {

    enum Payload: Codable {
        case file(URL)
        case webURL(URL)
        case plainText(String)
        case richText(Data)   // RTF
        case image(Data)      // PNG
    }

    let id: UUID
    var payload: Payload
    let addedAt: Date

    /// Lazily materialised backing file for synthesised payloads (text, images).
    private var materialisedURL: URL?

    init(payload: Payload, addedAt: Date = Date()) {
        self.id = UUID()
        self.payload = payload
        self.addedAt = addedAt
    }

    // Codable: `materialisedURL` is deliberately not persisted — temp files do
    // not survive a relaunch.
    private enum CodingKeys: String, CodingKey { case id, payload, addedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        payload = try c.decode(Payload.self, forKey: .payload)
        addedAt = try c.decode(Date.self, forKey: .addedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(payload, forKey: .payload)
        try c.encode(addedAt, forKey: .addedAt)
    }

    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool { lhs.id == rhs.id }

    // MARK: - Presentation

    var displayName: String {
        switch payload {
        case .file(let url):
            return url.lastPathComponent
        case .webURL(let url):
            return url.host.map { $0 + url.path } ?? url.absoluteString
        case .plainText(let text):
            return ShelfItem.firstLine(of: text)
        case .richText(let data):
            let text = NSAttributedString(rtf: data, documentAttributes: nil)?.string ?? "Rich Text"
            return ShelfItem.firstLine(of: text)
        case .image:
            return "Image"
        }
    }

    var subtitle: String {
        switch payload {
        case .file(let url):
            if url.isDirectory { return "Folder" }
            let type = UTType(filenameExtension: url.pathExtension)?.localizedDescription
            return [type, byteSizeDescription].compactMap { $0 }.joined(separator: " · ")
        case .webURL(let url):
            return url.scheme?.uppercased() ?? "Link"
        case .plainText(let text):
            return "\(text.count) characters"
        case .richText:
            return "Rich Text"
        case .image(let data):
            if let rep = NSBitmapImageRep(data: data) {
                return "\(rep.pixelsWide) × \(rep.pixelsHigh)"
            }
            return "Image"
        }
    }

    var byteSize: Int64? {
        switch payload {
        case .file(let url):
            return url.fileAllocatedSize
        case .plainText(let s):
            return Int64(s.utf8.count)
        case .richText(let d), .image(let d):
            return Int64(d.count)
        case .webURL(let u):
            return Int64(u.absoluteString.utf8.count)
        }
    }

    var byteSizeDescription: String? {
        guard let bytes = byteSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Non-blocking icon. Files use the Finder icon; images render themselves.
    func icon(size: CGFloat) -> NSImage {
        let image: NSImage
        switch payload {
        case .file(let url):
            image = NSWorkspace.shared.icon(forFile: url.path)
        case .webURL:
            image = ShelfItem.symbol("safari", fallback: "link")
        case .plainText:
            image = ShelfItem.symbol("doc.plaintext", fallback: "doc")
        case .richText:
            image = ShelfItem.symbol("doc.richtext", fallback: "doc")
        case .image(let data):
            image = NSImage(data: data) ?? ShelfItem.symbol("photo", fallback: "doc")
        }
        let copy = image.copy() as? NSImage ?? image
        copy.size = NSSize(width: size, height: size)
        return copy
    }

    /// Does this item still refer to something that exists?
    var isResolvable: Bool {
        if case .file(let url) = payload {
            return FileManager.default.fileExists(atPath: url.path)
        }
        return true
    }

    // MARK: - File representation

    /// A real file on disk for this item, creating one for synthesised payloads.
    /// Used by Quick Look, Compress, and drag-out promises.
    func fileURL() -> URL? {
        switch payload {
        case .file(let url):
            return url
        case .webURL(let url):
            return materialise(name: "\(sanitised(displayName)).webloc") { target in
                let plist: [String: Any] = ["URL": url.absoluteString]
                let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try data.write(to: target)
            }
        case .plainText(let text):
            return materialise(name: "\(sanitised(displayName)).txt") { target in
                try text.write(to: target, atomically: true, encoding: .utf8)
            }
        case .richText(let data):
            return materialise(name: "\(sanitised(displayName)).rtf") { target in
                try data.write(to: target)
            }
        case .image(let data):
            return materialise(name: "\(sanitised(displayName)).png") { target in
                try data.write(to: target)
            }
        }
    }

    /// The UTType a drag-out promise should advertise.
    var promisedType: UTType {
        switch payload {
        case .file(let url):
            return UTType(filenameExtension: url.pathExtension) ?? .data
        case .webURL: return UTType("com.apple.web-internet-location") ?? .data
        case .plainText: return .plainText
        case .richText: return .rtf
        case .image: return .png
        }
    }

    private func materialise(name: String, write: (URL) throws -> Void) -> URL? {
        if let existing = materialisedURL, FileManager.default.fileExists(atPath: existing.path) {
            return existing
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropShelf", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let target = dir.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: target.path) {
                try write(target)
            }
            materialisedURL = target
            return target
        } catch {
            NSLog("DropShelf: could not materialise item: \(error.localizedDescription)")
            return nil
        }
    }

    private func sanitised(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined(separator: "-")
        let bounded = String(cleaned.prefix(60))
        return bounded.isEmpty ? "Item" : bounded
    }

    private static func firstLine(of text: String) -> String {
        let line = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first ?? ""
        if line.isEmpty { return "Text" }
        return String(line.prefix(60))
    }

    private static func symbol(_ name: String, fallback: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: fallback, accessibilityDescription: nil)
            ?? NSImage()
    }
}

// MARK: - Reading items off a pasteboard

extension ShelfItem {

    /// Builds items from a dragging pasteboard (or the general clipboard).
    ///
    /// Order matters: file URLs win over text, because a Finder drag carries
    /// both. Honours the "convert text to plain text" preference.
    static func items(from pasteboard: NSPasteboard) -> [ShelfItem] {
        var result: [ShelfItem] = []

        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
           !urls.isEmpty {
            result += urls.map { ShelfItem(payload: .file($0.standardizedFileURL)) }
        }

        if result.isEmpty,
           let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty {
            result += urls.map { url in
                url.isFileURL ? ShelfItem(payload: .file(url.standardizedFileURL))
                              : ShelfItem(payload: .webURL(url))
            }
        }

        if result.isEmpty {
            let plainOnly = Preferences.shared.forcePlainText
            if !plainOnly, let rtf = pasteboard.data(forType: .rtf) {
                result.append(ShelfItem(payload: .richText(rtf)))
            } else if !plainOnly, let rtfd = pasteboard.data(forType: .rtfd),
                      let attributed = NSAttributedString(rtfd: rtfd, documentAttributes: nil),
                      let rtf = attributed.rtf(from: NSRange(location: 0, length: attributed.length),
                                               documentAttributes: [:]) {
                result.append(ShelfItem(payload: .richText(rtf)))
            } else if let string = pasteboard.string(forType: .string), !string.isEmpty {
                result.append(ShelfItem(payload: .plainText(string)))
            }
        }

        if result.isEmpty {
            if let tiff = pasteboard.data(forType: .tiff),
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                result.append(ShelfItem(payload: .image(png)))
            } else if let png = pasteboard.data(forType: .png) {
                result.append(ShelfItem(payload: .image(png)))
            }
        }

        return result
    }

    /// The pasteboard types a shelf advertises as a drop destination.
    static var acceptedTypes: [NSPasteboard.PasteboardType] {
        [.fileURL, .URL, .rtfd, .rtf, .string, .tiff, .png]
    }
}

// MARK: - URL helpers

extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    var fileAllocatedSize: Int64? {
        guard let values = try? resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) else {
            return nil
        }
        if let allocated = values.totalFileAllocatedSize { return Int64(allocated) }
        if let size = values.fileSize { return Int64(size) }
        return nil
    }
}

// MARK: - Shelf colour labels

enum ShelfPalette {
    /// Colours cycle so each visible shelf is distinguishable, matching the
    /// behaviour behind `preferences.enable-color-labels-checkbox`.
    static let colors: [NSColor] = [
        .systemBlue, .systemPurple, .systemPink, .systemOrange,
        .systemGreen, .systemTeal, .systemIndigo, .systemYellow,
    ]

    static func color(at index: Int) -> NSColor {
        colors[((index % colors.count) + colors.count) % colors.count]
    }
}
