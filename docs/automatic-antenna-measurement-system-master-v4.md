# Automatic Antenna Measurement System --- Master Project Context

> **Revision:** v4 — tích hợp kiểm tra lại SAA-2N/NanoVNA V2 protocol,
> MATLAB↔Python strategy và antenna-reference benchmark (2026-09-27).

> **Mục đích:** Tài liệu master dùng làm context cho các AI khác, làm
> tài liệu kỹ thuật nội bộ và làm cơ sở tiếp tục phát triển dự án.
>
> **Nguyên tắc cập nhật:** Các quyết định mới nhất trong tài liệu người
> dùng cung cấp được ưu tiên hơn các giả định cũ. Những điểm chưa xác
> nhận được giữ ở trạng thái **OPEN** thay vì tự suy diễn.
>
> **Quy ước trạng thái trong bản cập nhật này:**
> - **CONFIRMED (user):** người dùng đã xác nhận / phần cứng đã có.
> - **VERIFIED (source):** đã đối chiếu với tài liệu chính thức hoặc source code.
> - **RECOMMENDED:** đề xuất kỹ thuật, chưa được coi là quyết định cuối cùng của người dùng.
> - **OPEN:** chưa đủ bằng chứng hoặc chưa được chốt.

------------------------------------------------------------------------

## Cập nhật baseline --- 2026-09-27

Các thay đổi mới nhất đã được chốt:

-   Positioner là **cơ cấu chữ L**, không phải chữ U/yoke.
-   Kiến trúc NanoVNA hiện tại: **MATLAB R2025b → Python bridge →
    `NanoVNA_V2.py` → NanoVNA V2**.
-   Cách đóng gói `NanoVNA_V2.py` (dependency trực tiếp hay fork/tách
    riêng) vẫn **OPEN**.
-   **Anritsu MS46122B chỉ là future backend**; hiện tại chỉ có NanoVNA
    V2.
-   Hai antenna mảng 2.4 GHz sẽ đo với nhau và cũng là reference hiện
    tại; gain/reference pattern đã có sẽ dùng để so sánh/validation.
-   GUI phải cho nhập tần số tùy ý; 2.4 GHz là tần số trọng tâm.
-   **RECOMMENDED:** radiation-pattern scan dùng **S21 làm observable chính**;
    S11 dùng pre-check/matching diagnostic. Việc có đo S11 ở mọi angle hay
    không vẫn **OPEN**.
-   **Bỏ Digital Twin ROS2/Gazebo** khỏi phạm vi cần làm.
-   Homing thủ công là ưu tiên trước; auto-homing để nâng cấp sau.
-   AS5600 nằm trên **trục motor NEMA17**, không nằm trên output/antenna
    shaft.
-   MATLAB: **R2025b**.
-   Python version chưa khóa. **RECOMMENDED:** Python **3.11 64-bit** vì
    MATLAB R2025b hỗ trợ Python 3.9--3.12 và NanoVNA-Saver hiện yêu cầu
    Python >=3.10.
-   NanoVNA đang chạy **DiSlord v1.4.02 FPU**.
-   **VERIFIED (source):** SAA-2N/NanoVNA V2 dùng **USB CDC virtual serial
    port + binary register/FIFO protocol**, không phải NanoVNA V1 ASCII shell.
-   **VERIFIED (source):** dữ liệu `valuesFIFO` qua USB là dữ liệu raw,
    **không có user calibration trên máy được áp dụng**; PC-side calibration
    phải được thiết kế riêng nếu cần kết quả corrected.
-   ESP32 hiện mới có code test quay trục; chưa có communication/control
    protocol hoàn chỉnh.

------------------------------------------------------------------------

## Xác nhận bổ sung — chốt lần cuối

-   **Tên thiết bị chính xác:** NanoVNA **SAA-2N** — đã xác nhận đây là
    phần cứng S-A-A-2 thật (không phải NanoVNA-H/H4), khớp với phạm vi
    của NanoRFE UG1101. **VERIFIED (source):** Appendix II mô tả USB CDC
    + binary register/FIFO protocol của NanoVNA V2/S-A-A-2. Module
    `NanoVNA_V2.py` của NanoVNA-Saver là reference/driver phù hợp để thử
    reuse, nhưng compatibility thực tế với firmware DiSlord cụ thể vẫn
    phải được xác nhận trên thiết bị thật.
-   **Firmware DiSlord v1.4.02 FPU ↔ khả năng tương thích:** vì phần
    cứng đã xác nhận là S-A-A-2 thật, bộ lệnh cốt lõi (đọc/ghi register,
    FIFO, `deviceVariant = 0x02`) được kỳ vọng hoạt động đúng bất kể ai
    build firmware. Rủi ro còn lại chỉ ở mức hành vi biên (ví dụ cách
    phân biệt V2 thường với LiteVNA theo firmware version) — **chưa
    kiểm chứng bằng phép đo thật, cần xác nhận ngay ở lần thử bridge
    MATLAB→Python đầu tiên.**
-   **Khung chữ L:** đã **chế tạo xong phần cứng thật**, không còn là
    quyết định trên giấy.
-   **Nguồn/reference antenna GitHub cần phân biệt rõ:** repo
    `urmeo/Antenna` đã được tìm lại và xác nhận là benchmark **microstrip
    patch 2.45 GHz** (circular, F-shaped, triangular, square, hexagonal),
    có CST, chế tạo FR-4 và đo VNA thật. Tuy nhiên đây là **single-patch
    benchmark, không phải array**, và dữ liệu thực nghiệm công khai chủ yếu
    là **S11/VSWR**; main-lobe/radiation-pattern/gain trong repo chủ yếu là
    kết quả CST. Vì vậy repo này hữu ích để đối chiếu fabrication/S11 nhưng
    **không được coi là measured gain/pattern reference tuyệt đối**.
-   Nguồn GitHub chính xác của **hai antenna mảng vuông 2.4 GHz đang dùng
    trong hệ đo** vẫn phải được ghi riêng nếu chúng là một project khác.
-   **GUI tham khảo phần mềm thương mại (NSI-MI Arena, ASYSOFT):** vẫn
    là hướng tham khảo hợp lệ cho giao diện/tính năng dài hạn, nhưng
    là **việc tương lai**. Ưu tiên hiện tại là GUI tối giản, chạy được
    ngay, để tối ưu thời gian — không polish giao diện ở giai đoạn MVP.

------------------------------------------------------------------------

## 0. Executive Summary

Tôi đang xây dựng một **Automatic Direct Far-Field Antenna Measurement
System** sử dụng:

-   **VNA:** NanoVNA V2 S-A-A-2, khoảng 50 kHz--3 GHz; có hai đầu nối RF
    nhưng là **T/R VNA**, phù hợp đo S11 và forward S21, không phải full
    reciprocal 2-port VNA đo đủ S11/S21/S12/S22.
-   **VNA chính thức dự kiến:** Anritsu MS46122B-010, 1 MHz--8 GHz, 2
    port, SCPI/VISA, có calibration kit; **hiện chưa được cấp phép sử
    dụng**.
-   **MCU:** ESP32 DevKit V1.
-   **Motor driver:** TMC2209 rời.
-   **Angle sensor:** 2× AS5600.
-   **Mechanical positioner:** cơ cấu **chữ L**, 2 trục
    azimuth/elevation, truyền động GT2.
-   **Computer/software:** MATLAB là nền tảng chính; Python được dùng có
    chủ đích cho phần giao thức NanoVNA khi cần.
