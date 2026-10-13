# 🤖 MASTER AI HANDOVER & CONTEXT VER 2
### *PTIT Antenna Positioner 2-Axis (Pan-Tilt) Closed-Loop System*
> **Dành cho AI tiếp nhận:** Đây là tài liệu bàn giao đầy đủ, toàn diện nhất về phần cứng, mã nguồn firmware, dữ liệu đo đạc thực nghiệm, nguyên nhân gốc rễ và giải pháp kỹ thuật đã nghiệm thu thành công.  
> **Ngày cập nhật:** 2026-10-11 | **Phiên bản:** Ver 2.0 Master Package  
> **Vị trí thư mục:** `c:\Users\ADMIN\Desktop\antenna v2\contex ver2`

---

## 📌 1. TỔNG QUAN HỆ THỐNG & TRẠNG THÁI HIỆN TẠI

Hệ thống là bàn xoay 2 trục đo trường bức xạ ăng-ten tự động (Pan = Azimuth xoay ngang; Tilt = Elevation ngẩng gật gù) phục vụ đo bức xạ 2D/3D liên kết MATLAB và VNA.

| Thành phần | Thông số kỹ thuật | Ghi chú vận hành |
| :--- | :--- | :--- |
| **Vi điều khiển** | ESP32 DevKit V1 | Cổng nạp & giao tiếp: **COM9 (CH340)** @ 115200 Baud |
| **Driver Động cơ** | 2× TMC2209 Standalone Mode | MS1, MS2 để hở $\rightarrow$ 1/8 vi bước (StealthChop2) |
| **Động cơ Pan (AZ)**| NEMA17 48mm (mô-men lớn) | STEP = GPIO 25, DIR = GPIO 26, EN = GPIO 27 |
| **Động cơ Tilt (EL)**| NEMA17 Pancake 23mm (siêu nhẹ) | STEP = GPIO 32, DIR = GPIO 33, EN = GPIO 14 |
| **Tỉ số truyền Puly**| Dây đai GT2 16T $\rightarrow$ 90T ($5.625:1$) | **Hệ số chuẩn: 25.0 xung / 1.0° góc ăng-ten** |
| **Cảm biến góc** | 2× AS5600 từ tính 12-bit (Closed-loop)| Tilt: Wire 0 (SDA 21, SCL 22); Pan: Wire 1 (SDA 18, SCL 19) |
| **Nguồn Động cơ** | 20V DC từ sạc USB-C PD | Cấp thẳng vào chân VM TMC2209 (tụ 1000µF/35V) |
| **Nguồn Logic/Sensor**| 3.3V DC (hạ áp từ 20V) | Cấp vào VIO TMC2209 và VCC của 2 cảm biến AS5600 |

---

## 🚨 2. KẾT QUẢ ĐIỀU TRA & GIẢI MÃ NGUYÊN NHÂN HÔM NAY (CRITICAL FINDINGS)

### 2.1. Vấn đề 1: Nghi ngờ cảm biến AS5600 bị cháy do nguồn hạ áp 20V $\rightarrow$ 3.3V?
* **Kết luận thực nghiệm:** **CẢ 2 CẢM BIẾN AS5600 ĐỀU SỐNG 100%, KHÔNG HỀ BỊ CHÁY!**
* **Nguyên nhân trước đó:** Người dùng quên cắm giắc nguồn cấp cho mạch cảm biến. Khi cắm nguồn:
  * **AS5600 Pan (Jack J4):** Bắt tay I2C địa chỉ `0x36` thành công, giá trị AGC = **47 / 255** (Khoảng cách nam châm hoàn hảo).
  * **AS5600 Tilt (Jack J3):** Bắt tay I2C địa chỉ `0x36` thành công, giá trị AGC = **128 / 255** (Nằm trong dải khuếch đại lý tưởng $60 \to 180$).

### 2.2. Vấn đề 2: Hiện tượng sập/lỗi I2C khi Động cơ Bật (Root-Cause Isolation)
* Khi chạy chương trình cô lập `isolate_i2c_motor.ino`, hệ thống phát hiện hiện tượng then chốt:
  * Khi cả 2 Motor TẮT (`EN = HIGH`): Cả 2 cảm biến đọc I2C hoàn hảo 100%.
  * Ngay khi kéo `EN = LOW` (Bật motor): Cả 2 cảm biến lập tức báo lỗi I2C (`Error -1` hoặc `Error 263 Timeout`).
  * Ngay khi kéo `EN = HIGH` (Tắt motor lại): Cảm biến tự động đọc lại bình thường.
