import AppKit
import QuickLookThumbnailing

/// Real Quick Look previews for shelf items, with a generic Finder icon as the
/// fallback. Dropover links `QuickLookUI`, `ImageIO` and `PDFKit`
/// (ANALYSIS.md §2), which is what makes its shelves show actual page and
/// image previews rather than file-type icons.
///
/// Generation is asynchronous; `thumbnail(for:…)` returns `nil` on a miss and
/// invokes `onReady` once the image has landed so the caller can redraw.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private struct Key: Hashable {
        let path: String
        let side: Int
        let modified: TimeInterval
    }

    private var cache: [Key: NSImage] = [:]
    private var order: [Key] = []
    private var inFlight: Set<Key> = []
    private let limit = 400

    private init() {}

    func thumbnail(for url: URL,
                   side: CGFloat,
                   scale: CGFloat,
                   onReady: @escaping () -> Void) -> NSImage? {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        let key = Key(path: url.path, side: Int(side.rounded()), modified: modified)

        if let hit = cache[key] { return hit }
        guard !inFlight.contains(key) else { return nil }
        inFlight.insert(key)

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: side, height: side),
            scale: max(1, scale),
            representationTypes: .all)

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight.remove(key)
                guard let rep else { return }
                self.store(rep.nsImage, for: key)
                onReady()
            }
        }
        return nil
    }

    private func store(_ image: NSImage, for key: Key) {
        if cache[key] == nil { order.append(key) }
        cache[key] = image
        while order.count > limit {
            let evicted = order.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }

    func clear() {
        cache.removeAll()
        order.removeAll()
    }
}

// MARK: - Aspect-correct drawing

extension NSImage {
    /// Draws the image fitted inside `rect` without distorting it — needed
    /// because Quick Look thumbnails are not square.
    func drawAspectFit(in rect: NSRect) {
        guard size.width > 0, size.height > 0 else { return }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        let target = NSRect(x: rect.midX - fitted.width / 2,
                            y: rect.midY - fitted.height / 2,
                            width: fitted.width,
                            height: fitted.height)
        draw(in: target)
    }

    /// The fitted rect `drawAspectFit(in:)` would use, for drawing a border
    /// around a preview.
    func aspectFitRect(in rect: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(x: rect.midX - fitted.width / 2,
                      y: rect.midY - fitted.height / 2,
                      width: fitted.width,
                      height: fitted.height)
    }
}
