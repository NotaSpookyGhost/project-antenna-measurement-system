# 📋 IMPLEMENTATION PLAN & HANDOVER SPECIFICATION: ANTENNA MEASUREMENT & MATLAB SUBSYSTEM TO CODEX

**Project:** Automated Antenna Radiation Pattern Measurement System (`antenna-v3`)  
**Target Recipient:** OpenAI Codex / Next Development Agent  
**Authoring Agent:** Antigravity (Google DeepMind)  
**Date:** 2026-10-11  
**Spec Reference:** [`docs/automatic-antenna-measurement-system-master-v4.md`](file:///c:/Users/Spooky%20Laptop/.gemini/antigravity/scratch/antenna-v3/docs/automatic-antenna-measurement-system-master-v4.md) & [`README.md`](file:///c:/Users/Spooky%20Laptop/.gemini/antigravity/scratch/antenna-v3/README.md)

---

## 🧭 EXECUTIVE SUMMARY & SYSTEM CONTEXT

Hệ thống đo búp sóng anten tự động (`antenna-v3`) giải quyết bài toán đo đặc tính bức xạ anten (Radiation Pattern 2D/3D, Gain, HPBW, FBR, SLL) và các tham số tán xạ $S_{11}, S_{21}$ tại dải tần ISM 2.4 GHz (mở rộng 3–6 GHz). Hệ thống tích hợp:
1. **Phần cứng RF:** NanoVNA V2 / SAA-2N kết nối USB CDC (COM6).
2. **Phần cứng cơ khí:** Bàn xoay 2 trục điều khiển bằng ESP32 (COM9), driver TMC2209 StealthChop/SilentStep, encoder từ tính AS5600 12-bit đọc góc vòng kín (Closed-loop feedback).
3. **Phần mềm trung tâm:** MATLAB R2025b GUI tương tác thời gian thực + Driver Bridge Python giao tiếp nhị phân low-overhead.

Tài liệu này chuẩn bị theo skill `/superpowers-plan` nhằm bàn giao **toàn bộ tri thức, mã nguồn, kiến trúc, kiểm thử, công cụ MCP, và các kỹ năng (skills/prompts)** sang cho Codex tiếp nhận và duy trì dự án liền mạch.

---

## 🗺️ TỔNG QUAN KIẾN TRÚC & PHÂN HỆ CÔNG NGHỆ

```
┌────────────────────────────────────────────────────────────────────────┐
│                        MATLAB Subsystem (R2025b)                       │
│  ├── AntennaMeasurementApp.m (App Designer / Programmatic GUI)         │
│  ├── MeasurementOrchestrator.m (State Machine: IDLE, SCANNING, ABORT)  │
│  ├── PositionerController.m (Serial COM9, TMC2209, AS5600 feedback)    │
│  ├── VNAController.m (Out-of-Process Python Bridge, Mock & Hardware)   │
│  ├── PatternAnalyzer.m (HPBW, FBR, SLL, Absolute/Relative Gain)        │
│  └── DataManager.m (Export MAT, CSV 18 cols, JSON, TXT, PNG)          │
└──────────────────────────┬──────────────────────┬──────────────────────┘
                           │                      │
           (IPC / Out-of-process)                 │ (Serial COM9, 115200 baud)
                           ▼                      ▼
┌──────────────────────────────────────┐  ┌───────────────────────────────┐
│        Python Bridge Subsystem       │  │   ESP32 Positioner Controller │
│  ├── nanovna_bridge.py (JSON API)    │  │  - TMC2209 Step/Dir (Azimuth) │
│  └── nanovna_v2.py (UG1101 Protocol) │  │  - AS5600 Magnetic Encoder    │
└──────────────────┬───────────────────┘  │  - Dual-axis Safety Interlock │
                   │ USB CDC (COM6)       └───────────────────────────────┘
                   ▼
┌──────────────────────────────────────┐
│         NanoVNA V2 (SAA-2N)          │
│  Port 1: TX (Reference Horn WR-340)  │
│  Port 2: RX (Antenna Under Test)     │
└──────────────────────────────────────┘
```

---

## 🛠️ PHÂN HỆ 1: CHI TIẾT ANTENNA & RF HARDWARE

### 1. NanoVNA SAA-2N / V2 Protocol (`python/nanovna_v2.py`)
- **Giao thức:** Nhị phân theo chuẩn `UG1101` (xem [`docs/NanoVNA_GUI_UG1101/`](file:///c:/Users/Spooky%20Laptop/.gemini/antigravity/scratch/antenna-v3/docs/NanoVNA_GUI_UG1101)).
- **Cơ chế ghi/đọc:**
  - Lệnh ghi thanh ghi: `0x20` (WRITE) + `Addr` + `Value` (1/2/4 bytes).
  - Lệnh đọc thanh ghi: `0x10` (READ) + `Addr` + `Value`.
  - Đọc FIFO dữ liệu quét tần số: `0x30` (READ_FIFO) quét các điểm tần số $S_{11}, S_{21}$.
- **Cơ chế Flush & Đảm bảo Freshness:**
  - Luôn xả sạch buffer Serial trước khi kích hoạt sweep mới (`clear_buffer`).
  - Hỗ trợ fallback sang chế độ Sweep Discrete nếu FIFO bị nghẽn.
- **Port mapping:**
  - Port 1 (TX): Nối anten phát tham chiếu (Horn tiêu chuẩn WR-340 hoặc Patch chuẩn).
  - Port 2 (RX): Nối DUT (Antenna Under Test) trên trục xoay.

### 2. Thiết kế Anten tham chiếu & Đối tượng đo (`docs/`)
- [`01-system-overview.md`](file:///c:/Users/Spooky%20Laptop/.gemini/antigravity/scratch/antenna-v3/docs/01-system-overview.md): Tổng quan toàn hệ thống.
- [`02-lpda-research.md`](file:///c:/Users/Spooky%20Laptop/.gemini/antigravity/scratch/antenna-v3/docs/02-lpda-research.md): Nghiên cứu Anten Log-Periodic Dipole Array (LPDA).
- [`03-vivaldi-research.md`](file:///c:/Users/Spooky%20Laptop/.gemini/antigravity/scratch/antenna-v3/docs/03-vivaldi-research.md): Nghiên cứu Anten Vivaldi siêu rộng băng (UWB).
- [`04-horn-antenna-guide.md`](file:///c:/Users/Spooky%20Laptop/.gemini/antigravity/scratch/antenna-v3/docs/04-horn-antenna-guide.md): Hướng dẫn chế tạo và chuẩn hóa Horn WR-340 (độ lợi danh định ~10–12 dBi tại 2.45 GHz).
- [`05-conductive-coating-vn.md`](file:///c:/Users/Spooky%20Laptop/.gemini/antigravity/scratch/antenna-v3/docs/05-conductive-coating-vn.md): Kỹ thuật mạ phủ dẫn điện cho mẫu in 3D FDM.
- [`06-antenna-comparison.md`](file:///c:/Users/Spooky%20Laptop/.gemini/antigravity/scratch/antenna-v3/docs/06-antenna-comparison.md): Bảng so sánh đặc tính các họ anten đo lường.

---

## 💻 PHÂN HỆ 2: MATLAB SUBSYSTEM & THUẬT TOÁN

### 1. Thuật toán phân tích búp sóng (`matlab/classes/PatternAnalyzer.m`)
- **HPBW (-3 dB Beamwidth):**
  - Tìm đỉnh cực đại búp chính $\theta_{\max}$ với công suất $P_{\max}$.
  - Ngưỡng $-3\text{ dB}$: $P_{\text{target}} = P_{\max} - 3.0103\text{ dB}$.
  - Sử dụng **nội suy tuyến tính (Linear Interpolation)** giữa 2 điểm đo lân cận biên trái/phải để tìm góc chính xác tuyệt đối ($< 0.1^\circ$).
- **Side Lobe Level (SLL):**
  - Quét tìm tất cả các cực đại cục bộ (Local Peaks) bằng đạo hàm bậc 1 đổi dấu ngoài khoảng $\theta_{\max} \pm 0.75 \times \text{HPBW}$.
  - $\text{SLL (dB)} = P_{\text{sidelobe\_max}} - P_{\max}$.
- **Front-to-Back Ratio (FBR):**
  - Vùng phía sau: $\theta_{\text{back}} \in [\theta_{\max} + 180^\circ - 30^\circ, \theta_{\max} + 180^\circ + 30^\circ]$.
  - $\text{FBR (dB)} = P_{\max} - \max(P(\theta_{\text{back}}))$.
- **Tính toán Gain (Substitution Method):**
  $$G_{\text{DUT}}(\text{dBi}) = G_{\text{REF}}(\text{dBi}) + [S_{21,\text{DUT}}(\text{dB}) - S_{21,\text{REF}}(\text{dB})]$$

### 2. Bộ điều phối đo tự động (`matlab/classes/MeasurementOrchestrator.m`)
- Quản lý State Machine: `IDLE` -> `INITIALIZING` -> `HOMING` -> `SCANNING` -> `COMPLETED` / `ABORTED`.
- Quản lý logic quét góc:
  - Cho phép chọn hướng quét: **CW (Clockwise)** hoặc **CCW (Counter-Clockwise)**.
  - Quét bước: Dừng ở mỗi bước góc $\Delta \theta$ (ví dụ: $1^\circ, 2^\circ, 5^\circ$), đọc ổn định encoder AS5600, kích hoạt VNA quét tần số, ghi nhận dữ liệu rồi mới chuyển sang góc kế tiếp.
  - Xử lý Safe Abort: Khi người dùng nhấn Stop/Abort, dừng lập tức xung phát động cơ, tắt cấp nguồn cuộn dây nếu cần, bảo vệ cáp RF không bị xoắn gãy.

### 3. Quản lý định dạng dữ liệu (`matlab/classes/DataManager.m`)
Mỗi phiên quét xuất chuẩn 5 file vào thư mục `data/scans/YYYYMMDD_HHMMSS/`:
1. `scan_data.mat`: Struct dữ liệu gốc MATLAB (chứa mảng tần số, góc định vị, góc AS5600, ma trận $S_{11}, S_{21}$).
2. `scan_pattern.csv`: Bảng 18 cột (Target Angle, AS5600 Angle, S11 Real, S11 Imag, S11 Mag dB, S11 Phase, S21 Real, S21 Imag, S21 Mag dB, S21 Phase, v.v.).
3. `metadata.json`: Cấu hình tần số bắt đầu, tần số kết thúc, bước góc, mã thiết bị, phiên bản firmware, người vận hành.
4. `summary.txt`: Báo cáo tóm tắt chỉ số tự động (HPBW, SLL, FBR, Peak Gain).
5. `radiation_pattern.png`: Hình ảnh đồ thị búp sóng (Polar 2D & Cartesian).

---

## ⚙️ TOÀN BỘ CẤU HÌNH ANTIGRAVITY ĐƯỢC CHUYỂN GIAO CHO CODEX

### 1. Cấu hình MCP Servers (Model Context Protocol)
Các MCP server đang được cấu hình trên môi trường Antigravity sẵn sàng cho Codex kế thừa:
- **`matlab` MCP Server:**
  - `check_matlab_code`: Kiểm tra cú pháp script/class.
  - `detect_matlab_toolboxes`: Phát hiện toolbox RF, Antenna, Phased Array, Optimization.
  - `evaluate_matlab_code`: Thực thi nhanh biểu thức MATLAB.
  - `run_matlab_file`: Chạy file script/app.
  - `run_matlab_test_file`: Chạy unit test suite của MATLAB.
- **`serial` MCP Server:**
  - Quản lý trực tiếp cổng COM (COM6 NanoVNA, COM9 ESP32), gửi nhận byte, pulse DTR/RTS để reset ESP32.
- **`freecad` MCP Server:**
  - Tự động hóa CAD 3D, xuất file STEP/STL cho anten Horn WR-340 hoặc đế gá lắp bàn xoay.
- **`git` & `github` MCP Server:**
  - Quản trị phiên bản, commit, push, PR tự động.
- **`filesystem` MCP Server:**
  - Thao tác tệp tin tốc độ cao.

### 2. Danh mục Kỹ năng (Custom Skills) cốt lõi cần kích hoạt
Khi Codex làm việc với dự án này, hãy hướng dẫn Codex áp dụng các quy chuẩn từ skills:
- **`karpathy-coding` & `karpathy-python`:** Code đơn giản, tường minh, không over-engineer, tối thiểu dependencies.
- **`osmani-code-quality` & `osmani-debugging`:** Quy chuẩn chất lượng code sạch, kiểm tra boundary condition, xử lý lỗi an toàn.
- **`academic-research` & `technical-lookup`:** Tra cứu chính xác lý thuyết anten (Stutzman, Balanis), chuẩn IEEE Std 149 về đo lường anten, chuẩn cáp/RF connector SMA.
- **`superpowers-tdd` & `superpowers-plan`:** Bổ sung tính năng mới bằng chu trình kiểm thử trước (TDD) và kế hoạch theo phase.

---

## 🎯 KẾ HOẠCH BÀN GIAO THỰC THI (PHASE-BY-PHASE IMPLEMENTATION PLAN)

```markdown
### Phase 1: Môi trường & Khởi tạo (Environment & Handover Baseline)
- [ ] Task 1.1: Tạo tài liệu cấu hình `CODEX_GUIDE.md` tại thư mục gốc chứa hướng dẫn setup Python 3.11 (`pyserial`), MATLAB R2025b path.
- [ ] Task 1.2: Cung cấp `AGENTS.md` / `INSTRUCTIONS_FOR_CODEX.md` mô tả chi tiết cách gọi bridge Python, chạy mock test không cần cắm phần cứng.
- [ ] Checkpoint 1: Chạy `run_all_matlab_tests.m` và `python/test_saa2n.py` ở chế độ Mock đảm bảo 100% tests PASS.

### Phase 2: Quy chuẩn vận hành phần cứng (Hardware Operational Protocols)
- [ ] Task 2.1: Bàn giao quy trình kết nối cổng COM:
      - SAA-2N: COM6 (USB CDC nhị phân, 115200/VCP)
      - ESP32: COM9 (115200 baud, 8-N-1, Newline terminated commands)
- [ ] Task 2.2: Bàn giao quy trình hiệu chuẩn VNA (SOLT Calibration: Short - Open - Load - Through) trước khi đo anten.
- [ ] Task 2.3: Bàn giao các giới hạn góc xoay an toàn (Safety Interlock) của bàn xoay nhằm chống xoắn đứt cáp RF đồng trục RG402/RG316.

### Phase 3: Duy trì & Phát triển tính năng mở rộng (Future Roadmap for Codex)
- [ ] Task 3.1: Hỗ trợ đo 3D Radiation Pattern (quét đồng thời cả trục Azimuth $\phi$ và Elevation $\theta$).
- [ ] Task 3.2: Tích hợp thuật toán bù sai số phòng đo (Time-Domain Gating / Gating phản xạ đa đường).
- [ ] Task 3.3: Xuất định dạng file chuẩn mô phỏng quốc tế: `.ffe` (FEKO), `.pat` (CST Studio Suite), `.nsi` (NSI-MI).
```

---

## 🚀 CHECKLIST BÀN GIAO SẴN SÀNG CHO CODEX

1. **Thư mục dự án:** `c:\Users\Spooky Laptop\.gemini\antigravity\scratch\antenna-v3`
2. **Điểm vào MATLAB:** [`matlab/app/AntennaMeasurementApp.m`](file:///c:/Users/Spooky%20Laptop/.gemini/antigravity/scratch/antenna-v3/matlab/app/AntennaMeasurementApp.m)
3. **Master Test Suite:** [`matlab/run_all_matlab_tests.m`](file:///c:/Users/Spooky%20Laptop/.gemini/antigravity/scratch/antenna-v3/matlab/run_all_matlab_tests.m)
4. **Điểm vào Python Driver:** [`python/nanovna_bridge.py`](file:///c:/Users/Spooky%20Laptop/.gemini/antigravity/scratch/antenna-v3/python/nanovna_bridge.py) & [`python/nanovna_v2.py`](file:///c:/Users/Spooky%20Laptop/.gemini/antigravity/scratch/antenna-v3/python/nanovna_v2.py)
5. **Đặc tả hệ thống đầy đủ:** [`docs/automatic-antenna-measurement-system-master-v4.md`](file:///c:/Users/Spooky%20Laptop/.gemini/antigravity/scratch/antenna-v3/docs/automatic-antenna-measurement-system-master-v4.md)
