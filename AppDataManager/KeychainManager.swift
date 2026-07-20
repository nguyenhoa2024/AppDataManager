import Foundation
import Security

/// Sao luu / khoi phuc / xoa keychain THEO access group cua mot app.
///
/// Entitlement `keychain-access-groups = *` cho phep app nay nhin thay keychain
/// cua moi app. Vi vay moi thao tac o day deu phai loc theo access group da
/// resolve duoc cho bundleID dang xu ly — neu khong se dung nham item cua app khac.
enum KeychainManager {

    /// Chi dung 2 class chua du lieu dang nhap.
    /// Khong dung toi kSecClassCertificate / kSecClassKey / kSecClassIdentity:
    /// do la chung chi va khoa dung chung o muc he thong, xoa nham se hong
    /// nhung thu khong lien quan den app dang chon.
    private static let itemClasses: [CFString] = [
        kSecClassGenericPassword,
        kSecClassInternetPassword,
    ]

    // MARK: - Resolve access group

    /// Tim cac access group thuoc ve `bundleID`.
    ///
    /// Ba nguon, quan trong nhat la (1):
    ///  1. Doc THANG tu entitlements cua app — chinh xac tuyet doi. Nhieu app
    ///     dung nhom keychain khong lien quan gi ten bundle (vd LINE
    ///     jp.naver.line lai luu session o "ZW4U99SQQ3.com.linecorp.trident.shared").
    ///     Neu chi suy tu bundleID se bo sot -> restore khong lay lai duoc session.
    ///  2. Suy tu chinh bundleID (bundleID va vendor prefix).
    ///  3. Quet keychain thuc te, lay group co duoi khop bundleID/vendor.
    static func resolveAccessGroups(bundleID: String) -> [String] {
        let parts  = bundleID.components(separatedBy: ".")
        let vendor = parts.count >= 2 ? "\(parts[0]).\(parts[1])" : bundleID

        var groups = Set([bundleID, vendor])

        // (1) Tu entitlements — nguon dang tin nhat
        groups.formUnion(entitlementKeychainGroups(bundleID: bundleID))

        // (3) Quet ca hai class: app chi luu internet password se khong lo ra
        // group co team ID neu chi quet generic password.
        for cls in itemClasses {
            let query: [String: Any] = [
                kSecClass as String:              cls,
                kSecReturnAttributes as String:   true,
                kSecMatchLimit as String:         kSecMatchLimitAll,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            ]
            var ref: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess,
                  let items = ref as? [[String: Any]] else { continue }

            for item in items {
                guard let g = item[kSecAttrAccessGroup as String] as? String else { continue }
                // "TEAMID.com.example.app" -> phan sau dau cham dau tien
                let withoutTeam = g.contains(".")
                    ? g.components(separatedBy: ".").dropFirst().joined(separator: ".")
                    : g
                if g == bundleID || g == vendor
                    || withoutTeam == bundleID || withoutTeam == vendor
                    || withoutTeam.hasPrefix("\(vendor).") {
                    groups.insert(g)
                }
            }
        }
        return Array(groups)
    }

    /// Item co thuoc ve app dang xu ly khong.
    private static func belongs(_ item: [String: Any], to groups: Set<String>) -> Bool {
        guard let g = item[kSecAttrAccessGroup as String] as? String else { return false }
        return groups.contains(g)
    }

    /// Doc danh sach `keychain-access-groups` tu entitlements nhung trong
    /// binary cua app. Entitlements luu duoi dang plist XML text trong chu ky
    /// so, nen tim chuoi key roi bat cac <string> ngay sau la lay duoc.
    static func entitlementKeychainGroups(bundleID: String) -> [String] {
        guard let bundleDir = resolveBundlePath(bundleID: bundleID),
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: bundleDir, includingPropertiesForKeys: nil, options: []),
              let dotApp = contents.first(where: { $0.pathExtension == "app" }),
              let info   = readPlist(dotApp.appendingPathComponent("Info.plist")),
              let exe    = info["CFBundleExecutable"] as? String
        else { return [] }

        let binURL = dotApp.appendingPathComponent(exe)
        // mmap: binary co the vai tram MB, khong nap het vao RAM
        guard let data = try? Data(contentsOf: binURL, options: .mappedIfSafe),
              let keyRange = data.range(of: Data("keychain-access-groups".utf8))
        else { return [] }

        // Cua so 8KB sau key du chua vai group
        let end  = min(data.count, keyRange.upperBound + 8192)
        let tail = data.subdata(in: keyRange.upperBound ..< end)
        guard let s = String(data: tail, encoding: .ascii) ?? String(data: tail, encoding: .utf8),
              let arrEnd = s.range(of: "</array>")
        else { return [] }

