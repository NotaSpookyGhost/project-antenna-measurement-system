# 🤖 PTIT ANTENNA POSITIONER — BỘ BÀN GIAO CHO OPENAI CODEX
### *Hệ thống đo bức xạ ăng-ten 2D/3D tự động: ESP32 + MATLAB*
**Ngày nghiệm thu cuối: 2026-10-11 | Phiên bản: v4.0 FINAL HANDOVER**

---

> **🚨 CODEX: ĐỌC FILE NÀY TRƯỚC TIÊN TRƯỚC KHI LÀM BẤT CỨ ĐIỀU GÌ**
> Đây là tài liệu duy nhất cần nắm toàn bộ để code MATLAB điều khiển ESP32.

---

## 📋 DANH MỤC FOLDER NÀY

```
CODEX_HANDOVER/
├── AGENTS.md                    ← [ĐÂY] Tài liệu tổng hợp cho Codex (đọc đầu tiên)
├── firmware/
│   └── test_as5600.ino          ← Firmware chẩn đoán cảm biến AS5600 (dùng khi debug)
└── matlab/
    ├── positioner_control.m     ← [QUAN TRỌNG] Lớp điều khiển ESP32 qua Serial
    ├── vna_touchstone_analyzer.m← Phân tích file .s1p/.s2p từ NanoVNA / Anritsu
    └── measure_pattern_2d_3d.m  ← Quét tự động + vẽ đồ thị bức xạ 2D/3D
```

---

## ⚡ PHẦN 1: SƠ ĐỒ CẤU HÌNH CHÂN CẮNG ESP32 & NỐI DÂY

### 1.1. Sơ Đồ Chân ESP32 DevKit V1 (Đầy Đủ)

```
                    ╔═══════════════════════════════════════╗
                    ║        ESP32 DevKit V1 Pinout          ║
                    ╠═════════════╦═════════════════════════╣
     NGUỒN          ║   EN ─────  ║  (không dùng)           ║
     ─────          ║  3V3 ─[3.3V Bus]─→ VIO TMC2209(×2)   ║
     USB 5V → 3V3   ║              └──→ VCC AS5600(×2)      ║
     (máy tính)     ║  GND ─[COMMON GND]─ Tất cả GND       ║
                    ╠═════════════╬═════════════════════════╣
     PAN AXIS       ║  GPIO 25 ──── STEP_PAN  → TMC2209_Pan ║ STEP
     (Motor 48mm)   ║  GPIO 26 ──── DIR_PAN   → TMC2209_Pan ║ DIR
                    ║  GPIO 27 ──── EN_PAN    → TMC2209_Pan ║ ENABLE (Active LOW)
                    ╠═════════════╬═════════════════════════╣
     TILT AXIS      ║  GPIO 32 ──── STEP_TILT → TMC2209_Til ║ STEP
     (Motor 23mm)   ║  GPIO 33 ──── DIR_TILT  → TMC2209_Til ║ DIR
                    ║  GPIO 14 ──── EN_TILT   → TMC2209_Til ║ ENABLE (Active LOW)
                    ╠═════════════╬═════════════════════════╣
     I2C BUS 0      ║  GPIO 21 ──── SDA_TILT  → AS5600 Tilt ║ J3 Jack Hàng Không
     (Encoder Tilt) ║  GPIO 22 ──── SCL_TILT  → AS5600 Tilt ║ J3 Jack Hàng Không
                    ╠═════════════╬═════════════════════════╣
     I2C BUS 1      ║  GPIO 18 ──── SDA_PAN   → AS5600 Pan  ║ J4 Jack Hàng Không
     (Encoder Pan)  ║  GPIO 19 ──── SCL_PAN   → AS5600 Pan  ║ J4 Jack Hàng Không
                    ╠═════════════╬═════════════════════════╣
     USB SERIAL     ║  TX0 ──────── USB → PC (115200 baud)   ║ Lệnh điều khiển
     (Lệnh MATLAB)  ║  RX0 ──────── USB → PC                ║ Phản hồi vị trí
                    ╚═════════════╩═════════════════════════╝
```

### 1.2. Sơ Đồ Nối Dây Tổng Thể (Block Diagram)

