import Foundation

final class Settings {
    static let shared = Settings()
    private init() {}

    /// Giu toi da bao nhieu ban backup cho moi app truoc khi xoa ban cu nhat.
    let maxBackupsPerApp = 5

    /// Caches lon hon nguong nay thi bo qua khi backup — thu muc cache co the
    /// vai GB ma khoi phuc lai cung khong co y nghia gi.
    let maxCachesBytes: Int64 = 200 * 1024 * 1024

    /// Thu muc duoc copy vao file backup.
    ///
    /// Day la cac thu muc chua du lieu that su cua app. Khong backup `tmp`
    /// va `SystemData` vi iOS tu quan ly va tu tao lai.
    var backupSubdirs: [String] {
        [
            "Documents",
            "Library/Preferences",
            "Library/Application Support",
            "Library/Cookies",
            "Library/WebKit",
            "Library/HTTPStorages",
            "Library/Caches",
        ]
    }

    /// Thu muc hien trong man hinh xem duong dan.
    /// Chi de xem — viec xoa lam o muc container chu khong theo danh sach nay.
    var inspectSubdirs: [String] {
        [
            "Documents",
            "Library/Preferences",
            "Library/Application Support",
            "Library/Caches",
            "Library/Cookies",
            "Library/WebKit",
            "Library/HTTPStorages",
            "Library/Saved Application State",
            "Library/SplashBoard",
            "tmp",
            "SystemData",
        ]
    }

    var totalBackupCount: Int {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(
            at: PathConfig.backupRoot, includingPropertiesForKeys: nil, options: [])) ?? []
        return dirs.reduce(0) { total, dir in
            let files = (try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [])) ?? []
            return total + files.filter { $0.pathExtension == "zip" }.count
        }
    }
}
