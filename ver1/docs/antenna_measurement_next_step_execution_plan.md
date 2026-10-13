# Next-Step Execution Plan — Automatic Antenna Measurement System

> **Mục đích:** Kế hoạch triển khai tiếp theo sau khi đã xác minh thành công giao tiếp binary giữa PC và NanoVNA SAA-2N.
>
> **Baseline:** MATLAB R2025b → Python bridge → NanoVNA V2/SAA-2N  
> **Tần số trọng tâm:** ~2.4 GHz  
> **Thiết bị:** SAA-2N, DiSlord v1.4.02 FPU  
> **Ngày:** 2026-09-27

---

# 1. Trạng thái hiện tại

Chuỗi sau đã được xác minh hoạt động:

```text
Windows laptop
    ↓
USB CDC / COM6
    ↓
Python
    ↓
NanoVNA V2 binary protocol
    ↓
SAA-2N
```

Các test đã PASS:

- `INDICATE`: TX `0x0D` → RX `0x32`
- `deviceVariant = 0x02`
- `protocolVersion = 0x01`
- `hardwareRevision = 0x02`
- Configure sweep `2395–2405 MHz`, 11 points
- FIFO trả đúng `11 × 32 = 352 bytes`
- `freqIndex = 0..10`
- Parse được `S11 = REV0/FWD0`
- Parse được `S21 = REV1/FWD0`

**Kết luận hiện tại:** compatibility ở mức **communication/protocol = VERIFIED**.

Chưa được coi là verified:

- RF amplitude accuracy
- RF phase accuracy
- calibration
- repeatability
- MATLAB bridge
- motor/VNA synchronization
- radiation-pattern accuracy
- absolute gain

---

# 2. Milestone tiếp theo

## MILESTONE RF-1 — Known-DUT validation

Mục tiêu tiếp theo không phải GUI mà là chứng minh rằng backend Python đọc đúng dữ liệu RF.

Thứ tự ưu tiên:

```text
THRU
→ OPEN / SHORT / LOAD
→ complex phase
→ FIFO freshness
→ repeatability
→ compare NanoVNA-QT/Saver
→ MATLAB
```

---

# 3. Test A — THRU validation

## Setup

```text
NanoVNA Port 1
    │
    │ short SMA cable
    │
NanoVNA Port 2
```

Giữ sweep hiện tại:

```text
Start  = 2395 MHz
Stop   = 2405 MHz
Points = 11
```

## Kỳ vọng

Test hiện tại khi không có đường truyền cho:

```text
S21 ≈ -70 ... -79 dB
```

Khi nối THRU bằng cáp:

```text
S21 phải tăng lên rất mạnh,
thường gần 0 dB hoặc chỉ có một ít insertion loss.
```

Chưa cần yêu cầu chính xác tuyệt đối trước calibration.

## PASS

```text
S21_THROUGH >> S21_DISCONNECTED
```

và trace phải tương đối mượt theo tần số.

## FAIL

Nếu S21 vẫn quanh `-70 dB`, kiểm tra:

- REV1 field
- parser offset
- complex conversion
- stale FIFO
- cable/connector
- channel selection
- firmware-specific behavior

---

# 4. Test B — OPEN / SHORT / LOAD

## OPEN

Kỳ vọng:

```text
|S11| ≈ 1
S11_dB ≈ 0 dB
```

## SHORT

Kỳ vọng:

```text
|S11| ≈ 1
S11_dB ≈ 0 dB
```

OPEN và SHORT có magnitude tương tự nhưng phase khác đáng kể.

## 50-ohm LOAD

Kỳ vọng:

```text
|S11| thấp hơn rõ rệt so với OPEN/SHORT
```

Sau calibration phù hợp, return loss phải cải thiện đáng kể.

---

# 5. Test C — Complex data validation

Không chỉ in dB. Với một vài điểm tần số, in thêm:

```text
S11.real
S11.imag
abs(S11)
phase(S11)

S21.real
S21.imag
abs(S21)
phase(S21)
```

Raw complex data phải được giữ cho toàn bộ project.

Lý do:

- complex averaging
- phase analysis
- calibration
- time-domain processing
- gating
- reference correction
- later reprocessing

---

# 6. Test D — FIFO freshness

Đây là test rất quan trọng trước khi ghép motor.

Workflow mục tiêu:

```text
MOVE MOTOR
    ↓
POSITION_REACHED
    ↓
WAIT SETTLE
    ↓
CLEAR / DISCARD STALE FIFO
    ↓
ACQUIRE FRESH SWEEP
    ↓
VALIDATE freqIndex
    ↓
SAVE
```