```
  ┌─────────────────────────────────────────────────────────────────────┐
  │                    HỆ THỐNG POSITIONER V3.0                         │
  │                                                                     │
  │  [PC / MATLAB]                                                      │
  │      │                                                              │
  │      │ USB Cable (5V + Serial 115200)                               │
  │      ▼                                                              │
  │  ╔══════════════╗    3.3V ──────────────────────────────────┐       │
  │  ║  ESP32       ║    │                                       │       │
  │  ║  DevKit V1   ║    ├──→ VIO [TMC2209 Pan]                 │       │
  │  ║              ║    ├──→ VIO [TMC2209 Tilt]                │       │
  │  ║ G25→STEP_PAN ║    ├──→ VCC [AS5600 Tilt - J3]           │       │
  │  ║ G26→DIR_PAN  ║    └──→ VCC [AS5600 Pan  - J4]           │       │
  │  ║ G27→EN_PAN   ║                                            │       │
  │  ║ G32→STEP_TLT ║    I2C Bus 0 (Wire 0)                     │       │
  │  ║ G33→DIR_TILT ║    G21(SDA), G22(SCL) ──→ [AS5600 TILT] ─┤ J3   │
  │  ║ G14→EN_TILT  ║                                            │       │
  │  ║ G21→SDA_TILT ║    I2C Bus 1 (Wire 1)                     │       │
  │  ║ G22→SCL_TILT ║    G18(SDA), G19(SCL) ──→ [AS5600 PAN]  ─┘ J4   │
  │  ║ G18→SDA_PAN  ║                                                   │
  │  ║ G19→SCL_PAN  ║                                                   │
  │  ╚══════════════╝                                                   │
  │         │                         │                                 │
  │    ┌────┴────┐              ┌─────┴─────┐                           │
  │    │TMC2209  │              │ TMC2209   │                           │
  │    │  PAN    │              │  TILT     │                           │
  │    │ (48mm)  │              │ (23mm)    │                           │
  │    └────┬────┘              └─────┬─────┘                           │
  │    VM ──┤                   VM ───┤                                 │
  │    GND ─┤   [20V DC USB-C PD]    │                                 │
  │         └──────── 20V ───────────┘                                 │
  │                    │                                                │
  │               [Tụ 1000µF/35V dập xung]                             │
  │                                                                     │
  │    ┌────────────────┐        ┌────────────────┐                     │
  │    │ NEMA17 48mm    │        │ NEMA17 Pancake │                     │
  │    │ (Motor PAN)    │        │ 23mm (TILT)    │                     │
  │    │  GT2 16T ──────┤        │  GT2 16T ──────┤                     │
  │    │  → Puly 90T    │        │  → Puly 90T    │                     │
  │    │  Trục Azimuth  │        │  Trục Elevation│                     │
  │    └────────────────┘        └────────────────┘                     │
  └─────────────────────────────────────────────────────────────────────┘
```

### 1.3. Bảng 4 Jack Hàng Không GX12 / GX16 Trên Vỏ Hộp

```
  ┌─────────────────────────────────────────────────────────────────────┐
  │  J1: MOTOR PAN (48mm)              J2: MOTOR TILT (23mm)            │
  │  ┌───┬───┬───┬───┐                 ┌───┬───┬───┬───┐               │
  │  │ 1 │ 2 │ 3 │ 4 │                 │ 1 │ 2 │ 3 │ 4 │               │
  │  └───┴───┴───┴───┘                 └───┴───┴───┴───┘               │
  │    A+ (Đen)                          A+ (Đen)                       │
  │        A- (Xanh lá)                      A- (Xanh lá)              │
  │            B+ (Đỏ)                           B+ (Đỏ)               │
  │                B- (Xanh lam)                     B- (Xanh lam)     │
  │  Cắm vào 1A, 1B, 2A, 2B            Cắm vào 1A, 1B, 2A, 2B        │
  │  của TMC2209 PAN                    của TMC2209 TILT                │
  │                                                                     │
  │  J3: SENSOR AS5600 TILT            J4: SENSOR AS5600 PAN           │
  │  ┌───┬───┬───┬───┐                 ┌───┬───┬───┬───┐               │
  │  │ 1 │ 2 │ 3 │ 4 │                 │ 1 │ 2 │ 3 │ 4 │               │
  │  └───┴───┴───┴───┘                 └───┴───┴───┴───┘               │
  │    3.3V                              3.3V                           │
  │        GND                               GND                       │
  │            SCL → GPIO 22                     SCL → GPIO 19         │
  │                SDA → GPIO 21                     SDA → GPIO 18     │
  │  (DIR chân trên module hàn ─GND)    (DIR chân trên module hàn ─GND)│
  └─────────────────────────────────────────────────────────────────────┘
```

