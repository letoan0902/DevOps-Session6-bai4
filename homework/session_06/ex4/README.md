# Bài 4 - Quản lý tiến trình nền với nohup và tín hiệu Kill

Môn DevOps - Session 06. Ngày thực hiện: Thứ Ba, 2026-10-06, khoảng 09:10 đến 09:36 (giờ máy chủ, múi giờ +07).

## 1. Mục tiêu và bối cảnh

Mục tiêu của bài:

- Khởi chạy tiến trình chạy nền, độc lập với phiên terminal, bằng `nohup` và ký tự `&`.
- Giám sát tiến trình bằng `ps`, `pgrep`, `pstree`, `top` (và `htop`).
- Hiểu cơ chế tín hiệu (signal) và dùng `kill` đúng cách: SIGTERM (15) trước, SIGKILL (9) sau cùng.

Bối cảnh: có một kịch bản giám sát hệ thống viết bằng shell script chạy liên tục. Kịch bản phải tiếp tục chạy khi ngắt kết nối SSH, và khi cần phải tìm ra rồi tắt nó một cách an toàn.

Môi trường thực hiện:

| Hạng mục | Giá trị |
|---|---|
| Máy chủ | Ubuntu 24.04.3 LTS, kernel 6.8.0-87-generic |
| Hostname / IP | `halo` / `103.116.104.228` |
| Tài khoản | `devops` (uid 1001, thuộc nhóm sudo) |
| Thư mục làm việc | `/home/devops/scripts` |
| Kết nối | `ssh -p 2222 -i ~/.ssh/id_ed25519_ptit_s02 devops@103.116.104.228` |
| Máy cá nhân | Windows, Git Bash, IP công cộng `113.161.72.19` |
| Phiên bản công cụ | bash 5.2.21, procps-ng 4.0.4, coreutils 9.4 (nohup) |

Toàn bộ phiên làm việc được ghi lại theo thứ tự thời gian trong file [terminal_log.txt](terminal_log.txt). Các đoạn trích trong báo cáo này lấy từ file đó.

Các file trong thư mục bài nộp:

| File | Vai trò |
|---|---|
| `loop-monitor.sh` | Script chính theo đề: ghi thời gian vào `/tmp/monitor.log` mỗi 5 giây |
| `loop-monitor-stubborn.sh` | Biến thể bỏ qua SIGTERM, dùng để thử trường hợp phải dùng SIGKILL |
| `loop-monitor-graceful.sh` | Bản cải tiến có `trap`, file PID và dòng "stopped" |
| `terminal_log.txt` | Log đầy đủ phiên làm việc |

## 2. Bước 1 - Tạo script và cấp quyền thực thi

Đăng nhập SSH, kiểm tra nhanh môi trường rồi tạo script bằng heredoc theo gợi ý của đề. Dấu nháy đơn trong `<< 'EOF'` giúp shell không thay thế `$(date)` ngay lúc tạo file, nên nội dung được ghi nguyên văn.

```bash
devops@halo:~$ cd ~/scripts
devops@halo:~/scripts$ cat << 'EOF' > loop-monitor.sh
> #!/bin/bash
> while true; do
>     echo "System time: $(date)" >> /tmp/monitor.log
>     sleep 5
> done
> EOF
devops@halo:~/scripts$ cat loop-monitor.sh
#!/bin/bash
while true; do
    echo "System time: $(date)" >> /tmp/monitor.log
    sleep 5
done
```

Kiểm tra cú pháp bằng `bash -n` (chỉ phân tích cú pháp, không chạy script), thử chạy khi chưa có quyền thực thi, rồi cấp quyền:

```bash
devops@halo:~/scripts$ ls -l loop-monitor.sh
-rw-rw-r-- 1 devops devops 96 Oct  6 09:12 loop-monitor.sh
devops@halo:~/scripts$ bash -n loop-monitor.sh; echo "exit=$?"
exit=0
devops@halo:~/scripts$ ./loop-monitor.sh
bash: ./loop-monitor.sh: Permission denied
devops@halo:~/scripts$ chmod +x loop-monitor.sh
devops@halo:~/scripts$ ls -l loop-monitor.sh
-rwxrwxr-x 1 devops devops 96 Oct  6 09:12 loop-monitor.sh
```

Quyền chuyển từ `-rw-rw-r--` (664) sang `-rwxrwxr-x` (775): bit `x` được thêm cho owner, group và other. Lỗi `Permission denied` ở bước giữa chứng minh việc cấp quyền là bắt buộc trước khi chạy bằng `./`.

## 3. Bước 2 - Khởi chạy nền bằng nohup

```bash
devops@halo:~/scripts$ nohup ./loop-monitor.sh > /dev/null 2>&1 &
[1] 48317
devops@halo:~/scripts$ echo $!
48317
devops@halo:~/scripts$ jobs -l
[1]+ 48317 Running                 nohup ./loop-monitor.sh > /dev/null 2>&1 &
devops@halo:~/scripts$ ls nohup.out
ls: cannot access 'nohup.out': No such file or directory
devops@halo:~/scripts$ cat /tmp/monitor.log
System time: Tue Oct  6 09:16:41 AM +07 2026
System time: Tue Oct  6 09:16:46 AM +07 2026
System time: Tue Oct  6 09:16:51 AM +07 2026
System time: Tue Oct  6 09:16:56 AM +07 2026
```

