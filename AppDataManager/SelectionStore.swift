import Foundation

/// Nho lai app nao dang duoc chon, giua cac lan mo app.
///
/// Hai danh sach rieng biet:
///  - reset:  app se bi xoa du lieu
///  - backup: app se duoc sao luu (truoc khi reset, o nut "Backup + Reset")
final class SelectionStore {
    static let shared = SelectionStore()
    private init() {}

    private let resetKey  = "appdatamanager.resetIDs"
    private let backupKey = "appdatamanager.backupIDs"

    // MARK: - Reset
    func saveReset(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: resetKey)
    }
    func loadReset() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: resetKey) ?? [])
    }

    // MARK: - Backup
    func saveBackup(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: backupKey)
    }
    func loadBackup() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: backupKey) ?? [])
    }

    func clearAll() {
        UserDefaults.standard.removeObject(forKey: resetKey)
        UserDefaults.standard.removeObject(forKey: backupKey)
    }
}