-   **Antenna target:** hiện có hai antenna mảng vuông 2.4 GHz; tương
    lai có thể dùng horn antenna in 3D.
-   **Mục tiêu gần:** đo radiation pattern 2D một mặt cắt, khoảng
    200--300 điểm, tại một tần số cố định.
-   **Mục tiêu dài hạn:** tự động đo 2D/3D radiation pattern, tính
    Gain/HPBW/SLL/Axial Ratio khi phần cứng và phương pháp đo đáp ứng.

Kiến trúc phần mềm hiện tại là **MATLAB chính + Python phụ có chủ
đích**, không còn là MATLAB thuần túy.

------------------------------------------------------------------------

# 1. Mục tiêu và phạm vi

## 1.1. Chức năng chính

Hệ thống hướng tới:

-   Tự động điều khiển VNA.
-   Tự động điều khiển positioner.
-   Đồng bộ góc quay và quá trình đo.
-   Đo S11.
-   Đo S21 khi cần.
-   Thu dữ liệu phức gồm magnitude/phase nếu giao thức cung cấp.
-   Lưu dữ liệu raw.
-   Xây dựng radiation pattern 2D.
-   Xây dựng radiation pattern 3D.
-   Chuẩn hóa dữ liệu theo dB.
-   Tính:
    -   Gain
    -   HPBW / 3-dB beamwidth
    -   SLL / Side-Lobe Level
    -   Axial Ratio
-   Xuất CSV.
-   Vẽ polar plot 2D.
-   Vẽ Cartesian plot.
-   Vẽ 3D pattern tương tác.

## 1.2. Đối tượng đo

Hiện tại:

-   Microstrip / patch / SIW antenna.
-   Dải quan tâm khoảng 1--3 GHz.
-   Trọng tâm: **2.4 GHz**.
-   Hiện đang có **hai antenna mảng vuông 2.4 GHz** để test hệ đo.

Tương lai:

-   Horn antenna in 3D.

------------------------------------------------------------------------

# 2. Phần cứng

  -----------------------------------------------------------------------
  Thành phần                          Hiện trạng / thông tin
  ----------------------------------- -----------------------------------
  VNA chính thức                      Anritsu MS46122B-010, 1 MHz--8 GHz,
                                      2 port, USB, SCPI, calibration kit;
                                      **chưa được cấp phép dùng**

  VNA prototype                       NanoVNA V2 S-A-A-2, T/R VNA,
                                      khoảng 50 kHz--3 GHz; S11 + forward S21

  MCU                                 ESP32 DevKit V1

  Motor driver                        TMC2209 rời

  Angle sensor                        2× AS5600

  Motor                               Stepper motor

  Transmission                        GT2 belt, ratio 16:90 (motor:shaft)

  Mechanical frame                    **L-shaped frame (chữ L), 2-axis**

  Fabrication                         3D printer + mechanical parts

  Power                               USB-C PD 65 W laptop charger + PD
                                      Trigger

  Logic power                         Buck converter riêng

  Computer                            PC1 Ryzen 5 PRO 4650U; PC2
                                      i5-12400F, 64 GB RAM, RX6600
  -----------------------------------------------------------------------

------------------------------------------------------------------------

# 3. Kiến trúc cơ khí

## 3.1. Khung

Kiểu khung chính:

-   **L-shaped frame / cơ cấu chữ L**.
-   Đây là kiến trúc cơ khí hiện tại; các mô tả cũ về khung chữ U/yoke
    không còn đúng.
-   Các dự án như WSU AUTPaTT/WSU V2 và Southampton Braccio chỉ còn giá
    trị tham khảo về cơ khí, điều khiển hoặc workflow; **không được xem
    là mô tả hình học của positioner hiện tại**.
-   Có thể dùng chi tiết in 3D, rod/shaft và các linh kiện cơ khí phù
    hợp với thiết kế chữ L.

## 3.2. Hai trục

Hai trục:

-   Azimuth.
-   Elevation.

Cả hai dùng:

-   GT2 belt.
-   Ratio: 16:90 răng, motor:trục.

## 3.3. Feedback góc

Dùng:

-   2× AS5600.
-   Gắn trên **trục động cơ NEMA17**, không nằm trên trục quay/output
    shaft của antenna.
-   Mục đích: closed-loop feedback.

### Rủi ro

AS5600 đặt trên motor không đo trực tiếp góc của output shaft.

Do đó sai số có thể đến từ:

-   Belt stretch.
-   Belt backlash.
-   Pulley tolerance.
-   Mechanical play.
-   Shaft coupling.

Đây là một điểm cần đánh giá khi validation.

## 3.4. Giới hạn quay

-   Tối đa khoảng 360°/trục do vướng dây RF.
-   Khi quét 2 trục cần có chiến lược tránh xoắn dây tích lũy.

## 3.5. Homing

Hiện tại không dùng:

-   Limit switch.
-   Hall sensor.

Homing thủ công:

1.  Dùng thanh thẳng xuyên qua trục chính + trục quay.
2.  Đưa cơ cấu về reference khoảng 90°.
3.  Bấm Cal trong phần mềm.

**Quyết định hiện tại:** homing thủ công là phương án **ưu tiên cho
prototype/MVP**. Cơ chế homing tự động là nâng cấp tương lai, không phải
yêu cầu hiện tại.

## 3.6. Nguồn motor

Nguồn:

-   USB-C PD 65 W.
-   20 V / 3.25 A.
-   PD Trigger chọn 5/9/12/15/20 V.
-   Cấp vào TMC2209.
-   Không dùng boost converter.

------------------------------------------------------------------------

# 4. Kiến trúc điện tử

``` text
USB-C PD
   │
   ├── PD Trigger ──> Motor supply ──> TMC2209 ──> Stepper
   │
   └── Buck converter ──> Logic supply
                              │
                              └── ESP32 DevKit V1
                                   ├── AS5600 #1
                                   ├── AS5600 #2
                                   └── TMC2209 control
```

ESP32 chịu trách nhiệm low-level:

-   Step timing.
-   Direction.
-   Motor movement.
-   Position feedback.
-   Homing/calibration logic.
-   Stop/emergency behavior.
-   Giao tiếp serial với MATLAB.

------------------------------------------------------------------------

# 5. Kiến trúc RF / measurement

Mục tiêu là **direct far-field measurement**, không dùng NF2FF.

Một kiến trúc đo khả dĩ:

``` text
NanoVNA Port 1
      │
      ▼
TX / reference antenna
      │
      │ free-space
      ▼
DUT / receiving antenna
      │
      ▼
NanoVNA Port 2
```

Tùy phương pháp đo cuối cùng, reference antenna có thể là antenna đã
biết gain hoặc antenna broadband phù hợp.

## 5.1. Far-field

Khoảng cách đo cần thỏa điều kiện far-field:

``` text
R > 2D² / λ
```

Trong đó:

-   `R`: khoảng cách giữa hai antenna.
-   `D`: kích thước/aperture lớn nhất của antenna.
-   `λ`: bước sóng.

Khoảng cách thực tế cần được xác định sau khi chốt antenna và kích thước
lớn nhất.

## 5.2. Các yếu tố cần kiểm soát

-   Multipath.
-   Reflection.
-   Polarization mismatch.
-   Cable coupling.
-   Cable movement.
-   Connector repeatability.
-   Noise floor.
-   Dynamic range.
-   VNA calibration.
-   Mechanical alignment.
-   Center-of-rotation.
-   Angular repeatability.
-   Backlash.
-   Vibration.

------------------------------------------------------------------------

