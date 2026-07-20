import Foundation
import UIKit

// ZIPFoundation duoc nhung o dang source (thu muc ZIPFoundation/) nen khong import

/// Sao luu, khoi phuc va xoa du lieu cua mot app.
///
/// Toan bo thao tac I/O chay tren `ioQueue` (serial) de khong block main thread
/// va de hai lenh khong dam vao cung mot container.
final class DataManager {
    static let shared = DataManager()
    private let fm = FileManager.default

    private let ioQueue = DispatchQueue(
        label: "com.appdatamanager.io",
        qos: .utility, attributes: [],
        autoreleaseFrequency: .workItem)

    // MARK: - Background task
    //
    // Zip mot container vai tram MB co the lau hon thoi gian iOS cho phep app
    // chay khi bi day xuong nen. beginBackgroundTask xin them thoi gian.
    //
    // Dung class chu khong dung bien local: ca handler het gio lan code goi
    // end() deu phai thay cung mot identifier, neu khong se ket thuc hai lan
    // tren cung mot task va UIKit se bao loi.
    private final class BackgroundTask {
        private var id: UIBackgroundTaskIdentifier = .invalid
        private let lock = NSLock()

        init(name: String) {
            let start = { [self] in
                let newID = UIApplication.shared.beginBackgroundTask(withName: name) { [self] in
                    end()   // het gio: iOS doi minh tu ket thuc
                }
                lock.lock(); id = newID; lock.unlock()
            }
            if Thread.isMainThread { start() } else { DispatchQueue.main.sync(execute: start) }
        }

        func end() {
            lock.lock()
            let current = id
            id = .invalid
            lock.unlock()

            guard current != .invalid else { return }
            if Thread.isMainThread { UIApplication.shared.endBackgroundTask(current) }
            else { DispatchQueue.main.async { UIApplication.shared.endBackgroundTask(current) } }
        }
    }

    // MARK: - File helpers

    /// Xoa het noi dung mot thu muc nhung giu lai chinh thu muc do.
    ///
    /// Giu lai file metadata cua container — do la file iOS dung de biet
    /// container nay thuoc app nao. Xoa no di thi container thanh mo coi.
    private func wipeContainerContents(_ containerPath: String) {
        let url = URL(fileURLWithPath: containerPath)
        // options: [] (khong skipsHiddenFiles) — mot so app giau du lieu trong dotfile
        guard let items = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: []) else { return }

