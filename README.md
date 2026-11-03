# sumi-kakunin 確認

Dialog xác nhận đóng cửa sổ được bảo vệ, một app của hệ thống SUMI.

- Chạy: `sumi kakunin` (biến môi trường tùy chọn: `CONFIRM_APP`, `CONFIRM_TITLE`, `CONFIRM_WS`, `CONFIRM_MONITOR`).
- Hợp đồng: thoát mã `0` = Yes, mã `1` = No / Esc / bấm ra ngoài.
- Chạy độc lập, không cần hub. Cấu hình ở `~/.config/sumi/config.json`, màu ở `~/.config/sumi/colors.json`.

`View.qml` là giao diện thuần (không Process, không thoát tiến trình); `shell.qml` nối signal với exit code.
