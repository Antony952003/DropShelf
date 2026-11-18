import AppKit

/// Puts every new screenshot straight onto a shelf
/// (Dropover's `preferences.screenshots.title`, "Screenshot shelf").
///
/// Two detectors run together, de-duplicated by path:
///
/// 1. `NSMetadataQuery` on `kMDItemIsScreenCapture == 1`. Spotlight tags the
///    file itself, so this is independent of the filename's language and of
///    where the user points `com.apple.screencapture location`.
/// 2. A `DispatchSource` watch on the configured screenshot folder, which
///    still works if Spotlight indexing is off for that volume.
final class ScreenshotWatcher {
    static let shared = ScreenshotWatcher()

    private var query: NSMetadataQuery?
    private var directorySource: DispatchSourceFileSystemObject?
    private var directoryDescriptor: CInt = -1

    /// Only files newer than this are considered, so starting up does not
    /// dump every screenshot ever taken onto a shelf.
    private var baseline = Date()
    private var handled: Set<String> = []

    /// Consecutive screenshots collect into one shelf rather than spawning a
    /// card each.
    private weak var activeShelf: ShelfWindowController?
    private var lastDelivery = Date.distantPast
    private static let groupingWindow: TimeInterval = 90

    private init() {}

    var isRunning: Bool { query != nil || directorySource != nil }

    // MARK: Screenshot location

    /// Honours `com.apple.screencapture location`; falls back to the Desktop.
    static func screenshotDirectory() -> URL {
        if let raw = UserDefaults(suiteName: "com.apple.screencapture")?
            .string(forKey: "location"), !raw.isEmpty {
            let expanded = (raw as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    // MARK: Lifecycle

    func start() {
        guard Preferences.shared.screenshotShelf else { return }
        guard !isRunning else { return }
        baseline = Date()
        startMetadataQuery()
        startDirectoryWatch()
    }

    func stop() {
        if let query {
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate,
                                                      object: query)
            NotificationCenter.default.removeObserver(self,
                                                      name: .NSMetadataQueryDidFinishGathering,
                                                      object: query)
            query.stop()
        }
        query = nil

        directorySource?.cancel()
        directorySource = nil
        if directoryDescriptor >= 0 {
            close(directoryDescriptor)
            directoryDescriptor = -1
        }
    }

    func restart() {
        stop()
        start()
    }

    // MARK: Spotlight detector

    private func startMetadataQuery() {
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [Self.screenshotDirectory(), NSMetadataQueryUserHomeScope]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSCreationDateKey,
                                                  ascending: false)]
        query.notificationBatchingInterval = 0.25

        NotificationCenter.default.addObserver(
            self, selector: #selector(queryGathered(_:)),
            name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.addObserver(
            self, selector: #selector(queryUpdated(_:)),
            name: .NSMetadataQueryDidUpdate, object: query)

        self.query = query
        if !query.start() {
            NSLog("DropShelf: screenshot Spotlight query would not start; relying on the folder watch")
            self.query = nil
        }
    }

    /// The first pass returns the whole back catalogue — record it as seen and
    /// react to nothing.
    @objc private func queryGathered(_ notification: Notification) {
        guard let query else { return }
        query.disableUpdates()
        for index in 0..<query.resultCount {
            if let item = query.result(at: index) as? NSMetadataItem,
               let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                handled.insert(path)
            }
        }
        query.enableUpdates()
    }

    @objc private func queryUpdated(_ notification: Notification) {
        let added = notification.userInfo?[kMDQueryUpdateAddedItems as String] as? [NSMetadataItem]
        let changed = notification.userInfo?[kMDQueryUpdateChangedItems as String] as? [NSMetadataItem]
        for item in (added ?? []) + (changed ?? []) {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else {
                continue
            }
            consider(path: path)
        }
    }

    // MARK: Folder detector

    private func startDirectoryWatch() {
        let directory = Self.screenshotDirectory()
        // Record what is already there so only later arrivals count.
        for url in existingImages(in: directory) { handled.insert(url.path) }

        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            NSLog("DropShelf: cannot watch \(directory.path) for screenshots")
            return
        }
        directoryDescriptor = descriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            for url in self.existingImages(in: Self.screenshotDirectory()) {
                self.consider(path: url.path)
            }
        }
        source.setCancelHandler { [weak self] in
            guard let self, self.directoryDescriptor >= 0 else { return }
            close(self.directoryDescriptor)
            self.directoryDescriptor = -1
        }
        source.resume()
        directorySource = source
    }

    private func existingImages(in directory: URL) -> [URL] {
        let keys: [URLResourceKey] = [.creationDateKey, .contentTypeKey, .isRegularFileKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) else { return [] }

        return entries.filter { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let type = values.contentType else { return false }
            return type.conforms(to: .image)
        }
    }

    // MARK: Delivery

    private func consider(path: String) {
        guard Preferences.shared.screenshotShelf else { return }
        guard !handled.contains(path) else { return }

        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentTypeKey]),
              let created = values.creationDate,
              created >= baseline,
              values.contentType?.conforms(to: .image) == true else { return }

        handled.insert(path)

        // A screenshot is written in pieces; give the file a moment to settle
        // before handing it to a shelf, and confirm it is non-empty.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard size > 0, FileManager.default.isReadableFile(atPath: url.path) else { return }
            self.deliver(url: url)
        }
    }

    private func deliver(url: URL) {
        let item = ShelfItem(payload: .file(url))

        // Reuse the recent screenshot shelf if it is still open.
        if let shelf = activeShelf,
           ShelfStore.shared.controllers.contains(where: { $0 === shelf }),
           Date().timeIntervalSince(lastDelivery) < Self.groupingWindow {
            shelf.add(items: [item])
            shelf.window?.orderFrontRegardless()
        } else {
            let shelf = ShelfStore.shared.createShelf(at: NSEvent.mouseLocation, items: [item])
            shelf.rename(to: "Screenshots")
            activeShelf = shelf
        }
        lastDelivery = Date()
    }
}
