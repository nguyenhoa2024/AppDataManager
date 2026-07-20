import UIKit

final class MainViewController: UIViewController {

    // MARK: - State
    private var appList       = [AppItem]()
    private var backupEntries = [BackupEntry]()
    private var isLoading     = false

    // MARK: - UI
    private let headerLabel     = UILabel()
    private let resetRowBtn     = UIButton(type: .system)   // Chon app Reset
    private let resetCountLbl   = UILabel()
    private let backupRowBtn    = UIButton(type: .system)   // Chon app Backup
    private let backupCountLbl  = UILabel()
    private let backupResetBtn  = UIButton(type: .system)
    private let resetBtn        = UIButton(type: .system)
    private let manageBtn       = UIButton(type: .system)
    private let restoreQuickBtn = UIButton(type: .system)
    private let logTextView     = UITextView()
    private let progressOverlay = UIView()
    private let progressLabel   = UILabel()
    private let progressSpinner = UIActivityIndicatorView(style: .large)

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = C.bg
        setupUI()
        Logger.shared.onNewEntry = { [weak self] entry in self?.appendLog(entry) }
        loadApps()
        reloadBackups()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateSelectionCounts()
    }

    // MARK: - Data

    private func loadApps() {
        guard !isLoading else { return }
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let apps = AppEnumerator.installedApps()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                self.appList = apps
                self.updateSelectionCounts()
                self.appendLog("Quet xong: \(apps.count) app")
            }
        }
    }

    private func reloadBackups() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let list = DataManager.shared.loadAllBackups()
            DispatchQueue.main.async { self?.backupEntries = list }
        }
    }

    /// App trong tap Reset, da loc bo app khong con cai.
    private func resetItems() -> [AppItem] {
        let ids = SelectionStore.shared.loadReset()
        return appList.filter { ids.contains($0.bundleID) }
    }

    /// App trong tap Backup, da loc bo app khong con cai.
    private func backupItems() -> [AppItem] {
        let ids = SelectionStore.shared.loadBackup()
        return appList.filter { ids.contains($0.bundleID) }
    }

    // MARK: - Setup UI

    private func setupUI() {
        title = "App Data Manager"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "gearshape.fill"),
            style: .plain, target: self, action: #selector(settingsTapped))
        navigationItem.rightBarButtonItem?.tintColor = C.mint

        headerLabel.text = AppInfo.headerLine
        headerLabel.font = .systemFont(ofSize: 11, weight: .medium)
        headerLabel.textColor = C.grayText
        headerLabel.textAlignment = .center
        headerLabel.numberOfLines = 2

        // Hai dong chon app rieng biet
        styleRow(resetRowBtn,  title: "Chon app Reset",  color: C.red)
        styleRow(backupRowBtn, title: "Chon app Backup", color: C.blue)
        resetRowBtn .addTarget(self, action: #selector(pickResetTapped),  for: .touchUpInside)
        backupRowBtn.addTarget(self, action: #selector(pickBackupTapped), for: .touchUpInside)
        for lbl in [resetCountLbl, backupCountLbl] {
            lbl.font = .systemFont(ofSize: 12)
            lbl.textColor = C.grayText
            lbl.text = "0 app"
        }

        // Hai nut hanh dong (khong con nut Backup rieng)
        styleAction(backupResetBtn, title: "Backup\n+\nReset", color: C.orange)
        styleAction(resetBtn,       title: "Reset",            color: C.red)
        backupResetBtn.addTarget(self, action: #selector(backupResetTapped), for: .touchUpInside)
        resetBtn      .addTarget(self, action: #selector(resetTapped),       for: .touchUpInside)
        backupResetBtn.titleLabel?.numberOfLines = 3
        backupResetBtn.titleLabel?.textAlignment = .center

        styleNav(manageBtn,       title: "Quan ly backup", color: C.mint)
        styleNav(restoreQuickBtn, title: "Restore nhanh",  color: C.blue)
        manageBtn      .addTarget(self, action: #selector(manageTapped),       for: .touchUpInside)
        restoreQuickBtn.addTarget(self, action: #selector(restoreQuickTapped), for: .touchUpInside)

        logTextView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        logTextView.textColor = C.mint
        logTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logTextView.isEditable = false
        logTextView.layer.cornerRadius = 8
        logTextView.text = "San sang."

        progressOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        progressOverlay.layer.cornerRadius = 16
        progressOverlay.isHidden = true
        progressSpinner.color = C.mint
        progressLabel.textColor = .white
        progressLabel.font = .systemFont(ofSize: 13, weight: .medium)
        progressLabel.textAlignment = .center
        progressLabel.numberOfLines = 5
        [progressSpinner, progressLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            progressOverlay.addSubview($0)
        }

        let views: [UIView] = [headerLabel, resetRowBtn, resetCountLbl,
                               backupRowBtn, backupCountLbl,
                               backupResetBtn, resetBtn,
                               manageBtn, restoreQuickBtn,
                               logTextView, progressOverlay]
        views.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            headerLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            resetRowBtn.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 12),
            resetRowBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            resetRowBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            resetRowBtn.heightAnchor.constraint(equalToConstant: 46),
            resetCountLbl.centerYAnchor.constraint(equalTo: resetRowBtn.centerYAnchor),
            resetCountLbl.trailingAnchor.constraint(equalTo: resetRowBtn.trailingAnchor, constant: -14),

            backupRowBtn.topAnchor.constraint(equalTo: resetRowBtn.bottomAnchor, constant: 8),
            backupRowBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            backupRowBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            backupRowBtn.heightAnchor.constraint(equalToConstant: 46),
            backupCountLbl.centerYAnchor.constraint(equalTo: backupRowBtn.centerYAnchor),
            backupCountLbl.trailingAnchor.constraint(equalTo: backupRowBtn.trailingAnchor, constant: -14),

            backupResetBtn.topAnchor.constraint(equalTo: backupRowBtn.bottomAnchor, constant: 12),
            backupResetBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            backupResetBtn.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.44),
            backupResetBtn.heightAnchor.constraint(equalToConstant: 74),

            resetBtn.topAnchor.constraint(equalTo: backupResetBtn.topAnchor),
            resetBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            resetBtn.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.44),
            resetBtn.heightAnchor.constraint(equalToConstant: 74),

            manageBtn.topAnchor.constraint(equalTo: backupResetBtn.bottomAnchor, constant: 12),
            manageBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            manageBtn.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.44),
            manageBtn.heightAnchor.constraint(equalToConstant: 40),

            restoreQuickBtn.topAnchor.constraint(equalTo: manageBtn.topAnchor),
            restoreQuickBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            restoreQuickBtn.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.44),
            restoreQuickBtn.heightAnchor.constraint(equalToConstant: 40),

            logTextView.topAnchor.constraint(equalTo: manageBtn.bottomAnchor, constant: 12),
            logTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            logTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            logTextView.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -12),

            progressOverlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressOverlay.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            progressOverlay.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.85),
            progressOverlay.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),
            progressSpinner.topAnchor.constraint(equalTo: progressOverlay.topAnchor, constant: 24),
            progressSpinner.centerXAnchor.constraint(equalTo: progressOverlay.centerXAnchor),
            progressLabel.topAnchor.constraint(equalTo: progressSpinner.bottomAnchor, constant: 12),
            progressLabel.bottomAnchor.constraint(equalTo: progressOverlay.bottomAnchor, constant: -20),
            progressLabel.leadingAnchor.constraint(equalTo: progressOverlay.leadingAnchor, constant: 16),
            progressLabel.trailingAnchor.constraint(equalTo: progressOverlay.trailingAnchor, constant: -16),
        ])
    }

    private func styleRow(_ b: UIButton, title: String, color: UIColor) {
        b.setTitle("  \(title)", for: .normal)
        b.setTitleColor(color, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        b.contentHorizontalAlignment = .left
        b.backgroundColor = C.cellBg
        b.layer.cornerRadius = 8
    }

    private func styleAction(_ b: UIButton, title: String, color: UIColor) {
        b.setTitle(title, for: .normal)
        b.setTitleColor(color, for: .normal)
        b.titleLabel?.font = .boldSystemFont(ofSize: 15)
        b.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        b.layer.cornerRadius = 10
        b.layer.borderWidth = 1.5
        b.layer.borderColor = color.cgColor
    }

    private func styleNav(_ b: UIButton, title: String, color: UIColor) {
        b.setTitle(title, for: .normal)
        b.setTitleColor(color, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        b.backgroundColor = C.cellBg
        b.layer.cornerRadius = 8
    }

    // MARK: - Log / progress

    private func appendLog(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let current = self.logTextView.text ?? ""
            let limited = current.components(separatedBy: "\n").suffix(99).joined(separator: "\n")
            self.logTextView.text = limited.isEmpty ? text : limited + "\n" + text
            if let count = self.logTextView.text?.count, count > 0 {
                self.logTextView.scrollRangeToVisible(NSRange(location: count - 1, length: 1))
            }
        }
    }

    private func updateSelectionCounts() {
        resetCountLbl.text  = "\(resetItems().count) app"
        backupCountLbl.text = "\(backupItems().count) app"
    }

    private func showProgress(_ msg: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.progressLabel.text = msg
            self.progressOverlay.isHidden = false
            self.progressSpinner.startAnimating()
            self.view.bringSubviewToFront(self.progressOverlay)
        }
    }

    private func updateProgress(_ msg: String) {
        DispatchQueue.main.async { [weak self] in self?.progressLabel.text = msg }
    }

    private func hideProgress() {
        DispatchQueue.main.async { [weak self] in
            self?.progressSpinner.stopAnimating()
            self?.progressOverlay.isHidden = true
        }
    }

    private func setButtonsEnabled(_ on: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            [self.backupResetBtn, self.resetBtn, self.resetRowBtn, self.backupRowBtn,
             self.manageBtn, self.restoreQuickBtn].forEach {
                $0.isEnabled = on
                $0.alpha = on ? 1.0 : 0.5
            }
        }
    }

    // MARK: - Chon app

    @objc private func pickResetTapped() {
        let vc = AppSelectViewController(mode: .reset, appList: appList)
        vc.onDone = { [weak self] in self?.updateSelectionCounts() }
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func pickBackupTapped() {
        let vc = AppSelectViewController(mode: .backup, appList: appList)
        vc.onDone = { [weak self] in self?.updateSelectionCounts() }
        navigationController?.pushViewController(vc, animated: true)
    }

    // MARK: - Hanh dong

    @objc private func resetTapped() {
        let items = resetItems()
        guard !items.isEmpty else {
            appendLog(appList.isEmpty ? "Dang quet app, doi mot chut..." : "Chua chon app Reset")
            return
        }
        confirmDestructive(
            title: "Reset du lieu?",
            message: "Xoa sach du lieu cua:\n\(names(items))\n\nKhong co backup thi khong hoan tac duoc.",
            action: "Reset"
        ) { [weak self] in
            self?.runOperation(title: "Reset") { progress, done in
                DataManager.shared.resetApps(items: items, progress: progress) { _ in done() }
            }
        }
    }

    @objc private func backupResetTapped() {
        let backups = backupItems()
        let resets  = resetItems()
        guard !backups.isEmpty || !resets.isEmpty else {
            appendLog(appList.isEmpty ? "Dang quet app, doi mot chut..." : "Chua chon app nao")
            return
        }
        let message = "Se BACKUP:\n\(names(backups, empty: "(khong co)"))\n\n"
                    + "Roi RESET:\n\(names(resets, empty: "(khong co)"))\n\n"
                    + "App backup that bai se KHONG bi reset."
        confirmDestructive(title: "Backup roi Reset?", message: message, action: "Backup + Reset") {
            [weak self] in
            self?.runOperation(title: "Backup + Reset") { progress, done in
                DataManager.shared.backupThenReset(
                    backupItems: backups, resetItems: resets, progress: progress) { _ in done() }
            }
        }
    }

    private func names(_ items: [AppItem], empty: String = "") -> String {
        items.isEmpty ? empty : items.map { $0.displayName }.joined(separator: ", ")
    }

    private func runOperation(title: String,
                              _ body: (@escaping (String) -> Void, @escaping () -> Void) -> Void) {
        setButtonsEnabled(false)
        showProgress("\(title)...")
        appendLog("--- \(title) ---")
        body({ [weak self] msg in
            self?.updateProgress(msg)
            self?.appendLog(msg)
        }, { [weak self] in
            self?.hideProgress()
            self?.setButtonsEnabled(true)
            self?.appendLog("\(title) xong ✓")
            self?.reloadBackups()
        })
    }

    private func confirmDestructive(title: String, message: String,
                                    action: String, handler: @escaping () -> Void) {
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Huy", style: .cancel))
        a.addAction(UIAlertAction(title: action, style: .destructive) { _ in handler() })
        present(a, animated: true)
    }

    // MARK: - Backup: xem / restore

    @objc private func manageTapped() {
        let vc = BackupListViewController(entries: backupEntries)
        vc.onChanged = { [weak self] in self?.reloadBackups() }
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func restoreQuickTapped() {
        guard !backupEntries.isEmpty else { appendLog("Chua co backup nao"); return }
        let alert = UIAlertController(title: "Restore nhanh",
                                      message: "Chon ban backup:", preferredStyle: .actionSheet)
        for entry in backupEntries.prefix(5) {
            let label = "\(entry.displayName) — \(DateFormatter.display.string(from: entry.backupDate))"
            alert.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                self?.doRestore(entry: entry)
            })
        }
        alert.addAction(UIAlertAction(title: "Huy", style: .cancel))
        alert.popoverPresentationController?.sourceView = restoreQuickBtn
        alert.popoverPresentationController?.sourceRect = restoreQuickBtn.bounds
        present(alert, animated: true)
    }

    private func doRestore(entry: BackupEntry) {
        setButtonsEnabled(false)
        showProgress("Restore \(entry.displayName)...")
        appendLog("--- Restore: \(entry.displayName) ---")
        DataManager.shared.restore(zipURL: entry.zipURL) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.hideProgress()
                self.setButtonsEnabled(true)
                switch result {
                case .success(let msg): self.appendLog(msg)
                case .failure(let err): self.appendLog("Loi restore: \(err.localizedDescription)")
                }
            }
        }
    }

    @objc private func settingsTapped() {
        let vc  = SettingsViewController()
        let nav = UINavigationController(rootViewController: vc)
        styleNavBar(nav.navigationBar)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }
}