## Experiment

Thay đổi DUT liên tiếp:

```text
1. disconnected
2. THRU connected
3. disconnected
```

Mỗi lần phải nhận đúng trạng thái hiện tại, không phải packet cũ.

---

# 7. Test E — Repeatability

Giữ nguyên THRU.

Thực hiện:

```text
100 acquisitions
```

Tại 2400 MHz lưu:

```text
complex S21
S21_dB
S21_phase
```

Tính:

```text
mean(S21_dB)
std(S21_dB)
min
max

mean(phase)
std(phase)

timeout count
partial FIFO count
freqIndex error count
```

Mục tiêu: đo noise và short-term stability thật của backend.

---

# 8. Test F — Averaging

Thử:

```text
N = 1
N = 2
N = 4
N = 8
N = 16
```

So sánh:

```text
noise reduction
vs
measurement time
```

Ưu tiên average complex:

```python
S21_avg = mean(S21_complex)
S21_db = 20*log10(abs(S21_avg))
phase = angle(S21_avg)
```

Không mặc định average trực tiếp giá trị dB.

---

# 9. Test G — Compare with NanoVNA-QT / NanoVNA-Saver

Cùng một:

- SAA-2N
- DUT
- cable
- sweep
- point count
- calibration state

So sánh:

```text
frequency
S11 magnitude
S11 phase
S21 magnitude
S21 phase
```

## Acceptance

Cần thấy:

- cùng shape
- cùng resonance
- cùng xu hướng amplitude
- cùng behavior phase

Sai khác nhỏ do calibration/averaging/interpolation có thể chấp nhận nếu giải thích được.

---

# 10. Calibration — vẫn là một nhánh riêng

Không được giả định:

```text
calibration lưu trên màn hình SAA-2N
=
calibration áp vào USB FIFO
```

Cần nghiên cứu riêng:

1. NanoVNA-Saver calibration flow
2. S11 SOL
3. S21 response calibration
4. SOLT(T/R) nếu cần
5. mức calibration tối thiểu cho relative pattern
6. phương pháp cần cho absolute gain

---

# 11. Relative radiation pattern MVP

Trước mắt có thể dùng:

```text
S21(theta)
```

và normalize:

```text
Pattern_rel_dB(theta)
=
20*log10(|S21(theta)|)
-
max_theta(20*log10(|S21(theta)|))
```

Kết quả này là:

```text
Relative level (dB)
```

Không gọi là:

```text
Gain (dBi)
```

cho tới khi gain methodology được xác minh.

---

# 12. Backend được coi là READY khi

```text
[ ] handshake reliable
[ ] identity reliable
[ ] sweep config works
[ ] FIFO complete
[ ] stale FIFO handled
[ ] THRU S21 test PASS
[ ] OPEN test PASS
[ ] SHORT test PASS
[ ] LOAD test PASS
[ ] complex phase behavior plausible
[ ] 100-repeat test stable
[ ] comparison with NanoVNA-QT/Saver reasonable
```

---

# 13. Freeze Python API sau khi RF validation PASS

Recommended API:

```python
connect(port)

identify()

configure_sweep(
    start_hz,
    stop_hz,
    points,
    averages
)

clear_fifo()

acquire_sweep()

acquire_at_frequency(
    frequency_hz,
    averages
)

disconnect()
```

MATLAB không nên biết:

```text
0x0D
0x30
register address
packet offset
endianness
FIFO internals
```

---

# 14. Python return structure

Ví dụ:

```python
{
    "frequency_hz": [...],

    "s11_real": [...],
    "s11_imag": [...],

    "s21_real": [...],
    "s21_imag": [...],

    "metadata": {
        "device": "SAA-2N",
        "protocol_version": 1,
        "hardware_revision": 2
    }
}
```

---

# 15. MATLAB bridge — chỉ sau RF validation

Dùng:

```text
MATLAB R2025b
Python 3.11 64-bit — recommended
```

Test trước:

```matlab
pyenv(ExecutionMode="OutOfProcess")
```

Không bắt đầu bằng App Designer.

Đầu tiên chỉ cần:

```text
MATLAB script
↓
Python bridge
↓
COM6
↓
SAA-2N
↓
one sweep
↓
return complex S11/S21
↓
MATLAB plot
```

---

# 16. MATLAB bridge PASS criteria

```text
[ ] Python import OK
[ ] COM connect OK
[ ] identify OK
[ ] configure sweep OK
[ ] complex arrays return correctly
[ ] MATLAB conversion does not corrupt data
[ ] MATLAB plot matches Python
[ ] disconnect/reconnect OK
```

---

