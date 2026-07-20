import UIKit

/// Chon app de backup / reset. Lua chon duoc luu lai qua SelectionStore.
final class AppSelectViewController: UIViewController,
    UITableViewDataSource, UITableViewDelegate {

    private let appList: [AppItem]
    var onDone: (() -> Void)?

    private var selectedIDs = Set<String>()
    private let tableView   = UITableView(frame: .zero, style: .plain)
    private let countLabel  = UILabel()

    init(appList: [AppItem]) {
        self.appList = appList
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) khong dung") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Chon app"
        view.backgroundColor = C.bg

        // Bo id cua app da go khoi lua chon cu
        let installed = Set(appList.map { $0.bundleID })
        selectedIDs = SelectionStore.shared.load().intersection(installed)

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Xong", style: .done, target: self, action: #selector(doneTapped))
        navigationItem.rightBarButtonItem?.tintColor = C.mint
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Chon tat ca", style: .plain, target: self, action: #selector(selectAllTapped))
        navigationItem.leftBarButtonItem?.tintColor = C.orange

        countLabel.font = .systemFont(ofSize: 13)
        countLabel.textColor = C.grayText
        countLabel.textAlignment = .center

        tableView.backgroundColor = C.cellBg
        tableView.separatorColor  = C.sep
        tableView.layer.cornerRadius = 12
        tableView.dataSource = self
        tableView.delegate   = self

        [countLabel, tableView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            countLabel.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            countLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            countLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tableView.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16),
        ])
        updateCount()
    }

    private func updateCount() {
        countLabel.text = "Da chon \(selectedIDs.count)/\(appList.count) app"
    }

    @objc private func doneTapped() {
        SelectionStore.shared.save(selectedIDs)
        onDone?()
        navigationController?.popViewController(animated: true)
    }

    @objc private func selectAllTapped() {
        if selectedIDs.count == appList.count {
            selectedIDs.removeAll()
        } else {
            selectedIDs = Set(appList.map { $0.bundleID })
        }
        updateCount()
        tableView.reloadData()
    }

    // MARK: - TableView

    func tableView(_ tv: UITableView, numberOfRowsInSection section: Int) -> Int {
        appList.count
    }

    func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = tv.dequeueReusableCell(withIdentifier: "cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        cell.backgroundColor            = C.cellBg
        cell.textLabel?.textColor       = .white
        cell.detailTextLabel?.textColor = C.grayText
        cell.tintColor                  = C.mint
        if cell.selectedBackgroundView == nil {
            let v = UIView(); v.backgroundColor = C.selCell
            cell.selectedBackgroundView = v
        }
        let item = appList[ip.row]
        cell.textLabel?.text       = item.displayName
        cell.detailTextLabel?.text = item.bundleID
        cell.accessoryType = selectedIDs.contains(item.bundleID) ? .checkmark : .none
        return cell
    }

    func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
        tv.deselectRow(at: ip, animated: true)
        let id = appList[ip.row].bundleID
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
        updateCount()
        tv.reloadRows(at: [ip], with: .none)
    }

    func tableView(_ tv: UITableView, heightForRowAt ip: IndexPath) -> CGFloat { 56 }

    /// Vuot sang phai de xem duong dan file cua app, khong dong toi du lieu.
    func tableView(_ tv: UITableView,
                   leadingSwipeActionsConfigurationForRowAt ip: IndexPath)
        -> UISwipeActionsConfiguration? {
        let item = appList[ip.row]
        let action = UIContextualAction(style: .normal, title: "Files") { [weak self] _, _, done in
            done(true)
            self?.navigationController?.pushViewController(
                FilePathViewController(item: item), animated: true)
        }
        action.backgroundColor = C.blue
        return UISwipeActionsConfiguration(actions: [action])
    }
}