# 6. Gain, reference và calibration

Không được coi raw S21 là antenna gain tuyệt đối.

Nếu sử dụng reference antenna:

1.  Đặt reference antenna vào vị trí DUT.
2.  Đo response.
3.  Thay reference bằng DUT.
4.  Giữ nguyên:
    -   khoảng cách,
    -   alignment,
    -   polarization,
    -   cable routing,
    -   vị trí cơ khí.
5.  Đo DUT.
6.  Dùng reference measurement để hỗ trợ phương pháp tính gain.

**OPEN:** Cần chốt chính xác phương pháp absolute gain / substitution
measurement trước khi đưa Gain vào kết quả chính thức.

## 6.1. Calibration cần tách thành

### VNA calibration

Ví dụ:

-   SOLT.
-   Calibration kit tương ứng.
-   Port extension nếu cần.

### System calibration

Có thể cần:

-   Cable loss.
-   Reference path.
-   Free-space path.
-   Reference antenna.

### Mechanical calibration

-   Zero/reference angle.
-   Homing.
-   Angle offset.
-   Alignment.
-   Center-of-rotation.

## 6.2. NanoVNA V2 USB data và calibration — VERIFIED

NanoRFE UG1101 ghi rõ `valuesFIFO` trả về các giá trị I/Q raw của các wave
đo được và **không áp user calibration đang lưu trên thiết bị**. Host cũng
không thể truy cập trực tiếp calibrated data/user calibration của máy qua
USB data interface.

Hệ quả cho project:

-   Không được giả định `CAL → SAVE 0` trên màn hình SAA-2N sẽ tự động làm
    cho dữ liệu FIFO mà Python/MATLAB đọc trở thành calibrated S11/S21.
-   Để có corrected S11/S21 ở phía PC, cần một calibration workflow ở
    software hoặc reuse calibration implementation đã có.
-   NanoVNA V2 là **T/R VNA**. Theo NanoVNA-QT manual:
    -   SOL dùng để correct S11;
    -   SOLT (T/R) dùng để correct S11 và forward S21 response.
-   Với MVP radiation pattern tương đối, có thể tách bài toán:
    1. kiểm tra matching/S11;
    2. thu S21 theo góc;
    3. normalize pattern về peak = 0 dB;
    4. absolute gain/calibrated path xử lý ở milestone sau.

------------------------------------------------------------------------

# 7. Axial Ratio

Axial Ratio không nên được tính đơn giản từ một đường S21 magnitude duy
nhất.

Cần có thông tin polarization, ví dụ:

-   Hai thành phần phân cực trực giao.
-   Hoặc một phương pháp xoay polarization/reference phù hợp.

**OPEN:** Chưa xác nhận phần cứng hiện tại đủ để đo AR đúng nghĩa.

------------------------------------------------------------------------

# 8. Software Architecture --- quyết định hiện tại

## 8.1. Kiến trúc tổng thể

``` text
                    MATLAB
                       │
             ┌─────────┴─────────┐
             │                   │
        Python bridge        ESP32 serial
             │                   │
     NanoVNA V2 driver       Positioner
             │                   │
        NanoVNA V2          TMC2209 + AS5600
```

### Quyết định

**MATLAB là nền tảng chính.**

Python được dùng **phụ có chủ đích**, chủ yếu để tái sử dụng driver
NanoVNA V2 đã có.

Không xây thêm:

-   TCP layer.
-   SCPI adapter giả.
-   Virtual COM layer.

Trừ khi xuất hiện lý do kỹ thuật mới.

## 8.2. Lý do chọn MATLAB làm trung tâm

MATLAB thuận lợi cho:

-   Serial control.
-   Numerical processing.
-   Signal/data processing.
-   Visualization.
-   Polar plot.
-   3D plotting.
-   App Designer.
-   Tích hợp VNA chuyên nghiệp sau này qua SCPI/VISA.

------------------------------------------------------------------------

# 9. NanoVNA V2 software strategy

## 9.1. Kiến trúc hiện tại

Không ưu tiên tự viết lại toàn bộ binary protocol NanoVNA V2 bằng MATLAB
`serialport()` ngay từ đầu.

Kiến trúc hiện tại:

```text
MATLAB R2025b
      │
      │ py.*
      ▼
nanovna_bridge.py
      │
      ▼
NanoVNA V2 driver
      │
      │ pyserial / USB CDC
      ▼
Windows COMx
      │
      ▼
SAA-2N
```

MATLAB giữ vai trò:

-   measurement orchestration;
-   motor synchronization;
-   GUI/App Designer;
-   processing;
-   visualization;
-   logging;
-   gain/pattern methodology.

Python chỉ nên chịu trách nhiệm:

-   open/close COM;
-   V2 handshake;
-   read/write register;
-   configure sweep;
-   read FIFO;
-   convert raw wave values thành complex S11/S21;
-   timeout/retry/error handling.

## 9.2. USB interface và protocol — VERIFIED

NanoRFE UG1101 xác nhận NanoVNA V2/S-A-A-2 xuất hiện trên PC dưới dạng
**USB CDC virtual serial port** trong normal mode và BOOTLOAD mode.

Protocol là **host-initiated binary protocol**:

-   không có text command separator;
-   device chỉ gửi dữ liệu để trả lời command từ host;
-   multi-byte integer là **little endian**.

Một số command cốt lõi:

| Opcode | Tên | Ý nghĩa |
|---|---|---|
| `0x00` | NOP | no operation |
| `0x0D` | INDICATE | device trả ASCII `'2'` (`0x32`) |
| `0x10` | READ | đọc register 1 byte |
| `0x11` | READ2 | đọc register 2 byte |
| `0x12` | READ4 | đọc register 4 byte |
| `0x18` | READFIFO | đọc N record từ FIFO |
| `0x20` | WRITE | ghi 1 byte |
| `0x21` | WRITE2 | ghi 2 byte |
| `0x22` | WRITE4 | ghi 4 byte |
| `0x23` | WRITE8 | ghi 8 byte |
| `0x28` | WRITEFIFO | ghi dữ liệu vào FIFO |

**Protocol nuance:** NanoRFE UG1101 không liệt kê opcode `0x13 READ8` trong
host-command table, trong khi `DiSlord/NanoVNA-App` có define
`CMD_V2_READ_8 = 0x13`. Vì vậy `READ8` phải được coi là implementation
detail/extension cần test, không phải requirement của minimal bridge.
Các register 64-bit cần thiết cho sweep có thể được ghi bằng official
`WRITE8 (0x23)`.

Handshake tối thiểu để test thiết bị:

```text
TX: 0x0D
RX: 0x32   # ASCII '2'
```

Đây nên là phép test đầu tiên trước khi chạy sweep.

## 9.3. Register map cốt lõi — VERIFIED

| Address | Register | Type | Vai trò |
|---|---|---|---|
| `0x00..0x07` | `sweepStartHz` | uint64 | start frequency |
| `0x10..0x17` | `sweepStepHz` | uint64 | frequency step |
| `0x20..0x21` | `sweepPoints` | uint16 | số point |
| `0x22..0x23` | `valuesPerFrequency` | uint16 | số data value / frequency |
| `0x26` | `rawSamplesMode` | uint8 | chuyển sang raw-sample mode |
| `0x30` | `valuesFIFO` | FIFO | measurement records |
| `0xF0` | `deviceVariant` | uint8 | V2 = `0x02` |
| `0xF1` | `protocolVersion` | uint8 | V2 wire protocol = `0x01` |
| `0xF2` | `hardwareRevision` | uint8 | hardware revision |
| `0xF3` | `firmwareMajor` | uint8 | firmware major |
| `0xF4` | `firmwareMinor` | uint8 | firmware minor |