        var groups = [String]()
        var rest = s[s.startIndex ..< arrEnd.lowerBound]
        while let open = rest.range(of: "<string>"),
              let close = rest.range(of: "</string>"),
              open.upperBound <= close.lowerBound {
            groups.append(String(rest[open.upperBound ..< close.lowerBound]))
            rest = rest[close.upperBound...]
        }
        if !groups.isEmpty { plog("keychain groups tu entitlements \(bundleID): \(groups)") }
        return groups
    }

    // MARK: - Backup

    static func backup(bundleID: String) -> [[String: Any]] {
        let groups = Set(resolveAccessGroups(bundleID: bundleID))
        var results = [[String: Any]]()

        for cls in itemClasses {
            let query: [String: Any] = [
                kSecClass as String:              cls,
                kSecReturnAttributes as String:   true,
                kSecReturnData as String:         true,
                kSecMatchLimit as String:         kSecMatchLimitAll,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            ]
            var ref: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess,
                  let items = ref as? [[String: Any]] else { continue }

            // Loc theo access group — day la buoc quan trong, khong duoc bo.
            for item in items where belongs(item, to: groups) {
                if let s = serialize(item, cls: cls as String) { results.append(s) }
            }
        }

        let unique = dedupe(results)
        plog("keychain backup \(bundleID): \(unique.count) items, \(groups.count) groups")
        return unique
    }

    /// Thuoc tinh dinh danh duy nhat mot item.
    ///
    /// kSecAttrService chi co o generic password. Internet password duoc phan
    /// biet bang server/port/path/protocol/securityDomain — neu chi so
    /// account+service+group thi hai tai khoan tren hai website khac nhau se
    /// bi coi la mot, dan den mat item khi backup va ghi de khi restore.
    private static let identityAttributes: [CFString] = [
        kSecAttrAccount, kSecAttrService, kSecAttrAccessGroup,
        kSecAttrServer, kSecAttrPort, kSecAttrPath,
        kSecAttrProtocol, kSecAttrSecurityDomain,
    ]

    private static func identityKey(for item: [String: Any]) -> String {
        let cls = "\(item["_secClass"] ?? "")"
        let rest = identityAttributes
            .map { attr in "\(item[attr as String] ?? "")" }
            .joined(separator: "|")
        return cls + "|" + rest
    }

    /// Mot item co the xuat hien o nhieu query khac nhau — gom lai de khong
    /// luu trung.
    private static func dedupe(_ items: [[String: Any]]) -> [[String: Any]] {
        var seen = Set<String>()
        return items.filter { item in
            seen.insert(identityKey(for: item)).inserted
        }
    }

    private static func serialize(_ item: [String: Any], cls: String) -> [String: Any]? {
        var out: [String: Any] = ["_secClass": cls]
        for (k, v) in item {
            switch v {
            case let d as Data:     out[k] = d.base64EncodedString(); out[k + "__b64"] = true
            case let s as String:   out[k] = s
            case let n as NSNumber: out[k] = n
            default: break
            }
        }
        return out.count > 1 ? out : nil
    }

    // MARK: - Restore

    /// Thuoc tinh duoc phep dua vao SecItemAdd.
    ///
    /// SecItemCopyMatching tra ve ca thuoc tinh chi doc (cdat/mdat — ngay tao,
    /// ngay sua). Nem nhung cai do vao SecItemAdd se bi errSecParam va item
    /// bi bo im lang, nen phai loc truoc.
    private static let writableAttributes: Set<String> = [
        kSecValueData as String,
        kSecAttrAccount as String,
        kSecAttrService as String,
        kSecAttrAccessGroup as String,
        kSecAttrLabel as String,
        kSecAttrDescription as String,
        kSecAttrComment as String,
        kSecAttrGeneric as String,
        kSecAttrAccessible as String,
        kSecAttrSynchronizable as String,
        kSecAttrIsInvisible as String,
        // Rieng cho kSecClassInternetPassword
        kSecAttrServer as String,
        kSecAttrPort as String,
        kSecAttrPath as String,
        kSecAttrProtocol as String,
        kSecAttrAuthenticationType as String,
        kSecAttrSecurityDomain as String,
    ]

    static func restore(items: [[String: Any]]) {
        var restored = 0
        for item in items {
            guard let cls = item["_secClass"] as? String else { continue }

            var addQuery: [String: Any] = [kSecClass as String: cls as CFString]
            for (k, v) in item {
                guard k != "_secClass", !k.hasSuffix("__b64") else { continue }
                guard writableAttributes.contains(k) else { continue }
                if item[k + "__b64"] as? Bool == true,
                   let s = v as? String, let d = Data(base64Encoded: s) {
                    addQuery[k] = d
                } else {
                    addQuery[k] = v
                }
            }
            // Khong co payload thi khong khoi phuc duoc gi
            guard addQuery[kSecValueData as String] != nil else { continue }

            // Xoa ban cu (neu co) roi them lai — SecItemAdd bao loi neu trung.
            // Phai dung du bo thuoc tinh dinh danh, khong se xoa nham cac item
            // khac cung account trong cung access group.
            var delQuery: [String: Any] = [kSecClass as String: cls as CFString]
            for attr in identityAttributes {
                if let v = addQuery[attr as String] { delQuery[attr as String] = v }
            }
            SecItemDelete(delQuery as CFDictionary)
            if SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess { restored += 1 }
        }
        plog("keychain restore: \(restored)/\(items.count) items")
    }

    // MARK: - Clear

    /// Xoa keychain cua rieng `bundleID`. Item nao khong thuoc access group da
    /// resolve thi bo qua — khong dung den keychain cua app khac.
    static func clear(bundleID: String) {
        let groups = Set(resolveAccessGroups(bundleID: bundleID))
        guard !groups.isEmpty else { return }
        plog("keychain clear \(bundleID): \(groups.count) groups")

        var deleted = 0
        for cls in itemClasses {
            let query: [String: Any] = [
                kSecClass as String:              cls,
                kSecReturnAttributes as String:   true,
                kSecMatchLimit as String:         kSecMatchLimitAll,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            ]
            var ref: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess,
                  let items = ref as? [[String: Any]] else { continue }

            for item in items where belongs(item, to: groups) {
                var delQuery: [String: Any] = [
                    kSecClass as String:              cls,
                    kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
                ]
                for attr in identityAttributes {
                    if let v = item[attr as String] { delQuery[attr as String] = v }
                }
                if SecItemDelete(delQuery as CFDictionary) == errSecSuccess { deleted += 1 }
            }
        }
        plog("keychain clear \(bundleID): da xoa \(deleted) items")
    }
}
