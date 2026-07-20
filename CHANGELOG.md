# Changelog

Mỗi bản build có "build tag" dạng `v<version>-<ngày>-<giờ>` hiện ngay ở đầu màn hình chính và trong Cài đặt → so với dòng dưới đây là biết máy đang chạy bản nào.

## v1.1

- **Sửa restore lỗi `error 14`.** Nguyên nhân: file backup chứa symlink (ví dụ trong `Library/WebKit`) trỏ ra ngoài, ZIPFoundation chặn khi giải nén (`uncontainedSymlink`). Nay backup bỏ qua symlink, và restore giải nén thủ công bỏ qua symlink — nên restore được cả bản backup cũ đã lỡ chứa symlink.
- **Chọn app tách làm 2 danh sách riêng:** "Chọn app Reset" và "Chọn app Backup".
- **Còn 2 nút hành động:** "Backup + Reset" và "Reset" (bỏ nút Backup riêng). "Backup + Reset" sao lưu tập Backup rồi xoá tập Reset; app nào backup thất bại thì không bị xoá.
- **Danh sách app chỉ hiện app App Store / TrollStore**, ẩn app cài từ Sileo/dpkg. Sửa luôn đường dẫn bundle sai (`/var/mobile/Containers/Bundle/Application` → `/var/containers/Bundle/Application`) nên tên app cũng hiển thị đúng.
- **Tự ghi build tag mỗi lần build** (CI chèn vào Info.plist), hiện ở đầu màn hình và trong Cài đặt.

## v1.0

- Bản đầu. Backup / restore / reset dữ liệu app, xem đường dẫn container, log realtime.
- Viết lại từ một dự án cũ, giới hạn phạm vi tác động đúng app được chọn: bỏ giả mạo thông tin thiết bị, bỏ reset IDFA/IDFV, keychain lọc theo access group, chỉ đóng app đang xử lý.