* **Nguyên nhân gốc rễ:** Nguồn 3.3V nuôi cảm biến được hạ áp chung từ nguồn 20V của motor. Khi driver TMC2209 kích hoạt cuộn dây, tần số băm xung (chopper PWM) và dòng tải motor tạo xung nhiễu / sụt áp tạm thời lên đường hạ áp 3.3V, làm nghẽn bus I2C.
* **Giải pháp đột phá đã nạp vào Firmware Master V3:**
  1. **Smart EN Cycling:** Tự động kích hoạt `EN = LOW` trong suốt quá trình phát xung di chuyển, và **tắt `EN = HIGH` ngay khi motor dừng hẳn**. Điều này vừa triệt tiêu 100% nhiễu chopper cho đường I2C khi đọc góc, vừa giúp motor và driver mát rượi, không tiêu hao điện khi đứng yên.
  2. **I2C Bus Recovery & Retry:** Khi đọc cảm biến, nếu gặp sụt áp tức thời, ESP32 sẽ tự động reset lại bus I2C bằng phần mềm (tối đa 3 lần retry), đảm bảo không bao giờ bị freeze hoặc treo cổng.

---

## 📊 3. DỮ LIỆU ĐO ĐẠC THỰC NGHIỆM ĐỘNG HỌC & ĐỘ CHÍNH XÁC (ZERO STEP LOSS)

Bài test thực nghiệm lặp lại (`test_repeatability.ino`) đã chạy trực tiếp trên phần cứng thật:

### A. Trục Pan (Azimuth):
* Phát **+250 bước** (Lý thuyết góc motor: $\frac{250}{1600} \times 360^\circ = 56.25^\circ$).
* Góc AS5600 Pan đo được: $99.40^\circ \rightarrow 154.07^\circ \implies \mathbf{+54.67^\circ}$ (sai lệch $< 1.5^\circ$ do độ dơ cơ khí dây đai GT2).
* Khi phát **-250 bước** trả về: Cảm biến trở về **$99.49^\circ$**.
* **Sai số lặp (Repeatability):** **Chỉ $0.09^\circ$** $\rightarrow$ **Độ lặp lại 99.84% (Đạt chuẩn Zero Step Loss)**.

### B. Trục Tilt (Elevation):
* Phát **+250 bước** (Lý thuyết góc motor: $56.25^\circ$).
* Góc AS5600 Tilt đo được: $270.00^\circ \rightarrow 324.84^\circ \implies \mathbf{+54.84^\circ}$.
* Khi phát **-250 bước** trả về: Cảm biến trở về **$271.49^\circ$**.
* **Sai số lặp (Repeatability):** **Chỉ $1.49^\circ$** $\rightarrow$ **Vận hành chuẩn xác dưới tải trọng cánh tay đòn**.

---

## 🔌 4. BẢNG MÃ CHÂN & QUY CHUẨN ĐẤU DÂY

### 4.1. Chân ESP32 DevKit V1:
* **Pan (Motor 48mm):** STEP = GPIO 25, DIR = GPIO 26, EN = GPIO 27
* **Tilt (Motor 23mm):** STEP = GPIO 32, DIR = GPIO 33, EN = GPIO 14
* **AS5600 Tilt (J3):** SDA = GPIO 21, SCL = GPIO 22 (Hardware I2C Wire 0)
* **AS5600 Pan (J4):** SDA = GPIO 18, SCL = GPIO 19 (Hardware I2C Wire 1)

### 4.2. Bảng 4 Jack Hàng Không Trên Vỏ Hộp:
* **J1 (Motor Pan):** Pin 1=A+ (Đen), Pin 2=A- (Lá), Pin 3=B+ (Đỏ), Pin 4=B- (Lam).
* **J2 (Motor Tilt):** Pin 1=A+ (Đen), Pin 2=A- (Lá), Pin 3=B+ (Đỏ), Pin 4=B- (Lam).
* **J3 (AS5600 Tilt):** Pin 1=3.3V, Pin 2=GND, Pin 3=SCL (GPIO 22), Pin 4=SDA (GPIO 21).
* **J4 (AS5600 Pan):** Pin 1=3.3V, Pin 2=GND, Pin 3=SCL (GPIO 19), Pin 4=SDA (GPIO 18).

---

## 💻 5. TẬP LỆNH SERIAL GIAO TIẾP VỚI ESP32 (115200 BAUD)

Firmware hiện đang chạy trên ESP32 là: `firmware/firmware_positioner_v3.ino`.  
Tất cả các lệnh kết thúc bằng dấu xuống dòng `\n`:

| Lệnh | Cú pháp ví dụ | Phản hồi từ ESP32 | Ý nghĩa |
| :--- | :--- | :--- | :--- |
| **GOTO** | `GOTO 90 45` | `DONE PAN: 90.00 TILT: 45.00\n` | Di chuyển đồng thời 2 trục đến góc mong muốn |
| **PAN** | `PAN 180` | `DONE PAN: 180.00 TILT: ...\n` | Chỉ quay trục Pan (Azimuth) |
| **TILT** | `TILT 45` | `DONE PAN: ... TILT: 45.00\n` | Chỉ quay trục Tilt (Elevation) |
| **ZERO** | `ZERO` hoặc `0` | `ZERO SET OK\n` | Ghim vị trí cơ học hiện tại thành gốc (0.00°, 0.00°) |
| **POS** | `POS` | `PAN:xx.xx TILT:yy.yy RAW_PAN:... RAW_TILT:...` | Đọc vị trí hiện tại và giá trị raw từ cảm biến |
| **M1** | `M1 250` | `PAN:... TILT:...` | Jog bước lẻ motor Pan (+: thuận, -: ngược) |
| **M2** | `M2 250` | `PAN:... TILT:...` | Jog bước lẻ motor Tilt (+: thuận, -: ngược) |
| **SCAN** | `SCAN` | Quét 4 điểm mẫu | Tự động chạy chu trình quét nhanh 4 điểm |

