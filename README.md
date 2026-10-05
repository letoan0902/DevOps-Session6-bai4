# DevOps - Session 06 - Bài 4

Quản lý tiến trình nền với `nohup` và tín hiệu `kill`.

Bài tập yêu cầu viết một shell script giám sát chạy liên tục, khởi chạy ở chế độ nền độc lập với phiên terminal bằng `nohup`, tìm PID của tiến trình, rồi tắt an toàn bằng `kill` với SIGTERM (15) trước và SIGKILL (9) khi cần.

## Mục lục

- [Báo cáo chi tiết (homework/session_06/ex4/README.md)](homework/session_06/ex4/README.md)
  - Tạo script và cấp quyền thực thi
  - Khởi chạy nền bằng `nohup`
  - Tìm PID bằng `pgrep`, `ps`, `pstree`
  - Giám sát bằng `top`, `htop`, `tail`
  - Chứng minh tiến trình sống sót sau khi ngắt SSH
  - Tắt bằng SIGTERM, trường hợp phải dùng SIGKILL
  - Bảng tín hiệu, script cải tiến, xử lý sự cố

## Danh sách file

| Đường dẫn | Mô tả |
|---|---|
| `homework/session_06/ex4/README.md` | Báo cáo bài làm |
| `homework/session_06/ex4/loop-monitor.sh` | Script chính theo đề: ghi thời gian vào `/tmp/monitor.log` mỗi 5 giây |
| `homework/session_06/ex4/loop-monitor-stubborn.sh` | Biến thể bỏ qua SIGTERM, dùng để thử SIGKILL |
| `homework/session_06/ex4/loop-monitor-graceful.sh` | Bản cải tiến có `trap`, file PID và dòng "stopped" |
| `homework/session_06/ex4/terminal_log.txt` | Log đầy đủ phiên làm việc theo thứ tự thời gian |
