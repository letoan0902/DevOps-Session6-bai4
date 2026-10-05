#!/bin/bash
# Biến thể dùng để thử nghiệm: bỏ qua SIGTERM nên kill -15 không có tác dụng
trap '' TERM
while true; do
    echo "System time: $(date)" >> /tmp/monitor.log
    sleep 5
done