Kết quả: shell in `[1] 48317`, trong đó `1` là số job trong phiên shell hiện tại và `48317` là PID. `$!` là biến đặc biệt chứa PID của tiến trình nền gần nhất, khớp với số vừa in. `jobs -l` cho thấy job đang ở trạng thái `Running`. Dòng đầu tiên của log xuất hiện ngay lúc khởi chạy (09:16:41) vì vòng lặp ghi log trước rồi mới `sleep`.

### 3.1. Ý nghĩa từng thành phần của lệnh

| Thành phần | Tác dụng |
|---|---|
| `nohup` | Đặt cách xử lý SIGHUP thành "bỏ qua" (SIG_IGN) rồi `exec` lệnh phía sau. Cách xử lý "bỏ qua" được giữ nguyên qua `exec`, nên script nhận SIGHUP cũng không chết. Nếu stdin là terminal, `nohup` chuyển stdin sang một file không đọc được, và in thông báo `nohup: ignoring input` lên stderr. |
| `./loop-monitor.sh` | Script cần chạy, dùng đường dẫn tương đối vì đang ở trong `/home/devops/scripts`. |
| `> /dev/null` | Chuyển stdout vào "hố đen". Nếu stdout còn là terminal, `nohup` tự tạo file `nohup.out` trong thư mục hiện tại. Script này đã tự ghi log vào `/tmp/monitor.log` nên không cần `nohup.out`. |
| `2>&1` | Chuyển stderr về cùng nơi với stdout (`/dev/null`). Thứ tự bắt buộc: `> /dev/null` đứng trước rồi mới `2>&1`. |
| `&` | Chạy lệnh ở nền: shell trả lại prompt ngay, không chờ tiến trình kết thúc. |

Kiểm tra trực tiếp: file `nohup.out` không tồn tại (`ls nohup.out` báo lỗi) vì stdout đã được chuyển hướng từ đầu.

### 3.2. So sánh với các cách khác

| Cách | Cơ chế | Hạn chế |
|---|---|---|
| Chỉ dùng `&` | Chạy nền nhưng vẫn thuộc phiên terminal. Khi terminal đóng, shell gửi SIGHUP đến các job, tiến trình chết. | Không an toàn cho tác vụ cần sống sau khi logout. |
| `nohup cmd &` | Bỏ qua SIGHUP, tiến trình sống tiếp sau khi terminal đóng. | Vẫn là con của shell cho tới khi shell thoát; khi đó được init nhận nuôi. Không có cách "gắn lại" terminal. |
| `cmd &` rồi `disown` (hoặc `disown -h`) | Xóa job khỏi bảng job của shell nên shell không gửi SIGHUP khi thoát. | Tiến trình vẫn gắn với terminal; nếu ghi ra terminal đã đóng sẽ bị lỗi. Không chặn được SIGHUP gửi từ nơi khác. |
| `setsid cmd &` | Tạo session mới, tiến trình không còn terminal điều khiển nên không nhận SIGHUP do đóng terminal. | Cần chuyển hướng stdin/stdout/stderr thủ công. |
| `tmux` / `screen` | Chạy shell trong một server riêng, có thể detach rồi attach lại để xem và gõ lệnh. | Thích hợp cho tác vụ tương tác; tốn thêm công cụ cho một script chỉ cần chạy nền. |
| Service của systemd | systemd quản lý vòng đời, tự khởi động lại, ghi log vào journal. | Cần quyền cấu hình; là hướng nên dùng cho tác vụ chạy dài hạn (xem mục 10). |

## 4. Bước 3 - Tìm PID của tiến trình

### 4.1. pgrep

```bash
devops@halo:~/scripts$ pgrep -f loop-monitor.sh
48317
devops@halo:~/scripts$ pgrep -af loop-monitor.sh
48317 /bin/bash ./loop-monitor.sh
```

`-f` khớp pattern với toàn bộ dòng lệnh (không chỉ tên tiến trình), `-a` in kèm dòng lệnh đầy đủ. Dòng lệnh thật là `/bin/bash ./loop-monitor.sh`: kernel đọc dòng `#!/bin/bash` và chạy script bằng trình thông dịch bash, PID vẫn là PID của tiến trình do `nohup` `exec` ra.

### 4.2. ps aux và grep

```bash
devops@halo:~/scripts$ ps aux | grep loop-monitor.sh
devops     48317  0.0  0.0   7372  3200 pts/0    S    09:16   0:00 /bin/bash ./loop-monitor.sh
devops     48359  0.0  0.0   9144  2304 pts/0    S+   09:18   0:00 grep --color=auto loop-monitor.sh
```

Kết quả có hai dòng. Dòng thứ hai là chính lệnh `grep loop-monitor.sh` vừa chạy: dòng lệnh của nó chứa chuỗi cần tìm nên `ps` liệt kê nó và `grep` lại khớp với nó. Mẹo để loại dòng này: viết một ký tự của pattern trong cặp ngoặc vuông.

```bash
devops@halo:~/scripts$ ps aux | grep "[l]oop-monitor.sh"
devops     48317  0.0  0.0   7372  3200 pts/0    S    09:16   0:00 /bin/bash ./loop-monitor.sh
```

Pattern `[l]oop-monitor.sh` vẫn khớp với `loop-monitor.sh`, nhưng dòng lệnh của chính `grep` chứa chuỗi `[l]oop-monitor.sh` (có dấu `]` chen giữa) nên không còn khớp.

Ý nghĩa các cột của `ps aux`:

| Cột | Ý nghĩa | Giá trị ở dòng script |
|---|---|---|
| USER | Chủ sở hữu tiến trình | `devops` |
| PID | Mã tiến trình | 48317 |
| %CPU | Tỷ lệ CPU đã dùng trên thời gian sống của tiến trình | 0.0 |
| %MEM | Tỷ lệ RAM vật lý đang chiếm | 0.0 (3200 KiB trên khoảng 7,7 GiB RAM) |
| VSZ | Kích thước bộ nhớ ảo (KiB) | 7372 |
| RSS | Bộ nhớ vật lý thực sự đang dùng (KiB) | 3200 |
| TTY | Terminal điều khiển; `?` nghĩa là không có | `pts/0` |
| STAT | Trạng thái tiến trình | `S` |
| START | Thời điểm bắt đầu | 09:16 |
| TIME | Tổng thời gian CPU đã tiêu thụ | 0:00 |
| COMMAND | Dòng lệnh đầy đủ | `/bin/bash ./loop-monitor.sh` |

Trạng thái `S` là interruptible sleep: tiến trình đang chờ sự kiện (ở đây là chờ tiến trình con `sleep 5` kết thúc), không chiếm CPU và có thể bị đánh thức bằng tín hiệu. Dòng của `grep` có `S+` vì `+` đánh dấu tiến trình thuộc nhóm tiến trình foreground của terminal; script chạy nền nên không có `+`. Một số trạng thái khác: `R` đang chạy hoặc sẵn sàng chạy, `D` chờ I/O không thể ngắt, `T` đang bị dừng, `Z` zombie.

### 4.3. ps -ef, ps -o và pstree

```bash
devops@halo:~/scripts$ ps -ef | grep "[l]oop-monitor"
devops     48317   48202  0 09:16 pts/0    00:00:00 /bin/bash ./loop-monitor.sh
devops@halo:~/scripts$ ps -o pid,ppid,pgid,sid,tty,stat,etime,cmd -p 48317
    PID    PPID    PGID     SID TTY      STAT     ELAPSED CMD
  48317   48202   48317   48202 pts/0    S          02:16 /bin/bash ./loop-monitor.sh
devops@halo:~/scripts$ pstree -p -A 48317
loop-monitor.sh(48317)---sleep(48402)
devops@halo:~/scripts$ pstree -s -p -A 48317
systemd(1)---sshd(971)---sshd(48190)---sshd(48201)---bash(48202)---loop-monitor.sh(48317)---sleep(48408)
```

Diễn giải:

- PPID = 48202 là shell `bash` của phiên SSH hiện tại (`echo $$` ở đầu phiên cũng trả về 48202).
- PGID = 48317: job nền được đặt trong nhóm tiến trình riêng, PGID bằng PID của nó. SID = 48202: cả hai cùng session do bash làm session leader, TTY là `pts/0`.
- ELAPSED = 02:16 khớp với thời gian từ 09:16:41 tới 09:18:57.
- `pstree` cho thấy script có tiến trình con `sleep`. PID của `sleep` đổi sau mỗi 5 giây (48402 rồi 48408) vì mỗi vòng lặp sinh ra một tiến trình `sleep 5` mới. Tùy chọn `-A` ép pstree dùng ký tự ASCII để dễ copy, `-s` hiển thị chuỗi tiến trình cha.

## 5. Bước 4 - Giám sát tiến trình

### 5.1. top

```bash
devops@halo:~/scripts$ top -b -n 1 -p 48317
top - 09:19:52 up 12 days,  3:41,  1 user,  load average: 0.00, 0.01, 0.00
Tasks:   1 total,   0 running,   1 sleeping,   0 stopped,   0 zombie
%Cpu(s):  0.6 us,  0.4 sy,  0.0 ni, 98.7 id,  0.2 wa,  0.0 hi,  0.1 si,  0.0 st 
MiB Mem :   7937.4 total,   5412.8 free,   1021.6 used,   1503.0 buff/cache
MiB Swap:   2048.0 total,   2048.0 free,      0.0 used.   6915.8 avail Mem 

    PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND
  48317 devops    20   0    7372   3200   2944 S   0.0   0.0   0:00.06 loop-monitor.sh
```

`-b` là chế độ batch (in ra stdout, không tương tác), `-n 1` chỉ lấy một lần cập nhật, `-p 48317` giới hạn ở PID đã tìm được. Tiến trình dùng 0.0% CPU và 0.0% RAM, đúng với bản chất của một vòng lặp gần như chỉ ngủ. Cột COMMAND của `top` hiển thị tên tiến trình (`comm`), ở đây là tên file script `loop-monitor.sh`, khác với cột COMMAND của `ps aux` là dòng lệnh đầy đủ.

### 5.2. htop

`htop` là công cụ tương tác tương tự `top` nhưng dễ dùng hơn, trong bài này chỉ cần các thao tác sau:

- F3 (hoặc `/`): tìm kiếm theo tên, gõ `loop-monitor` để nhảy tới tiến trình.
- F4: lọc danh sách theo chuỗi.
- F5: bật chế độ cây tiến trình, thấy `sleep` nằm dưới `loop-monitor.sh`.
- F9: mở danh sách tín hiệu để gửi cho tiến trình đang chọn (chọn 15 SIGTERM hoặc 9 SIGKILL, tương đương lệnh `kill`).
- F10 hoặc `q`: thoát.

### 5.3. tail, wc và tail -f