        let keep = ".com.apple.mobile_container_manager.metadata.plist"
        for item in items where item.lastPathComponent != keep {
            autoreleasepool {
                shellRm(item.path)              // rm -rf qua posix_spawn
                try? fm.removeItem(at: item)    // du phong neu shellRm that bai
            }
        }
    }

    private func wipeContentsRecursive(of dir: URL) {
        guard let items = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        else { return }
        for item in items {
            autoreleasepool {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDir {
                    wipeContentsRecursive(of: item)
                    try? fm.removeItem(at: item)
                } else {
                    try? fm.setAttributes(
                        [.posixPermissions: NSNumber(value: Int16(0o666))],
                        ofItemAtPath: item.path)
                    try? fm.removeItem(at: item)
                }
            }
        }
    }

    private func copyDirFull(from src: URL, to dst: URL) {
        // Tao dst TRUOC khi doc src: restore da xoa dst roi moi goi ham nay,
        // neu doc src that bai ma thoat som thi dst se mat han thay vi rong.
        try? fm.createDirectory(at: dst, withIntermediateDirectories: true)
        guard let items = try? fm.contentsOfDirectory(
            at: src, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [])
        else { return }
        for item in items {
            autoreleasepool {
                let vals = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                // Bo qua symlink: nhieu app dat symlink (vd trong WebKit) tro toi
                // /var/... ben ngoai. Neu nhet vao zip, luc restore ZIPFoundation
                // se chan (ArchiveError uncontainedSymlink) va hong ca ban backup.
                if vals?.isSymbolicLink == true { return }
                let target = dst.appendingPathComponent(item.lastPathComponent)
                if vals?.isDirectory == true {
                    copyDirFull(from: item, to: target)
                } else {
                    if fm.fileExists(atPath: target.path) { try? fm.removeItem(at: target) }
                    try? fm.copyItem(at: item, to: target)
                }
            }
        }
    }

    /// Ten cac file/thu muc trong container KHONG dua vao backup.
    ///  - metadata plist: cua rieng iOS, khong phai du lieu app
    ///  - tmp, Library/Caches: iOS coi la vut duoc, khong chua session,
    ///    ma lai co the rat to
    private let skipRelPaths: Set<String> = [
        ".com.apple.mobile_container_manager.metadata.plist",
        "tmp",
        "Library/Caches",
    ]

    /// Copy TOAN BO cay thu muc cua mot container (tru cac muc trong
    /// `skipRelPaths` va symlink). Day la diem khac cot loi so voi ban cu:
    /// truoc chi copy vai thu muc con nen mat session nam o cho khac.
    private func copyContainerTree(from src: URL, to dst: URL) {
        try? fm.createDirectory(at: dst, withIntermediateDirectories: true)
        copyTreeInner(src: src, dst: dst, rel: "")
    }

    private func copyTreeInner(src: URL, dst: URL, rel: String) {
        guard let items = try? fm.contentsOfDirectory(
            at: src, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []) else { return }
        for item in items {
            autoreleasepool {
                let name    = item.lastPathComponent
                let relPath = rel.isEmpty ? name : "\(rel)/\(name)"
                if skipRelPaths.contains(relPath) { return }
                let vals = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if vals?.isSymbolicLink == true { return }   // symlink -> loi 14 luc restore
                let target = dst.appendingPathComponent(name)
                if vals?.isDirectory == true {
                    try? fm.createDirectory(at: target, withIntermediateDirectories: true)
                    copyTreeInner(src: item, dst: target, rel: relPath)
                } else {
                    if fm.fileExists(atPath: target.path) { try? fm.removeItem(at: target) }
                    try? fm.copyItem(at: item, to: target)
                }
            }
        }
    }

    /// Do lai container tu ban backup: xoa sach noi dung hien tai (giu metadata)
    /// roi chep toan bo tu `src` vao.
    private func restoreContainerTree(from src: URL, to dst: URL) {
        guard fm.fileExists(atPath: src.path) else { return }
        wipeContainerContents(dst.path)
        guard let items = try? fm.contentsOfDirectory(
            at: src, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return }
        for item in items {
            autoreleasepool {
                let target = dst.appendingPathComponent(item.lastPathComponent)
                let isDir  = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDir { copyDirFull(from: item, to: target) }
                else {
                    if fm.fileExists(atPath: target.path) { try? fm.removeItem(at: target) }
                    try? fm.copyItem(at: item, to: target)
                }
            }
        }
    }

    /// Tao lai khung thu muc chuan ma iOS dung cho mot app vua cai.
    ///
    /// Sau khi wipe sach container, app se CRASH luc mo neu thieu cac thu muc
    /// nay (Documents, Library, tmp...). Tao lai de app khoi dong duoc nhu moi.
    private func recreateContainerSkeleton(at path: String, isDataContainer: Bool) {
        var dirs = ["Library", "Library/Caches", "Library/Preferences"]
        if isDataContainer { dirs += ["Documents", "SystemData", "tmp"] }
        for d in dirs {
            try? fm.createDirectory(atPath: "\(path)/\(d)", withIntermediateDirectories: true)
        }
    }

    private func dirSize(_ url: URL) -> Int64 {
        var total: Int64 = 0
        guard let e = fm.enumerator(at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]) else { return 0 }
        for case let f as URL in e {
            autoreleasepool {
                if let s = (try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                    total += Int64(s)
                }
            }
        }
        return total
    }

    private func freeSpace() -> Int64 {
        (try? fm.attributesOfFileSystem(
            forPath: "/private/var/mobile"))?[.systemFreeSize] as? Int64 ?? 0
    }

    private func countItems(at path: String) -> Int {
        guard let items = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil, options: [])
        else { return 0 }
        return items.filter {
            $0.lastPathComponent != ".com.apple.mobile_container_manager.metadata.plist"
        }.count
    }


    // MARK: - API cong khai

    /// Backup cac app da chon vao MOT file duy nhat (backup gop).
    /// `completion` nhan ve danh sach app backup thanh cong.
    func backupApps(items: [AppItem],
                    progress: @escaping (String) -> Void,
                    completion: @escaping ([AppItem]) -> Void) {
        guard !items.isEmpty else {
            DispatchQueue.main.async { progress("Chon it nhat 1 app"); completion([]) }
            return
        }
        let task = BackgroundTask(name: "appdatamanager.backup")
        ioQueue.async {
            var succeeded = [AppItem]()
            do {
                succeeded = try self.backupCombined(items: items, progress: progress)
                DispatchQueue.main.async {
                    progress("Backup xong \(succeeded.count)/\(items.count) app → 1 file")
                }
            } catch {
                plog("backup loi: \(error)")
                DispatchQueue.main.async { progress("Loi backup: \(error.localizedDescription)") }
            }
            // Tu dong dong cac app da chon sau khi xong
            killAppsAndWait(processNames: items.map { $0.processName })
            DispatchQueue.main.async { progress("Da dong \(items.count) app") }
            task.end()
            DispatchQueue.main.async { completion(succeeded) }
        }
    }

    func resetApps(items: [AppItem],
                   progress: @escaping (String) -> Void,
                   completion: @escaping ([AppItem]) -> Void) {
        run(items: items, taskName: "reset", progress: progress, completion: completion) { item in
            let count = try self.clearOne(item: item)
            return "Da xoa \(item.displayName) (\(count) muc)"
        }
    }

    /// Backup mot tap app, roi reset mot tap app khac.
    ///
    /// `backupItems` va `resetItems` co the la hai tap khac nhau. Nguyen tac
    /// an toan: mot app nam trong CA hai tap chi bi reset khi backup cua no
    /// thanh cong — de khong xoa mat du lieu ma le ra da phai luu. App chi
    /// nam trong tap reset (khong yeu cau backup) thi reset binh thuong.
    func backupThenReset(backupItems: [AppItem],
                         resetItems: [AppItem],
                         progress: @escaping (String) -> Void,
                         completion: @escaping ([AppItem]) -> Void) {
        backupApps(items: backupItems, progress: progress) { backedUp in
            let backupIDs = Set(backupItems.map { $0.bundleID })
            let okIDs     = Set(backedUp.map { $0.bundleID })

            var toReset = [AppItem]()
            for item in resetItems {
                let inBackupSet = backupIDs.contains(item.bundleID)
                if inBackupSet && !okIDs.contains(item.bundleID) {
                    let msg = "Bo qua reset \(item.displayName): backup that bai"
                    plog(msg)
                    DispatchQueue.main.async { progress(msg) }
                } else {
                    toReset.append(item)
                }
            }

            guard !toReset.isEmpty else {
                DispatchQueue.main.async {
                    progress("Khong reset app nao"); completion(backedUp)
                }
                return
            }
            self.resetApps(items: toReset, progress: progress, completion: completion)
        }
    }

    /// Vong lap chung cho backup/reset: chay tuan tu, bao tien do, mot app loi
    /// thi ghi nhan roi di tiep chu khong dung ca me.
    /// Tra ve qua `completion` nhung app chay khong loi.
    private func run(items: [AppItem],
                     taskName: String,
                     progress: @escaping (String) -> Void,
                     completion: @escaping ([AppItem]) -> Void,
                     work: @escaping (AppItem) throws -> String) {
        guard !items.isEmpty else {
            DispatchQueue.main.async { progress("Chon it nhat 1 app"); completion([]) }
            return
        }
        let total = items.count
        let task  = BackgroundTask(name: "appdatamanager.\(taskName)")
        ioQueue.async {
            var succeeded = [AppItem]()
            for (i, item) in items.enumerated() {
                autoreleasepool {
                    let step = "[\(i + 1)/\(total)]"
                    DispatchQueue.main.async { progress("\(step) \(item.displayName)...") }
                    do {
                        let msg = try work(item)
                        succeeded.append(item)
                        DispatchQueue.main.async { progress("\(step) \(msg) ✓") }
                    } catch {
                        plog("\(taskName) loi \(item.bundleID): \(error)")
                        DispatchQueue.main.async {
                            progress("\(step) Loi \(item.displayName): \(error.localizedDescription)")
                        }
                    }
                }
            }
            // Tu dong dong cac app da xu ly, de lan mo sau chung khoi dong lai
            // sach (voi du lieu vua reset/restore) chu khong dung state cu.
            killAppsAndWait(processNames: items.map { $0.processName })
            DispatchQueue.main.async { progress("Da dong \(items.count) app") }
            task.end()
            DispatchQueue.main.async { completion(succeeded) }
        }
    }

    // MARK: - Backup gop nhieu app vao 1 file

    /// Backup tat ca `items` vao 1 zip duy nhat. Tra ve cac app thanh cong.
    /// Cau truc zip (format v3):
    ///   manifest.json        { version:"3", backupDate, apps:[{...}] }
    ///   apps/<bundleID>/data/…
    ///   apps/<bundleID>/groups/<gid>/…
    ///   apps/<bundleID>/plugins/<pid>/…
    ///   apps/<bundleID>/keychain.json
    private func backupCombined(items: [AppItem],
                                progress: @escaping (String) -> Void) throws -> [AppItem] {
        // Uoc luong tong dung luong de kiem tra bo nho
        var size: Int64 = 0
        for item in items {
            let c = resolveAllContainers(bundleID: item.bundleID)
            if let m = c.data { size += dirSize(m) }
            for (_, u) in c.appGroups { size += dirSize(u) }
            for (_, u) in c.plugins   { size += dirSize(u) }
        }
        let free = freeSpace()
        if size > 0 && free > 0 && free < size * 2 {
            throw AppError.insufficientDiskSpace(needed: size * 2, available: free)
        }

        // Dong tat ca app truoc khi copy
        killAppsAndWait(processNames: items.map { $0.processName })

        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: tempRoot) }
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        var appManifests = [[String: Any]]()
        var succeeded    = [AppItem]()
        let total = items.count
        for (i, item) in items.enumerated() {
            let step = "[\(i + 1)/\(total)]"
            DispatchQueue.main.async { progress("\(step) Backup \(item.displayName)...") }
            do {
                let m = try self.stageAppBackup(
                    item: item, into: tempRoot.appendingPathComponent("apps/\(item.bundleID)"))
                appManifests.append(m)
                succeeded.append(item)
                DispatchQueue.main.async { progress("\(step) \(item.displayName) ✓") }
            } catch {
                plog("backup loi \(item.bundleID): \(error)")
                DispatchQueue.main.async {
                    progress("\(step) Loi \(item.displayName): \(error.localizedDescription)")
                }
            }
        }
        guard !succeeded.isEmpty else { throw AppError.nothingSelected }

        let manifest: [String: Any] = [
            "version":    "3",
            "backupDate": ISO8601DateFormatter.shared.string(from: Date()),
            "apps":       appManifests,
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted)
            .write(to: tempRoot.appendingPathComponent("manifest.json"))

        let destDir = PathConfig.backupRoot
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        let stamp  = DateFormatter.fileStamp.string(from: Date())
        let zipURL = destDir.appendingPathComponent("backup_\(stamp).zip")
        if fm.fileExists(atPath: zipURL.path) { try? fm.removeItem(at: zipURL) }
        try fm.zipItem(at: tempRoot, to: zipURL,
                       shouldKeepParent: false, compressionMethod: .deflate)
        pruneCombinedBackups()
        plog("backup gop xong: \(zipURL.lastPathComponent), \(succeeded.count) app")
        return succeeded
    }

    /// Chep du lieu 1 app vao thu muc `appDir` (data/groups/plugins/keychain),
    /// tra ve manifest entry cua app do.
    private func stageAppBackup(item: AppItem, into appDir: URL) throws -> [String: Any] {
        let containers = resolveAllContainers(bundleID: item.bundleID)
        guard let mainURL = containers.data
        else { throw AppError.containerNotFound(item.bundleID) }
        try fm.createDirectory(at: appDir, withIntermediateDirectories: true)

        copyContainerTree(from: mainURL, to: appDir.appendingPathComponent("data"))

        var groupIDs = [String]()
        for (gid, url) in containers.appGroups {
            copyContainerTree(from: url, to: appDir.appendingPathComponent("groups/\(gid)"))
            groupIDs.append(gid)
        }
        var pluginIDs = [String]()
        for (pid, url) in containers.plugins {
            copyContainerTree(from: url, to: appDir.appendingPathComponent("plugins/\(pid)"))
            pluginIDs.append(pid)
        }

        let keychainItems = KeychainManager.backup(bundleID: item.bundleID)
        if let data = try? JSONSerialization.data(withJSONObject: keychainItems, options: []) {
            try? data.write(to: appDir.appendingPathComponent("keychain.json"))
        }
        plog("  staged \(item.bundleID): \(groupIDs.count) group, \(pluginIDs.count) plugin, \(keychainItems.count) keychain")

        return [
            "bundleID":    item.bundleID,
            "displayName": item.displayName,
            "processName": item.processName,
            "appGroups":   groupIDs,
            "plugins":     pluginIDs,
        ]
    }

    /// Giu lai `maxBackupsPerApp` file backup gop moi nhat o thu muc goc.
    private func pruneCombinedBackups() {
        guard let files = try? fm.contentsOfDirectory(
            at: PathConfig.backupRoot, includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]) else { return }
        let zips = files.filter { $0.pathExtension == "zip" }.sorted {
            let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            return d1 > d2
        }
        let limit = Settings.shared.maxBackupsPerApp
        if zips.count > limit { zips.dropFirst(limit).forEach { try? fm.removeItem(at: $0) } }
    }

    // MARK: - Xoa du lieu mot app
    //
    // Muc tieu: dua app ve dung trang thai nhu vua cai xong.
    // Pham vi cham toi, khong hon: container cua app, app group va plugin
    // container cua no, cac file he thong dat ten theo bundleID cua no, va
    // keychain thuoc access group cua no.

    @discardableResult
    private func clearOne(item: AppItem) throws -> Int {
        let containers = resolveAllContainers(bundleID: item.bundleID)
        guard let dataPath = containers.data?.path
        else { throw AppError.containerNotFound(item.bundleID) }

        plog("=== reset: \(item.bundleID) ===")
        var deleted = 0

        // ① Dong app. Chi dong app dang xu ly, khong dong app khac.
        killAppAndWait(processName: item.processName)

        // ② Container chinh
        plog("--- data container ---")
        deleted += countItems(at: dataPath)
        wipeContainerContents(dataPath)

        // ③ App group container (du lieu chia se giua app va extension cua no)
        plog("--- app groups (\(containers.appGroups.count)) ---")
        for (gid, url) in containers.appGroups {
            plog("  group: \(gid)")
            deleted += countItems(at: url.path)
            wipeContainerContents(url.path)
        }

        // ④ Plugin container (widget, share sheet, keyboard...)
        plog("--- plugins (\(containers.plugins.count)) ---")
        for (pid, url) in containers.plugins {
            plog("  plugin: \(pid)")
            deleted += countItems(at: url.path)
            wipeContainerContents(url.path)
        }

        // ⑤ File he thong nam ngoai container
        plog("--- system paths ---")
        SystemCleaner.shared.clearSystemPaths(for: item.bundleID)
        for (gid, _) in containers.appGroups {
            SystemCleaner.shared.clearSystemPaths(for: gid)
        }
        SystemCleaner.shared.clearPushNotifications(for: item.bundleID)
        SystemCleaner.shared.clearManagedPreferences(for: item.bundleID)
        SystemCleaner.shared.clearICloudKV(bundleID: item.bundleID, containerPath: dataPath)

        // ⑥ WebKit — nhieu app dang nhap qua WebView, du lieu nam rieng cho nay
        plog("--- webkit ---")
        SystemCleaner.shared.clearWKWebViewData(containerPath: dataPath)
        for (_, url) in containers.appGroups {
            SystemCleaner.shared.clearWKWebViewData(containerPath: url.path)
        }

        // ⑦ Keychain cua rieng app nay
        KeychainManager.clear(bundleID: item.bundleID)

        // ⑧ Quet lai lan hai.
        // Ly do: mot vai tien trinh he thong (nsurlsessiond, cfprefsd) co the
        // ghi lai file vao container ngay sau khi minh xoa.
        plog("--- quet lai ---")
        wipeContainerContents(dataPath)
        for (_, url) in containers.appGroups { wipeContainerContents(url.path) }

        // ⑨ Tao lai khung thu muc chuan.
        // Wipe sach xong ma khong lam buoc nay thi app se CRASH luc mo (thieu
        // Documents/Library/tmp...). Day la buoc dua app ve nhu vua cai.
        plog("--- tao lai khung thu muc ---")
        recreateContainerSkeleton(at: dataPath, isDataContainer: true)
        for (_, url) in containers.appGroups {
            recreateContainerSkeleton(at: url.path, isDataContainer: false)
        }

        plog("=== xong: \(item.bundleID), \(deleted) muc ===")
        return deleted
    }

    // MARK: - Khoi phuc

    func restore(zipURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        let task = BackgroundTask(name: "appdatamanager.restore")
        ioQueue.async {
            autoreleasepool {
                do {
                    let tmp = self.fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    defer { try? self.fm.removeItem(at: tmp) }
                    // Giai nen thu cong thay cho fm.unzipItem: bo qua symlink.
                    // fm.unzipItem chan symlink tro ra ngoai (uncontainedSymlink =
                    // ArchiveError 14) va hong ca lan restore — ke ca ban backup cu
                    // lo chua symlink cung restore duoc nho buoc nay.
                    try self.extractSkippingSymlinks(zipURL: zipURL, to: tmp)

                    let data = try Data(contentsOf: tmp.appendingPathComponent("manifest.json"))
                    guard let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else { throw AppError.invalidManifest }

                    let resultMsg: String
                    if let apps = manifest["apps"] as? [[String: Any]] {
                        // ── Format v3: backup gop, moi app o apps/<bundleID>/ ──
                        var names = [String]()
                        for appM in apps {
                            guard let bid = appM["bundleID"] as? String else { continue }
                            let ok = self.restoreOneApp(
                                appDir: tmp.appendingPathComponent("apps/\(bid)"), manifest: appM)
                            let dn = (appM["displayName"] as? String) ?? bid
                            if ok {
                                names.append(dn)
                                plog("restore: \(dn) ✓")
                            } else {
                                plog("restore: bo qua \(dn) (khong tim container)")
                            }
                        }
                        guard !names.isEmpty else { throw AppError.containerNotFound("khong app nao") }
                        resultMsg = "Restore xong: \(names.joined(separator: ", ")) ✓"
                    } else {
                        // ── Format cu (v1/v2): 1 app moi file ──
                        guard let bundleID = manifest["bundleID"] as? String
                        else { throw AppError.invalidManifest }
                        let dn = (manifest["displayName"] as? String) ?? bundleID
                        let single: [String: Any] = [
                            "bundleID":    bundleID,
                            "processName": manifest["processName"] as? String ?? "",
                            "appGroups":   manifest["appGroups"] as? [String] ?? [],
                            "plugins":     manifest["plugins"] as? [String] ?? [],
                        ]
                        // v2 co data/ ngay goc; v1 co container/<sub>
                        let hasData = self.fm.fileExists(atPath: tmp.appendingPathComponent("data").path)
                        _ = self.restoreOneApp(appDir: tmp, manifest: single, legacyV1: !hasData)
                        resultMsg = "Restore xong: \(dn) ✓"
                    }

                    task.end()
                    completion(.success(resultMsg))
                } catch {
                    // Ghi ro domain + code de sau con biet loi gi (vd "error 14")
                    let ns = error as NSError
                    plog("restore loi: \(ns.domain) code=\(ns.code) — \(error.localizedDescription)")
                    task.end()
                    completion(.failure(error))
                }
            }
        }
    }

    /// Khoi phuc 1 app tu `appDir` (chua data/groups/plugins/keychain.json).
    /// `legacyV1` = true khi la backup cu chi co container/<sub>.
    /// Tra ve false neu khong tim thay container cua app.
    @discardableResult
    private func restoreOneApp(appDir: URL, manifest appM: [String: Any],
                              legacyV1: Bool = false) -> Bool {
        guard let bundleID = appM["bundleID"] as? String else { return false }
        let containers = resolveAllContainers(bundleID: bundleID)
        guard let mainURL = containers.data else {
            plog("restore: khong tim container \(bundleID)"); return false
        }
        let procRaw = (appM["processName"] as? String) ?? ""
        let proc = procRaw.isEmpty
            ? String(bundleID.components(separatedBy: ".").last?.prefix(15) ?? "")
            : procRaw
        killAppAndWait(processName: proc)
        plog("restore app: \(bundleID)")

        if legacyV1 {
            for sub in Settings.shared.backupSubdirs {
                autoreleasepool {
                    let src = appDir.appendingPathComponent("container/\(sub)")
                    guard fm.fileExists(atPath: src.path) else { return }
                    let dst = mainURL.appendingPathComponent(sub)
                    if fm.fileExists(atPath: dst.path) {
                        wipeContentsRecursive(of: dst); try? fm.removeItem(at: dst)
                    }
                    let isDir = (try? src.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    if isDir { copyDirFull(from: src, to: dst) }
                    else { try? fm.copyItem(at: src, to: dst) }
                }
            }
        } else {
            restoreContainerTree(from: appDir.appendingPathComponent("data"), to: mainURL)
            for gid in (appM["appGroups"] as? [String]) ?? [] {
                guard let dst = containers.appGroups.first(where: { $0.0 == gid })?.1 else {
                    plog("  bo qua group (khong resolve): \(gid)"); continue
                }
                restoreContainerTree(from: appDir.appendingPathComponent("groups/\(gid)"), to: dst)
                plog("  restored group: \(gid)")
            }
            for pid in (appM["plugins"] as? [String]) ?? [] {
                guard let dst = containers.plugins.first(where: { $0.0 == pid })?.1 else {
                    plog("  bo qua plugin (khong resolve): \(pid)"); continue
                }
                restoreContainerTree(from: appDir.appendingPathComponent("plugins/\(pid)"), to: dst)
            }
        }

        if let kData  = try? Data(contentsOf: appDir.appendingPathComponent("keychain.json")),
           let kItems = try? JSONSerialization.jsonObject(with: kData) as? [[String: Any]] {
            KeychainManager.restore(items: kItems)
        }

        // Backup khong luu tmp/Library-Caches nen tao lai cho du khung
        recreateContainerSkeleton(at: mainURL.path, isDataContainer: true)
        for (_, url) in containers.appGroups {
            recreateContainerSkeleton(at: url.path, isDataContainer: false)
        }
        killAppAndWait(processName: proc)   // dong app de lan mo sau nap du lieu moi
        return true
    }

    /// Giai nen zip vao `dst`, bo qua entry symlink va entry co duong dan
    /// khong an toan (thoat ra ngoai `dst`). Thay cho fm.unzipItem de tranh
    /// ArchiveError.uncontainedSymlink (code 14).
    private func extractSkippingSymlinks(zipURL: URL, to dst: URL) throws {
        // init(url:accessMode:) la throwing trong ZIPFoundation 0.9.19
        let archive = try Archive(url: zipURL, accessMode: .read)
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        let base = dst.standardizedFileURL.path

        for entry in archive {
            autoreleasepool {
                if entry.type == .symlink {
                    plog("  bo qua symlink: \(entry.path)")
                    return
                }
                let target = dst.appendingPathComponent(entry.path).standardizedFileURL
                // Chan path traversal: target phai nam trong dst
                guard target.path == base || target.path.hasPrefix(base + "/") else {
                    plog("  bo qua entry ngoai pham vi: \(entry.path)")
                    return
                }
                if entry.type == .directory {
                    try? fm.createDirectory(at: target, withIntermediateDirectories: true)
                } else {
                    try? fm.createDirectory(
                        at: target.deletingLastPathComponent(),
                        withIntermediateDirectories: true)
                    _ = try? archive.extract(entry, to: target)
                }
            }
        }
    }

    // MARK: - Danh sach backup

    func loadAllBackups() -> [BackupEntry] {
        try? fm.createDirectory(at: PathConfig.backupRoot, withIntermediateDirectories: true)
        // Quet de quy: file gop moi nam o thu muc goc, backup cu nam trong
        // thu muc con theo bundleID.
        guard let en = fm.enumerator(at: PathConfig.backupRoot,
            includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
        else { return [] }

        var entries = [BackupEntry]()
        for case let fileURL as URL in en where fileURL.pathExtension == "zip" {
            autoreleasepool {
                // Doc manifest truc tiep trong zip, khong can giai nen ca file
                guard let archive = try? Archive(url: fileURL, accessMode: .read),
                      let entry   = archive["manifest.json"] else { return }
                var raw = Data()
                _ = try? archive.extract(entry, consumer: { raw.append($0) })
                guard let dict    = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                      let dateStr = dict["backupDate"] as? String,
                      let date    = ISO8601DateFormatter.shared.date(from: dateStr)
                else { return }

                var apps = [BackupApp]()
                if let arr = dict["apps"] as? [[String: Any]] {
                    // Format v3: nhieu app
                    for a in arr {
                        if let bid = a["bundleID"] as? String {
                            apps.append(BackupApp(bundleID: bid,
                                                  displayName: (a["displayName"] as? String) ?? bid))
                        }
                    }
                } else if let bid = dict["bundleID"] as? String {
                    // Format cu: 1 app
                    apps.append(BackupApp(bundleID: bid,
                                          displayName: (dict["displayName"] as? String) ?? bid))
                }
                guard !apps.isEmpty else { return }
                let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                entries.append(BackupEntry(zipURL: fileURL, backupDate: date,
                                           fileSize: Int64(size), apps: apps))
            }
        }
        return entries.sorted { $0.backupDate > $1.backupDate }
    }
}
