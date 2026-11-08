# sumi-kakunin 確認

Dialog xác nhận đóng cửa sổ được bảo vệ, một app của hệ thống SUMI.

- Chạy: `sumi kakunin`, gắn thẳng vào keybind Hyprland, không cần script ngoài. Điểm vào là `kakunin.sh` (manifest `run`), ba lớp:
  1. **filter**: đọc cửa sổ đang focus (`hyprctl`) và OPTION `protectedClasses`; chỉ đọc, chưa làm gì, chưa chạy Quickshell.
  2. **execute**: class không khớp danh sách thì đóng ngay, không khởi động Quickshell nên không có độ trễ.
  3. **dialog**: class khớp thì mới chạy `shell.qml` hiện dialog; Yes mới đóng, No/Esc thì không đóng gì.
- Cửa sổ luôn được đóng theo địa chỉ đọc ở lớp 1, nên lia chuột đổi focus trong lúc hỏi không làm đóng nhầm. Kết quả `hyprctl` ghi ở `/tmp/sumi-kakunin.log`.
- `protectedClasses` chỉnh trong hub (OPTIONS của kakunin): glob `zen*`, `Minecraft*`; chưa đặt = hai mục đó, `[]` = không bảo vệ app nào.
- Mã thoát: `0` = đã đóng, `1` = không đóng (No / Esc / bấm ra ngoài / không có cửa sổ).
- Chạy `qs -p shell.qml` trực tiếp (không qua `kakunin.sh`): `shell.qml` tự làm cả 3 lớp; có biến `CONFIRM_APP` (+ `CONFIRM_TITLE`, `CONFIRM_WS`, `CONFIRM_MONITOR`) thì chỉ hiện dialog, không tự đóng.
- Chạy độc lập, không cần hub. Cấu hình ở `~/.config/sumi/config.json`, màu ở `~/.config/sumi/colors.json`.

`View.qml` là giao diện thuần (không Process, không thoát tiến trình); `shell.qml` nối signal với exit code.
