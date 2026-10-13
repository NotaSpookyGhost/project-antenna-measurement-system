# Báo Cáo Nghiệm Thu Thiết Kế Hệ Thống Điều Khiển Ăng-Ten 2 Trục (Phiên Bản v3.0)

- **Tên dự án:** Antenna Positioner 2-Axis (Pan - Tilt)
- **Phiên bản nghiệm thu:** v3.0 (Tối Giản & Siêu Tốc)
- **Thời gian nghiệm thu:** 2026-10-03 14:21:00
- **Trạng thái:** Nghiệm thu thành công 100% trên phần cứng thực tế

---

## 1. Mục Tiêu Thiết Kế & Yêu Cầu Kỹ Thuật

1. Điều khiển đồng thời 2 trục: Trục Pan (Azimuth - xoay ngang cả cụm) và Trục Tilt (Elevation - ngẩng gật gù).
2. Tốc độ quay nhanh dứt khoát ($\sim 18^\circ/\text{s}$, quay $90^\circ$ trong $\sim 5$ giây).
3. Động cơ chạy êm ái bằng công nghệ StealthChop2, không tiếng rít, không giật khựng.
4. Vòng kín (Closed-Loop) giám sát qua 2 cảm biến từ tính 12-bit AS5600 gắn trực tiếp sau đuôi trục motor NEMA17.
5. Cắt giảm tối đa linh kiện, không cần module hạ áp ngoài, cắm trực tiếp USB máy tính 5V.

---

## 2. Lịch Sử Vấn Đề Gặp Phải & Nguyên Nhân Gốc Rễ

| STT | Vấn Đề Trước Đây | Nguyên Nhân Gốc Rễ | Giải Pháp Triệt Để (v3.0) |
| :--- | :--- | :--- | :--- |
| **1** | Motor kêu rú và giật mạnh | Code giả định UART hoạt động nên áp dụng vi bước 1/16 (50 bước/°), nhưng chân PDN bị hở mạch ngầm trên bo TMC2209. Driver tự chạy Standalone 1/8 vi bước $\rightarrow$ tần số xung sai lệch hoàn toàn. | Chuyển hẳn sang Standalone phần cứng, lấy đúng tỉ số thực nghiệm **$25.0$ bước / $1^\circ$**. |
| **2** | Góc quay bị vọt đi gấp đôi | Code tính $50$ bước/độ (1/16 vi bước), trong khi phần cứng thực tế chạy 1/8 vi bước chỉ cần $25$ bước/độ. Gửi 2250 bước làm anten quay $90^\circ$ thay vì $45^\circ$. | Chuẩn hóa tỉ số bước: $1600 \times 5.625 = 9000$ bước cho $360^\circ$ $\rightarrow$ **$25.0$ bước/độ**. |
| **3** | Cổng cảm biến bị chéo nhau | Cảm biến J3 và J4 bị ngược giữa Pan và Tilt. | Đã đảo lại trực tiếp trong code: Jack J4 (GPIO 18, 19) đọc Pan; Jack J3 (GPIO 21, 22) đọc Tilt. |
| **4** | Lỗi I2C timeout (Error 263) & motor giật cộc cộc | Code cũ gọi đọc I2C bên trong vòng lặp phát xung làm trễ 2-3ms mỗi xung. | Tuyệt đối không đọc I2C trong khi phát xung. Dùng thuật toán Bresenham gia tốc dốc mềm hình thang chuyên dụng. |

---

## 3. Cấu Hình Phần Cứng Chính Thức Đã Chuẩn Hóa

### 3.1. Phân Bổ Nguồn Điện (Tối giản 100%)
* **Nguồn Logic:** Cáp USB 5V cắm từ máy tính vào cổng nạp ESP32.
* **Nguồn 3.3V Logic Bus:** Chân `3V3` của ESP32 nuôi:
  - Chân `VIO` của cả 2 driver TMC2209 ($\sim 6\text{mA}$).
  - Chân `VCC` của cả 2 cảm biến AS5600 ($\sim 20\text{mA}$).
  - Tổng dòng chỉ $\approx 26\text{mA}$, IC nguồn ESP32 mát rượi, cực kỳ ổn định.
* **Nguồn Động Cơ:** Nguồn 20V DC từ sạc Type-C PD cấp thẳng vào chân `VM` và `GND` của 2 driver TMC2209 (kèm tụ lọc 1000µF 35V chống sốc áp).
* **Mass Chung (Common GND):** GND nguồn 20V, GND ESP32, GND TMC2209 và GND AS5600 hàn thông nhau 100%.

### 3.2. Sơ Đồ Chân Cắm ESP32 DevKit V1
* **Trục Pan (Azimuth - Motor 48mm):**
  - `STEP`: GPIO 25
  - `DIR`: GPIO 26
  - `EN`: GPIO 27 (Active LOW)
  - `Chân PDN, MS1, MS2`: Để trống (Không cắm dây)
* **Trục Tilt (Elevation - Motor 23mm Pancake):**
  - `STEP`: GPIO 32
  - `DIR`: GPIO 33
  - `EN`: GPIO 14 (Active LOW)
  - `Chân PDN, MS1, MS2`: Để trống (Không cắm dây)
