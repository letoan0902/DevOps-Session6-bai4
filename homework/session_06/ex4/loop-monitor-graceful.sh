#!/bin/bash
# loop-monitor-graceful.sh - bản cải tiến của loop-monitor.sh
# - Ghi PID vào /tmp/loop-monitor.pid để lần sau dừng đúng tiến trình, không phải đoán PID.
# - Bắt SIGTERM và SIGINT: ghi dòng "stopped" vào log, xóa file PID rồi mới thoát.
# Lưu ý: SIGKILL (9) và SIGSTOP (19) không thể bắt nên script không xử lý được.

LOG=/tmp/monitor.log
PIDFILE=/tmp/loop-monitor.pid
SLEEP_PID=""

cleanup() {
    [ -n "$SLEEP_PID" ] && kill "$SLEEP_PID" 2>/dev/null
    echo "System time: $(date) - stopped by signal $1 (PID $$)" >> "$LOG"
    rm -f "$PIDFILE"
    exit 0
}
trap 'cleanup TERM' TERM
trap 'cleanup INT' INT

echo $$ > "$PIDFILE"
echo "System time: $(date) - started (PID $$)" >> "$LOG"

while true; do
    echo "System time: $(date)" >> "$LOG"
    # Chạy sleep ở nền rồi wait, để trap được xử lý ngay thay vì chờ hết 5 giây.
    sleep 5 &
    SLEEP_PID=$!
    wait "$SLEEP_PID"
done