### 1.4. Cấu Hình Driver TMC2209 — Standalone Mode

```
  ╔═══════════════════════════════════════════════════════════════╗
  ║  TMC2209 STANDALONE MODE (KHÔNG dùng UART, KHÔNG cắm PDN)    ║
  ╠═══════════════════════════════════════════════════════════════╣
  ║  Chân PDN_UART  → ĐỂ HỞ (không nối gì)                       ║
  ║  Chân MS1       → ĐỂ HỞ (floating)  ┐ → Vi bước: 1/8        ║
  ║  Chân MS2       → ĐỂ HỞ (floating)  ┘   (StealthChop2)       ║
  ║  Chân VM        → 20V DC từ sạc USB-C PD                      ║
  ║  Chân VIO       → 3.3V từ chân 3V3 của ESP32                  ║
  ║  Chân GND       → Common Ground (nối chung tất cả)            ║
  ║  Chân STEP      → GPIO từ ESP32                               ║
  ║  Chân DIR       → GPIO từ ESP32                               ║
  ║  Chân EN        → GPIO từ ESP32 (Active LOW: 0=bật motor)     ║
  ║  Chân 1A,1B,2A,2B → Cuộn dây motor NEMA17 qua Jack cắm       ║
  ╠═══════════════════════════════════════════════════════════════╣
  ║  TÍNH TOÁN ĐỘNG HỌC:                                          ║
  ║  Góc cơ bản motor: 1.8°/bước → 200 bước/vòng                 ║
  ║  Vi bước 1/8:      200 × 8 = 1600 xung/vòng motor             ║
  ║  Tỉ số puly GT2:   16 răng → 90 răng = 5.625 : 1             ║
  ║  TỔNG:             1600 × 5.625 = 9000 xung/360° ăng-ten     ║
  ║  HỆ SỐ CHUẨN:      ➡ 25.0 xung / 1.0° GÓC ĂNG-TEN           ║
  ╚═══════════════════════════════════════════════════════════════╝
```

---

## 📡 PHẦN 2: GIAO THỨC SERIAL GIỮA MATLAB VÀ ESP32

### 2.1. Bảng Tập Lệnh Đầy Đủ (Serial 115200 Baud, Dấu kết thúc '\n')

```
  ┌─────────────────────────────────────────────────────────────────────┐
  │  LỆNH MATLAB → ESP32 (MATLAB gửi, ESP32 thực hiện)                  │
  ├────────────────────────┬───────────────────────────────────────────┤
  │ Cú pháp lệnh           │ Ý nghĩa & Ví dụ                           │
  ├────────────────────────┼───────────────────────────────────────────┤
  │ GOTO <pan> <tilt>      │ Xoay đồng thời 2 trục về góc mong muốn   │
  │                        │ Ví dụ: "GOTO 90 45" → Pan=90°, Tilt=45°  │
  │ PAN <angle>            │ Chỉ xoay trục Pan (Azimuth)               │
  │                        │ Ví dụ: "PAN 180" → quay ngang 180°       │
  │ TILT <angle>           │ Chỉ xoay trục Tilt (Elevation)            │
  │                        │ Ví dụ: "TILT 30" → ngẩng 30°             │
  │ ZERO                   │ Ghim vị trí hiện tại thành (0°, 0°)       │
  │ POS                    │ Truy vấn vị trí → ESP32 trả về:           │
  │                        │ "PAN:90.00 TILT:45.00 RAW_PAN:1024       │
  │                        │  RAW_TILT:512"                            │
  │ SCAN                   │ Chạy hành trình thử 4 điểm tự động        │
  │                        │ (45°/20° → 90°/45° → 180°/60° → 0°/0°)  │
  │ M1 <steps>             │ Jog trực tiếp motor Pan: +dương=thuận     │
  │ M2 <steps>             │ Jog trực tiếp motor Tilt: +dương=thuận   │
  └────────────────────────┴───────────────────────────────────────────┘

  TỐC ĐỘ CHUYỂN ĐỘNG THAM KHẢO (để MATLAB tính thời gian chờ):
  ├── Tốc độ hành trình:    ~18.18 °/giây (2200 µs/xung)
  ├── Quay 45°:             ~2.8 giây
  ├── Quay 90°:             ~5.3 giây
  └── Quay 360°:            ~20 giây (hành trình đầy đủ Pan)
```

