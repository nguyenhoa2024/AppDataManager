import Foundation
import UIKit

/// Thong tin phien ban, gom ca "build tag" do CI ghi vao Info.plist moi lan
/// build — de nhin la biet ngay dang chay ban nao.
enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// Nhan build do CI dat (vd "v1.1-20260720-1530"). Neu build tay/local
    /// thi con la "dev".
    static var buildTag: String {
        let tag = Bundle.main.infoDictionary?["ADMBuildTag"] as? String ?? ""
        return tag.isEmpty ? "dev" : tag
    }

    /// Dong hien o dau man hinh chinh.
    static var headerLine: String {
        "v\(version) (build \(build))  ·  \(buildTag)\n"
        + "iOS \(UIDevice.current.systemVersion)  ·  \(getDeviceModel())"
    }
}
