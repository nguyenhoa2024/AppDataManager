import Foundation

final class AppEnumerator {
    static func installedApps() -> [AppItem] {
        let fm    = FileManager.default
        let ownID = Bundle.main.bundleIdentifier ?? ""
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

        guard let dataDirs = try? fm.contentsOfDirectory(
            at: PathConfig.dataContainersBase,
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [] }

        let skip = ["com.apple.", "com.openssh.", "com.saurik."]
        var results = [AppItem]()
        for dir in dataDirs { autoreleasepool {
            let meta = dir.appendingPathComponent(
                ".com.apple.mobile_container_manager.metadata.plist")
            guard let dict = readPlist(meta),
                  let bid  = dict["MCMMetadataIdentifier"] as? String,
                  !bid.isEmpty, bid != ownID,
                  !skip.contains(where: { bid.hasPrefix($0) }) else { return }
            let name = nameMap[bid] ?? (bid.components(separatedBy: ".").last ?? bid)
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
