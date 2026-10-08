# 🔬 Vivaldi Antenna PCB — Các Project Open-Source & Workflow Nhanh Nhất

> **Mục tiêu:** Tìm project Vivaldi antenna có file sẵn để gửi gia công PCB, hoặc có file simulation/design chuyển sang PCB nhanh nhất.

> **CẬP NHẬT:** Phát hiện 2 project cực kỳ quan trọng: **ifrht/vivaldi-antenna** (0.8–3 GHz, KiCad + Gerber, ĐÃ FABRICATE, BÁO CÁO ĐO) và **csondurr/wideband-vivaldi-antenna-balun** (2–6 GHz, CST + Gerber, MIT license).

---

## ⚡ TL;DR — Bảng Xếp Hạng Theo Thời Gian

| Rank | Project / Workflow | Thời gian đến đặt PCB | Có file sẵn? | Covers 2.4 GHz? |
|---|---|---|---|---|
| 🥇⭐ | **ifrht/vivaldi-antenna** | **~10 phút!** (Gerber sẵn) | ✅ **KiCad + Gerber + Report** | ✅ **0.8–3 GHz** |
| 🥈⭐ | **csondurr wideband-vivaldi-balun** | **~10 phút!** (Gerber ZIP sẵn) | ✅ **CST + Gerber ZIP** | ✅ **2–6 GHz** |
| 🥉 | **MyriadRF Vivaldi** | ~30 phút (KiCad → Gerber) | ✅ KiCad + Gerber + Measured | ❌ 5.5/10 GHz |
| 4 | **HugoTronics Antipodal Vivaldi** | ~1–2 giờ (DXF → KiCad → Gerber) | ✅ DXF + CST + STL | ⚠️ 4G/5G band |
| 5 | **rookiepeng/antenna-models** | ~2–4 giờ (CST → DXF → KiCad) | ✅ CST file | ❌ 5.8 GHz |
| 6 | **Python DXF Generator** | ~2–3 giờ (script → DXF → KiCad) | ✅ Code tự generate | ✅ Tùy chỉnh |
| 7 | **changpuak.ch Calculator** | ~3–4 giờ (calc → dimensions → KiCad) | ✅ Online tool | ✅ Tùy chỉnh |
| 8 | **MATLAB Antenna Toolbox** | ~2–3 giờ (nếu có license) | ✅ `gerberWrite()` | ✅ `design(vivaldi, 2.4e9)` |

> [!IMPORTANT]
> **PHÁT HIỆN MỚI:** 2 project đầu tiên (**ifrht** và **csondurr**) có **Gerber files sẵn sàng** và **COVER 2.4 GHz**. Bạn có thể download Gerber → upload JLCPCB → đặt hàng ngay lập tức!

---

## 🏆🏆 Project #0a: ifrht/vivaldi-antenna — **KHUYẾN NGHỊ SỐ 1**

**⭐ Project PHÙ HỢP NHẤT: 0.8–3 GHz, KiCad + Gerber READY, ĐÃ FABRICATE, có ảnh PCB thật!**

