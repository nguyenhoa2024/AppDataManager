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
            at: src, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        else { return }
        for item in items {
            autoreleasepool {
                let target = dst.appendingPathComponent(item.lastPathComponent)
                let isDir  = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDir {
                    copyDirFull(from: item, to: target)
                } else {
                    if fm.fileExists(atPath: target.path) { try? fm.removeItem(at: target) }
                    try? fm.copyItem(at: item, to: target)
                }
            }
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

    private func pruneOldBackups(for bundleID: String) {
        let limit = Settings.shared.maxBackupsPerApp
        let dir   = PathConfig.backupDir(for: bundleID)
        guard let files = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey], options: []) else { return }
        let zips = files.filter { $0.pathExtension == "zip" }.sorted {
            let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            return d1 > d2
        }
        if zips.count > limit {
            zips.dropFirst(limit).forEach { try? fm.removeItem(at: $0) }
        }
    }

    // MARK: - API cong khai

    /// `completion` nhan ve danh sach app THANH CONG — quan trong voi
    /// backupThenReset, xem giai thich o duoi.
    func backupApps(items: [AppItem],
                    progress: @escaping (String) -> Void,
                    completion: @escaping ([AppItem]) -> Void) {
        run(items: items, taskName: "backup", progress: progress, completion: completion) { item in
            try self.backupOne(item: item)
            return "Da luu \(item.displayName)"
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

    /// Backup roi reset — CHI reset nhung app da backup thanh cong.
    ///
    /// Neu reset ca nhung app backup that bai (het bo nho, khong tim thay
    /// container...) thi du lieu mat han ma khong co gi khoi phuc. Vi vay
    /// phai loc theo ket qua cua buoc backup.
    func backupThenResetApps(items: [AppItem],
                             progress: @escaping (String) -> Void,
                             completion: @escaping ([AppItem]) -> Void) {
        backupApps(items: items, progress: progress) { backedUp in
            let skipped = items.filter { item in
                !backedUp.contains { $0.bundleID == item.bundleID }
            }
            for item in skipped {
                let msg = "Bo qua reset \(item.displayName): backup that bai"
                plog(msg)
                DispatchQueue.main.async { progress(msg) }
            }
            guard !backedUp.isEmpty else {
                DispatchQueue.main.async {
                    progress("Khong app nao backup duoc, khong reset gi ca")
                    completion([])
                }
                return
            }
            self.resetApps(items: backedUp, progress: progress, completion: completion)
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
            task.end()
            DispatchQueue.main.async { completion(succeeded) }
        }
    }

    // MARK: - Backup mot app

    private func backupOne(item: AppItem) throws {
        guard let container = resolveContainerPath(bundleID: item.bundleID)
        else { throw AppError.containerNotFound(item.bundleID) }

        plog("backup: \(item.bundleID) → \(container.lastPathComponent)")

        let size = dirSize(container)
        let free = freeSpace()
        // Can gap doi: mot ban copy tam + mot file zip.
        // free == 0 nghia la khong doc duoc dung luong trong (khong phai la
        // het bo nho) — cu chay tiep, de buoc zip bao loi that neu thieu cho.
        if size > 0 && free > 0 && free < size * 2 {
            throw AppError.insufficientDiskSpace(needed: size * 2, available: free)
        }

        // Dong app truoc khi copy, tranh copy phai file dang duoc ghi do
        killAppAndWait(processName: item.processName)

        let destDir = PathConfig.backupDir(for: item.bundleID)
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        let stamp  = DateFormatter.fileStamp.string(from: Date())
        let zipURL = destDir.appendingPathComponent("\(item.bundleID)_\(stamp).zip")

        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: tempRoot) }
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let stage = tempRoot.appendingPathComponent("container")
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)

        for sub in Settings.shared.backupSubdirs {
            autoreleasepool {
                let src = container.appendingPathComponent(sub)
                guard fm.fileExists(atPath: src.path) else { return }
                // Caches co the phinh rat to ma lai khong dang luu
                if sub == "Library/Caches" && dirSize(src) > Settings.shared.maxCachesBytes {
                    plog("  bo qua Caches: qua lon"); return
                }
                let dst = stage.appendingPathComponent(sub)
                try? fm.createDirectory(at: dst.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
                let isDir = (try? src.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDir { copyDirFull(from: src, to: dst) }
                else { try? fm.copyItem(at: src, to: dst) }
            }
        }

        let manifest: [String: Any] = [
            "bundleID":    item.bundleID,
            "displayName": item.displayName,
            "processName": item.processName,
            "backupDate":  ISO8601DateFormatter.shared.string(from: Date()),
            "version":     "1",
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted)
            .write(to: tempRoot.appendingPathComponent("manifest.json"))

        let keychainItems = KeychainManager.backup(bundleID: item.bundleID)
        if let data = try? JSONSerialization.data(withJSONObject: keychainItems,
                                                  options: .prettyPrinted) {
            try? data.write(to: tempRoot.appendingPathComponent("keychain.json"))
        }

        if fm.fileExists(atPath: zipURL.path) { try? fm.removeItem(at: zipURL) }
        try fm.zipItem(at: tempRoot, to: zipURL,
                       shouldKeepParent: false, compressionMethod: .deflate)
        pruneOldBackups(for: item.bundleID)
        plog("backup xong: \(zipURL.lastPathComponent)")
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
                    try self.fm.unzipItem(at: zipURL, to: tmp)

                    let data = try Data(contentsOf: tmp.appendingPathComponent("manifest.json"))
                    guard let manifest    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let bundleID    = manifest["bundleID"]    as? String,
                          let displayName = manifest["displayName"] as? String
                    else { throw AppError.invalidManifest }

                    guard let container = resolveContainerPath(bundleID: bundleID)
                    else { throw AppError.containerNotFound(bundleID) }

                    let proc = (manifest["processName"] as? String)
                        ?? String(bundleID.components(separatedBy: ".").last?.prefix(15) ?? "")
                    killAppAndWait(processName: proc)

                    plog("restore: \(displayName) → \(container.lastPathComponent)")
                    for sub in Settings.shared.backupSubdirs {
                        autoreleasepool {
                            let src = tmp.appendingPathComponent("container/\(sub)")
                            guard self.fm.fileExists(atPath: src.path) else { return }
                            let dst = container.appendingPathComponent(sub)
                            if self.fm.fileExists(atPath: dst.path) {
                                self.wipeContentsRecursive(of: dst)
                                try? self.fm.removeItem(at: dst)
                            }
                            let isDir = (try? src.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                            if isDir { self.copyDirFull(from: src, to: dst) }
                            else { try? self.fm.copyItem(at: src, to: dst) }
                            plog("  restored: \(sub)")
                        }
                    }

                    if let kData  = try? Data(contentsOf: tmp.appendingPathComponent("keychain.json")),
                       let kItems = try? JSONSerialization.jsonObject(with: kData) as? [[String: Any]] {
                        KeychainManager.restore(items: kItems)
                    }

                    task.end()
                    completion(.success("Restore xong: \(displayName) ✓"))
                } catch {
                    plog("restore loi: \(error)")
                    task.end()
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Danh sach backup

    func loadAllBackups() -> [BackupEntry] {
        try? fm.createDirectory(at: PathConfig.backupRoot, withIntermediateDirectories: true)
        guard let appDirs = try? fm.contentsOfDirectory(
            at: PathConfig.backupRoot, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]) else { return [] }

        var entries = [BackupEntry]()
        for appDir in appDirs {
            guard let files = try? fm.contentsOfDirectory(
                at: appDir, includingPropertiesForKeys: [.fileSizeKey], options: [])
            else { continue }
            for fileURL in files where fileURL.pathExtension == "zip" {
                autoreleasepool {
                    // Doc manifest truc tiep trong zip, khong can giai nen ca file
                    guard let archive = try? Archive(url: fileURL, accessMode: .read),
                          let entry   = archive["manifest.json"] else { return }
                    var raw = Data()
                    _ = try? archive.extract(entry, consumer: { raw.append($0) })
                    guard let dict        = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                          let bundleID    = dict["bundleID"]    as? String,
                          let displayName = dict["displayName"] as? String,
                          let dateStr     = dict["backupDate"]  as? String,
                          let date        = ISO8601DateFormatter.shared.date(from: dateStr)
                    else { return }
                    let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    entries.append(BackupEntry(zipURL: fileURL, bundleID: bundleID,
                                               displayName: displayName, backupDate: date,
                                               fileSize: Int64(size)))
                }
            }
        }
        return entries.sorted { $0.backupDate > $1.backupDate }
    }
}
