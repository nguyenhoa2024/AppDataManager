import UIKit

/// Danh sach cac ban backup: xem, restore, xoa.
final class BackupListViewController: UIViewController,
    UITableViewDataSource, UITableViewDelegate {

    private var entries: [BackupEntry]
    var onChanged: (() -> Void)?

    private let tableView  = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private let spinner    = UIActivityIndicatorView(style: .medium)

    init(entries: [BackupEntry]) {
        self.entries = entries
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) khong dung") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Quan ly backup"
        view.backgroundColor = C.bg

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Lam moi", style: .plain, target: self, action: #selector(reload))
        navigationItem.rightBarButtonItem?.tintColor = C.mint

        tableView.backgroundColor = C.bg
        tableView.separatorColor  = C.sep
        tableView.dataSource = self
        tableView.delegate   = self

        emptyLabel.text = "Chua co backup nao"
        emptyLabel.textColor = C.grayText
        emptyLabel.textAlignment = .center
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.isHidden = !entries.isEmpty

        spinner.color = C.mint
        spinner.hidesWhenStopped = true

        [tableView, emptyLabel, spinner].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: guide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: guide.topAnchor, constant: 40),
        ])
    }

    @objc private func reload() {
        spinner.startAnimating()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let list = DataManager.shared.loadAllBackups()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.spinner.stopAnimating()
                self.entries = list
                self.emptyLabel.isHidden = !list.isEmpty
                self.tableView.reloadData()
            }
        }
    }

    // MARK: - TableView

    func tableView(_ tv: UITableView, numberOfRowsInSection section: Int) -> Int { entries.count }

    func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = tv.dequeueReusableCell(withIdentifier: "cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        let e = entries[ip.row]
        cell.backgroundColor            = C.cellBg
        cell.textLabel?.textColor       = .white
        cell.detailTextLabel?.textColor = C.grayText
        cell.textLabel?.text = "\(e.displayName)  ·  \(DateFormatter.display.string(from: e.backupDate))"
        let fmt = ByteCountFormatter(); fmt.countStyle = .file
        cell.detailTextLabel?.text = "\(e.bundleID)  ·  \(fmt.string(fromByteCount: e.fileSize))"
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
        tv.deselectRow(at: ip, animated: true)
        showRestoreAlert(entry: entries[ip.row])
    }

    func tableView(_ tv: UITableView, heightForRowAt ip: IndexPath) -> CGFloat { 60 }

    func tableView(_ tv: UITableView,
                   trailingSwipeActionsConfigurationForRowAt ip: IndexPath)
        -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "Xoa") { [weak self] _, _, done in
            guard let self = self, ip.row < self.entries.count else { done(false); return }
            try? FileManager.default.removeItem(at: self.entries[ip.row].zipURL)
            self.entries.remove(at: ip.row)
            tv.deleteRows(at: [ip], with: .fade)
            self.emptyLabel.isHidden = !self.entries.isEmpty
            self.onChanged?()
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    // MARK: - Restore

    private func showRestoreAlert(entry: BackupEntry) {
        let fmt = ByteCountFormatter(); fmt.countStyle = .file
        let a = UIAlertController(
            title: "Restore \(entry.displayName)?",
            message: """
                Ngay: \(DateFormatter.display.string(from: entry.backupDate))
                File: \(entry.zipURL.lastPathComponent)
                Size: \(fmt.string(fromByteCount: entry.fileSize))

                Du lieu hien tai cua app se bi ghi de.
                """,
            preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Huy", style: .cancel))
        a.addAction(UIAlertAction(title: "Restore", style: .default) { [weak self] _ in
            self?.doRestore(entry: entry)
        })
        present(a, animated: true)
    }

    private func doRestore(entry: BackupEntry) {
        let overlay = makeOverlay(msg: "Dang restore \(entry.displayName)...")
        view.addSubview(overlay)
        view.bringSubviewToFront(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        DataManager.shared.restore(zipURL: entry.zipURL) { [weak self] result in
            DispatchQueue.main.async {
                overlay.removeFromSuperview()
                let msg: String
                switch result {
                case .success(let m): msg = m
                case .failure(let e): msg = "Loi: \(e.localizedDescription)"
                }
                let alert = UIAlertController(title: nil, message: msg, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(alert, animated: true)
            }
        }
    }

    private func makeOverlay(msg: String) -> UIView {
        let v = UIView()
        v.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        v.translatesAutoresizingMaskIntoConstraints = false

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = C.mint
        spinner.startAnimating()

        let label = UILabel()
        label.text = msg
        label.textColor = .white
        label.font = .systemFont(ofSize: 13)
        label.textAlignment = .center
        label.numberOfLines = 2

        [spinner, label].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            v.addSubview($0)
        }
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: v.centerYAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -20),
        ])
        return v
    }
}