| Mục | Chi tiết |
|---|---|
| **Tên** | vivaldi-antenna |
| **GitHub** | [ifrht/vivaldi-antenna](https://github.com/ifrht/vivaldi-antenna) |
| **Loại** | Standard Vivaldi |
| **Frequency range** | **0.8 GHz – 3.0 GHz** ← COVER 2.4 GHz! |
| **VSWR** | < 2.5 across band |
| **PCB material** | FR4, 2-layer |

### Files có sẵn:
| File type | Có? | Ghi chú |
|---|---|---|
| **KiCad project (.kicad_pcb)** | ✅ | `vivaldi.kicad_pcb` |
| **Gerber files (.gbr, .drl)** | ✅ | `gerber/` folder — **SẴN SÀNG GỬI JLCPCB** |
| **PDF Report** | ✅ | `Report.pdf` — có thể chứa S11/pattern data |
| **Photos of fabricated PCB** | ✅ | `Product/on.jpg`, `Product/arka.jpg` |

### Workflow — NHANH NHẤT:
```
1. git clone https://github.com/ifrht/vivaldi-antenna
2. Lấy tất cả file trong thư mục gerber/
3. Upload lên JLCPCB
4. Đặt hàng
⏱️ Thời gian: ~10 PHÚT
```

> [!TIP]
> Đây là **project duy nhất** tìm được có đồng thời: Gerber sẵn + cover 2.4 GHz + đã fabricate thực tế + có ảnh prototype. **Khuyến nghị mạnh nhất.**

---

## 🏆🏆 Project #0b: csondurr/wideband-vivaldi-antenna-balun — **Runner-up**

**⭐ Vivaldi + Balun riêng, 2–6 GHz, Gerber ZIP sẵn, MIT License, thiết kế chất lượng cao.**

| Mục | Chi tiết |
|---|---|
| **Tên** | wideband-vivaldi-antenna-balun |
| **GitHub** | [csondurr/wideband-vivaldi-antenna-balun](https://github.com/csondurr/wideband-vivaldi-antenna-balun) |
| **Loại** | Balanced tapered-slot Vivaldi + wideband microstrip-to-slotline balun |
| **Frequency range** | **2.0 GHz – 6.0 GHz** ← COVER 2.4 GHz! |
| **Gain (SIMULATED)** | 7.16 dBi @ 2 GHz, 8.79 dBi @ 4 GHz |
| **PCB material** | ⚠️ Thiết kế cho **RO4350B** (1.524 mm) — KHÔNG phải FR4 |
| **Kích thước** | 155 mm × 215 mm |
| **License** | **MIT License** |

### Files có sẵn:
| File type | Có? | Ghi chú |
|---|---|---|
| **CST project (.cst)** | ✅ | Full simulation model |
| **Gerber ZIP (Vivaldi)** | ✅ | `VivaldiGerber.zip` — sẵn sàng! |
| **Gerber ZIP (Balun)** | ✅ | `BalunGerber.zip` — balun riêng |

### Workflow:
```
1. git clone https://github.com/csondurr/wideband-vivaldi-antenna-balun
2. Unzip VivaldiGerber.zip
3. Upload lên JLCPCB
4. Đặt hàng
⏱️ Thời gian: ~10 PHÚT
```

> [!WARNING]
> **Chú ý:** Project này thiết kế cho **RO4350B** (εr ≈ 3.48), KHÔNG phải FR4 (εr ≈ 4.4). Nếu bạn đặt trên **FR4**, tần số sẽ bị **dịch xuống** do εr cao hơn. Đây có thể là acceptable cho mục đích đo antenna, nhưng performance sẽ không match chính xác với simulation.
>
> **Chưa fabricate thực tế** — tác giả ghi rõ: "Physical prototype, VNA, gain and radiation-pattern measurements are still required."

---

## 🏆 Project #1: HugoTronics — Antipodal Vivaldi Antenna Design

**Project hoàn thiện nhất với nhiều loại file nhất.**

| Mục | Chi tiết |
|---|---|
| **Tên** | Vivaldi-Antipodal-Antenna-Design |
| **GitHub** | [HugoTronics/Vivaldi-Antipodal-Antenna-Design](https://github.com/HugoTronics/Vivaldi-Antipodal-Antenna-Design) |
| **Loại** | **Antipodal Vivaldi** (không cần balun — feed trực tiếp bằng microstrip!) |
| **Frequency range** | Wideband, thiết kế cho 4G/5G |
| **PCB material** | FR4 |
| **Số lớp** | 2-layer |

### Files có sẵn:
| File type | Có? | Ghi chú |
|---|---|---|
| **DXF (TOP layer)** | ✅ | Copper pattern mặt trên |
| **DXF (BOT layer)** | ✅ | Copper pattern mặt dưới |
| **DXF (EDGE cuts)** | ✅ | Board outline |
| **CST project (.cst)** | ✅ | Full simulation model |
| **STL (3D mount)** | ✅ | 3D-printed support structure |
| KiCad | ❌ | Cần import DXF vào KiCad |
| Gerber | ❌ | Cần generate từ KiCad |

### Workflow nhanh nhất:
```
1. Clone repo → download DXF files
2. Mở KiCad PCB Editor
3. File → Import → Graphics → chọn DXF TOP → đặt vào layer F.Cu
4. Import DXF BOT → đặt vào layer B.Cu
5. Import DXF EDGE → đặt vào Edge.Cuts
6. Thêm SMA footprint (edge-launch SMA)
7. Export Gerber → Order JLCPCB
⏱️ Thời gian: ~1–2 giờ
```

### Tại sao Antipodal Vivaldi tốt cho bạn:
- **Không cần balun** — microstrip feed trực tiếp → đơn giản hơn Vivaldi thường
- Top layer: taper mở rộng sang phải
- Bottom layer: taper mở rộng sang trái
- SMA connector nối trực tiếp vào microstrip feed
- **Chế tạo PCB 2-layer chuẩn**, không cần kỹ thuật đặc biệt

> [!WARNING]
> Project này thiết kế cho 4G/5G bands. Nếu bạn cần 2.4 GHz, có thể cần **scale up** kích thước. Bạn có thể dùng CST file đi kèm để re-simulate cho 2.4 GHz trước khi fabricate.

---

## 🏆 Project #2: MyriadRF — Vivaldi Antenna (KiCad)

**Project duy nhất có sẵn KiCad native files!**

| Mục | Chi tiết |
|---|---|
| **Tên** | Vivaldi Antenna |
| **GitHub** | [myriadrf/vivaldi-antenna](https://github.com/myriadrf/vivaldi-antenna) |
| **Tổ chức** | MyriadRF (open-source SDR hardware organization) |
| **Loại** | Standard Vivaldi (tapered slot) |
| **Frequency range** | Optimized for **5.5 GHz và 10 GHz** |
| **PCB** | FR4, 2-layer |

### Files có sẵn:
| File type | Có? | Ghi chú |
|---|---|---|
| **KiCad project** | ✅ | Native KiCad files! |
| **Gerber** | ✅ (likely) | Export từ KiCad |
| **Simulation results** | ✅ | Documented in repo |
| **Preliminary measurements** | ✅ | Some measurement data |
| CST/HFSS | ❌ | |
| DXF | ❌ (KiCad has it built in) | |

### Workflow nhanh nhất:
```
1. git clone https://github.com/myriadrf/vivaldi-antenna
2. Mở KiCad project file
3. Review/modify design nếu cần
4. Plot → Gerber
5. Order JLCPCB
⏱️ Thời gian: ~30 phút (nếu dùng nguyên design)
```

> [!WARNING]
> Thiết kế cho 5.5/10 GHz — **quá nhỏ cho 2.4 GHz**. Cần scale lên hoặc redesign taper curve. Tuy nhiên KiCad files cho bạn starting point tuyệt vời.

---

## 🏆 Project #3: rookiepeng/antenna-models — CST Vivaldi 5.8 GHz

| Mục | Chi tiết |
|---|---|
| **Tên** | antenna-models (collection) |
| **GitHub** | [rookiepeng/antenna-models](https://github.com/rookiepeng/antenna-models) |
| **Vivaldi model** | `5.8G_Vivaldi_EdgeFed_FR4.cst` |
| **Frequency** | 5.8 GHz |
| **PCB** | FR4, edge-fed |
| **File format** | CST Studio Suite (.cst) |

### Files có sẵn:
| File type | Có? |
|---|---|
| **CST project (.cst)** | ✅ |
| KiCad/Gerber | ❌ |
| DXF | ❌ (export từ CST) |

### Workflow:
```
1. Download .cst file
2. Mở trong CST Studio Suite
3. Modify parameters cho 2.4 GHz
4. Simulate → verify S11 & pattern
5. Export layer → DXF
6. Import DXF vào KiCad
7. Generate Gerber → Order
⏱️ Thời gian: ~3–4 giờ (cần CST license)
```

### Bonus — Các model khác trong cùng repo:
- 1.575 GHz Patch Antenna (circularly polarized)
- 1.58 GHz Planar Monopole on FR4
- 8–12 GHz Horn Antenna
- 9 GHz Slot Antenna with Grooves

---

## 🛠️ Tool #1: changpuak.ch — Antipodal Vivaldi Antenna Calculator (MIỄN PHÍ)

**Calculator online tính toán kích thước Vivaldi cho TẦN SỐ BẤT KỲ.**

| Mục | Chi tiết |
|---|---|
| **URL** | [changpuak.ch/electronics/ap_vivaldi_antenna.php](https://www.changpuak.ch/electronics/ap_vivaldi_antenna.php) |
| **Loại** | Online calculator |
| **Output** | Dimensional parameters + taper curve coordinates |
| **Chi phí** | MIỄN PHÍ |
| **Tùy chỉnh tần số** | ✅ YES — nhập tần số mong muốn |

### Workflow:
```
1. Truy cập changpuak.ch
2. Nhập: f_low = 2.0 GHz, f_high = 3.0 GHz (hoặc rộng hơn)
3. Nhập: substrate εr = 4.4 (FR4), thickness = 1.6 mm
4. Calculator tính: taper length, opening rate, element dimensions
5. Dùng output coordinates vẽ trong KiCad hoặc CST
⏱️ Thời gian: ~3–4 giờ (tính toán nhanh, nhưng cần vẽ thủ công)
```

---

## 🛠️ Tool #2: Python DXF Generator — TỰ TẠO VIVALDI CHO 2.4 GHz

**Cách nhanh nhất để tạo Vivaldi antenna tùy chỉnh cho bất kỳ tần số nào.**

Dùng Python + `ezdxf` + `numpy` để generate exponential taper curve → export DXF → import KiCad:

```python
import numpy as np
import ezdxf

def vivaldi_taper(L, W, taper_rate, num_points=200):
    """Generate exponential taper curve for Vivaldi antenna.
    
    L: taper length (mm) - roughly λ/2 at lowest freq
    W: max opening width (mm) - roughly λ/2 at lowest freq  
    taper_rate: exponential rate (typically 0.02-0.05)
    """
    t = np.linspace(0, L, num_points)
    # Exponential taper: y = C1 * exp(R*x) + C2
    C2 = -W/2 * 1/(np.exp(taper_rate*L) - 1)
    C1 = -C2
    y = C1 * np.exp(taper_rate * t) + C2
    return t, y

# Design for 2.4 GHz
# λ = 125 mm at 2.4 GHz
# Taper length ≈ 1.5λ = 187.5 mm
# Opening ≈ λ/2 = 62.5 mm
L = 190  # mm
W = 65   # mm  
rate = 0.025

x, y_upper = vivaldi_taper(L, W, rate)
y_lower = -y_upper  # Mirror

# Create DXF
doc = ezdxf.new()
msp = doc.modelspace()

# Upper taper curve
points_upper = list(zip(x, y_upper))
points_lower = list(zip(x, y_lower))

msp.add_lwpolyline(points_upper)
msp.add_lwpolyline(points_lower)

doc.saveas("vivaldi_2_4ghz.dxf")
print(f"Vivaldi antenna DXF saved: {L}mm x {W}mm for 2.4 GHz")
```

### Workflow:
```
1. Chạy Python script → sinh vivaldi_2_4ghz.dxf
2. Mở KiCad PCB Editor
3. Import DXF → F.Cu layer (top taper)
4. Tạo mirrored taper cho B.Cu (bottom layer) - cho antipodal design
5. Thêm SMA connector footprint
6. Thêm board outline
7. Export Gerber → Order JLCPCB
⏱️ Thời gian: ~2–3 giờ
```

> [!TIP]
> Script trên là **starting point**. Bạn cần fine-tune `taper_rate`, `L`, `W` dựa trên simulation hoặc calculator. Dùng changpuak.ch calculator để lấy chính xác dimensions, rồi plug vào script.

---

## 🛠️ Tool #3: MATLAB Antenna Toolbox (Nếu có license)

**Workflow mạnh nhất nếu bạn có MATLAB license.**

```matlab
% Tạo Vivaldi antenna cho 2.4 GHz
v = vivaldi;
v = design(v, 2.4e9);  % Auto-design cho 2.4 GHz

% Xem geometry
show(v)

% Simulate
figure; pattern(v, 2.4e9)       % Radiation pattern
figure; returnLoss(v, linspace(1e9, 4e9, 100))  % S11

% Export Gerber trực tiếp!
gerberWrite(v, 'vivaldi_2p4ghz')  % → Gerber files ready for JLCPCB
```

| Feature | Chi tiết |
|---|---|
| `vivaldi` | Standard Vivaldi |
| `vivaldiAntipodal` | Antipodal Vivaldi (no balun needed) |
| `vivaldiOffsetCavity` | Vivaldi with cavity-backed slot |
| `design(v, freq)` | **Auto-design** cho tần số chỉ định |
| `gerberWrite(v)` | **Export Gerber trực tiếp** — gửi luôn cho JLCPCB! |
| `pattern(v, freq)` | Simulate radiation pattern |

> [!TIP]
> MATLAB `gerberWrite()` là **con đường nhanh nhất từ ý tưởng → Gerber** nếu bạn có license. Chạy 3 dòng code → có Gerber files.

---

## 📊 So Sánh Chi Tiết Tất Cả Projects

| Tiêu chí | HugoTronics | MyriadRF | rookiepeng | Python Gen | changpuak | MATLAB |
|---|---|---|---|---|---|---|
| **Loại Vivaldi** | Antipodal | Standard | Standard | Tùy chỉnh | Antipodal | Tùy chỉnh |
| **File format** | DXF+CST+STL | KiCad | CST | Python→DXF | Calculator | MATLAB→Gerber |
| **Gerber-ready?** | ⚠️ Cần convert | ✅ Gần sẵn | ❌ Cần convert | ⚠️ Cần import | ❌ Manual | ✅ `gerberWrite()` |
| **Covers 2.4 GHz?** | ⚠️ Cần scale | ❌ 5.5/10 GHz | ❌ 5.8 GHz | ✅ Tùy chỉnh | ✅ Tùy chỉnh | ✅ `design(v,2.4e9)` |
| **FR4 2-layer** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Fabricated?** | ✅ | ✅ | ❓ | Phụ thuộc bạn | Phụ thuộc bạn | Phụ thuộc bạn |
| **Measured S11** | ❓ | ✅ Preliminary | ❌ Sim only | ❌ | ❌ | ❌ Sim only |
| **Measured rad. pattern** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ Sim only |
| **Chi phí tool** | Free | Free | Cần CST | Free (Python) | Free | Cần MATLAB |
| **Thời gian → Gerber** | ~1–2h | ~30 min | ~3–4h | ~2–3h | ~3–4h | ~30 min |
| **Khả năng customize** | Qua CST | Qua KiCad | Qua CST | ✅ Hoàn toàn | ✅ Hoàn toàn | ✅ Hoàn toàn |

---

## 🎯 Khuyến Nghị Theo Tình Huống Của Bạn

### Nếu bạn có CST Studio Suite:
```
🥇 HugoTronics CST file → modify cho 2.4 GHz → simulate → export DXF → KiCad → Gerber
   hoặc
🥇 rookiepeng CST file → modify → export → KiCad → Gerber
```
Ưu điểm: Có thể simulate S11 + radiation pattern TRƯỚC KHI fabricate.

### Nếu bạn có MATLAB + Antenna Toolbox:
```
🥇 v = design(vivaldi, 2.4e9); gerberWrite(v);
```
Nhanh nhất. Literally 3 dòng code → Gerber files.

### Nếu bạn chỉ có KiCad (không có CST/MATLAB):
```
🥇 MyriadRF KiCad project → study & learn structure → scale cho 2.4 GHz
   +
🥈 changpuak.ch calculator → lấy exact dimensions cho 2.4 GHz
   +
🥉 Python DXF script → generate taper curve → import KiCad
```

### Nếu bạn muốn NHANH NHẤT có thể:
```
🥇 Clone MyriadRF KiCad project
   → Dùng changpuak.ch tính dimensions cho 2.4 GHz
   → Modify KiCad layout theo dimensions mới
   → Export Gerber
   → Order JLCPCB
⏱️ Tổng: ~2–3 giờ
```

---

## ⚠️ Lưu Ý Quan Trọng Khi Scale Vivaldi Cho 2.4 GHz

| Thông số | 5.8 GHz (design gốc) | 2.4 GHz (cần scale) | Tỷ lệ |
|---|---|---|---|
| λ (wavelength) | 51.7 mm | 125 mm | ×2.42 |
| Taper length | ~80 mm | ~190 mm | ×2.42 |
| Opening width | ~30 mm | ~65 mm | ×2.42 |
| Board size (ước tính) | ~100×60 mm | ~200×150 mm | ×2.42 |
| SMA transition | Phải redesign | Phải redesign | — |

> [!CAUTION]
> **KHÔNG đơn giản chỉ scale kích thước lên ×2.42!** Bạn cần:
> 1. Tính lại microstrip width cho 50Ω trên FR4 1.6mm (khoảng 3.0 mm)
> 2. Adjust taper rate cho dải tần mới
> 3. Kiểm tra SMA-to-microstrip transition
> 4. Nếu có CST, **simulate trước** để verify S11 < -10 dB tại 2.4 GHz

---

## 📎 Tất Cả Links Quan Trọng

| Resource | URL |
|---|---|
| HugoTronics Antipodal Vivaldi | [github.com/HugoTronics/Vivaldi-Antipodal-Antenna-Design](https://github.com/HugoTronics/Vivaldi-Antipodal-Antenna-Design) |
| MyriadRF Vivaldi (KiCad) | [github.com/myriadrf/vivaldi-antenna](https://github.com/myriadrf/vivaldi-antenna) |
| rookiepeng Antenna Models (CST) | [github.com/rookiepeng/antenna-models](https://github.com/rookiepeng/antenna-models) |
| changpuak.ch Vivaldi Calculator | [changpuak.ch/electronics/ap_vivaldi_antenna.php](https://www.changpuak.ch/electronics/ap_vivaldi_antenna.php) |
| MATLAB Vivaldi docs | [mathworks.com/help/antenna/ref/vivaldi.html](https://www.mathworks.com/help/antenna/ref/vivaldi.html) |
| MATLAB gerberWrite docs | [mathworks.com/help/antenna/ref/gerberwrite.html](https://www.mathworks.com/help/antenna/ref/gerberwrite.html) |
| COMSOL Vivaldi example | [comsol.com/model/vivaldi-antenna-12093](https://www.comsol.com/model/vivaldi-antenna-12093) |
| OpenEMS (free EM simulator) | [github.com/thliebig/openEMS](https://github.com/thliebig/openEMS) |
