# 📡 Project Antenna Measurement System

> **Automated Antenna Radiation Pattern Measurement & Characterization System**  
> Tích hợp **MATLAB R2025b GUI**, cầu nối **Python NanoVNA V2 (SAA-2N)** qua giao thức nhị phân USB CDC, và bộ định vị xoay 2 trục **ESP32** (TMC2209 Pan + encoder từ AS5600 vòng kín).

---

## 🎯 1. Giới thiệu tổng quan (System Overview)

Dự án phát triển hệ thống tự động hóa đo búp sóng bức xạ (Radiation Pattern) và tham số tán xạ $S_{11}, S_{21}$ của anten tại dải tần ISM **2.4 GHz** (hỗ trợ mở rộng lên đến 3–6 GHz).

Hệ thống kết hợp đồng bộ giữa phần cứng đo RF chính xác cao chi phí thấp (**NanoVNA SAA-2N**), bộ xoay cơ khí chính xác điều khiển bởi **ESP32**, và phần mềm điều khiển trung tâm trên **MATLAB** với giao diện đồ họa trực quan (GUI).

```
   ┌────────────────────────────────────────────────────────┐
   │             MATLAB R2025b Subsystem (GUI)              │
   │  AntennaMeasurementApp | MeasurementOrchestrator       │
   │  PatternAnalyzer (HPBW, SLL, FBR, Gain) | DataManager   │
   └───────────────────────┬────────────────────────────────┘
                           │
             ┌─────────────┴─────────────┐
             ▼                           ▼
   ┌───────────────────────┐   ┌────────────────────────────┐
   │ Python OutOfProcess   │   │   ESP32 Positioner (COM9)  │
   │    Driver Bridge      │   │   • TMC2209 SilentStep (Pan│
   │  nanovna_bridge.py    │   │   • AS5600 12-bit Closed-Loop  │
   └──────────┬────────────┘   │   • Tilt Interlock Protection  │
              │ USB CDC (COM6) └────────────────────────────┘
              ▼
   ┌───────────────────────┐
   │  NanoVNA V2 / SAA-2N  │ ──► [Port 1: TX Ref Horn / Patch]
   │  Binary Register/FIFO │ ──► [Port 2: RX Antenna Under Test (DUT)]
   └───────────────────────┘
```

---

## 📁 2. Cấu trúc thư mục dự án (Repository Structure)

```
project-antenna-measurement-system/
├── matlab/                          # Toàn bộ subsystem MATLAB R2025b
│   ├── app/
│   │   └── AntennaMeasurementApp.m  # Ứng dụng GUI tương tác thời gian thực
│   ├── classes/
│   │   ├── VNAController.m          # Điều khiển NanoVNA V2 / SAA-2N (Real & Mock)
│   │   ├── PositionerController.m   # Điều khiển bàn xoay ESP32 & AS5600
│   │   ├── MeasurementOrchestrator.m# Động cơ quét góc tự động & State Machine
│   │   ├── PatternAnalyzer.m        # Thuật toán tính HPBW, SLL, FBR, Gain, đồ thị Polar/Cartesian
│   │   └── DataManager.m            # Xuất/nhập dữ liệu MAT, CSV (18 cột), JSON, TXT, PNG
│   ├── tests/                       # Bộ kiểm thử Unit & End-to-End
│   │   ├── test_pattern_analyzer.m  # Kiểm thử thuật toán búp sóng
│   │   ├── test_orchestrator_mock.m # Mô phỏng quét 360° & DataManager
│   │   ├── test_orchestrator_real_vna_mock_motor.m # Test VNA thật + Motor ảo
│   │   ├── test_real_esp32_pan_as5600.m            # Test phần cứng ESP32 trên COM9
│   │   ├── test_scan_direction_and_abort.m         # Test chiều quét CW/CCW & Abort an toàn
│   │   └── test_app_gui.m           # Tự động hóa kiểm thử GUI
│   ├── view_scan_dataset.m          # Công cụ xem lại dữ liệu quét lịch sử
│   ├── test_python_bridge.m         # Kiểm thử cầu nối MATLAB <-> Python <-> SAA-2N
│   ├── run_all_matlab_tests.m       # Master Test Runner chạy toàn bộ test suite
│   └── README.md                    # Tài liệu chi tiết phân hệ MATLAB
│
├── python/                          # Driver giao tiếp nhị phân NanoVNA SAA-2N
│   ├── nanovna_bridge.py            # API bridge cấp cao gọi từ MATLAB
│   ├── nanovna_v2.py                # Driver protocol UG1101 (Registers, Sweeps, FIFO)
│   ├── test_saa2n.py                # Script kiểm tra giao tiếp nhanh qua CLI
│   └── tests/                       # Unit tests giao tiếp, FIFO freshness, repeatability
│
├── docs/                            # Tài liệu kỹ thuật, thiết kế & quy chuẩn
│   ├── 01-system-overview.md        # Tổng quan kiến trúc hệ thống
│   ├── 04-horn-antenna-guide.md     # Hướng dẫn anten chuẩn Horn WR-340
│   ├── automatic-antenna-measurement-system-master-v4.md # Đặc tả hệ thống Master v4
│   └── NanoVNA_GUI_UG1101/          # Tài liệu giao thức truyền thông NanoVNA V2
│
├── data/                            # Thư mục lưu trữ dữ liệu quét & kiểm định
│   ├── validation/                  # Dữ liệu đối sánh & đồ thị chuẩn mẫu
│   └── scans/                       # Kết quả các phiên đo quét thực tế
│
├── references/                      # Danh mục tài liệu tham khảo & links
├── .gitignore                       # Quy tắc loại trừ file tạm thời
└── README.md                        # Tài liệu tổng quan dự án
```