# 17. Fixed-frequency strategy cho radiation pattern

Ba phương án:

## A. 1 point tại 2.400 GHz

Nhanh nhất nhưng ít khả năng kiểm tra lỗi.

## B. Narrow sweep

```text
2395–2405 MHz
11 points
```

Dùng point 2400 MHz cho pattern nhưng vẫn lưu cả 11 points.

**Recommended cho MVP đầu tiên** vì backend này đã được test.

## C. Wider local sweep

Ví dụ:

```text
2380–2420 MHz
```

Hữu ích nếu resonance lệch khỏi 2.4 GHz nhưng chậm hơn.

---

# 18. Ghép motor sau MATLAB bridge

Architecture:

```text
                MATLAB
               /                    /               ESP32 serial   Python bridge
          ↓               ↓
      Positioner         SAA-2N
```

---

# 19. Measurement state machine đề xuất

```text
IDLE
 ↓
MOVE
 ↓
POSITION_REACHED
 ↓
SETTLING
 ↓
CLEAR_FIFO
 ↓
MEASURE
 ↓
VALIDATE_DATA
 ↓
SAVE
 ↓
NEXT_ANGLE
```

---

# 20. First 2D scan

Không bắt đầu bằng 200–300 points.

## Engineering test đầu tiên

```text
10° step
~36 points
```

Mục tiêu:

```text
prove end-to-end synchronization
```

Sau đó tăng dần:

```text
10°
→ 5°
→ 2°
→ ~1–1.5°
```

Final MVP:

```text
200–300 points
```

---

# 21. Dữ liệu phải lưu tại mỗi góc

```text
timestamp

commanded_angle
measured_angle

frequency[]

S11_real[]
S11_imag[]

S21_real[]
S21_imag[]

selected_S21_complex
selected_S21_dB
selected_S21_phase

positioner_state
VNA_status
measurement_index
```

---

# 22. Real-time plot

Live plot đầu tiên:

```text
polarplot(theta, relative_S21_dB)
```

với:

```text
relative_S21_dB
=
S21_dB - max(S21_dB)
```

Label:

```text
Relative level (dB)
```

Không label `Gain (dBi)` ở MVP.

---

# 23. Sau khi 2D scan hoạt động

Triển khai lần lượt:

```text
main beam angle
HPBW
SLL
front-to-back ratio
```

Trước khi chạy với measurement thật, test thuật toán bằng synthetic pattern.

---

# 24. Gain — để sau relative pattern

Không làm absolute gain cho đến khi chốt:

```text
reference antenna
reference gain
distance
polarization
cable routing
calibration
free-space path
environment
substitution methodology
```

---

# 25. 3D — chỉ sau khi 2D ổn định

Sau đó mới thêm elevation.

Possible scan:

```text
azimuth sweep
↓
elevation step
↓
reverse azimuth sweep
↓
elevation step
```

Dùng zigzag/boustrophedon để hạn chế xoắn dây.

---

# 26. Development priority

```text
1. THRU test
2. OPEN / SHORT / LOAD
3. Complex phase validation
4. FIFO freshness
5. 100-repeat stability test
6. Compare NanoVNA-QT/Saver
7. Freeze Python backend
8. MATLAB plain-script bridge
9. Fixed-frequency acquisition
10. ESP32 + VNA synchronized loop
11. Coarse 2D scan
12. 200–300 point scan
13. HPBW / SLL
14. Calibration refinement
15. Gain
16. Elevation
17. 3D
18. Final App Designer GUI
```

---

# 27. Không nên làm lúc này

Tạm thời tránh:

```text
polished GUI
3D visualization
absolute gain claims
axial ratio
Anritsu backend
auto-homing
ROS2/Gazebo
commercial-software-style UI
```

---

# 28. Code structure đề xuất

```text
project/
│
├── python/
│   ├── nanovna_v2.py
│   ├── nanovna_bridge.py
│   │
│   └── tests/
│       ├── test_handshake.py
│       ├── test_thru.py
│       ├── test_s11_loads.py
│       ├── test_repeatability.py
│       └── test_fifo_freshness.py
│
├── matlab/
│   ├── test_python_bridge.m
│   ├── test_sweep.m
│   ├── test_fixed_frequency.m
│   └── test_scan_loop.m
│
├── data/
│   ├── validation/
│   ├── raw/
│   └── scans/
│
└── docs/
```

---

# 29. Immediate scripts nên viết

## `test_thru.py`

Output:

```text
frequency
complex S11
complex S21
S11 dB
S21 dB
phase
```

## `test_repeatability.py`

100 acquisitions.

Output:

```text
mean
std
min
max
phase stability
read error counters
```

## `test_fifo_freshness.py`

Xác minh không đọc stale measurement.

## `test_python_bridge.m`

MATLAB gọi Python và vẽ một sweep.

---

# 30. Experiment log format

Mỗi validation run nên tạo:

```text
validation_YYYYMMDD_HHMMSS/
│
├── config.json
├── raw.csv
├── summary.txt
└── plot.png
```

Ví dụ config:

```json
{
  "device": "SAA-2N",
  "display_firmware": "DiSlord v1.4.02 FPU",
  "protocol_version": 1,
  "hardware_revision": 2,
  "start_hz": 2395000000,
  "stop_hz": 2405000000,
  "points": 11,
  "dut": "THRU cable"
}
```

---

# 31. Firmware version note

Thiết bị hiển thị:

```text
DiSlord v1.4.02 FPU
```

USB registers trả:

```text
firmwareMajor = 1
firmwareMinor = 2
```

Không nên thay display version bằng `1.2`.

Lưu riêng:

```text
display_firmware = DiSlord v1.4.02 FPU
usb_register_firmware_major = 1
usb_register_firmware_minor = 2
```

cho đến khi semantic relationship được xác minh.

---

# 32. Status classification

## VERIFIED

```text
SAA-2N hardware family
USB CDC
COM detection
V2 INDICATE handshake
identity register read
sweep register configuration
FIFO acquisition
32-byte record parsing
basic S11/S21 computation path
```

## RECOMMENDED

```text
Python bridge
Python 3.11
MATLAB OutOfProcess Python
narrow 2395–2405 MHz sweep for MVP
complex data storage
S21 as primary radiation-pattern observable
```

## OPEN

```text
absolute gain methodology
PC-side calibration implementation
NanoVNA-Saver dependency vs extracted driver
final averaging count
final angular resolution
full 360° vs limited sector
final antenna separation
reference methodology
3D scan strategy
axial ratio
```

---

# 33. Câu hỏi để AI/kỹ sư khác phản biện

1. Chuỗi THRU → OPEN/SHORT/LOAD đã đủ để validate backend chưa?
2. S11/S21 conversion có đúng cho DiSlord firmware này không?
3. Có behavior FIFO đặc thù nào cần flush/synchronization khác không?
4. Nên dùng `valuesPerFrequency` hay repeated acquisition software-side?
5. Cách chắc chắn nhất để lấy fresh sweep sau khi motor settle?
6. Narrow 11-point sweep có tốt hơn single-frequency point cho MVP không?
7. Complex averaging nên triển khai thế nào?
8. Nên dùng NanoVNA-QT hay NanoVNA-Saver làm reference comparison?
9. Calibration tối thiểu cho relative radiation pattern là gì?
10. Calibration/reference methodology nào cần trước absolute gain?
11. MATLAB ↔ Python nên trao đổi NumPy/complex array theo cách nào ít overhead?
12. Recovery logic khi:
    - timeout,
    - partial FIFO,
    - invalid `freqIndex`,
    - disconnect,
    - motor stall?

---

# 34. Gate trước MATLAB

Chỉ chuyển sang MATLAB khi:

```text
THRU             PASS
OPEN             PASS
SHORT            PASS
LOAD             PASS
complex phase    PASS
repeatability    PASS
FIFO freshness   PASS
comparison       PASS
```

---

# 35. Gate trước antenna scan

Chỉ bắt đầu scan khi:

```text
MATLAB bridge works
+
VNA stable
+
motor stable
+
fresh-measurement synchronization proven
```

---

# 36. Definition of first successful system demo

Demo thành công đầu tiên không phải:

```text
GUI mở được
```

mà phải là:

```text
1. User presses START
2. MATLAB commands azimuth
3. ESP32 confirms position
4. system waits for settle
5. fresh S21 acquired
6. raw complex data saved
7. polar plot updates
8. next angle automatically
9. complete coarse scan
10. saved raw data can be reloaded
```

---

# 37. Immediate next action

**Làm THRU test trước.**

```text
Port 1
  ↓
short SMA cable
  ↓
Port 2
```

Dùng lại:

```text
2395–2405 MHz
11 points
```

Lưu:

```text
complex S11
complex S21
S11_dB
S21_dB
phase
```

Nếu S21 từ khoảng:

```text
-70...-79 dB
```

nhảy lên vùng gần:

```text
0 dB / small cable loss
```

thì forward transmission chain được xác nhận rất mạnh.

Sau đó làm ngay:

```text
OPEN / SHORT / LOAD
→ 100-repeat stability
→ comparison
→ MATLAB bridge
```
