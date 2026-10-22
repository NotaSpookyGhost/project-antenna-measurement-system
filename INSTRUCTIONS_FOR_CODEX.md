# 🤖 INSTRUCTIONS & SYSTEM BRIEFING FOR OPENAI CODEX

> **VNA Workbench (2026-10-15):** Read `docs/vna-workbench-user-guide.md` and
> `docs/vna-workbench-implementation-log.md` for current calibration/session/export APIs.
> The software-only gate is `matlab/tests/run_vna_software_tests.m` plus Python unit
> discovery in `.venv-vna`; the master runner and device scripts below are hardware capable.
> `S11/S21` stay raw, `CorrectedS11/CorrectedS21` are separate; TR means forward
> enhanced response, not full two-port. No hardware qualification is implied by Mock tests.

> **Bản đối chiếu môi trường:** Đọc `CODEX_GUIDE.md` trước khi chạy lệnh kiểm thử hoặc kết nối thiết bị. Tài liệu đó ghi lại đường dẫn và hành vi đã xác minh trên máy Codex; một số lệnh và mô tả mock trong bản bàn giao này chưa khớp với mã hiện tại.

> **Dành riêng cho Codex / AI Agent tiếp quản dự án:**  
> Bạn đang tiếp nhận codebase **Hệ thống tự động hóa đo búp sóng anten (Antenna Radiation Pattern Measurement System)** tại thư mục này.

---

## 📌 1. BẢN ĐỒ DỰ ÁN & ĐIỂM GỌI CHÍNH (ENTRY POINTS)

1. **Khởi động Giao diện GUI chính:**
   - File: `matlab/app/AntennaMeasurementApp.m`
   - Cách chạy trong MATLAB:
     ```matlab
     addpath('matlab/classes', 'matlab/app');
     app = AntennaMeasurementApp();
     ```
2. **Bộ điều phối quét đo & Máy trạng thái (State Machine):**
   - File: `matlab/classes/MeasurementOrchestrator.m`
   - Quản lý quá trình quay bàn xoay -> dừng ổn định -> kích hoạt quét NanoVNA -> lưu trữ dữ liệu.
3. **Phân tích búp sóng RF (Pattern Analytics):**
   - File: `matlab/classes/PatternAnalyzer.m`
   - Tính toán HPBW (-3 dB) bằng nội suy tuyến tính, mức búp phụ (SLL), tỉ số trước sau (FBR), độ lợi tuyệt đối/tương đối (Gain substitution method).
4. **Cầu nối VNA Python - MATLAB:**
   - MATLAB Wrapper: `matlab/classes/VNAController.m`
   - Python Out-Of-Process Bridge: `python/nanovna_bridge.py`
   - Protocol UG1101 NanoVNA V2/SAA-2N: `python/nanovna_v2.py`
5. **Điều khiển bàn xoay ESP32:**
   - File: `matlab/classes/PositionerController.m`
   - Giao tiếp qua Serial cổng `COM9`, điều khiển động cơ bước TMC2209 và đọc encoder từ tính vòng kín AS5600.

---

## 🧪 2. CHẠY BỘ KIỂM THỬ (TEST SUITE)

Mọi thay đổi code hoặc refactor của bạn PHẢI đảm bảo toàn bộ test suite vượt qua:
```matlab
% Chạy trong MATLAB command window:
cd('matlab');
run('run_all_matlab_tests.m');
```

Kiểm thử driver Python độc lập:
```bash
python python/test_saa2n.py
```

---

## ⚙️ 3. MÔI TRƯỜNG & THIẾT LẬP PHẦN CỨNG

- **Cổng COM chuẩn:**
  - `COM6`: NanoVNA SAA-2N (USB CDC nhị phân)
  - `COM9`: ESP32 Positioner (115200 baud)
- **Chế độ Mock (Khi không cắm thiết bị thật):**
  - Cả `VNAController` và `PositionerController` đều tích hợp sẵn cờ `isMock = true` mô phỏng búp sóng chuẩn cosine-squared $S_{21}$ và phản hồi bước xoay tức thì để bạn phát triển thuật toán mà không cần phần cứng.
- **Python Runtime:**
  - Yêu cầu Python 3.11+ 64-bit với thư viện `pyserial`.

---

## 📚 4. TÀI LIỆU CHI TIẾT
Đọc các tài liệu đặc tả sau trước khi thực hiện thay đổi lớn:
- [`docs/automatic-antenna-measurement-system-master-v4.md`](file:///c:/Users/Spooky%20Laptop/.gemini/antigravity/scratch/antenna-v3/docs/automatic-antenna-measurement-system-master-v4.md)
- [`plans/2026-10-11-codex-handover-plan.md`](file:///c:/Users/Spooky%20Laptop/.gemini/antigravity/scratch/antenna-v3/plans/2026-10-11-codex-handover-plan.md)