---

## ⚡ 3. Hướng dẫn cài đặt & Khởi chạy (Getting Started)

### Yêu cầu môi trường
- **MATLAB:** Phiên bản **R2025b** (hoặc R2024a/b).
- **Python:** **Python 3.11+ 64-bit** (cần `pyserial`):
  ```bash
  pip install pyserial
  ```
- **Phần cứng:**
  - NanoVNA V2 / SAA-2N kết nối qua USB (mặc định nhận cổng `COM6`).
  - ESP32 Positioner kết nối qua USB (mặc định nhận cổng `COM9`).

---

### A. Chạy Giao diện Người dùng (MATLAB GUI)
Mở MATLAB, chuyển đến thư mục gốc của dự án và chạy:
```matlab
addpath('matlab/app');
app = AntennaMeasurementApp();
```
* **Chế độ kiểm thử (Mock Mode):** Có thể chạy mô phỏng toàn phần khi không có phần cứng kết nối.
* **Chế độ thực tế (Hardware Mode):** Tự động phát hiện SAA-2N (`COM6`) và ESP32 (`COM9`), hiển thị đồ thị Polar/Cartesian thời gian thực và đo quét tự động.

---

### B. Chạy kiểm thử tự động toàn bộ hệ thống
Trong cửa sổ lệnh MATLAB:
```matlab
run('matlab/run_all_matlab_tests.m');
```

---

### C. Kiểm tra độc lập driver Python NanoVNA
Từ terminal (PowerShell / Command Prompt):
```bash
python python/test_saa2n.py
```

---

## 📊 4. Các chỉ số búp sóng & Định dạng dữ liệu

### Giải thuật búp sóng (`PatternAnalyzer.m`)
| Chỉ số | Tên gọi | Phương pháp tính toán |
|---|---|---|
| **HPBW (-3 dB)** | Half Power Beamwidth | Nội suy tuyến tính tìm chính xác điểm cắt $-3\text{ dB}$ (độ chính xác $< 0.1^\circ$) |
| **SLL** | Side Lobe Level | Cực đại địa phương ngoài vùng búp chính ($> 0.75 \times \text{HPBW}$) |
| **FBR** | Front-to-Back Ratio | So sánh đỉnh búp chính với cực đại trong vùng $\theta_0 \pm 180^\circ \pm 30^\circ$ |
| **Gain (DUT)** | Độ lợi anten | Phương pháp thay thế: $G_{DUT} = G_{REF} + (S_{21,DUT} - S_{21,REF})$ |

### Định dạng xuất dữ liệu (`DataManager.m`)
Mỗi phiên đo xuất đầy đủ 5 thành phần:
1. `scan_data.mat`: Dữ liệu số học ma trận đầy đủ (MATLAB v7.3).
2. `scan_pattern.csv`: Bảng 18 cột RF (góc chỉ định, góc thực AS5600, $S_{11}, S_{21}$ thực/ảo, dB, pha).
3. `metadata.json`: Cấu hình tần số, thông tin phần cứng, firmware, timestamp.
4. `summary.txt`: Báo cáo tóm tắt chỉ số bức xạ.
5. `radiation_pattern.png`: Đồ thị bức xạ Polar và Cartesian độ phân giải cao.

---

## 🛡️ License & Tác giả

Dự án được xây dựng và duy trì bởi **[@NotaSpookyGhost](https://github.com/NotaSpookyGhost)**.
Phục vụ nghiên cứu đo lường anten và thực hành hệ thống điều khiển tự động.