Việc ghi sweep registers đưa thiết bị vào **USB data mode**, khi đó PC
điều khiển sweep. Manual cũng nói không thể đọc lại user-entered sweep
parameters trên UI thông qua các register này.

**Lưu ý cho firmware v1.4.02 FPU:** protocol family đã được xác nhận,
nhưng mapping giữa chuỗi version hiển thị `v1.4.02 FPU` và các byte
`firmwareMajor/firmwareMinor` phải được log từ thiết bị thật; không suy
diễn chỉ từ tên version trên màn hình.

## 9.4. FIFO record 32 byte — VERIFIED

Mỗi `valuesFIFO` record có **32 bytes**.

Phần **official UG1101** xác nhận:

```text
offset      field                type
0x00..03    fwd0Re               int32
0x04..07    fwd0Im               int32
0x08..0B    rev0Re               int32
0x0C..0F    rev0Im               int32
0x10..13    rev1Re               int32
0x14..17    rev1Im               int32
0x18..19    freqIndex            uint16
0x1A..1F    reserved             6 bytes
```

Trong **`DiSlord/NanoVNA-App` implementation**, cùng record 32 byte được
khai báo là:

```text
reserved[5] + checksum
```

tức byte cuối (`0x1F`) được app diễn giải như checksum. Vì UG1101 vẫn
đánh dấu `0x1A..0x1F` là reserved, bridge nên coi checksum này là
**DiSlord implementation behavior cần kiểm chứng**, không phải điều kiện
official protocol bắt buộc cho mọi NanoVNA V2 firmware.

Ngoài ra `valuesFIFO` được firmware liên tục fill. Nếu muốn acquisition
kiểu on-demand, official manual yêu cầu **clear stale FIFO trước khi đọc**
bằng cách ghi một giá trị bất kỳ vào địa chỉ FIFO `0x30`.

`DiSlord/NanoVNA-App` cũng định nghĩa maximum USB points cho V2/V2 Plus
là 1024 trong implementation của app; software của project không nên
hard-code một con số lớn hơn nếu chưa test hardware/firmware cụ thể.

## 9.5. Tính S11/S21 từ raw wave data — VERIFIED

Định nghĩa complex wave:

```text
FWD0 = fwd0Re + j*fwd0Im
REV0 = rev0Re + j*rev0Im
REV1 = rev1Re + j*rev1Im
```

Sau đó:

```text
S11 = REV0 / FWD0
S21 = REV1 / FWD0
```

Manual cảnh báo các complex values đọc trực tiếp có thể có random phase;
phải chia complex cho reference channel `FWD0` để lấy magnitude/phase có
ý nghĩa.

Điều này là lý do raw storage phải giữ **complex S11/S21**, không chỉ dB.

## 9.6. Calibration qua USB — VERIFIED

`valuesFIFO` **không chứa user-calibrated data**. User calibration lưu
trên máy không được áp vào FIFO và host không thể lấy calibrated data
trực tiếp từ on-device calibration.

Do đó cần phân biệt:

```text
on-device calibration
≠
PC-side USB acquisition calibration
```

Nếu cần corrected S21 để làm gain nghiêm túc, calibration phải được thực
hiện/áp dụng trong PC software hoặc thông qua một implementation được
reuse và đã kiểm chứng.

## 9.7. Driver/reference code hiện có

### NanoVNA-Saver

Repository:

```text
https://github.com/NanoVNA-Saver/nanovna-saver
```

Các bản/package của NanoVNA-Saver có module:

```text
NanoVNASaver/Hardware/NanoVNA_V2.py
```

Các issue lịch sử của chính repo cho thấy module này đã được dùng với
SAA-2N/NanoVNA V2 và có logic đọc version/FIFO.

NanoVNA-Saver hiện phát triển bằng Python 3, README hiện tại yêu cầu
**Python >= 3.10**.

### NanoVNA-Saver V2 support branch/fork

```text
https://github.com/nanovna/nanovna-saver-v2-support
```

Đây là reference lịch sử hữu ích để xem V2-specific implementation.

### DiSlord NanoVNA-App

```text
https://github.com/DiSlord/NanoVNA-App
```

File quan trọng:

```text
NanoVNA_v2_comms.h
```

Source này xác nhận opcode, FIFO struct và nhiều register constant, nên
rất hữu ích để kiểm tra chéo Python driver.

### DiSlord firmware

```text
https://github.com/DiSlord/NanoVNA-V2-firmware
```

Dùng làm reference cho behavior/firmware, không phải API Python.

## 9.8. Quyết định reuse driver

**OPEN — chưa chốt A/B:**

### A. Dùng NanoVNA-Saver như dependency

Ưu:

-   reuse tối đa;
-   ít code protocol tự sở hữu;
-   có calibration/measurement logic để tham khảo.

Nhược:

-   kéo dependency/app architecture không cần thiết;
-   API nội bộ có thể thay đổi;
-   MATLAB project phụ thuộc cấu trúc package NanoVNA-Saver.

### B. Tách/fork/extract minimal V2 driver

Ví dụ module project:

```text
python/
├── nanovna_bridge.py
├── nanovna_v2.py
└── tests/
```

Ưu:

-   API nhỏ;
-   MATLAB không phụ thuộc GUI/app state;
-   dễ test/recover;
-   dễ thay backend sau này.

Nhược:

-   phải duy trì code riêng;
-   cần chú ý license nếu copy/fork source GPL.

**RECOMMENDED:** về kiến trúc dài hạn, B sạch hơn; nhưng không coi đây là
quyết định cuối cùng cho đến khi proof-of-communication chạy thành công.

## 9.9. License

NanoVNA-Saver dùng GPL-3.0.

Nếu copy/fork trực tiếp code GPL vào project sẽ được phân phối/public,
cần xem nghĩa vụ GPL.

Một lựa chọn giảm coupling license là:

1. dùng official NanoRFE protocol specification;
2. dùng NanoVNA-Saver/DiSlord source để kiểm chứng behavior;
3. viết minimal implementation riêng dựa trên specification.

Quyết định license/project-distribution vẫn cần xem theo phạm vi thực tế.

## 9.10. MATLAB R2025b ↔ Python

MathWorks compatibility table xác nhận MATLAB R2025b hỗ trợ Python:

```text
3.9
3.10
3.11
3.12
```

NanoVNA-Saver hiện yêu cầu Python >=3.10.

**RECOMMENDED:** dùng **Python 3.11 64-bit** cho environment riêng của
project. Đây là recommendation, chưa khóa thành quyết định cuối cùng.

MATLAB có thể gọi Python qua:

```matlab
pyenv(...)
py.<module>.<function>(...)
```

## 9.11. InProcess hay OutOfProcess

**RECOMMENDED để thử đầu tiên:**

```matlab
pyenv(ExecutionMode="OutOfProcess")
```

Lý do:

-   serial/backend được cô lập khỏi MATLAB process;
-   thuận lợi hơn khi cần restart Python environment sau COM/driver error.

Không nên gọi Python cho từng byte. API phải coarse-grained:

```text
MATLAB → acquire_sweep()
Python → tự xử lý register/FIFO
Python → trả cả block frequency + complex S11/S21
```

Overhead của MATLAB↔Python khi đó không đáng kể so với sweep/motor time.

## 9.12. API contract đề xuất

