import UIKit

final class SettingsViewController: UIViewController,
    UITableViewDataSource, UITableViewDelegate {

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private enum Action: Int, CaseIterable {
        case clearSelection, deleteAllBackups

        var title: String {
            switch self {
            case .clearSelection:    return "Xoa lua chon app"
            case .deleteAllBackups:  return "Xoa tat ca backup"
            }
        }
    }

    /// Cache chu khong dung computed property: `totalBackupCount` phai duyet
    /// het thu muc backup, ma cellForRowAt goi lien tuc khi cuon.
    private var infoRows = [(String, String)]()

    private func refreshInfoRows() {
        infoRows = [
            ("Phien ban",     "\(AppInfo.version) (build \(AppInfo.build))"),
            ("Build tag",     AppInfo.buildTag),
            ("iOS",           UIDevice.current.systemVersion),
            ("Thiet bi",      getDeviceModel()),
            ("Backup path",   PathConfig.backupRoot.path),
            ("Tong backup",   "\(Settings.shared.totalBackupCount) file"),
            ("Giu moi app",   "\(Settings.shared.maxBackupsPerApp) ban gan nhat"),
            ("ZIPFoundation", "0.9.19 (nhung dang source)"),
        ]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Cai dat"
        view.backgroundColor = C.bg

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Dong", style: .plain, target: self, action: #selector(close))
        navigationItem.leftBarButtonItem?.tintColor = C.mint
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Log", style: .plain, target: self, action: #selector(showLogs))
        navigationItem.rightBarButtonItem?.tintColor = C.orange

        tableView.backgroundColor = C.bg
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshInfoRows()
        tableView.reloadData()
    }

    @objc private func close() { dismiss(animated: true) }

    @objc private func showLogs() {
        let logs = Logger.shared.allLogs()
        navigationController?.pushViewController(
            LogViewController(text: logs.isEmpty ? "Chua co log." : logs.joined(separator: "\n")),
            animated: true)
    }

    // MARK: - TableView

    func numberOfSections(in tv: UITableView) -> Int { 2 }

    func tableView(_ tv: UITableView, numberOfRowsInSection s: Int) -> Int {
        s == 0 ? infoRows.count : Action.allCases.count
    }

    func tableView(_ tv: UITableView, titleForHeaderInSection s: Int) -> String? {
        s == 0 ? "Thong tin" : "Hanh dong"
    }

    func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        if ip.section == 1 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: "action")
            cell.backgroundColor = C.cellBg
            cell.textLabel?.textAlignment = .center
            cell.textLabel?.textColor = C.red
            cell.textLabel?.text = Action(rawValue: ip.row)?.title
            return cell
        }
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "info")
        cell.backgroundColor = C.cellBg
        cell.selectionStyle = .none
        cell.textLabel?.textColor = .white
        cell.detailTextLabel?.textColor = C.grayText
        cell.detailTextLabel?.numberOfLines = 2
        cell.detailTextLabel?.lineBreakMode = .byCharWrapping
        cell.textLabel?.text       = infoRows[ip.row].0
        cell.detailTextLabel?.text = infoRows[ip.row].1
        return cell
    }

    func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
        tv.deselectRow(at: ip, animated: true)
        guard ip.section == 1, let action = Action(rawValue: ip.row) else { return }
        switch action {
        case .clearSelection:
            SelectionStore.shared.clearAll()
            showAlert("Da xoa lua chon app")
        case .deleteAllBackups:
            confirmDeleteAllBackups()
        }
    }

    private func confirmDeleteAllBackups() {
        let a = UIAlertController(title: "Xoa tat ca backup?",
                                  message: "Khong the hoan tac.",
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Huy", style: .cancel))
        a.addAction(UIAlertAction(title: "Xoa", style: .destructive) { [weak self] _ in
            let fm = FileManager.default
            if let dirs = try? fm.contentsOfDirectory(
                at: PathConfig.backupRoot, includingPropertiesForKeys: nil, options: []) {
                dirs.forEach { try? fm.removeItem(at: $0) }
            }
            self?.refreshInfoRows()
            self?.tableView.reloadData()
            self?.showAlert("Da xoa tat ca backup")
        })
        present(a, animated: true)
    }

    private func showAlert(_ msg: String) {
        let a = UIAlertController(title: nil, message: msg, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }
}

/// Xem toan bo log da ghi tu luc mo app.
final class LogViewController: UIViewController {
    private let text: String

    init(text: String) {
        self.text = text
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) khong dung") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Log"
        view.backgroundColor = C.bg

        let tv = UITextView()
        tv.text = text
        tv.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        tv.textColor = C.mint
        tv.backgroundColor = C.bg
        tv.isEditable = false
        tv.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tv)

        NSLayoutConstraint.activate([
            tv.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        DispatchQueue.main.async {
            let count = tv.text.count
            if count > 0 { tv.scrollRangeToVisible(NSRange(location: count - 1, length: 1)) }
        }
    }
}
