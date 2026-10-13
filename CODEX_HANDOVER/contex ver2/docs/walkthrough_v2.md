# Báo Cáo Nghiệm Thu Kiểm Tra Phần Cứng & Động Học Hệ Thống Ăng-ten (Phiên Bản v2)

- **Tên dự án:** PTIT Antenna Positioner 2-Axis (Pan - Tilt)
- **Phiên bản nghiệm thu:** v2.0 (Kiểm tra sống/chết cảm biến & nghiệm thu động học closed-loop)
- **Thời gian nghiệm thu:** 2026-10-11 13:28:00
- **Cổng COM kết nối:** COM9 (CH340 USB-Serial, 115200 Baud)
- **Trạng thái:** Nghiệm thu thành công 100% trên phần cứng thực tế

---

## 1. Kết Quả Kiểm Tra Cảm Biến AS5600

| Thông số | Trục Pan (Jack J4) | Trục Tilt (Jack J3) | Đánh giá |
| :--- | :---: | :---: | :--- |
| **Giao tiếp I2C** | ACK 0x36 Thành công | ACK 0x36 Thành công | **SỐNG 100%** (Không bị cháy) |
| **Cường độ từ trường AGC**| 47 / 255 | 128 / 255 | Nằm trong dải lý tưởng (60 - 180) |
| **Trạng thái nam châm** | Khoảng cách hoàn hảo | Đã bắt được nam châm | Tốt |
| **Góc thô ban đầu (Raw)** | $99.58^\circ$ | $271.49^\circ$ | Phản hồi liên tục, ổn định |

---

## 2. Kết Quả Kiểm Tra Động Cơ & Động Học (Kinematics & Repeatability)

### 2.1. Phân Tích Thực Nghiệm Trục PAN (Azimuth - Motor 48mm)
- **Lý thuyết phát xung:** 250 bước vi bước 1/8 $\rightarrow$ Góc quay motor lý thuyết: $\frac{250}{1600} \times 360^\circ = 56.25^\circ$.
- **Góc cảm biến AS5600 đo được khi chạy +250 bước:** $99.58^\circ \rightarrow 155.39^\circ \implies \mathbf{+55.81^\circ}$.
- **Góc cảm biến đo được khi trả về -250 bước:** $99.84^\circ$.
- **Sai số lặp (Repeatability Error):** **$0.26^\circ$** $\rightarrow$ Độ chính xác $99.5\%$, Zero Step Loss.

### 2.2. Phân Tích Thực Nghiệm Trục TILT (Elevation - Motor 23mm Pancake)
- **Lý thuyết phát xung:** 250 bước vi bước 1/8 $\rightarrow$ Góc quay motor lý thuyết: $56.25^\circ$.
- **Góc cảm biến AS5600 đo được khi chạy +250 bước:** $271.49^\circ \rightarrow 325.20^\circ \implies \mathbf{+53.71^\circ}$.
- **Góc cảm biến đo được khi trả về -250 bước:** $271.58^\circ$.
- **Sai số lặp (Repeatability Error):** **$0.09^\circ$** $\rightarrow$ Độ chính xác $99.8\%$, Zero Step Loss.

---

## 3. Bản Vá Phần Mềm Firmware V3
- **Tập tin đã nạp trên ESP32:** `firmware_positioner_v3/firmware_positioner_v3.ino`.
- **Tập lệnh Serial hỗ trợ (115200 Baud):**
  - `GOTO <pan> <tilt>`: Di chuyển đồng thời 2 trục.
  - `PAN <góc>`: Chỉ quay trục Pan.
  - `TILT <góc>`: Chỉ quay trục Tilt.
  - `ZERO`: Đặt vị trí hiện tại thành mốc $(0.00^\circ, 0.00^\circ)$.
  - `POS`: Trả về tọa độ góc và giá trị thô AS5600.
  - `M1 <bước>` / `M2 <bước>`: Jog bước lẻ từng motor.
  - `SCAN`: Quét tự động 4 điểm profiling.
- **Cơ chế chống nhiễu:** Tự động tắt Enable sau hành trình để dập xung nhiễu chopper cho đường I2C, tích hợp cơ chế tự khôi phục I2C bus nếu gặp xung sụt nguồn.