```bash
devops@halo:~/scripts$ tail -n 10 /tmp/monitor.log
System time: Tue Oct  6 09:19:51 AM +07 2026
System time: Tue Oct  6 09:19:56 AM +07 2026
System time: Tue Oct  6 09:20:01 AM +07 2026
System time: Tue Oct  6 09:20:06 AM +07 2026
System time: Tue Oct  6 09:20:11 AM +07 2026
System time: Tue Oct  6 09:20:16 AM +07 2026
System time: Tue Oct  6 09:20:21 AM +07 2026
System time: Tue Oct  6 09:20:26 AM +07 2026
System time: Tue Oct  6 09:20:31 AM +07 2026
System time: Tue Oct  6 09:20:36 AM +07 2026
devops@halo:~/scripts$ wc -l /tmp/monitor.log
50 /tmp/monitor.log
```

Mười dòng cách nhau đúng 5 giây. Kiểm tra số học: từ 09:16:41 đến 09:20:46 là 245 giây, 245 / 5 + 1 = 50 dòng, khớp với `wc -l`.

`tail -f` theo dõi file theo thời gian thực: in 10 dòng cuối rồi chờ dòng mới. Sau khoảng 12 giây có thêm 3 dòng (09:21:11, 09:21:16, 09:21:21), nhấn Ctrl+C để thoát (terminal hiển thị `^C`). Ctrl+C chỉ dừng `tail`: terminal chỉ gửi SIGINT cho nhóm tiến trình foreground, còn script nền nằm trong nhóm tiến trình khác nên không bị ảnh hưởng.

## 6. Bước 5 - Chứng minh tiến trình sống sót khi ngắt SSH

Ghi lại PID và số dòng log ngay trước khi thoát:

```bash
devops@halo:~/scripts$ date; pgrep -f loop-monitor.sh; wc -l /tmp/monitor.log
Tue Oct  6 09:21:58 AM +07 2026
48317
64 /tmp/monitor.log
devops@halo:~/scripts$ jobs
[1]+  Running                 nohup ./loop-monitor.sh > /dev/null 2>&1 &
devops@halo:~/scripts$ exit
logout
Connection to 103.116.104.228 closed.
```

Trên máy cá nhân, chờ khoảng 2 phút rồi đăng nhập lại:

```bash
$ date '+%F %T'
2026-10-06 09:22:19
$ sleep 120
$ date '+%F %T'
2026-10-06 09:24:27
$ ssh -p 2222 -i ~/.ssh/id_ed25519_ptit_s02 devops@103.116.104.228
Welcome to Ubuntu 24.04.3 LTS (GNU/Linux 6.8.0-87-generic x86_64)
...
Last login: Tue Oct  6 09:10:14 2026 from 113.161.72.19
```

Kiểm tra trong phiên mới:

```bash
devops@halo:~$ echo $$
48601
devops@halo:~$ jobs
devops@halo:~$ pgrep -af loop-monitor.sh
48317 /bin/bash ./loop-monitor.sh
devops@halo:~$ grep SigIgn /proc/48317/status
SigIgn:	0000000000000001
devops@halo:~$ ps -o pid,ppid,tty,stat,etime,cmd -p 48317
    PID    PPID TTY      STAT     ELAPSED CMD
  48317       1 ?        S          08:29 /bin/bash ./loop-monitor.sh
devops@halo:~$ pstree -s -p -A 48317
systemd(1)---loop-monitor.sh(48317)---sleep(48627)
devops@halo:~$ wc -l /tmp/monitor.log
108 /tmp/monitor.log
```

Bảng đối chiếu trước và sau khi ngắt kết nối:

| Chỉ tiêu | Trước khi thoát (phiên 1) | Sau khi đăng nhập lại (phiên 2) |
|---|---|---|
| PID script | 48317 | 48317 (giữ nguyên) |
| PPID | 48202 (bash của phiên SSH) | 1 (systemd) |
| TTY | pts/0 | `?` (không còn terminal) |
| Shell hiện tại | PID 48202 | PID 48601 (shell mới) |
| `jobs` | Có job `[1]` | Rỗng, vì đây là shell mới không biết job cũ |
| Số dòng log | 64 (lúc 09:21:58) | 108 (lúc 09:25:38) |

Số dòng tăng từ 64 lên 108, tức 44 dòng trong 220 giây (từ 09:21:58 đến 09:25:38), đúng với chu kỳ 5 giây. Đoạn log quanh thời điểm ngắt kết nối (09:22:12) liên tục, không có khoảng trống:

```bash
devops@halo:~$ sed -n '63,70p' /tmp/monitor.log
System time: Tue Oct  6 09:21:51 AM +07 2026
System time: Tue Oct  6 09:21:56 AM +07 2026
System time: Tue Oct  6 09:22:01 AM +07 2026
System time: Tue Oct  6 09:22:06 AM +07 2026
System time: Tue Oct  6 09:22:11 AM +07 2026
System time: Tue Oct  6 09:22:16 AM +07 2026
System time: Tue Oct  6 09:22:21 AM +07 2026
System time: Tue Oct  6 09:22:26 AM +07 2026
```

### 6.1. Cơ chế SIGHUP và vai trò của nohup

SIGHUP (Hang Up, số 1) vốn được tạo ra để báo "đường dây modem đã ngắt". Với terminal hiện đại, khi cửa sổ terminal đóng hoặc kết nối SSH đứt, pseudo-terminal bị đóng, kernel gửi SIGHUP cho session leader (bash). Bash là shell tương tác nên khi nhận SIGHUP sẽ gửi tiếp SIGHUP cho các job còn trong bảng job của nó. Hành động mặc định của SIGHUP là kết thúc tiến trình, vì vậy job chạy nền bằng `&` thông thường sẽ chết theo.

