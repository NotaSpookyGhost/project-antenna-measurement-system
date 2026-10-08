# Automated Antenna Measurement System — MATLAB Subsystem

Hệ thống phần mềm điều khiển và đo quét búp sóng bức xạ anten tự động trên **MATLAB R2025b**, tích hợp thiết bị phân tích mạng vector **NanoVNA SAA-2N** và bộ định vị xoay 2 trục **Positioner (ESP32 DevKit V1)**.

---

## 1. Cấu trúc thư mục

```
matlab/
├── app/
│   └── AntennaMeasurementApp.m        # Ứng dụng giao diện đồ họa GUI tương tác
├── classes/
│   ├── VNAController.m                # Điều khiển NanoVNA V2 / SAA-2N (Real & Mock)
│   ├── PositionerController.m         # Điều khiển động cơ ESP32 & mã hóa góc AS5600 (Hardware & Mock)
│   ├── MeasurementOrchestrator.m      # Máy trạng thái quét góc tự động (Scan Engine)
│   ├── PatternAnalyzer.m              # Thuật toán tính HPBW, SLL, FBR, Gain, vẽ đồ thị
│   └── DataManager.m                  # Quản lý xuất/nhập dữ liệu chuẩn MAT, CSV, JSON, PNG
├── tests/
│   ├── test_pattern_analyzer.m        # Unit test giải thuật búp sóng (HPBW, SLL, FBR, Gain)
│   ├── test_orchestrator_mock.m       # Test mô phỏng toàn trình quét 360° & kiểm tra toàn vẹn
│   ├── test_orchestrator_real_vna_mock_motor.m  # Test kết hợp VNA phần cứng thật + Motor ảo
│   ├── test_real_esp32_pan_as5600.m             # Test phần cứng thật ESP32 + TMC2209 Pan + AS5600 (Khóa bảo vệ Tilt)
│   └── test_app_gui.m                 # Test tự động hóa giao diện GUI và chụp màn hình
├── view_scan_dataset.m                # Công cụ xem lại dữ liệu quét cũ (2D Polar, Cartesian, Trace, 3D)
├── test_python_bridge.m               # Test cầu nối giao tiếp MATLAB <-> Python <-> SAA-2N
└── run_all_matlab_tests.m             # Master Runner chạy toàn bộ test suite
```

---

## 2. Cách khởi động và sử dụng

### A. Mở ứng dụng GUI tương tác (`AntennaMeasurementApp`)
Trong cửa sổ lệnh MATLAB:
```matlab
cd 'c:\Users\Spooky Laptop\.gemini\antigravity\scratch\antenna-v3'
addpath('matlab/app');
app = AntennaMeasurementApp();
```
* **Chế độ VNA:** Có thể chọn `Real (USB COM6)` khi cắm SAA-2N hoặc `Mock` để chạy thử nghiệm.
* **Chế độ Positioner:** Chọn `Mock` khi chưa cắm ESP32 hoặc `Hardware` khi đã kết nối motor.
* **Các nút chức năng:**
  * `START SCAN`: Bắt đầu quét tự động theo dải góc và bước nhảy đã đặt.
  * `Pause / Resume`: Tạm dừng hoặc tiếp tục quét.
  * `STOP`: Dừng khẩn cấp.
  * `Export Dataset`: Lưu bộ dữ liệu hoàn chỉnh (MAT, CSV 18 cột, JSON, TXT, PNG).
  * `Load Scan File`: Mở lại file quét cũ để xem và phân tích.

---

### B. Kiểm thử phần cứng thật ESP32 + TMC2209 Pan + AS5600 (`test_real_esp32_pan_as5600`)
Chạy lệnh sau để kết nối và kiểm tra thực tế trên bàn xoay (cổng `COM9`):
```matlab
cd 'c:\Users\Spooky Laptop\.gemini\antigravity\scratch\antenna-v3'
run('matlab/tests/test_real_esp32_pan_as5600.m')
```
* **Khóa an toàn trục Tilt:** Tự động bảo vệ (không phát xung vào trục Tilt bị cháy driver).
* **Kiểm tra vòng kín AS5600:** Kiểm tra góc xoay thực tế và tỉ số truyền GT2 16:90.

---

### C. Chạy toàn bộ Test Suite (Master Test Runner)
Chạy lệnh sau để tự động kiểm thử toàn bộ subsystem (tự động tích hợp bài test phần cứng nếu phát hiện `COM9`):
```matlab
cd 'c:\Users\Spooky Laptop\.gemini\antigravity\scratch\antenna-v3'
run('matlab/run_all_matlab_tests.m')
```

---

### D. Xem lại bộ dữ liệu quét bất kỳ (`view_scan_dataset`)
```matlab
view_scan_dataset('data/scans/sim_azimuth_20260930_144716')
% hoặc gọi không tham số để mở hộp thoại chọn file .mat:
view_scan_dataset()
```

---

## 3. Các chỉ số kỹ thuật đạt được (§14 Master Doc)

| Chỉ số | Ý nghĩa | Phương pháp tính |
|---|---|---|
| **HPBW (-3 dB)** | Bề rộng búp sóng nửa công suất | Nội suy tuyến tính tìm chính xác điểm cắt $-3\text{ dB}$ (độ chính xác $< 0.1^\circ$) |
| **SLL** | Mức búp sóng phụ lớn nhất | Tìm cực đại địa phương ngoài vùng chùm chính ($> 0.75 \times \text{HPBW}$) |
| **FBR** | Tỉ số bức xạ trước/sau | So sánh đỉnh búp chính với cực đại vùng $\theta_0 \pm 180^\circ \pm 30^\circ$ |
| **Gain (DUT)** | Ước lượng độ lợi anten | Phương pháp thay thế: $G_{DUT} = G_{REF} + (S_{21,DUT} - S_{21,REF})$ |

---

## 4. Cấu trúc lưu trữ dữ liệu (§13 & §21)
Mỗi lần quét xuất ra thư mục tại `data/scans/<tên_quét>_<timestamp>/`:
1. `scan_data.mat`: Dữ liệu số học ma trận đầy đủ (MATLAB v7.3).
2. `scan_pattern.csv`: 18 cột RF (góc chỉ định, góc AS5600, $S_{11}, S_{21}$ phần thực, phần ảo, biên độ dB, pha độ).
3. `metadata.json`: Cấu hình tần số, thiết bị, firmware, thời gian đo.
4. `summary.txt`: Bản tóm tắt kết quả đo và các chỉ số búp sóng.
5. `radiation_pattern.png`: Đồ thị búp sóng 2D Polar và Cartesian độ phân giải cao.