* **Cảm biến AS5600 Pan (Gắn đuôi motor Pan):**
  - Jack J4 (I2C Bus 1): `SDA` = GPIO 18, `SCL` = GPIO 19, `VCC` = 3.3V, `GND` = Mass.
* **Cảm biến AS5600 Tilt (Gắn đuôi motor Tilt):**
  - Jack J3 (I2C Bus 0): `SDA` = GPIO 21, `SCL` = GPIO 22, `VCC` = 3.3V, `GND` = Mass.

### 3.3. Quy Chuẩn 4 Cổng Jack 4-Pin Trên Vách Hộp (Aviation GX12/GX16)
- **Jack J1 (Motor Pan 48mm):** Pin 1=Cuộn A+ (Đen), Pin 2=Cuộn A- (Lá), Pin 3=Cuộn B+ (Đỏ), Pin 4=Cuộn B- (Lam).
- **Jack J2 (Motor Tilt 23mm):** Pin 1=Cuộn A+ (Đen), Pin 2=Cuộn A- (Lá), Pin 3=Cuộn B+ (Đỏ), Pin 4=Cuộn B- (Lam).
- **Jack J3 (AS5600 Tilt):** Pin 1=VCC (3.3V), Pin 2=GND (Mass), Pin 3=SCL (GPIO 22), Pin 4=SDA (GPIO 21).
- **Jack J4 (AS5600 Pan):** Pin 1=VCC (3.3V), Pin 2=GND (Mass), Pin 3=SCL (GPIO 19), Pin 4=SDA (GPIO 18).
*(File bản vẽ đồ họa chi tiết: `so_do_toan_bo_mach_4jack.html`)*

---

## 4. Dữ Liệu Thực Nghiệm & Kết Quả Đo Đạc

### 4.1. Kiểm tra tỉ số truyền thực nghiệm (Lệnh M1 250 bước):
* **Số bước phát:** 250 xung vi bước 1/8.
* **Góc quay lý thuyết của motor:** $\frac{250}{1600} \times 360^\circ = \mathbf{56.25^\circ}$.
* **Góc đo thực tế từ cảm biến:** **$-56.34^\circ$**.
* **Sai số:** **$0.09^\circ$ (chưa tới 0.1°)** $\rightarrow$ Độ chính xác đạt $99.84\%$.

### 4.2. Kiểm tra độ lặp lại (Repeatability Test - Chu kỳ 3 lần):
* Chạy `90 90` lần 1: Encoder Pan = `215.2°` | Tilt = `311.1°`
* Về `0 0` lần 1: Encoder Pan = `4.7°` | Tilt = `96.8°`
* Chạy `90 90` lần 2: Encoder Pan = `215.2°` | Tilt = `311.1°` (Trùng khớp 100%)
* Về `0 0` lần 2: Encoder Pan = `4.7°` | Tilt = `96.8°` (Trùng khớp 100%)
* Chạy `90 90` lần 3: Encoder Pan = `215.2°` | Tilt = `311.1°` (Trùng khớp 100%)
* **Kết luận:** Hệ thống đạt mức trượt bước bằng 0 (**Zero Step Loss**).

### 4.3. Kiểm tra tốc độ di chuyển:
* Góc quay $90^\circ$: Hoàn thành trong **$5.33$ giây** ($\sim 18^\circ/\text{s}$).
* Góc quay $45^\circ$: Hoàn thành trong **$2.86$ giây**.
* Góc quay $180^\circ$: Hoàn thành trong **$10.28$ giây**.
* Chuyển động lướt dốc mềm, không rung lắc cơ khí.

---

## 5. Hướng Dẫn Sử Dụng & Bảng Lệnh Serial

Tốc độ baud: **115200**.

| Lệnh | Cú Pháp | Ví Dụ | Chức Năng |
| :--- | :--- | :--- | :--- |
| **GOTO** | `<pan> <tilt>` | `90 45` | Quay đồng thời 2 trục đến góc Pan 90°, Tilt 45° |
| **PAN** | `PAN <góc>` | `PAN 180` | Chỉ quay trục Pan |
| **TILT** | `TILT <góc>` | `TILT 60` | Chỉ quay trục Tilt |
| **ZERO** | `ZERO` hoặc `0` | `ZERO` | Ghim vị trí thực tế hiện tại thành mốc $0.00^\circ$ |
| **POS** | `POS` | `POS` | Đọc vị trí góc ăng-ten và góc thô của encoder |
| **SCAN** | `SCAN` | `SCAN` | Tự động chạy quét 4 điểm mẫu tốc độ cao |
| **M1** | `M1 <bước>` | `M1 250` | Quay lẻ motor Pan một số bước (số âm quay ngược) |
| **M2** | `M2 <bước>` | `M2 250` | Quay lẻ motor Tilt một số bước |

---

## 6. Kết Luận & Bàn Giao

Hệ thống đã giải quyết dứt điểm toàn bộ các trục trặc về UART, sai lệch tỉ số bước, rung giật và ngắt nguồn. Toàn bộ thiết kế phần cứng và mã nguồn v3.0 đạt độ hoàn thiện cao, vận hành bền bỉ và sẵn sàng cho các nhiệm vụ đo kiểm ăng-ten thực tế.
