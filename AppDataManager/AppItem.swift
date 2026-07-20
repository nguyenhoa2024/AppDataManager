import Foundation

struct AppItem: Codable {
    let displayName: String
    let bundleID:    String
    /// Ten tien trinh (CFBundleExecutable). Kernel cat con 15 ky tu nen
    /// khi so sanh voi p_comm phai cat theo.
    let processName: String
}

struct BackupEntry {
    let zipURL:      URL
    let bundleID:    String
    let displayName: String
    let backupDate:  Date
    var fileSize:    Int64 = 0
}

enum PathConfig {
    /// /var/mobile/Documents luon ghi duoc duoi TrollStore, khac voi container
    /// cua app (bi xoa khi go app).
    static let backupRoot = URL(fileURLWithPath:
        "/private/var/mobile/Documents/AppDataManager/backups")
    static let dataContainersBase = URL(fileURLWithPath:
        "/private/var/mobile/Containers/Data/Application")
    static let bundleContainersBase = URL(fileURLWithPath:
        "/private/var/mobile/Containers/Bundle/Application")
    static let appGroupBase = URL(fileURLWithPath:
        "/private/var/mobile/Containers/Shared/AppGroup")

    static func backupDir(for bundleID: String) -> URL {
        backupRoot.appendingPathComponent(bundleID)
    }
}

enum AppError: LocalizedError {
    case containerNotFound(String)
    case invalidManifest
    case nothingSelected
    case insufficientDiskSpace(needed: Int64, available: Int64)
    case zipFailed(String)

    var errorDescription: String? {
        switch self {
        case .containerNotFound(let id): return "Khong tim thay container: \(id)"
        case .invalidManifest:           return "File backup bi loi"
        case .nothingSelected:           return "Chon it nhat 1 app"
        case .insufficientDiskSpace(let needed, let available):
            let f = ByteCountFormatter(); f.countStyle = .file
            return "Khong du bo nho. Can \(f.string(fromByteCount: needed)), "
                 + "con \(f.string(fromByteCount: available))"
        case .zipFailed(let reason):     return "Zip loi: \(reason)"
        }
    }
}

extension DateFormatter {
    static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    static let display: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}

extension ISO8601DateFormatter {
    static let shared = ISO8601DateFormatter()
}
