import Foundation
import Darwin

// ── Path config ──────────────────────────────────────────────────────────────
// All container base paths
enum ContainerBase {
    static let data     = "/private/var/mobile/Containers/Data/Application"
    static let bundle   = "/private/var/containers/Bundle/Application"
    static let appGroup = "/private/var/mobile/Containers/Shared/AppGroup"
    static let plugin   = "/private/var/mobile/Containers/Data/PluginKitPlugin"
    static let library  = "/private/var/mobile/Library"
}

// All resolved UUID paths for one bundleID
struct AppContainers {
    var bundleID:   String
    var data:       URL?           // main Data container UUID path
    var bundle:     URL?           // Bundle container UUID path
    var appGroups:  [(String, URL)]  // [(groupIdentifier, UUID path)]
    var plugins:    [(String, URL)]  // [(pluginBundleID, UUID path)]
}

// ── Resolve functions ─────────────────────────────────────────────────────────

// Resolve Data container UUID (primary — used for all data ops)
func resolveContainerPath(bundleID: String) -> URL? {
    guard let entries = try? FileManager.default.contentsOfDirectory(
              at: URL(fileURLWithPath: ContainerBase.data),
              includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    else { return nil }
    for entry in entries {
        let meta = entry.appendingPathComponent(
            ".com.apple.mobile_container_manager.metadata.plist")
        if let dict = readPlist(meta),
           let id   = dict["MCMMetadataIdentifier"] as? String,
           id == bundleID { return entry }
    }
    return nil
}

// Resolve Bundle container UUID
func resolveBundlePath(bundleID: String) -> URL? {
    guard let entries = try? FileManager.default.contentsOfDirectory(
              at: URL(fileURLWithPath: ContainerBase.bundle),
              includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    else { return nil }
    for entry in entries {
        // Bundle containers have .app inside
        guard let contents = try? FileManager.default.contentsOfDirectory(
                  at: entry, includingPropertiesForKeys: nil, options: []),
              let dotApp = contents.first(where: { $0.pathExtension == "app" }),
              let dict   = readPlist(dotApp.appendingPathComponent("Info.plist")),
              let id     = dict["CFBundleIdentifier"] as? String,
              id == bundleID
        else { continue }
        return entry
    }
    return nil
}

// Resolve ALL AppGroup UUID paths for a bundleID
func resolveAllAppGroups(bundleID: String) -> [(String, URL)] {
    guard let entries = try? FileManager.default.contentsOfDirectory(
              at: URL(fileURLWithPath: ContainerBase.appGroup),
              includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    else { return [] }

    let parts  = bundleID.components(separatedBy: ".")
    let vendor = parts.count >= 2 ? "\(parts[0]).\(parts[1])" : bundleID
    let short  = parts.last?.lowercased() ?? bundleID.lowercased()

    var results = [(String, URL)]()
    for entry in entries {
        let meta = entry.appendingPathComponent(
            ".com.apple.mobile_container_manager.metadata.plist")
        guard let dict = readPlist(meta) else { continue }
        let gid    = dict["MCMMetadataIdentifier"] as? String ?? ""
        let gidLow = gid.lowercased()

        var matched = false

        // Method 1: MCMMetadataContent array lists this app
        if let apps = dict["MCMMetadataContent"] as? [String] {
            matched = apps.contains(bundleID)
                || apps.contains(where: { $0.hasPrefix(vendor) })
        }
        // Method 2: group identifier contains vendor/app name
        if !matched {
            matched = gidLow.contains(vendor.lowercased())
                || gidLow.contains(".\(short)")
                || gid == bundleID
                || gid.hasPrefix("group.\(vendor)")
                || gid.hasPrefix("group.\(bundleID)")
        }
        if matched {
            results.append((gid, entry))
            plog("AppGroup UUID: \(gid) → \(entry.lastPathComponent)")
        }
    }
    return results
}

// Resolve ALL Plugin/Extension UUID paths for a bundleID
func resolveAllPlugins(bundleID: String) -> [(String, URL)] {
    guard let entries = try? FileManager.default.contentsOfDirectory(
              at: URL(fileURLWithPath: ContainerBase.plugin),
              includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    else { return [] }

    let prefix = bundleID + "."
    var results = [(String, URL)]()
    for entry in entries {
        let meta = entry.appendingPathComponent(
            ".com.apple.mobile_container_manager.metadata.plist")
        guard let dict = readPlist(meta),
              let id   = dict["MCMMetadataIdentifier"] as? String,
              id.hasPrefix(prefix) || id == bundleID
        else { continue }
        results.append((id, entry))
        plog("Plugin UUID: \(id) → \(entry.lastPathComponent)")
    }
    return results
}

// Resolve ALL containers for one bundleID in one call
func resolveAllContainers(bundleID: String) -> AppContainers {
    var c        = AppContainers(bundleID: bundleID, data: nil,
                                 bundle: nil, appGroups: [], plugins: [])
    c.data       = resolveContainerPath(bundleID: bundleID)
    c.bundle     = resolveBundlePath(bundleID: bundleID)
    c.appGroups  = resolveAllAppGroups(bundleID: bundleID)
    c.plugins    = resolveAllPlugins(bundleID: bundleID)

    plog("=== Containers for \(bundleID) ===")
    plog("  Data   : \(c.data?.lastPathComponent ?? "nil")")
    plog("  Bundle : \(c.bundle?.lastPathComponent ?? "nil")")
    plog("  Groups : \(c.appGroups.count)")
    plog("  Plugins: \(c.plugins.count)")
    return c
}

// ── Shell rm -rf ──────────────────────────────────────────────────────────────
// Mirrors: os.execute('rm -rf "' .. path .. '"') from Lua
@discardableResult
func shellRm(_ path: String) -> Int32 {
    guard !path.isEmpty, path != "/", path != "/private" else { return -1 }
    var pid: pid_t = 0
    let args = ["/bin/rm", "-rf", path]
    var cargs = args.map { strdup($0) }
    cargs.append(nil)
    let ret = posix_spawn(&pid, "/bin/rm", nil, nil, &cargs, nil)
    cargs.dropLast().forEach { free($0) }
    if ret == 0 {
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        return status
    }
    return ret
}

// ── Kill apps ─────────────────────────────────────────────────────────────────
func killAppsAndWait(processNames: [String]) {
    let targets = Set(processNames.map { String($0.prefix(15)) })
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    var size = 0
    sysctl(&mib, 4, nil, &size, nil, 0)
    let count = (size / MemoryLayout<kinfo_proc>.stride) + 64
    var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
    var actualSize = count * MemoryLayout<kinfo_proc>.stride
    sysctl(&mib, 4, &procs, &actualSize, nil, 0)
    let n = actualSize / MemoryLayout<kinfo_proc>.stride
    for i in 0 ..< n {
        autoreleasepool {
            let comm = procs[i].kp_proc.p_comm
            let name = withUnsafeBytes(of: comm) { raw -> String in
                guard let ptr = raw.bindMemory(to: CChar.self).baseAddress else { return "" }
                return String(cString: ptr)
            }
            if targets.contains(name) { kill(procs[i].kp_proc.p_pid, SIGKILL) }
        }
    }
    Thread.sleep(forTimeInterval: 2.0)
}

func killAppAndWait(processName: String) {
    killAppsAndWait(processNames: [processName, "WebContent", "com.apple.Web"])
}

/// Model phan cung, vd "iPhone12,1". Goi sysctlbyname hai lan:
/// lan dau de biet can bao nhieu byte, lan hai de lay du lieu that.
func getDeviceModel() -> String {
    var size = 0
    sysctlbyname("hw.machine", nil, &size, nil, 0)
    // size == 0 nghia la lan goi dau that bai — doc tiep se cham vung nho trong
    guard size > 0 else { return "unknown" }
    var machine = [CChar](repeating: 0, count: size)
    sysctlbyname("hw.machine", &machine, &size, nil, 0)
    return String(cString: machine)
}