```python
connect(port)
identify()
configure_sweep(start_hz, stop_hz, points, averages)
acquire_sweep()
acquire_at_frequency(freq_hz, averages)
disconnect()
```

`identify()` nên trả tối thiểu:

```text
deviceVariant
protocolVersion
hardwareRevision
firmwareMajor
firmwareMinor
port
```

`acquire_sweep()` nên trả:

```text
frequency[]
s11_complex[]
s21_complex[]
```

MATLAB **không** nên biết opcode/register/FIFO layout.

## 9.13. Proof-of-communication bắt buộc trước GUI

Thứ tự test:

1. Windows xác nhận `COMx`.
2. Python/pyserial mở port.
3. Gửi `INDICATE (0x0D)` → chờ `0x32`.
4. Đọc `0xF0..0xF4`.
5. Log raw identity/version.
6. Configure một sweep nhỏ quanh 2.4 GHz.
7. Đọc đúng N × 32 byte FIFO records.
8. Check `freqIndex`; nếu driver/firmware DiSlord sử dụng checksum byte
   thì validate checksum theo implementation, nhưng không coi checksum là
   field official UG1101.
9. Tính complex S11/S21.
10. So sánh cùng DUT với NanoVNA-QT hoặc NanoVNA-Saver.
11. Chỉ sau khi khớp mới đưa bridge vào MATLAB/App Designer.

## 9.14. S21 hay S11 cho radiation-pattern MVP

**Technical conclusion:**

-   Với kiến trúc TX antenna → free space → RX antenna → Port 2,
    **S21 là observable chính để dựng radiation pattern theo góc**.
-   S11 có giá trị để:
    -   kiểm tra matching;
    -   kiểm tra antenna/cable/connector trước scan;
    -   phát hiện setup bất thường.
-   Quét S11 theo góc **không thay thế** transmission-pattern measurement.

Do đó **RECOMMENDED MVP**:

```text
S11 = pre-check / health diagnostic
S21 = primary angle-scan data
```

Việc user có muốn lưu cả S11 ở từng góc hay chỉ đo trước scan vẫn **OPEN**.

## 9.15. Fixed-frequency acquisition

Không nhất thiết sweep 101/201 point ở mỗi góc nếu mục tiêu là pattern tại
2.4 GHz.

Có ba phương án:

1. single/CW-like point;
2. vài point quanh 2.4 GHz;
3. small-span sweep rồi chọn/average vùng quanh 2.4 GHz.

**RECOMMENDED cho MVP:** small-span hoặc vài point quanh 2.4 GHz trước,
vì dễ kiểm tra stability hơn single point tuyệt đối. Sau validation mới
tối ưu tốc độ.

Averaging nên ưu tiên trên **complex values** khi cần giữ phase:

```text
S21_avg = mean(S21_complex)
```

sau đó mới tính:

```text
magnitude_dB = 20*log10(abs(S21_avg))
phase = angle(S21_avg)
```

------------------------------------------------------------------------

# 10. Positioner software

ESP32 **chưa có protocol điều khiển hoàn chỉnh**. Hiện tại mới chỉ có
code test để quay trục/motor.

Kiến trúc dự kiến sau này là ESP32 cung cấp một protocol đơn giản để
MATLAB điều khiển.

Ví dụ:

``` text
HOME
MOVE 90
ANGLE 45
STOP
STATUS
```

Phía ESP32 xử lý:

-   stepper movement.
-   AS5600 feedback.
-   position reached.
-   stop.
-   status.

MATLAB xử lý:

-   high-level scan sequence.
-   trigger measurement.
-   data logging.
-   synchronization.

## 10.1. Synchronized measurement

``` text
MATLAB
  │
  ├── command ESP32 → target angle
  │
  ▼
ESP32 moves
  │
  ▼
AS5600 confirms position
  │
  ▼
ESP32 → POSITION_REACHED
  │
  ▼
Mechanical settling delay
  │
  ▼
MATLAB triggers NanoVNA measurement
  │
  ▼
NanoVNA sweep
  │
  ▼
MATLAB receives data
  │
  ▼
Save angle + frequency + complex measurement
  │
  ▼
Next angle
```

------------------------------------------------------------------------

# 11. Reuse / open-source strategy

Mục tiêu là **reuse tối đa**, không tự viết lại những phần đã có.

## 11.1. VNA

Ưu tiên:

-   NanoVNA-Saver `NanoVNA_V2.py`.

## 11.2. Motor

Có thể tái sử dụng:

-   TMCStepper.
-   Thư viện/driver AS5600.

Không cần tự viết driver thanh ghi từ đầu nếu thư viện đáp ứng yêu cầu.

## 11.3. Mechanical reference

Tham khảo:

-   WSU AUTPaTT.
-   WSU V2.
-   Southampton Braccio ở mức kiến trúc PC↔controller/VNA.

## 11.4. Pattern analysis

Hiện chưa có package open-source đã xác nhận phù hợp để cắm trực tiếp
cho toàn bộ:

-   Gain.
-   HPBW.
-   SLL.
-   AR.

Phần này dự kiến tự viết vì algorithm tương đối nhỏ và cần phù hợp với
dữ liệu đo thực tế.

------------------------------------------------------------------------

# 12. Mô phỏng / Digital Twin --- quyết định mới

**Digital Twin bằng ROS2/Gazebo đã được loại khỏi phạm vi hiện tại và
không còn cần thiết cho dự án.**

Lý do thực dụng: cơ cấu thật đã bắt đầu được chế tạo/test, thời gian dự
án hạn chế và ưu tiên hiện tại là hoàn thành chuỗi đo thật.

Fusion 360 vẫn có thể dùng như công cụ CAD để:

-   kiểm tra kích thước;
-   kiểm tra va chạm;
-   hoàn thiện cơ cấu chữ L;
-   kiểm tra pulley/belt và chi tiết in 3D.

Một **FakeVNA/mock data** nhỏ trong software vẫn có thể hữu ích để test
thuật toán hoặc GUI nếu cần, nhưng đây không phải Digital Twin và không
phải milestone bắt buộc.

------------------------------------------------------------------------

# 13. Data architecture

Không chỉ lưu plot. Phải lưu raw numerical data.

Đề xuất:

``` text
measurement/
├── metadata
│   ├── frequency
│   ├── points
│   ├── angle_step
│   ├── distance
│   ├── antenna_info
│   └── calibration_info
│
├── angle
├── frequency
├── S11
├── S21
├── magnitude
├── phase
│
└── processed
    ├── gain
    ├── HPBW
    ├── SLL
    └── AR
```

Nên có thêm:

-   timestamp.
-   VNA model / COM port.
-   `deviceVariant`, `protocolVersion`, `hardwareRevision`.
-   firmware version.
-   software/driver version.
-   motor position thực tế và target angle.
-   azimuth/elevation convention.
-   calibration state / calibration file.
-   measurement configuration.
-   antenna TX/RX identifiers.
-   polarization.
-   antenna separation.
-   cable identifiers/routing notes.
-   room/environment notes.

**Bắt buộc giữ complex data** thay vì chỉ dB:

```text
frequency
S11_real
S11_imag
S21_real
S21_imag
S11_dB
S21_dB
S11_phase
S21_phase
```

Processed data có thể tái tạo lại từ raw complex data; ngược lại không
thể phục hồi phase/calibration information đầy đủ nếu chỉ lưu plot/dB.

------------------------------------------------------------------------

# 14. Radiation pattern analysis

## 14.1. Normalization

Pattern thường được đưa về:

``` text
Peak = 0 dB
```

sau đó biểu diễn theo góc.

## 14.2. HPBW

Quy trình:

1.  Tìm main-lobe peak.
2.  Tìm hai điểm giao với `-3 dB`.
3.  Nội suy nếu sample angle không trùng chính xác.
4.  Tính:

``` text
HPBW = theta2 - theta1
```

## 14.3. SLL

Cần:

1.  Xác định main lobe.
2.  Xác định boundary/null hoặc logic phân vùng phù hợp.
3.  Tìm side-lobe peak.
4.  Tính mức side-lobe tương đối với main-lobe peak.

Cần tránh nhầm:

-   main-lobe shoulder.
-   back lobe.
-   noise peak.

## 14.4. Gain

Cần reference/calibration methodology hợp lệ.

Không dùng:

``` text
Gain = raw S21
```

## 14.5. Axial Ratio

Cần polarization measurement.

Không nên tuyên bố AR từ một scalar S21 magnitude curve nếu không có đủ
thông tin phân cực.

------------------------------------------------------------------------

# 15. GUI dự kiến

Cuối cùng có thể dùng MATLAB App Designer.

**Ưu tiên hiện tại:** GUI tối giản, chạy được ngay để tối ưu thời gian
MVP — không polish giao diện ở giai đoạn này.

**Tham khảo tương lai (không phải bây giờ):** giao diện/tính năng của
phần mềm thương mại NSI-MI Arena (MI-3000) và ASYSOFT — đã được dùng
làm nguồn cảm hứng ban đầu để chọn hướng MATLAB App Designer, dự kiến
quay lại tham khảo khi làm bản GUI hoàn chỉnh sau MVP.

Các thành phần:

### Connection

-   NanoVNA status.
-   Python bridge status.
-   ESP32 status.

### Measurement setup

-   Start frequency.
-   Stop frequency.
-   Number of points.
-   Measurement frequency.
-   Angle step.
-   Distance.
-   Antenna/reference configuration.

### Control

-   HOME.
-   CALIBRATE.
-   START.
-   STOP.
-   EMERGENCY STOP.

### Visualization

-   S11.
-   S21.
-   Polar pattern.
-   Cartesian pattern.
-   3D pattern.

### Results

-   Gain.
-   HPBW.
-   SLL.
-   AR.

### Export

-   CSV.
-   MAT.
-   Figure/image nếu cần.

------------------------------------------------------------------------

# 16. Phát triển theo MVP

## Giai đoạn 1 --- chứng minh hệ thống 2D

Thời gian thực tế hiện bị giới hạn khoảng **1--2 tuần**, nên ưu tiên một
MVP nhỏ.

Mục tiêu:

-   Một trục azimuth.
-   Một tần số cố định.
-   Khoảng 200--300 điểm.
-   Radiation pattern 2D.

### Đã xác nhận

-   Azimuth đã quay ổn định qua serial.
-   AS5600 feedback đã hoạt động.
-   Cơ khí + code trục azimuth đã được test.
-   Chuyển động được đánh giá là ổn định/mượt.

### Việc quan trọng còn lại

-   Thử Python → USB CDC → SAA-2N trước khi ghép MATLAB:
    -   `INDICATE 0x0D → 0x32`;
    -   đọc `0xF0..0xF4`;
    -   sweep nhỏ quanh 2.4 GHz;
    -   đọc FIFO 32-byte records;
    -   tính S11/S21.
-   So sánh measurement với NanoVNA-QT/NanoVNA-Saver trên cùng DUT.
-   Sau đó thử MATLAB → Python bridge → measurement block.
-   Sau đó mới tích hợp với vòng quét góc.
-   **RECOMMENDED:** S21 là dữ liệu chính của radiation-pattern scan;
    S11 dùng pre-check/matching diagnostic. Việc có lưu/đo S11 tại mọi
    angle hay không vẫn **OPEN**.

### Scan loop

Ví dụ:

``` text
360° / 250 points ≈ 1.44° / step
```

Quy trình:

``` text
target angle
    ↓
move
    ↓
AS5600 confirms
    ↓
settling
    ↓
measure
    ↓
save complex data
    ↓
next angle
```

### GUI MVP

Chỉ cần:

-   Connect.
-   Start.
-   Stop.
-   Angle step.
-   Polar plot real-time.
-   Export CSV.

------------------------------------------------------------------------

# 17. Giai đoạn 2 --- 3D

Sau khi Giai đoạn 1 thành công:

-   Thêm elevation.
-   Scan θ-φ.
-   Dùng zigzag / boustrophedon để hạn chế xoắn dây.
-   Dựng 3D pattern.

Có thể dùng:

``` text
sph2cart
surf
```

Mục tiêu dài hạn:

-   Khoảng 1000 điểm.
-   Tăng dần angular resolution.

------------------------------------------------------------------------

# 18. Lộ trình cũ và lộ trình đã cập nhật

## Lộ trình cũ

``` text
A Python + Git
→ B Arduino 2-axis
→ C Fusion 360
→ D ROS2/Gazebo
→ E Fake VNA
→ F đọc S11/S21 từ MS46122B
→ G pattern 2D
→ H pattern 3D
```

## Lộ trình cập nhật

``` text
A. NanoVNA V2 + Python bridge
        ↓
B. MATLAB đọc được measurement thật
        ↓
C. Azimuth scan 2D
        ↓
D. Radiation pattern 2D
        ↓
E. HPBW / SLL cơ bản
        ↓
F. Reference/gain methodology
        ↓
G. Elevation axis
        ↓
H. 3D pattern
        ↓
I. Axial Ratio
        ↓
J. App Designer GUI hoàn chỉnh
        ↓
K. Validation
        ↓
L. Có thể chuyển sang Anritsu MS46122B khi được cấp phép
```

------------------------------------------------------------------------

# 19. Anritsu MS46122B --- future upgrade path

Anritsu MS46122B-010 là VNA mục tiêu cho phiên bản chính thức nếu được
cấp phép.

Lợi thế kiến trúc hiện tại:

-   MATLAB đã là software center.
-   Sau này có thể dùng SCPI/VISA cho Anritsu.
-   Phần positioner/analysis/GUI có thể giữ nguyên.
-   Chỉ thay hoặc thêm VNA backend.

Nên thiết kế software theo abstraction:

``` text
VNA interface
   │
   ├── NanoVNA backend
   │      └── Python bridge
   │
   └── Anritsu backend
          └── SCPI/VISA
```

------------------------------------------------------------------------

# 20. Rủi ro

## 20.1. Cơ khí

-   Backlash.
-   Belt error.
-   Rung.
-   Lệch tâm.
-   AS5600 ở motor thay vì output shaft.

## 20.2. RF

-   Multipath.
-   Reflection.
-   Cable coupling.
-   Cable phase change.
-   Polarization mismatch.
-   Noise floor.
-   Dynamic range.

## 20.3. Đồng bộ

-   Motor chưa settle nhưng đã đo.
-   Position feedback sai.
-   Measurement data lệch angle.

## 20.4. Cable management

Đặc biệt khi 2 trục cùng quay:

-   Cable twist.
-   Cable tension.
-   Phase variation.
-   Mechanical drag.

Cần scan strategy phù hợp.

## 20.5. AR

Chưa xác nhận phần cứng đáp ứng yêu cầu polarization measurement.

------------------------------------------------------------------------

# 21. RF absorber đang nghiên cứu

Đang cân nhắc vật liệu rẻ hơn foam pyramidal thương mại:

-   Ferrite tile.
-   ESD foam.

Mục tiêu:

-   Giảm reflection.
-   Giảm multipath.

Cần đánh giá thực nghiệm tại khoảng 2.4 GHz trước khi coi là RF absorber
phù hợp.

------------------------------------------------------------------------

# 22. Antenna và phương án reference hiện tại

## 22.1. Hai antenna mảng 2.4 GHz

Hiện có **hai antenna mảng vuông 2.4 GHz** và chúng sẽ được dùng như
**khối đo với nhau** trong hệ thống.

Measurement architecture:

```text
NanoVNA Port 1
      ↓
TX antenna
      ↓ free space
RX antenna
      ↓
NanoVNA Port 2
```

Với architecture này, **S21 theo góc** là dữ liệu trực tiếp để xây
relative transmission/radiation pattern của setup.

Hai antenna hiện tại cũng có thể tham gia reference/substitution
methodology khi gain/reference data của chúng đủ tin cậy, nhưng không
được tự động đồng nhất:

```text
raw S21
=
absolute antenna gain
```

Nguồn GitHub chính xác của **hai antenna mảng vuông hiện đang có** cần
được ghi riêng nếu chưa lưu trong project notes, cùng với:

-   geometry;
-   substrate;
-   feed;
-   measured gain;
-   measured 2D/3D pattern;
-   measurement distance;
-   calibration method;
-   chamber/open-range environment.

## 22.1.1. Benchmark GitHub đã tìm lại: `urmeo/Antenna`

Repository:

```text
https://github.com/urmeo/Antenna
```

Tên hiện tại:

```text
Microstrip Patch Antenna 2.45 GHz Benchmark
```

Repo có **năm single-patch geometries**:

-   circular;
-   F-shaped;
-   triangular;
-   square;
-   hexagonal.

Nó **không phải antenna array**.

Repo cung cấp:

-   CST simulation;
-   source/macro CST;
-   FR-4 fabrication;
-   ảnh/quy trình chế tạo;
-   Rohde & Schwarz ZVH VNA measurement;
-   measured S11/VSWR;
-   simulation-vs-measurement comparison;
-   documentation và analysis tooling.

Điểm cần phân biệt khi dùng để validation:

-   **Measured thực nghiệm công khai:** chủ yếu S11/VSWR.
-   **Far-field main-lobe / side-lobe / gain-pattern values:** chủ yếu
    từ CST simulation trong repo.
-   Vì vậy repo này rất tốt để kiểm tra reproduction/fabrication/S11,
    nhưng **không đủ một mình để làm ground-truth measured radiation
    pattern/gain cho hệ positioner**.

Do đó master phải coi `urmeo/Antenna` là **external benchmark/reference
project riêng**, không tự động coi nó là nguồn của hai antenna mảng đang
dùng.

## 22.2. Tần số

-   Tần số trọng tâm: **2.4 GHz**.
-   GUI phải cho phép người dùng **nhập/chọn tần số tùy ý** trong phạm
    vi phần cứng và measurement setup cho phép.
-   MVP có thể bắt đầu tại 2.4 GHz nhưng software không được hard-code
    chỉ một tần số.

## 22.3. Horn antenna

Hướng tương lai:

-   Horn antenna in 3D.
-   Có thể nghiên cứu metallization/coating sau.

## 22.4. Quan hệ với BTL Truyền sóng và Anten

BTL Truyền sóng và Anten:

-   antenna in phẳng trên PCB;
-   FR4;
-   dưới 5 GHz.

Quan hệ chính xác giữa antenna BTL và hai antenna mảng của hệ đo vẫn có
thể được cập nhật sau nếu cần.

------------------------------------------------------------------------

# 23. Validation plan

Không chỉ kiểm tra "chạy được".

Cần kiểm tra:

### Mechanical

-   Repeatability.
-   Angle accuracy.
-   Backlash.
-   Zero offset.

### VNA

-   USB handshake `0x0D → 0x32`.
-   Read/record `0xF0..0xF4`.
-   FIFO packet-length/integrity check.
-   Repeatability.
-   S11/S21 stability.
-   Compare custom bridge với NanoVNA-QT/NanoVNA-Saver trên cùng DUT.
-   Calibration.
-   Xác minh rõ dữ liệu nào là raw và dữ liệu nào đã PC-side corrected.

### RF

-   Noise floor.
-   Multipath.
-   Cable effects.
-   Distance/far-field.

### Measurement

-   Repeated scan.
-   Reference antenna.
-   Comparison with known result.
-   Comparison with simulation/datasheet/lab measurement khi có.

### Software

-   FakeVNA.
-   Known synthetic pattern.
-   Unit tests cho HPBW/SLL.
-   Data integrity.
-   Angle/data synchronization.

------------------------------------------------------------------------

# 24. Các quyết định hiện tại

  -----------------------------------------------------------------------
  Hạng mục                            Quyết định
  ----------------------------------- -----------------------------------
  Measurement type                    Direct far-field

  Main frequency                      2.4 GHz

  Prototype VNA                       NanoVNA V2 S-A-A-2, T/R VNA

  Future VNA                          Anritsu MS46122B nếu được cấp phép

  Main software                       MATLAB R2025b

  Python                              Có, bridge/reuse layer có chủ đích;
                                      3.11 64-bit RECOMMENDED, chưa khóa

  NanoVNA protocol                    V2 binary register/FIFO VERIFIED;
                                      `NanoVNA_V2.py` là reference/reuse
                                      candidate; packaging A/B vẫn OPEN

  TCP                                 Không

  Virtual COM                         Không

  Fake SCPI adapter                   Không

  MCU                                 ESP32 DevKit V1

  Motor driver                        TMC2209

  Position sensor                     AS5600

  Mechanical frame                    **L-shaped frame / chữ L**

  Drive                               GT2 belt

  Homing                              **Manual ưu tiên cho MVP;
                                      auto-homing là nâng cấp tương lai**

  First MVP                           2D azimuth scan; S21 là primary
                                      observable RECOMMENDED; S11 pre-check,
                                      per-angle S11 vẫn OPEN

  First scan size                     200--300 points

  Long-term                           3D, \~1000 points

  GUI                                 MATLAB App Designer

  NF2FF                               Không

  Raw data                            Bắt buộc lưu

  Gain                                Chưa chốt methodology cuối

  AR                                  Chưa chốt hardware/method

  RF absorber                         Đang nghiên cứu
  -----------------------------------------------------------------------

------------------------------------------------------------------------

# 25. Các vấn đề còn OPEN sau cập nhật 2026-09-27

Các mục dưới đây **chưa được chốt** và AI khác không được tự suy diễn:

1.  `NanoVNA_V2.py`: dùng trực tiếp NanoVNA-Saver như dependency hay
    fork/tách thành module riêng? (**B/tách minimal driver được RECOMMENDED
    về kiến trúc, nhưng chưa chốt**.)
2.  MATLAB R2025b ↔ Python: **Python 3.11 64-bit được RECOMMENDED**;
    environment/dependency lock cụ thể vẫn cần test.
3.  DiSlord v1.4.02 FPU ↔ V2 driver: protocol family/register/FIFO đã
    VERIFIED theo S-A-A-2, nhưng **compatibility thực tế qua handshake,
    version read và sweep đầu tiên vẫn chưa kiểm chứng**.
4.  S21 đã được xác định về mặt kỹ thuật là **primary observable cho
    radiation-pattern transmission scan**. OPEN còn lại là có đo/lưu S11
    tại từng angle hay chỉ dùng S11 làm pre-check.