### 2.2. Cấu Trúc Phản Hồi Từ ESP32

```
  ESP32 phản hồi về MATLAB sau khi hoàn thành lệnh:
  → Sau lệnh GOTO/PAN/TILT:   "DONE PAN:90.00 TILT:45.00\n"
  → Sau lệnh POS:             "PAN:90.00 TILT:45.00 RAW_PAN:1024 RAW_TILT:512\n"
  → Sau lệnh ZERO:            "ZERO SET OK\n"
  → Lỗi I2C:                  "WARN: SENSOR TIMEOUT\n"
```

### 2.3. Quy Tắc An Toàn Khi Code MATLAB Gửi Lệnh Serial

```
  ⚠ QUAN TRỌNG CHO CODEX — CÁC QUY TẮC BẮT BUỘC:

  1. LUÔN thêm delay/pause() đủ dài sau mỗi lệnh GOTO để chờ motor dừng hẳn.
     Công thức tính thời gian chờ:
       wait_sec = max(abs(delta_pan), abs(delta_tilt)) / 18.0 + 0.5  % (giây)

  2. KHÔNG gửi lệnh mới khi motor còn đang chạy (không có interrupt báo "done").
     → Dùng pause(wait_sec) hoặc poll lệnh POS chờ vị trí ổn định.

  3. KHÔNG đọc cảm biến AS5600 trong khi phát xung (đây là quy tắc của firmware
     ESP32, MATLAB không cần làm gì nhưng cần hiểu: chỉ đọc POS sau khi đã đợi).

  4. Trước khi bắt đầu chu trình đo, luôn gửi lệnh ZERO để đặt điểm gốc.

  5. Sau khi đo xong, gửi "GOTO 0 0" để đưa ăng-ten về vị trí an toàn.
```

---

## 🔧 PHẦN 3: VẤN ĐỀ ĐANG CẦN KHẮC PHỤC

### Milestone 1: Khắc Phục Điểm Nghẽn Trục Tilt (Cảm Biến Đóng Băng 340.8°)

```
  TRIỆU CHỨNG:
  ─────────────
  Khi motor Tilt xoay vượt qua 45° → 60°, thanh ghi góc AS5600 Tilt đột ngột
  bị đóng băng ở giá trị 340.8° (tương ứng raw = ~3877/4096).
  Motor có thể vẫn tiếp tục xoay nhưng MATLAB sẽ đọc sai góc.

  3 GIẢ THUYẾT NGUYÊN NHÂN:
  ──────────────────────────
  [A] Cáp I2C Jack J3 bị căng khi đầu ngẩng cao → hở tiếp xúc SDA/SCL
      KIỂM TRA: Nạp firmware/test_as5600.ino, quan sát Serial Monitor
                khi tay lắc nhẹ bó dây Jack J3

  [B] Motor Pancake 23mm bị quá tải mô-men uốn lệch tâm
      (cáp RG400 nặng ghì lại + trọng tâm lệch)
      KIỂM TRA: Thử tháo cáp RG400 ra, xoay tay kiểm tra motor có
                đủ lực giữ góc không

  [C] Nam châm diametrical sau đuôi trục motor bị lỏng keo
      KIỂM TRA: Quan sát giá trị AGC trong test_as5600.ino có nhảy
                loạn khi motor xoay không

  CÁCH DÙNG FIRMWARE CHẨN ĐOÁN:
  ───────────────────────────────
  1. Nạp file firmware/test_as5600.ino vào ESP32 qua PlatformIO/Arduino IDE
  2. Mở Serial Monitor tại 115200 baud
  3. Quan sát các dòng:
     >> [TILT: 45.2°]  [PAN: 90.0°]    ← Bình thường
     >> [TILT: LỖI ĐỌC]  [PAN: 90.0°] ← Mất kết nối I2C
     >> [TILT: 340.8°]  [PAN: 90.0°]  ← Nam châm/cảm biến bị đóng băng
```

### Milestone 4: Quét Tự Động 2D/3D Radiation Pattern Qua MATLAB