`nohup` chặn chuỗi này ở khâu cuối: tiến trình đã đặt SIGHUP ở trạng thái bị bỏ qua. Cách xử lý "bỏ qua" được giữ nguyên qua `exec` và qua `fork`, và với shell không tương tác, tín hiệu đã bị bỏ qua từ lúc khởi động thì script không thể bắt hay đặt lại bằng `trap`. Bằng chứng: `SigIgn: 0000000000000001` trong `/proc/48317/status`, mặt nạ bit có bit 0 (SIGHUP, số 1) được bật.

Khi bash cha thoát, tiến trình mất cha và trở thành mồ côi. Kernel gán nó cho tiến trình init (PID 1, tức systemd), vì vậy PPID chuyển từ 48202 thành 1. TTY chuyển thành `?` vì terminal điều khiển đã biến mất.

Lưu ý về `KillUserProcesses` của systemd-logind: nếu tùy chọn này bật (`yes`), khi người dùng logout, systemd sẽ kết thúc toàn bộ tiến trình thuộc session của họ, kể cả tiến trình chạy bằng `nohup`. Trên Ubuntu giá trị mặc định là `no`, đã kiểm tra trên máy chủ:

```bash
devops@halo:~$ loginctl show -p KillUserProcesses
KillUserProcesses=no
```

Nếu quản trị viên đặt `KillUserProcesses=yes` trong `/etc/systemd/logind.conf`, `nohup` không còn đủ: cần `systemd-run --user`, `loginctl enable-linger` hoặc tạo service riêng.

## 7. Bước 6 - Tắt tiến trình an toàn bằng SIGTERM (15)

```bash
devops@halo:~$ ps aux | grep loop-monitor.sh
devops     48317  0.0  0.0   7372  3200 ?        S    09:16   0:00 /bin/bash ./loop-monitor.sh
devops     48689  0.0  0.0   9144  2304 pts/0    S+   09:27   0:00 grep --color=auto loop-monitor.sh
devops@halo:~$ kill -15 48317
devops@halo:~$ echo $?
0
devops@halo:~$ ps -ef | grep "[s]leep 5"
devops     48703       1  0 09:27 ?        00:00:00 sleep 5
devops@halo:~$ ps aux | grep loop-monitor.sh
devops     48715  0.0  0.0   9144  2304 pts/0    S+   09:27   0:00 grep --color=auto loop-monitor.sh
devops@halo:~$ pgrep -f loop-monitor.sh; echo "exit=$?"
exit=1
devops@halo:~$ wc -l /tmp/monitor.log
134 /tmp/monitor.log
devops@halo:~$ sleep 10; wc -l /tmp/monitor.log
134 /tmp/monitor.log
devops@halo:~$ tail -n 3 /tmp/monitor.log
System time: Tue Oct  6 09:27:36 AM +07 2026
System time: Tue Oct  6 09:27:41 AM +07 2026
System time: Tue Oct  6 09:27:46 AM +07 2026
```

Ba cách viết `kill 48317`, `kill -15 48317` và `kill -TERM 48317` tương đương nhau, vì SIGTERM là tín hiệu mặc định của `kill`.

Kết luận sau khi kill:

- `echo $?` bằng 0 nghĩa là `kill` gửi tín hiệu thành công (không phải script đã thoát với mã 0). Nếu PID không tồn tại, `kill` báo `No such process` và trả về mã khác 0.
- `ps aux | grep` chỉ còn dòng của chính `grep`, `pgrep` trả về `exit=1` (không tìm thấy tiến trình nào): script đã biến mất.
- Hai lần `wc -l` cách nhau 10 giây cùng cho 134 dòng, dòng cuối của log là 09:27:46: log đã ngừng tăng.
- Số dòng cũng khớp tính toán: 134 dòng ứng với (09:27:46 - 09:16:41) / 5 + 1 = 134.

Chi tiết kỹ thuật về tiến trình con: SIGTERM chỉ được gửi tới PID 48317 (bash), không tới tiến trình con `sleep 5` đang chạy. Bash chết ngay, còn `sleep 5` bị mồ côi, có PPID = 1 (xem dòng `ps -ef` ở trên, PID 48703) và tự kết thúc khi hết 5 giây. Sau vài giây `ps` không còn thấy nó. Vì tiến trình con này vô hại và rất ngắn nên không cần xử lý, nhưng nếu tiến trình con chạy lâu thì phải gửi tín hiệu cho cả nhóm tiến trình (`kill -TERM -- -<PGID>`) hoặc dùng `pkill -f`.

## 8. Bước 7 - Khi SIGTERM không tắt được: dùng SIGKILL (9)

Để tái hiện tình huống tiến trình không phản hồi SIGTERM, tạo biến thể `loop-monitor-stubborn.sh` có dòng `trap '' TERM` (đặt SIGTERM ở trạng thái bị bỏ qua):

Nội dung đầy đủ nằm trong file `loop-monitor-stubborn.sh`; khác duy nhất so với bản gốc là dòng `trap '' TERM` ở đầu.

Chạy bằng nohup, kiểm tra và gửi SIGTERM:

```bash
devops@halo:~/scripts$ nohup ./loop-monitor-stubborn.sh > /dev/null 2>&1 &
[1] 48775
devops@halo:~/scripts$ pgrep -af loop-monitor-stubborn.sh
48775 /bin/bash ./loop-monitor-stubborn.sh
devops@halo:~/scripts$ grep SigIgn /proc/48775/status
SigIgn:	0000000000004001
devops@halo:~/scripts$ kill -15 48775
devops@halo:~/scripts$ echo $?
0
devops@halo:~/scripts$ ps -o pid,ppid,stat,etime,cmd -p 48775
    PID    PPID STAT     ELAPSED CMD
  48775   48601 S          01:00 /bin/bash ./loop-monitor-stubborn.sh
devops@halo:~/scripts$ sleep 10; ps -o pid,ppid,stat,etime,cmd -p 48775
    PID    PPID STAT     ELAPSED CMD
  48775   48601 S          01:22 /bin/bash ./loop-monitor-stubborn.sh
```

