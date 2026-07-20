import Foundation

/// Nho lai app nao dang duoc chon, giua cac lan mo app.
final class SelectionStore {
    static let shared = SelectionStore()
    private init() {}

    private let selectionKey = "appdatamanager.selectedIDs"

    func save(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: selectionKey)
    }

    func load() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: selectionKey) ?? [])
    }

    func clearAll() {
        UserDefaults.standard.removeObject(forKey: selectionKey)
    }
}
