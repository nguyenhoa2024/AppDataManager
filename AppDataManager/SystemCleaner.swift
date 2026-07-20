import Foundation

/// Xoa cac file thuoc ve MOT app cu the nam ngoai container cua no.
///
/// Nguyen tac: moi ham o day deu nhan `identifier` (bundleID hoac app group ID)
/// va chi dung toi duong dan co ten khop voi identifier do. Khong co ham nao
/// tac dong len toan he thong hay len app khac.
final class SystemCleaner {
    static let shared = SystemCleaner()
    private let fm = FileManager.default
    private init() {}

    // MARK: - Duong dan he thong nam ngoai container
    //
    // iOS khong giu het du lieu cua app trong container. Mot phan nam rai o
    // /var/mobile/Library, dat ten theo bundleID. Day la danh sach cac cho do.
    func clearSystemPaths(for identifier: String) {
        let base = "/private/var/mobile/Library"

        let exactPaths = [
            "\(base)/Cookies/\(identifier).binarycookies",
            "\(base)/Preferences/\(identifier).plist",
            "\(base)/WebKit/\(identifier)",
            "\(base)/Caches/\(identifier)",
            "\(base)/SplashBoard/Snapshots/\(identifier)",
            "\(base)/SplashBoard/Snapshots/sceneID:\(identifier)-default",
            "\(base)/HTTPStorages/\(identifier)",
            "\(base)/Safari/PerSitePreferences/\(identifier)",
            "\(base)/Caches/com.apple.nsurlsessiond/Downloads/\(identifier)",
            "\(base)/WebKit/WebsiteData/\(identifier)",
            "\(base)/Metadata/\(identifier)",
            "\(base)/LocalCache/\(identifier)",
            "\(base)/Caches/CloudKit/\(identifier)",
            "\(base)/Application Support/CachedData/\(identifier)",
            "\(base)/Saved Application State/\(identifier).savedState",
        ]
        for path in exactPaths {
            guard fm.fileExists(atPath: path) else { continue }
            shellRm(path)
            try? fm.removeItem(atPath: path)
            plog("  sys rm: \(path.components(separatedBy: "/").last ?? path)")
        }

        // Quet them cac file dat ten dang "<bundleID>.something" trong cung thu muc.
        // Phai co ranh gioi dau cham: hasPrefix tran se an nham "com.foo.bar2"
        // khi dang xu ly "com.foo.bar", con `contains` thi con te hon.
        let scanDirs = [
            "\(base)/Cookies",
            "\(base)/Preferences",
            "\(base)/WebKit",
            "\(base)/Caches",
            "\(base)/SplashBoard/Snapshots",
            "\(base)/HTTPStorages",
            "\(base)/WebKit/WebsiteData",
            "\(base)/Caches/com.apple.nsurlsessiond/Downloads",
            "\(base)/Metadata",
            "\(base)/LocalCache",
            "\(base)/Caches/CloudKit",
            "\(base)/Saved Application State",
        ]
        for dir in scanDirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item == identifier || item.hasPrefix(identifier + ".") {
                let full = "\(dir)/\(item)"
                shellRm(full)
                try? fm.removeItem(atPath: full)
                plog("  sys rm: \(item)")
            }
        }
    }

    // MARK: - Du lieu WKWebView nam trong container
    //
    // Bao gom WebsiteData, LocalStorage, IndexedDB, ServiceWorkerRegistrations...
    // Tat ca deu nam duoi Library/WebKit nen xoa ca thu muc la du.
    func clearWKWebViewData(containerPath: String) {
        for sub in ["Library/WebKit", "Library/Cookies"] {
            let path = "\(containerPath)/\(sub)"
            guard fm.fileExists(atPath: path) else { continue }
            shellRm(path)
            try? fm.removeItem(atPath: path)
            plog("  webkit rm: \(sub)")
        }
    }

    // MARK: - iCloud key-value store cache
    func clearICloudKV(bundleID: String, containerPath: String) {
        let paths = [
            "\(containerPath)/Library/SyncedPreferences",
            "/private/var/mobile/Library/SyncedPreferences/\(bundleID).plist",
        ]
        for path in paths where fm.fileExists(atPath: path) {
            shellRm(path)
            try? fm.removeItem(atPath: path)
            plog("  icloud kv rm: \(URL(fileURLWithPath: path).lastPathComponent)")
        }

        let syncDir = "/private/var/mobile/Library/SyncedPreferences"
        if let items = try? fm.contentsOfDirectory(atPath: syncDir) {
            for item in items where item == bundleID || item.hasPrefix(bundleID + ".") {
                try? fm.removeItem(atPath: "\(syncDir)/\(item)")
                plog("  icloud kv rm: \(item)")
            }
        }
    }

    // MARK: - Thong bao da gui cua app
    func clearPushNotifications(for bundleID: String) {
        let paths = [
            "/private/var/mobile/Library/BulletinBoard/\(bundleID)",
            "/private/var/mobile/Library/UserNotifications/\(bundleID)",
        ]
        for path in paths where fm.fileExists(atPath: path) {
            shellRm(path)
            try? fm.removeItem(atPath: path)
        }
        plog("  push cleared: \(bundleID)")
    }

    // MARK: - Managed preferences (do profile MDM day xuong)
    func clearManagedPreferences(for bundleID: String) {
        let path = "/private/var/mobile/Library/Managed Preferences/mobile/\(bundleID).plist"
        if fm.fileExists(atPath: path) {
            try? fm.removeItem(atPath: path)
            plog("  managed pref rm: \(bundleID)")
        }
    }
}