5.  Protocol MATLAB ↔ ESP32 cuối cùng dùng ASCII hay binary?
6.  ESP32 hiện mới ở mức test quay trục; command set, feedback packet và
    state machine chưa được thiết kế hoàn chỉnh.
7.  Angular convention 0°/90° và hệ tọa độ azimuth/elevation cuối cùng
    chưa được ghi nhận là đã chốt.
8.  Scan MVP sẽ dùng toàn bộ 360° hay một khoảng góc nhỏ hơn?
9.  Khoảng cách giữa hai antenna và kích thước aperture lớn nhất cần
    được xác định để kiểm tra far-field.
10. Gain extraction/reference methodology cụ thể vẫn cần được chốt dù
    antenna reference đã có gain.
11. Repo `urmeo/Antenna` đã được ghi lại như **single-patch benchmark
    2.45 GHz**, không phải array và không cung cấp measured far-field
    pattern/gain ground truth đầy đủ. **Nguồn chính xác + measurement
    conditions của hai antenna mảng vuông hiện tại vẫn cần được ghi riêng**
    nếu đó là một project khác.
12. Axial Ratio vẫn là chức năng dài hạn; hardware/method polarization
    chưa chốt.
13. Mức validation cuối cùng mong muốn: prototype/demo, engineering
    validation hay research-grade vẫn cần làm rõ khi dự án tiến xa hơn.

------------------------------------------------------------------------

# 26. Master instruction cho AI khác

Khi tiếp tục hỗ trợ dự án này:

-   Ưu tiên các quyết định mới nhất trong tài liệu.
-   Không tự ý quay lại kiến trúc Python-only hoặc
    MATLAB-direct-to-NanoVNA nếu chưa có lý do kỹ thuật mới.
-   Hiện tại kiến trúc NanoVNA là **MATLAB R2025b → Python bridge →
    `NanoVNA_V2.py` → NanoVNA V2**.
-   Ưu tiên reuse code open-source đã tồn tại.
-   NanoVNA V2 protocol đã được VERIFIED từ NanoRFE UG1101 và source
    DiSlord; không tự phát minh protocol khác.
-   Trước mắt dùng `NanoVNA_V2.py`/NanoVNA-Saver và DiSlord source làm
    reference; dependency trực tiếp hay tách minimal driver vẫn OPEN.
-   Luôn nhớ FIFO USB là **raw, không có on-device user calibration**.
-   Không coi raw S21 là absolute gain.
-   Không tính Axial Ratio từ một scalar magnitude curve nếu chưa có
    thông tin polarization.
-   Không bắt đầu bằng GUI phức tạp trước khi acquisition backend chạy
    ổn.
-   Luôn giữ raw data.
-   Phân biệt rõ:
    -   simulation,
    -   functional prototype,
    -   validated measurement.
-   Khi có điểm chưa chốt, hỏi người dùng thay vì tự giả định.

------------------------------------------------------------------------

# 27. Tài liệu và repository đã kiểm tra

## 27.1. Protocol / official documentation

1. **NanoRFE — NanoVNA V2 User Manual (UG1101)**  
   https://www.nanorfe.com/nanovna-v2-user-manual.html

   Dùng để xác nhận:
   - S-A-A-2/NanoVNA V2 scope;
   - USB CDC virtual serial;
   - binary command set;
   - register map;
   - USB data mode;
   - 32-byte FIFO format;
   - raw FIFO không áp user calibration;
   - reference-channel complex division;
   - SOL/SOLT behavior trong NanoVNA-QT.

## 27.2. Firmware / communication implementation

2. **DiSlord — NanoVNA-V2-firmware**  
   https://github.com/DiSlord/NanoVNA-V2-firmware

3. **DiSlord — NanoVNA-App**  
   https://github.com/DiSlord/NanoVNA-App

4. **DiSlord — `NanoVNA_v2_comms.h`**  
   https://github.com/DiSlord/NanoVNA-App/blob/main/NanoVNA_v2_comms.h

   Dùng để kiểm tra chéo opcode, FIFO struct, USB-point limits và register
   constants.

## 27.3. Python / driver reference

5. **NanoVNA-Saver**  
   https://github.com/NanoVNA-Saver/nanovna-saver

6. **NanoVNA-Saver V2 support fork**  
   https://github.com/nanovna/nanovna-saver-v2-support

7. **Issue #365 — SAA-2N connection / USB MODE behavior**  
   https://github.com/NanoVNA-Saver/nanovna-saver/issues/365

8. **Issue #396 — V2 version-register timeout**  
   https://github.com/NanoVNA-Saver/nanovna-saver/issues/396

9. **Issue #317 — segmented calibration/V2 behavior**  
   https://github.com/NanoVNA-Saver/nanovna-saver/issues/317

Các issue lịch sử này không phải specification; chúng được dùng để thiết
kế timeout/retry/state handling và test compatibility.

## 27.4. Antenna measurement automation

10. **realraum/antpatt — Antenna Pattern Measurement System**  
    https://github.com/realraum/antpatt

    Ví dụ thực tế của workflow NanoVNA + rotor + automated pattern
    acquisition. Repo dùng modified NanoVNA-Saver/command-line workflow;
    project hiện tại không cần copy architecture này nguyên xi.

11. **qrp73/NanoVNA-MATLAB**  
    https://github.com/qrp73/NanoVNA-MATLAB

    Hữu ích để tham khảo MATLAB workflow, nhưng không được giả định tương
    thích S-A-A-2 nếu phần giao tiếp dựa trên NanoVNA V1 ASCII commands.

## 27.5. Antenna benchmark/reference

12. **urmeo/Antenna — Microstrip Patch Antenna 2.45 GHz Benchmark**  
    https://github.com/urmeo/Antenna

    Có CST + FR-4 fabrication + VNA S11/VSWR measurement cho năm
    single-patch geometries. Không phải array; far-field/gain values chủ
    yếu là simulation, nên không coi là measured pattern ground truth.

## 27.6. MATLAB / Python

13. **MathWorks — Versions of Python Compatible with MATLAB Products by Release**  
    https://www.mathworks.com/support/requirements/python-compatibility.html

14. **MathWorks — `pyenv`**  
    https://www.mathworks.com/help/matlab/ref/pyenv.html

15. **MathWorks — Out-of-process execution of Python**  
    https://www.mathworks.com/help/matlab/matlab_external/out-of-process-execution-of-python-functionality.html

------------------------------------------------------------------------

# 28. Immediate next technical milestone

Không bắt đầu bằng GUI lớn.

Milestone tiếp theo phải tạo được một log tương tự:

```text
PORT = COMx

INDICATE:
TX 0D
RX 32
PASS

IDENTITY:
deviceVariant    = 0x02
protocolVersion  = 0x01
hardwareRevision = ...
firmwareMajor    = ...
firmwareMinor    = ...

SWEEP:
start  = ...
step   = ...
points = ...

FIFO:
expected_records = N
received_records = N
packet_size      = 32
reserved/checksum behavior = ...
errors           = ...

RESULT:
frequency[]
S11_complex[]
S21_complex[]
```

Sau đó:

1. đo một DUT/cable/thru ổn định;
2. export kết quả;
3. so sánh với NanoVNA-QT hoặc NanoVNA-Saver;
4. chỉ khi sai số/behavior đã hiểu rõ mới nối sang MATLAB;
5. sau đó mới ghép vòng quay azimuth.

Đây là gate quan trọng nhất trước khi phát triển tiếp GUI và pattern
automation.