```
  MỤC TIÊU:
  ──────────
  Chạy matlab/measure_pattern_2d_3d.m để điều khiển ESP32 qua Serial,
  quét bức xạ ăng-ten trên lưới góc raster, vẽ đồ thị Polar 2D và mặt
  cầu 3D tự động trong MATLAB.

  CÁCH CHẠY:
  ───────────
  % Quét 2D mặt phẳng Azimuth (H-plane):
  data = measure_pattern_2d_3d('COM3', '2D_PAN');

  % Quét 3D toàn không gian cầu:
  data = measure_pattern_2d_3d('COM3', '3D_SPHERICAL');

  % Chế độ giả lập (không cắm phần cứng):
  data = measure_pattern_2d_3d('', '2D_PAN');  % Tự chạy simulation
```

---

## 📐 PHẦN 4: TÓM TẮT SỐ LIỆU THAM CHIẾU QUAN TRỌNG

| Tham số | Giá trị | Ghi chú |
| :--- | :---: | :--- |
| Baudrate Serial | **115200** | Kết nối USB ESP32 ↔ MATLAB |
| Hệ số bước chuẩn | **25.0 xung/°** | TMC2209 1/8 vi bước, Puly 16:90 |
| Tốc độ xoay | **~18.18 °/s** | Tốc độ cruise 2200 µs/xung |
| Dải Pan (Azimuth) | **0° → 360°** | Toàn vòng tròn |
| Dải Tilt (Elevation) | **0° → 90°** | Từ nằm ngang đến thẳng đứng |
| Độ phân giải encoder | **0.0879°** (12-bit) | 4096 điểm/vòng AS5600 |
| Độ lặp lại (repeatability) | **100%** | Đã nghiệm thu v3.0 Zero Step Loss |
| Cổng I2C Tilt | Bus 0: SDA=21, SCL=22 | Jack J3 |
| Cổng I2C Pan | Bus 1: SDA=18, SCL=19 | Jack J4 |
| STEP/DIR/EN Pan | GPIO 25 / 26 / 27 | EN active LOW |
| STEP/DIR/EN Tilt | GPIO 32 / 33 / 14 | EN active LOW |
| Nguồn Motor | **20V DC** | Sạc USB-C PD qua trigger 20V |
| Nguồn Logic | **3.3V** từ chân ESP32 | Nuôi VIO TMC2209 và VCC AS5600 |

---

## 📁 PHẦN 5: PROMPT KÍCH HOẠT CHO CODEX (COPY/PASTE NGAY)

```text
=============================================================================
CONTEXT SYNC — PTIT ANTENNA POSITIONER (OPENAI CODEX)
Thư mục làm việc: [nơi bạn đặt folder này]
=============================================================================

Tôi có một hệ thống đo bức xạ ăng-ten gồm:
- Bàn xoay Pan-Tilt 2 trục (Azimuth + Elevation)
- Điều khiển: ESP32 DevKit V1 kết nối PC qua USB Serial 115200 baud
- Driver: 2× TMC2209 Standalone Mode (1/8 vi bước, MS1/MS2 để hở, PDN để hở)
- Encoder: 2× AS5600 từ tính 12-bit gắn đuôi motor NEMA17
- Tỉ số bước: 25.0 xung / 1° góc ăng-ten
- Tốc độ: ~18.18°/giây, cần đợi (delta_angle/18.0 + 0.5) giây sau mỗi lệnh GOTO

CHÂN ESP32:
  Pan:  STEP=GPIO25, DIR=GPIO26, EN=GPIO27 | Encoder I2C1: SDA=GPIO18, SCL=GPIO19
  Tilt: STEP=GPIO32, DIR=GPIO33, EN=GPIO14 | Encoder I2C0: SDA=GPIO21, SCL=GPIO22

TẬP LỆNH SERIAL (gửi qua MATLAB serialport, kết thúc bằng '\n'):
  "GOTO <pan> <tilt>" → Di chuyển 2 trục đồng thời
  "POS"               → Trả về "PAN:xx.xx TILT:yy.yy RAW_PAN:N RAW_TILT:M"
  "ZERO"              → Đặt vị trí hiện tại là gốc (0°, 0°)
  "SCAN"              → Chạy chu trình kiểm tra 4 điểm tự động

VẤN ĐỀ CẦN XỬ LÝ:
  Khi Tilt > 45° thì cảm biến Tilt bị đóng băng ở 340.8° (nghi do dây J3 lỏng
  hoặc motor 23mm bị quá tải). File firmware/test_as5600.ino dùng để chẩn đoán.

NHIỆM VỤ: Code MATLAB điều khiển quét bức xạ 2D/3D và phân tích Touchstone VNA.
=============================================================================
```
