import Foundation

/// Log vong tron, giu 200 dong gan nhat.
///
/// `onNewEntry` de MainViewController hien log ngay trong man hinh chinh —
/// tren thiet bi that khong xem duoc Xcode console nen day la cach duy nhat
/// theo doi mot thao tac dang chay.
final class Logger {
    static let shared = Logger()
    private init() {}

    private let queue   = DispatchQueue(label: "com.appdatamanager.logger")
    private var entries = [String]()
    private let maxEntries = 200

    var onNewEntry: ((String) -> Void)?

    func log(_ msg: String, file: String = #file, line: Int = #line) {
        let ts    = DateFormatter.display.string(from: Date())
        let entry = "[\(ts)] \(msg)"

        queue.async { [weak self] in
            guard let self = self else { return }
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.onNewEntry?(entry)
        }

        #if DEBUG
        let fname = URL(fileURLWithPath: file).lastPathComponent
        print("AppDataManager [\(fname):\(line)] \(msg)")
        #endif
    }

    func allLogs() -> [String] { queue.sync { entries } }
    func clear()              { queue.async { self.entries.removeAll() } }
}

func plog(_ msg: String, file: String = #file, line: Int = #line) {
    Logger.shared.log(msg, file: file, line: line)
}
