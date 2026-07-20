import Foundation

/// Liet ke app de backup/reset.
///
/// Chi lay app "binh thuong": co bundle o /var/containers/Bundle/Application
/// (App Store + TrollStore) va co data container. App cai qua Sileo/dpkg khong
/// co bundle o do nen bi loai — dung yeu cau chi hien app App Store/he thong.
final class AppEnumerator {
    static func installedApps() -> [AppItem] {
        let fm    = FileManager.default
        let ownID = Bundle.main.bundleIdentifier ?? ""

        // ── Buoc 1: quet bundle containers, dung ban do bundleID -> (ten, process).
        // Ban do nay dong thoi la "danh sach trang": chi app co bundle o day moi
        // duoc phep xuat hien — nho vay app Sileo/dpkg bi loai tu goc.
        var nameMap = [String: String]()
        var procMap = [String: String]()

        if let dirs = try? fm.contentsOfDirectory(
            at: PathConfig.bundleContainersBase,
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for dir in dirs { autoreleasepool {
                guard let contents = try? fm.contentsOfDirectory(
                          at: dir, includingPropertiesForKeys: nil, options: []),
                      let dotApp   = contents.first(where: {
                          $0.pathExtension == "app" && !$0.lastPathComponent.hasPrefix(".")
                      }),
                      let dict     = readPlist(dotApp.appendingPathComponent("Info.plist")),
                      let bid      = dict["CFBundleIdentifier"] as? String,
                      bid != ownID, !bid.hasPrefix("com.apple.")
                else { return }
                let name = (dict["CFBundleDisplayName"] as? String)
                        ?? (dict["CFBundleName"] as? String)
                        ?? dotApp.deletingPathExtension().lastPathComponent
                let exe  = (dict["CFBundleExecutable"] as? String) ?? ""
                nameMap[bid] = name.isEmpty ? bid : name
                procMap[bid] = String(exe.prefix(15))
            }}
        }

        // ── Buoc 2: quet data containers, chi giu app co trong nameMap
        guard let dataDirs = try? fm.contentsOfDirectory(
            at: PathConfig.dataContainersBase,
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [] }

        var results = [AppItem]()
        var seen    = Set<String>()
        for dir in dataDirs { autoreleasepool {
            let meta = dir.appendingPathComponent(
                ".com.apple.mobile_container_manager.metadata.plist")
            guard let dict = readPlist(meta),
                  let bid  = dict["MCMMetadataIdentifier"] as? String,
                  // Loc chinh: phai co bundle App Store/TrollStore tuong ung
                  let name = nameMap[bid],
                  !seen.contains(bid)
            else { return }
            seen.insert(bid)
            let proc = procMap[bid] ?? String(name.prefix(15))
            results.append(AppItem(displayName: name, bundleID: bid, processName: proc))
        }}
        return results.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }
}

func readPlist(_ url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url),
          let obj  = try? PropertyListSerialization.propertyList(
              from: data, format: nil) as? [String: Any]
    else { return nil }
    return obj
}
