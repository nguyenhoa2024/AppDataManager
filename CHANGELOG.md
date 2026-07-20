# Changelog

Mỗi bản build có "build tag" dạng `v<version>-<ngày>-<giờ>` hiện ngay ở đầu màn hình chính và trong Cài đặt → so với dòng dưới đây là biết máy đang chạy bản nào.

## v1.4

- **Chặn backup rỗng.** App vừa bị reset (chỉ còn khung thư mục, không keychain) sẽ không tạo được backup — trước đây tạo ra file ~3KB vô dụng mà restore lại **xoá sạch data hiện có**. Nay báo "app rỗng, không backup".
- **Chặn restore từ backup rỗng.** Nếu bản backup không có dữ liệu thật, restore sẽ **giữ nguyên** data hiện tại thay vì wipe rồi nạp số 0. (Vá đúng vụ "restore xong container rỗng, app không như cũ".)
- **Reset xoá keychain triệt để hơn.** Xoá trên mọi class (password, internet password, key, certificate, identity) + cả bản iCloud-synced, và xoá thẳng theo access group — cho "xoá data app" thật sự sạch. Vẫn chỉ đụng keychain của app được chọn.

## v1.3

- **Sửa gốc lỗi keychain — vá cả 3 triệu chứng cùng lúc:** LINE restore xong vẫn đòi xác thực; Facebook reset xong vẫn còn đăng nhập. Nguyên nhân chung: nhiều app dùng nhóm keychain **không suy được từ bundle ID** (LINE: `ZW4U99SQQ3.com.linecorp.trident.shared`; FB: `T84QZS65DQ.platformFamily`) nên bộ lọc cũ bỏ sót → reset không xoá, backup không lưu. Nay **đọc thẳng `keychain-access-groups` từ entitlements của app** nên bắt đúng mọi nhóm. Reset xoá sạch, backup/restore giữ được session.
- **Backup gộp:** chọn nhiều app để backup thì ra **1 file duy nhất** chứa tất cả (format v3), restore 1 phát khôi phục hết. Vẫn restore được backup cũ (v1/v2).
- **Hiện logo app** trong màn chọn app (dùng icon service của hệ thống).

## v1.2

- **Backup giờ là FULL.** Trước chỉ lưu vài thư mục con của container chính nên mất session (đã test hụt trên LINE). Nay lưu **toàn bộ** container chính + **tất cả app group** + **plugin container** + keychain. Chỉ bỏ `tmp` và `Library/Caches` (iOS coi là vứt được, không chứa session). Restore khôi phục lại đúng các chỗ đó → session sống sót qua backup→reset→restore.
- **Sửa Reset làm app crash không mở được.** Nguyên nhân: wipe sạch container khiến thiếu khung thư mục chuẩn (`Documents`, `Library`, `tmp`…). Nay sau khi wipe sẽ tạo lại khung → app mở được như vừa cài. Restore cũng tạo lại khung.
- **Tự động đóng app đã chọn sau khi Reset/Backup xong**, để lần mở sau app khởi động lại sạch với dữ liệu mới.
- Định dạng backup nâng lên v2; vẫn restore được các bản backup v1 cũ.

## v1.1

- **Sửa restore lỗi `error 14`.** Nguyên nhân: file backup chứa symlink (ví dụ trong `Library/WebKit`) trỏ ra ngoài, ZIPFoundation chặn khi giải nén (`uncontainedSymlink`). Nay backup bỏ qua symlink, và restore giải nén thủ công bỏ qua symlink — nên restore được cả bản backup cũ đã lỡ chứa symlink.
- **Chọn app tách làm 2 danh sách riêng:** "Chọn app Reset" và "Chọn app Backup".
- **Còn 2 nút hành động:** "Backup + Reset" và "Reset" (bỏ nút Backup riêng). "Backup + Reset" sao lưu tập Backup rồi xoá tập Reset; app nào backup thất bại thì không bị xoá.
- **Danh sách app chỉ hiện app App Store / TrollStore**, ẩn app cài từ Sileo/dpkg. Sửa luôn đường dẫn bundle sai (`/var/mobile/Containers/Bundle/Application` → `/var/containers/Bundle/Application`) nên tên app cũng hiển thị đúng.
- **Tự ghi build tag mỗi lần build** (CI chèn vào Info.plist), hiện ở đầu màn hình và trong Cài đặt.

## v1.0

- Bản đầu. Backup / restore / reset dữ liệu app, xem đường dẫn container, log realtime.
- Viết lại từ một dự án cũ, giới hạn phạm vi tác động đúng app được chọn: bỏ giả mạo thông tin thiết bị, bỏ reset IDFA/IDFV, keychain lọc theo access group, chỉ đóng app đang xử lý.