`kill -15` vẫn trả về mã 0 (gửi thành công) nhưng tiến trình còn nguyên sau hơn 10 giây. Mặt nạ `SigIgn: 0000000000004001` cho thấy hai bit được bật: bit 0 (SIGHUP, do `nohup`) và bit 14 (SIGTERM, số 15, do `trap '' TERM`). Chỉ khi đó mới dùng SIGKILL:

```bash
devops@halo:~/scripts$ kill -9 48775
[1]+  Killed                  nohup ./loop-monitor-stubborn.sh > /dev/null 2>&1
devops@halo:~/scripts$ ps -o pid,stat,etime,cmd -p 48775
    PID STAT     ELAPSED CMD
devops@halo:~/scripts$ ps -ef | grep "[s]leep 5"
devops     48831       1  0 09:31 ?        00:00:00 sleep 5
devops@halo:~/scripts$ pgrep -af "sleep 5"; echo "exit=$?"
exit=1
devops@halo:~/scripts$ tail -n 3 /tmp/monitor.log
System time: Tue Oct  6 09:31:32 AM +07 2026
System time: Tue Oct  6 09:31:37 AM +07 2026
System time: Tue Oct  6 09:31:42 AM +07 2026
```

Tiến trình biến mất khỏi `ps`; bash của phiên báo `Killed`. Tiến trình con `sleep 5` (PID 48831) bị mồ côi, PPID = 1, và tự kết thúc sau vài giây (lần `pgrep` sau đó cho `exit=1`). Nếu nó còn sót lại, dọn bằng `pkill -f "sleep 5"` (cẩn thận pattern, vì `pkill -f` khớp mọi tiến trình có dòng lệnh chứa chuỗi đó, kể cả của người khác nếu dùng sudo).

Vì sao SIGKILL không thể bị bắt hay bỏ qua: SIGKILL (9) và SIGSTOP (19) được kernel xử lý trực tiếp, không chuyển cho tiến trình. Tiến trình không có cơ hội chạy handler hay `trap`, nên không ai chặn được. Đây là lý do SIGKILL luôn hiệu quả (trừ tiến trình ở trạng thái `D` đang chờ I/O hoặc zombie). Đổi lại, tiến trình chết đột ngột:

- không dọn dẹp file tạm, không xóa file khóa (lock file) hay file PID;
- không xả bộ đệm ghi dở ra đĩa, dữ liệu có thể hỏng hoặc thiếu;
- không báo cho tiến trình con, nên có thể để lại tiến trình mồ côi như `sleep` ở trên;
- tiến trình cha thấy mã thoát 137 (128 + 9), còn với SIGTERM là 143 (128 + 15).

Vì vậy SIGKILL chỉ dùng sau cùng, khi đã thử SIGTERM, chờ đủ lâu mà tiến trình vẫn không thoát.

## 9. Bước 8 - Bảng tín hiệu thường dùng và quy trình tắt chuẩn

Danh sách tín hiệu trên máy chủ (bash 5.2.21, Linux x86_64):

```bash
devops@halo:~/scripts$ kill -l
 1) SIGHUP	 2) SIGINT	 3) SIGQUIT	 4) SIGILL	 5) SIGTRAP
 6) SIGABRT	 7) SIGBUS	 8) SIGFPE	 9) SIGKILL	10) SIGUSR1
11) SIGSEGV	12) SIGUSR2	13) SIGPIPE	14) SIGALRM	15) SIGTERM
16) SIGSTKFLT	17) SIGCHLD	18) SIGCONT	19) SIGSTOP	20) SIGTSTP
21) SIGTTIN	22) SIGTTOU	23) SIGURG	24) SIGXCPU	25) SIGXFSZ
26) SIGVTALRM	27) SIGPROF	28) SIGWINCH	29) SIGIO	30) SIGPWR
31) SIGSYS	34) SIGRTMIN	35) SIGRTMIN+1	36) SIGRTMIN+2	37) SIGRTMIN+3
38) SIGRTMIN+4	39) SIGRTMIN+5	40) SIGRTMIN+6	41) SIGRTMIN+7	42) SIGRTMIN+8
43) SIGRTMIN+9	44) SIGRTMIN+10	45) SIGRTMIN+11	46) SIGRTMIN+12	47) SIGRTMIN+13
48) SIGRTMIN+14	49) SIGRTMIN+15	50) SIGRTMAX-14	51) SIGRTMAX-13	52) SIGRTMAX-12
53) SIGRTMAX-11	54) SIGRTMAX-10	55) SIGRTMAX-9	56) SIGRTMAX-8	57) SIGRTMAX-7
58) SIGRTMAX-6	59) SIGRTMAX-5	60) SIGRTMAX-4	61) SIGRTMAX-3	62) SIGRTMAX-2
63) SIGRTMAX-1	64) SIGRTMAX	
```

Các số tín hiệu đánh số từ 1 đến 64. Số 32 và 33 bị thư viện luồng của glibc giữ lại nên bash không liệt kê; vì vậy danh sách hiển thị 62 tín hiệu.

Các tín hiệu hay gặp:

| Tên (số) | Ý nghĩa | Bắt hoặc bỏ qua được | Tình huống dùng |
|---|---|---|---|
| SIGHUP (1) | Terminal bị đóng, hoặc yêu cầu đọc lại cấu hình | Có | Daemon như nginx nhận SIGHUP để nạp lại cấu hình (`kill -HUP`); nohup dùng cách bỏ qua tín hiệu này |
| SIGINT (2) | Ngắt từ bàn phím (Ctrl+C) | Có | Dừng chương trình đang chạy ở foreground |
| SIGQUIT (3) | Thoát từ bàn phím (Ctrl+\\), có thể tạo core dump | Có | Dừng để lấy core dump phục vụ chẩn đoán lỗi |
| SIGKILL (9) | Buộc kết thúc ngay | Không | Biện pháp cuối khi SIGTERM không có tác dụng |
| SIGUSR1 (10) | Tín hiệu do người dùng định nghĩa | Có | Ứng dụng tự quy định, ví dụ xoay file log, in trạng thái |
| SIGTERM (15) | Yêu cầu kết thúc lịch sự, tín hiệu mặc định của `kill` | Có | Cách dừng chuẩn, cho phép dọn dẹp trước khi thoát |
| SIGCONT (18) | Tiếp tục tiến trình đang bị dừng | Có (handler); việc tiếp tục luôn xảy ra | Chạy lại tiến trình sau SIGSTOP hoặc Ctrl+Z |
| SIGSTOP (19) | Tạm dừng tiến trình | Không | Đóng băng tiến trình để điều tra mà không kết thúc nó |

Quy trình tắt chuẩn gồm ba bước: gửi TERM, chờ, kiểm tra còn sống không rồi mới KILL. Đoạn lệnh mẫu:

```bash
PID=48317
kill -15 "$PID"                       # 1. yêu cầu dừng lịch sự
for i in 1 2 3 4 5; do                # 2. chờ tối đa 5 giây
    kill -0 "$PID" 2>/dev/null || { echo "Đã dừng sau SIGTERM"; exit 0; }
    sleep 1
done
echo "Vẫn còn sống, gửi SIGKILL"      # 3. biện pháp cuối cùng
kill -9 "$PID"
```

`kill -0` không gửi tín hiệu thật, chỉ kiểm tra tiến trình còn tồn tại và mình có quyền gửi tín hiệu hay không. Trước khi chạy `kill`, luôn kiểm tra lại PID bằng `ps -p <PID> -o pid,user,cmd`.

## 10. Mở rộng - Script có trap, file PID và hướng dùng systemd

### 10.1. loop-monitor-graceful.sh

Bản cải tiến bắt SIGTERM và SIGINT để ghi dòng "stopped" vào log và xóa file PID trước khi thoát, đồng thời ghi PID vào `/tmp/loop-monitor.pid`:

Phần cốt lõi của script (toàn bộ nội dung nằm trong file `loop-monitor-graceful.sh`):

```bash
cleanup() {
    [ -n "$SLEEP_PID" ] && kill "$SLEEP_PID" 2>/dev/null
    echo "System time: $(date) - stopped by signal $1 (PID $$)" >> "$LOG"
    rm -f "$PIDFILE"
    exit 0
}
trap 'cleanup TERM' TERM
trap 'cleanup INT' INT

echo $$ > "$PIDFILE"
while true; do
    echo "System time: $(date)" >> "$LOG"
    sleep 5 &
    SLEEP_PID=$!
    wait "$SLEEP_PID"
done
```

Điểm đáng chú ý: bash trì hoãn việc chạy `trap` cho đến khi lệnh foreground đang chạy (ở đây là `sleep 5`) kết thúc. Chạy `sleep` ở nền rồi `wait` giúp `wait` bị ngắt ngay khi có tín hiệu, `trap` chạy tức thì và không để lại `sleep` mồ côi.

Kết quả chạy thử:

```bash
devops@halo:~/scripts$ nohup ./loop-monitor-graceful.sh > /dev/null 2>&1 &
[1] 48903
devops@halo:~/scripts$ cat /tmp/loop-monitor.pid
48903
devops@halo:~/scripts$ kill -15 $(cat /tmp/loop-monitor.pid)
[1]+  Done                    nohup ./loop-monitor-graceful.sh > /dev/null 2>&1
devops@halo:~/scripts$ tail -n 4 /tmp/monitor.log
System time: Tue Oct  6 09:34:35 AM +07 2026
System time: Tue Oct  6 09:34:40 AM +07 2026
System time: Tue Oct  6 09:34:45 AM +07 2026
System time: Tue Oct  6 09:34:47 AM +07 2026 - stopped by signal TERM (PID 48903)
devops@halo:~/scripts$ ls /tmp/loop-monitor.pid
ls: cannot access '/tmp/loop-monitor.pid': No such file or directory
devops@halo:~/scripts$ pgrep -af "sleep 5"; echo "exit=$?"
exit=1
```

Script thoát có kiểm soát: bash báo `Done` (mã thoát 0 thay vì `Killed`), dòng "stopped" được ghi vào log, file PID bị xóa và không còn `sleep` sót lại.

### 10.2. Lưu ý và hướng dài hạn

- `/tmp` bị xóa khi khởi động lại máy (và có thể bị dọn định kỳ), nên `/tmp/monitor.log` và `/tmp/loop-monitor.pid` không bền. Dùng `/var/log` hoặc `/run` cho môi trường thật.
- `nohup` không tự khởi động lại tiến trình sau reboot hoặc khi tiến trình crash.
- Với tác vụ chạy lâu dài nên chuyển sang service của systemd. Ví dụ unit tối giản `/etc/systemd/system/loop-monitor.service`:

```ini
[Unit]
Description=Loop monitor ghi thời gian mỗi 5 giây
After=network.target

[Service]
Type=simple
User=devops
ExecStart=/home/devops/scripts/loop-monitor-graceful.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Khi đó `systemctl start|stop|status loop-monitor` thay thế việc tự tìm PID và gửi `kill`: `systemctl stop` gửi SIGTERM, chờ hết thời gian chờ rồi mới gửi SIGKILL, đúng quy trình ở mục 9.

## 11. Bảng xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| `bash: ./loop-monitor.sh: Permission denied` | Chưa có quyền thực thi | `chmod +x loop-monitor.sh` |
| `nohup: ignoring input` | stdin là terminal, `nohup` cắt stdin khỏi terminal và báo trên stderr. Thông báo vô hại. Với lệnh đầy đủ ở bài này, stderr đã vào `/dev/null` nên không hiện | Thêm `< /dev/null` nếu muốn bỏ hẳn |
| Xuất hiện `nohup.out` | stdout chưa được chuyển hướng | Dùng `> /dev/null 2>&1` hoặc `> file.log 2>&1` |
| `cannot execute: required file not found` | File script có xuống dòng CRLF (tạo trên Windows), `/bin/bash^M` không tồn tại | `sed -i 's/\r$//' loop-monitor.sh`, lưu file với LF |
| Nhiều bản chạy trùng, log ghi gấp nhiều lần | Chạy script nhiều lần mà không kiểm tra | `pgrep -c -f loop-monitor.sh` để đếm; dừng bằng `pkill -f loop-monitor.sh` hoặc kill từng PID; hoặc dùng file PID như bản graceful |
| Kill nhầm tiến trình | Dùng `pkill -f` với pattern quá rộng, hoặc gõ nhầm PID | Kiểm tra bằng `pgrep -af <pattern>` trước khi `pkill`; xác nhận PID bằng `ps -p <PID> -o pid,user,cmd` |
| `kill: (48317) - No such process` | PID đã thoát hoặc gõ sai | Tìm lại bằng `pgrep -af` |
| `kill: (PID) - Operation not permitted` | Tiến trình của user khác | Chỉ dùng `sudo kill` khi thật sự cần và đã xác nhận đúng tiến trình |
| `kill -9` không hiệu lực | Tiến trình ở trạng thái `D` (chờ I/O) hoặc `Z` (zombie) | Xử lý nguyên nhân I/O; với zombie thì cần tiến trình cha thu dọn (`wait`) hoặc dừng tiến trình cha |
| Log không tăng nhưng tiến trình còn | Tiến trình bị dừng (`T`) hoặc đĩa/`/tmp` đầy | `ps -o stat`; nếu `T` thì `kill -CONT <PID>`; kiểm tra `df -h /tmp` |

## 12. Đối chiếu yêu cầu đề bài

| Yêu cầu | Đã thực hiện | Vị trí |
|---|---|---|
| Viết `loop-monitor.sh` ghi thời gian vào `/tmp/monitor.log` mỗi 5 giây bằng `while true` và `sleep` | Đúng nội dung gợi ý của đề | `loop-monitor.sh`, mục 2 |
| Gán quyền thực thi | `chmod +x`, quyền từ `-rw-rw-r--` thành `-rwxrwxr-x` | Mục 2 |
| Khởi chạy nền độc lập bằng `nohup` | `nohup ./loop-monitor.sh > /dev/null 2>&1 &`, PID 48317 | Mục 3 |
| Tìm PID | `pgrep -f`, `pgrep -af`, `ps aux`, `ps -ef`, `ps -o`, `pstree` | Mục 4 |
| Kiểm tra bằng `ps aux`, `tail -n 10` | Đã chạy, log cách nhau 5 giây | Mục 4, 5 |
| Ghi đều đặn kể cả khi tắt session và đăng nhập lại | Log tăng từ 64 lên 108 dòng, PID giữ nguyên, PPID = 1 | Mục 6 |
| Tắt bằng SIGTERM trước | `kill -15 48317`, tiến trình biến mất khỏi `ps aux` | Mục 7 |
| Nếu không tắt được mới dùng SIGKILL | Thử với `loop-monitor-stubborn.sh`: `kill -15 48775` vô hiệu, `kill -9 48775` thành công | Mục 8 |
| README ghi lệnh nohup, kết quả tail, lệnh kill kèm PID | Có đầy đủ trong các mục 3, 5, 7, 8 | File này |

## 13. Kết luận

- `nohup` làm cho tiến trình bỏ qua SIGHUP nên sống sót khi terminal đóng hoặc SSH ngắt. Tiến trình 48317 chạy liên tục qua lần logout, PID không đổi, PPID chuyển thành 1 và TTY thành `?`, log tăng đều mỗi 5 giây.
- `pgrep -af`, `ps -o` và `pstree` là bộ công cụ nhanh để tìm PID, PPID, trạng thái và tiến trình con; `top`/`htop` giúp xem tài nguyên theo thời gian thực. Mẹo `grep "[l]oop-monitor"` loại bỏ dòng của chính `grep`.
- Tắt tiến trình theo thứ tự SIGTERM (15), chờ và kiểm tra, rồi mới SIGKILL (9). SIGTERM cho phép dọn dẹp; SIGKILL không bắt được, không dọn dẹp và có thể để lại tiến trình con mồ côi, vì vậy chỉ dùng cuối cùng.
- Với tác vụ chạy dài hạn nên dùng service của systemd thay cho `nohup`, và để script xử lý SIGTERM bằng `trap` để thoát có kiểm soát.
