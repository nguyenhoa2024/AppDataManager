import UIKit

/// Xem cau truc container cua mot app: container chinh, app group, plugin.
/// Chi doc — man hinh nay khong xoa gi ca.
final class FilePathViewController: UIViewController,
    UITableViewDataSource, UITableViewDelegate {

    struct PathEntry {
        let path:   String
        let size:   Int64
        let exists: Bool
    }

    private let item: AppItem
    private var sections = [(title: String, paths: [PathEntry])]()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let spinner   = UIActivityIndicatorView(style: .medium)

    init(item: AppItem) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) khong dung") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = item.displayName
        view.backgroundColor = C.bg
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Lam moi", style: .plain, target: self, action: #selector(reload))
        navigationItem.rightBarButtonItem?.tintColor = C.mint

        tableView.backgroundColor = C.bg
        tableView.separatorColor  = C.sep
        tableView.dataSource = self
        tableView.delegate   = self
        spinner.color = C.mint
        spinner.hidesWhenStopped = true

        [tableView, spinner].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: guide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        loadPaths()
    }

    @objc private func reload() { loadPaths() }

    private func loadPaths() {
        sections.removeAll()
        tableView.reloadData()
        spinner.startAnimating()
        // Tinh dung luong phai duyet ca cay thu muc — dua sang background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result = self.buildSections()
            DispatchQueue.main.async {
                self.spinner.stopAnimating()
                self.sections = result
                self.tableView.reloadData()
            }
        }
    }

    private func buildSections() -> [(title: String, paths: [PathEntry])] {
        let fm = FileManager.default
        var result = [(title: String, paths: [PathEntry])]()

        guard let container = resolveContainerPath(bundleID: item.bundleID) else {
            return [("Loi", [PathEntry(
                path: "Khong tim thay container: \(item.bundleID)", size: 0, exists: false)])]
        }

        result.append(("Container", [
            PathEntry(path: container.path, size: dirSize(container), exists: true),
        ]))

        var subEntries = [PathEntry]()
        for sub in Settings.shared.inspectSubdirs {
            let url    = container.appendingPathComponent(sub)
            let exists = fm.fileExists(atPath: url.path)
            subEntries.append(PathEntry(path: url.path,
                                        size: exists ? dirSize(url) : 0,
                                        exists: exists))
        }
        result.append(("Thu muc con", subEntries))

        let prefDir = container.appendingPathComponent("Library/Preferences")
        if fm.fileExists(atPath: prefDir.path),
           let files = try? fm.contentsOfDirectory(
               at: prefDir, includingPropertiesForKeys: [.fileSizeKey], options: []) {
            let entries = files.map { url -> PathEntry in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return PathEntry(path: url.path, size: Int64(size), exists: true)
            }.sorted { $0.path < $1.path }
            if !entries.isEmpty { result.append(("Library/Preferences", entries)) }
        }

        for (gid, groupURL) in resolveAllAppGroups(bundleID: item.bundleID) {
            result.append(("App Group: \(gid)", containerEntries(groupURL,
                subdirs: ["Library", "Documents", "tmp", "SystemData"])))
        }

        for (pid, pluginURL) in resolveAllPlugins(bundleID: item.bundleID) {
            result.append(("Plugin: \(pid)", containerEntries(pluginURL,
                subdirs: ["Library", "Documents", "tmp"])))
        }

        return result
    }

    private func containerEntries(_ root: URL, subdirs: [String]) -> [PathEntry] {
        let fm = FileManager.default
        var entries = [PathEntry(path: root.path, size: dirSize(root), exists: true)]
        for sub in subdirs {
            let url    = root.appendingPathComponent(sub)
            let exists = fm.fileExists(atPath: url.path)
            entries.append(PathEntry(path: url.path,
                                     size: exists ? dirSize(url) : 0,
                                     exists: exists))
        }
        return entries
    }

    private func dirSize(_ url: URL) -> Int64 {
        var total: Int64 = 0
        guard let e = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey],
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

    private func fmt(_ bytes: Int64) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    // MARK: - TableView

    func numberOfSections(in tv: UITableView) -> Int { sections.count }

    func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int {
        sections[s].paths.count
    }

    func tableView(_ tv: UITableView, titleForHeaderInSection s: Int) -> String? {
        let total = sections[s].paths.reduce(0) { $0 + $1.size }
        return total > 0 ? "\(sections[s].title) — \(fmt(total))" : sections[s].title
    }

    func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell  = UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        let entry = sections[ip.section].paths[ip.row]
        cell.backgroundColor = C.cellBg
        cell.textLabel?.textColor = entry.exists ? .white : C.grayText
        cell.textLabel?.font = .systemFont(ofSize: 12)
        cell.textLabel?.numberOfLines = 2
        cell.detailTextLabel?.textColor = C.mint
        cell.detailTextLabel?.font = .systemFont(ofSize: 11)
        // Duong dan day du rat dai — hien 3 thanh phan cuoi, bam vao xem het
        cell.textLabel?.text = entry.path.components(separatedBy: "/").suffix(3).joined(separator: "/")
        cell.detailTextLabel?.text = entry.exists
            ? (entry.size > 0 ? fmt(entry.size) : "rong")
            : "khong ton tai"
        return cell
    }

    func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
        tv.deselectRow(at: ip, animated: true)
        let entry = sections[ip.section].paths[ip.row]
        let a = UIAlertController(title: "Duong dan", message: entry.path, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Copy", style: .default) { _ in
            UIPasteboard.general.string = entry.path
        })
        a.addAction(UIAlertAction(title: "Dong", style: .cancel))
        present(a, animated: true)
    }

    func tableView(_ tv: UITableView, heightForRowAt ip: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }
}
