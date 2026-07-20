import UIKit
import ObjectiveC

/// Lay icon cua mot app theo bundleID.
///
/// Dung API rieng cua UIKit:
///   +[UIImage _applicationIconImageForBundleIdentifier:format:scale:]
/// Day la cach cac trinh quan ly app (Filza, AppList...) lay icon — no di qua
/// icon service cua he thong nen chay duoc ca voi app chi co icon trong
/// Assets.car (khong co file PNG roi). App nay co entitlement TrollStore nen
/// goi duoc API rieng.
enum AppIconLoader {
    private static let cache = NSCache<NSString, UIImage>()
    private static let side: CGFloat = 44   // kich thuoc hien trong cell

    static func icon(for bundleID: String) -> UIImage? {
        if let cached = cache.object(forKey: bundleID as NSString) { return cached }
        guard let raw = privateIcon(for: bundleID) else { return nil }
        let img = resized(raw, to: side)
        cache.setObject(img, forKey: bundleID as NSString)
        return img
    }

    private static func privateIcon(for bundleID: String) -> UIImage? {
        let sel = NSSelectorFromString("_applicationIconImageForBundleIdentifier:format:scale:")
        guard let method = class_getClassMethod(UIImage.self, sel) else { return nil }
        typealias Fn = @convention(c)
            (AnyObject, Selector, NSString, Int, CGFloat) -> Unmanaged<UIImage>?
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        let scale = UIScreen.main.scale
        // format doi theo phien ban iOS; thu vai gia tri, lay cai dau tien ra anh
        for format in [2, 1, 0, 3] {
            if let unmanaged = fn(UIImage.self, sel, bundleID as NSString, format, scale) {
                let img = unmanaged.takeUnretainedValue()
                if img.size.width > 0 { return img }
            }
        }
        return nil
    }

    private static func resized(_ img: UIImage, to side: CGFloat) -> UIImage {
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
