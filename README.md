# App Data Manager

Công cụ TrollStore để quản lý dữ liệu app **trên thiết bị của chính bạn**: sao lưu, khôi phục, xoá dữ liệu, và xem cấu trúc container.

> Yêu cầu: iOS 15.0+, arm64, đã cài TrollStore.

## Tính năng

| Chức năng | Mô tả |
|---|---|
| **Backup** | Nén dữ liệu app thành `.zip`, kèm keychain thuộc access group của chính app đó |
| **Restore** | Khôi phục từ một bản backup, ghi đè dữ liệu hiện tại |
| **Reset** | Xoá sạch dữ liệu app, đưa về trạng thái như vừa cài |
| **Xem file** | Duyệt container / app group / plugin container, xem dung lượng từng thư mục |
| **Log** | Ghi lại mọi thao tác, xem realtime ngay trong app |

Backup lưu ở `/var/mobile/Documents/AppDataManager/backups/<bundleID>/`, giữ 5 bản gần nhất mỗi app (đổi trong [Settings.swift](AppDataManager/Settings.swift)).

## Phạm vi tác động

Đây là điểm quan trọng nhất của thiết kế. Khi reset một app, công cụ **chỉ** đụng tới:

- Data container của app đó
- App group + plugin container của app đó
- File hệ thống trong `/var/mobile/Library` **đặt tên theo bundleID** của app đó
- Keychain thuộc **access group đã resolve được** cho app đó

Không có thao tác nào chạy trên toàn hệ thống. Cụ thể, dự án này **không** làm những việc sau, dù về mặt kỹ thuật entitlement cho phép:

- Không kill toàn bộ tiến trình — chỉ đóng đúng app đang xử lý
- Không `SecItemDelete` không lọc — luôn lọc theo access group
- Không đụng chứng chỉ / khoá / identity trong keychain, chỉ 2 class chứa thông tin đăng nhập
- Không xoá cookie của Safari hay của app khác
- Không giả mạo thông tin thiết bị, không reset IDFA/IDFV

## Cấu trúc code

```
AppDataManager/
├── AppDelegate.swift            Điểm vào, dựng nav stack
├── MainViewController.swift     Màn hình chính
├── AppSelectViewController.swift
├── BackupListViewController.swift
├── FilePathViewController.swift Xem đường dẫn (chỉ đọc)
├── SettingsViewController.swift
│
├── DataManager.swift            Backup / restore / reset — logic chính
├── KeychainManager.swift        Keychain, lọc theo access group
├── SystemCleaner.swift          File hệ thống ngoài container
├── ContainerResolver.swift      Map bundleID → UUID container
├── AppEnumerator.swift          Liệt kê app đã cài
│
├── AppItem.swift                Model + đường dẫn + lỗi
├── Settings.swift               Hằng số cấu hình
├── SelectionStore.swift         Nhớ lựa chọn qua UserDefaults
├── Logger.swift                 Log vòng tròn 200 dòng
└── Colors.swift
```

### Vài chỗ đáng đọc nếu muốn học iOS internals

**`ContainerResolver.swift`** — iOS không đặt container theo bundleID mà theo UUID ngẫu nhiên. Muốn tìm container của một app phải duyệt `/var/mobile/Containers/Data/Application/*/` rồi đọc `.com.apple.mobile_container_manager.metadata.plist` trong mỗi thư mục để lấy `MCMMetadataIdentifier`. App group nằm ở cây khác (`Containers/Shared/AppGroup`), extension nằm ở cây khác nữa (`PluginKitPlugin`).

**`ContainerResolver.killAppsAndWait`** — dùng `sysctl` với `KERN_PROC_ALL` để lấy danh sách tiến trình, so `p_comm` với tên executable. Lưu ý kernel cắt `p_comm` còn 15 ký tự nên phải cắt tên theo trước khi so.

**`KeychainManager.resolveAccessGroups`** — access group thật thường có dạng `TEAMID.com.example.app`, mà team ID thì không đoán được từ bundleID. Cách làm: quét keychain thật, lấy group nào có phần sau dấu chấm đầu tiên khớp với bundleID hoặc vendor prefix.

**`DataManager.clearOne`** — quét hai lượt. Lượt hai cần thiết vì `cfprefsd` và `nsurlsessiond` có thể ghi lại file vào container ngay sau khi mình xoá.

## Build

Build chạy trên GitHub Actions (macOS runner) — xem [.github/workflows/build.yml](.github/workflows/build.yml). Push lên `main` hoặc bấm *Run workflow*, artifact `.tipa` nằm trong tab Actions và trong Releases.

Vài điểm trong pipeline:

- **ZIPFoundation nhúng dạng source**, không dùng SPM. Vì app cài qua TrollStore không được ký thật, dynamic framework sẽ không load được; copy thẳng file `.swift` vào target thì chỉ còn một binary duy nhất.
- **`ldid -S`** gắn entitlements vào binary mà không cần certificate của Apple — đây là "fake sign" mà TrollStore chấp nhận.
- **`.tipa` chỉ là `.ipa` đổi đuôi** — cấu trúc y hệt: thư mục `Payload/` chứa `.app`.

Build local (cần macOS + Xcode):

```bash
# Nhúng ZIPFoundation trước
curl -fsSL https://github.com/weichsel/ZIPFoundation/archive/refs/tags/0.9.19.tar.gz -o /tmp/zip.tar.gz
tar -xzf /tmp/zip.tar.gz -C /tmp/
mkdir -p AppDataManager/ZIPFoundation
cp /tmp/ZIPFoundation-0.9.19/Sources/ZIPFoundation/*.swift AppDataManager/ZIPFoundation/

xcodebuild clean build \
  -project AppDataManager.xcodeproj \
  -scheme AppDataManager \
  -sdk iphoneos -configuration Release \
  CODE_SIGNING_ALLOWED=NO SYMROOT=build

ldid -SAppDataManager/entitlements.plist \
  build/Release-iphoneos/AppDataManager.app/AppDataManager
```

## Cài đặt

TrollStore → Install IPA → chọn `AppDataManager.tipa`.

## Lưu ý

Reset dữ liệu **không hoàn tác được** nếu chưa backup. Nút "Backup + Reset" làm backup trước rồi mới xoá — dùng nút đó cho an toàn.

Công cụ này dành cho dữ liệu app trên máy của bạn. Nó không phải và không nên dùng như công cụ vượt giới hạn tài khoản hay né hệ thống chống gian lận của bên khác.