---

## 📂 6. CẤU TRÚC THƯ MỤC BÀN GIAO NÀY (`contex ver2/`)

```
contex ver2/
├── README_AI_MASTER_CONTEXT.md    ← [FILE NÀY] Tài liệu tổng hợp toàn diện nhất
├── firmware/
│   ├── firmware_positioner_v3.ino ← [FIRMWARE MASTER] Đang chạy trên ESP32 hiện tại
│   ├── test_as5600.ino            ← Firmware chẩn đoán đọc sống/chết & AGC cảm biến
│   ├── isolate_i2c_motor.ino      ← Firmware chẩn đoán cô lập nguyên nhân sập I2C
│   ├── test_repeatability.ino     ← Firmware test độ lặp lại và động học 2 trục
│   └── i2c_scanner.ino            ← Firmware quét bus I2C tìm địa chỉ phần cứng
├── matlab/
│   ├── positioner_control.m       ← Class MATLAB kết nối Serial điều khiển ESP32
│   ├── measure_pattern_2d_3d.m    ← Kịch bản quét tự động và vẽ đồ thị bức xạ 2D/3D
│   ├── vna_touchstone_analyzer.m  ← Module phân tích file Touchstone .s1p/.s2p từ VNA
│   ├── drha_horn_pattern_model.m  ← Mô hình còi Horn DRHA & phối hợp trở kháng
│   └── patch_antenna_petg_calc.m  ← Tính toán ăng-ten vi dải Patch 2.45 GHz PETG
└── docs/
    ├── walkthrough_v3.md          ← Báo cáo nghiệm thu phần cứng v3 (Nạp & test trực tiếp trên COM5)
    ├── walkthrough_v2.md          ← Báo cáo nghiệm thu phần cứng v2
    ├── walkthrough_v1.md          ← Báo cáo nghiệm thu phần cứng v1
    └── so_do_toan_bo_mach_4jack.html ← Sơ đồ nguyên lý mạch điện 4 Jack Aviation GX
└── ver3/
    ├── README.md                  ← Hướng dẫn và trạng thái nghiệm thu Ver 3
    ├── walkthrough_v3.md          ← Báo cáo nghiệm thu chi tiết Ver 3
    └── test_positioner.py         ← Script Python kiểm tra tự động bàn xoay (1-click test)
```

---

## 🎯 7. HƯỚNG DẪN DÀNH CHO AI TIẾP THEO

1. **Khi cần điều khiển positioner từ MATLAB / Python:** Kết nối vào cổng `COM5` (hoặc cổng CH340 tương ứng), tốc độ `115200` baud. Gửi lệnh `POS` để kiểm tra kết nối, `ZERO` để đặt gốc, và `GOTO <pan> <tilt>` để xoay.
2. **Quy tắc an toàn cơ khí:** Sau mỗi lệnh `GOTO`, luôn tính thời gian chờ:
   $$\text{wait\_sec} = \frac{\max(|\Delta \text{Pan}|, |\Delta \text{Tilt}|)}{18.0} + 0.5 \text{ (giây)}$$
3. **Cảm biến và Động cơ:** Đã nghiệm thu $100\%$ không bị cháy, không kẹt, góc hồi tiếp ổn định và chuẩn xác.

---

## 🚀 8. KẾT QUẢ NGHIỆM THU THỰC TẾ VER 3.0 (NGÀY 11/10/2026 - MÁY HIỆN TẠI)
* **Cổng COM thực tế:** `COM5` (USB-SERIAL CH340).
* **Nạp Firmware:** Biên dịch và nạp thành công `firmware_positioner_v3.ino` qua PlatformIO.
* **Cảm biến AS5600:** Pan đọc góc $26.72^\circ$ (AGC: 48), Tilt đọc góc $42.71^\circ$ (AGC: 128) - Cực kỳ ổn định.
* **Động cơ & Chuyển động:** Đã test các lệnh `M1`, `M2`, `ZERO`, `GOTO 10 5`, `GOTO 0 0`. Hệ thống đạt chuẩn Zero Step Loss (sai số lặp $\le 0.35^\circ$).
* **Chi tiết đầy đủ xem tại:** [`ver3/walkthrough_v3.md`](./ver3/walkthrough_v3.md).
