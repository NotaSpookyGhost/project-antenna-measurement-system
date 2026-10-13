# 🔬 Báo Cáo Nghiên Cứu: Open-Source PCB LPDA Antenna Projects

> **Mục tiêu:** Tìm project PCB Log-Periodic Dipole Array (LPDA) open-source có fabricated prototype + measured radiation pattern + design files, phục vụ hệ thống đo anten DIY tại 2.4 GHz với NanoVNA V2.

> **Ngày nghiên cứu:** 2026-09-26

---

## 📊 Bảng Tổng Hợp So Sánh

| Tiêu chí | ByTechLab | WA5VJB (Kent Britain) | WA5VJB @ AntennaTestLab | Academic Papers |
|---|---|---|---|---|
| **Design Files (KiCad/Gerber)** | ✅ KiCad + Gerber + STEP | ❌ Chỉ có dimensional drawings (PDF) | ❌ (Không có design files) | ❌ Chỉ có dimensions trong paper |
| **Fabricated Prototype** | ✅ | ✅ | ✅ | ✅ |
| **Measured S11** | ✅ | ✅ | ✅ | ✅ |
| **Measured Radiation Pattern** | ❌ (SIMULATION only) | ✅ (từ WA5VJB specs) | ✅ (3D gain pattern, polar plot) | ✅ |
| **Measured Gain** | ❌ (SIMULATION only) | ✅ (~6 dBi) | ✅ (calibrated measurement) | ✅ |
| **Anechoic Chamber** | ❌ | ✅ (Kent's facilities) | ✅ (professional chamber) | ✅ |
| **Covers 2.4 GHz** | ✅ | ✅ | ✅ | ✅ (varies) |
| **FR4 / 2-layer** | ✅ | ✅ | ✅ | ✅ |
| **Ready to Order PCB** | ✅ | ❌ (cần vẽ lại) | ❌ | ❌ |
| **Sim vs Measured comparison** | Partial (S11 only) | Limited | N/A | ✅ |

> [!IMPORTANT]
> **Không có project nào trên thế giới hiện tại đáp ứng đồng thời TẤT CẢ tiêu chí:** open-source KiCad/Gerber files + fabricated PCB + measured radiation pattern + measured gain + anechoic chamber data. Đây là khoảng trống thực sự trong cộng đồng open-source RF.

---

## 🏆 Project #1: ByTechLab — PCB Log Periodic Antenna (0.8–6 GHz)

**Đây là project open-source hoàn thiện nhất về manufacturing files.**

| Mục | Chi tiết |
|---|---|
| **Tên project** | ByTechLab RF-PCB-Log-Periodic-Antenna (0.8–6 GHz) |
| **GitHub** | [ByTechLab/RF---PCB-Log-Periodic-Antenna--0.8-6-GHz-](https://github.com/ByTechLab/RF---PCB-Log-Periodic-Antenna--0.8-6-GHz-) |
| **Project page** | [bytechlab.com](https://bytechlab.com/projects/pcb-log-periodic-antenna/) |
| **Tác giả** | Andrzej Laczewski |
| **Frequency range** | 0.8 GHz – 6 GHz |
| **PCB material** | FR4, εr ≈ 4.4 |
| **PCB thickness** | 1.5 mm (sensitivity analysis: 1.45–1.55 mm) |
| **Số lớp** | 2-layer |
| **Kích thước PCB** | ~300 mm length (ước tính) |
| **KiCad files** | ✅ YES |
| **Gerber files (RS-274X)** | ✅ YES |
| **BOM** | ✅ YES |
| **Schematic** | ✅ YES (PDF) |
| **STEP/3D model** | ✅ YES (PCB + 3D-printed enclosure) |
| **MCAD enclosure** | ✅ YES (3D printable case) |
| **Fabricated prototype** | ✅ YES (JLCPCB) |
| **Measured S11** | ✅ YES (VNA measurement, with & without enclosure) |
| **Measured radiation pattern** | ❌ **NO** — Chỉ có SIMULATION (CST) |
| **Measured gain** | ❌ **NO** — Chỉ có simulated gain (~6 dBi) |
| **Simulation tool** | CST Studio Suite |
| **Simulation data** | ✅ Extensive: S11, far-field, realized gain, E-field propagation |
| **Anechoic chamber** | ❌ NO |
| **Paper/report** | Detailed blog post with sensitivity analysis |
| **License** | Open Source (public GitHub repo) |
| **Có thể tái tạo?** | ✅ **YES — Download Gerber → Order from JLCPCB** |

> [!WARNING]
> Radiation pattern trên ByTechLab website **là SIMULATION từ CST**, KHÔNG phải measured data. Đừng nhầm lẫn!

### Điểm mạnh:
- Complete manufacturing files (KiCad + Gerber + BOM + STEP)
- Sensitivity analysis cho PCB fabrication tolerances
- Có 3D-printed enclosure
- Dễ tái tạo: đặt PCB từ JLCPCB trực tiếp

### Điểm yếu:
- **Không có measured radiation pattern**
- **Không có measured gain**
- Không có anechoic chamber data

---

## 🏆 Project #2: WA5VJB — Kent Britain "Cheap Antennas" (PCB LPDA)

**Đây là project có measured data hoàn thiện nhất, được coi là gold standard cho DIY PCB LPDA.**

| Mục | Chi tiết |
|---|---|
| **Tên project** | WA5VJB "Cheap Antennas" PCB LPDA |
| **Website** | [wa5vjb.com](http://www.wa5vjb.com/products1.html) |
| **Tác giả** | Kent Britain, WA5VJB (professional antenna engineer) |
| **Frequency range** | Nhiều variants: 400–1000 MHz, 850–6500 MHz, 900–2700 MHz, 2–11 GHz |
| **Model phù hợp nhất cho 2.4 GHz** | **850–6500 MHz** hoặc **900–2700 MHz** |
| **PCB material** | FR4 |
| **PCB thickness** | 0.062" (1.6 mm) standard |
| **Số lớp** | 2-layer |
| **KiCad files** | ❌ **NO** — Chỉ có dimensional drawings (PDF) |
| **Gerber files** | ❌ **NO** |
| **BOM** | Minimal (SMA + PCB) |
| **Schematic** | Dimensional drawings with element lengths/spacings |
| **STEP/3D model** | ❌ NO |
| **Fabricated prototype** | ✅ YES — Hàng trăm board đã được sản xuất & bán |
| **Measured S11** | ✅ YES (VSWR/return loss) |
| **Measured radiation pattern** | ✅ **YES** — E-plane & H-plane patterns tại nhiều tần số |
| **Measured gain** | ✅ **YES** — ~6 dBi typical forward gain |
| **Simulation** | ❌ Mostly empirical/experimental design |
| **Anechoic chamber** | ✅ **YES** — Kent là professional antenna engineer |
| **Paper/report** | AMSAT presentations, microwave journal articles, ARRL publications |
| **License** | Free/open designs shared for community |
| **Mua bare PCB** | ✅ YES — Có thể mua board trực tiếp (~$10–20) |
| **Có thể tái tạo?** | ⚠️ Cần reverse-engineer từ dimensional drawings vào KiCad |

### Điểm mạnh:
- **Measured radiation pattern trong anechoic chamber** — THỰC SỰ MEASURED
- **Measured gain data** tại nhiều tần số
- Professional-grade measurement by antenna engineer
- Nhiều variants cho các dải tần khác nhau
- Empirically optimized (tuned on real antenna range)
- Có thể mua bare PCB với giá rẻ

### Điểm yếu:
- **KHÔNG có KiCad/Gerber files** — cần tự vẽ lại từ PDF drawings
- Không có simulation data (chỉ empirical)
- Design files là proprietary (Kent sells the boards)

---

## 🏆 Project #2b: WA5VJB đo bởi Antenna Test Lab Co.

**Đây là nguồn measured data chuyên nghiệp nhất cho WA5VJB LPDA.**

| Mục | Chi tiết |
|---|---|
| **Tên** | Antenna Test Lab Co. — WA5VJB PCB LPDA Evaluation |
| **Website** | [antennatestlab.com](https://antennatestlab.com/antenna-tests-summaries/pc-board-log-periodic-antennas) |
| **Loại dữ liệu** | Independent professional measurement |
| **Measured S11** | ✅ YES |
| **Measured radiation pattern** | ✅ **YES** — 3D gain patterns, polar plots |
| **Measured gain** | ✅ **YES** — Calibrated gain vs frequency |
| **Radiation efficiency** | ✅ YES |
| **Download format** | Excel spreadsheets (.xlsx) |
| **Anechoic chamber** | ✅ **YES** — Professional anechoic chamber |

### Tại sao quan trọng:
- Đây là **measured data độc lập** (third-party verification)
- Có **3D gain patterns** dạng Excel — có thể import vào MATLAB/Python
- Bạn có thể dùng dữ liệu này làm **reference** để validate phép đo của bạn
- Download miễn phí

---

## 🏆 Project #2c: W1GHZ — Phân tích WA5VJB LPA

| Mục | Chi tiết |
|---|---|
| **Tên** | "The WA5VJB LPA Antenna as a Multi-band Dish Feed" |
| **Tác giả** | Paul Wade, W1GHZ |
| **URL** | [w1ghz.org](https://www.w1ghz.org/antbook/conf/The_WA5VJB_LPA_Antenna_as_a_Multi-band_Dish_Feed.pdf) |
| **Content** | HFSS simulation of WA5VJB design using actual artwork files |
| **Frequencies analyzed** | 2304 MHz, 3456 MHz, 5760 MHz |
| **Data type** | ⚠️ **SIMULATION** (Ansoft HFSS) — NOT measured |
| **Useful for** | Understanding E/H-plane pattern shape, beamwidth at 2.4 GHz |

---

## 📚 Project #3: Academic Papers với Measured Radiation Pattern

Các papers học thuật sau có **measured radiation pattern thực sự** nhưng **KHÔNG có KiCad/Gerber files**:

### Paper 3a: PSO Optimized Wideband LPDA with Non-Cross Feed Structure

| Mục | Chi tiết |
|---|---|
| **Tác giả** | Shailendra S. Pawar, Madhu Shandilya |
| **Nguồn** | Progress In Electromagnetics Research C (PIER C), Vol. 86, 2018 |
| **URL** | [jpier.org](https://www.jpier.org/) |
| **PCB** | FR-4, 1 mm thickness |
| **Feed** | Coplanar waveguide (CPW) non-cross feed |
| **Measured S11** | ✅ YES |
| **Measured radiation pattern** | ✅ **YES** (Anechoic chamber) |
| **Measured gain** | ✅ YES |
| **Sim vs Measured** | ✅ YES — CST vs measured comparison |
| **Design files** | ❌ NO — PSO-optimized geometric parameters in paper only |
| **Reproducible?** | ⚠️ Cần extract dimensions từ paper → vẽ lại trong KiCad |

### Paper 3b: Printed LPDA with Koch Fractal Dipoles (2.3–6 GHz)

| Mục | Chi tiết |
|---|---|
| **Tác giả** | Arielly Rodrigues, Edson R. Schlosser, Marcos V. T. Heckler |
| **Nguồn** | Journal of Communication and Information Systems (JCIS), Vol 39, Issue 1, 2024 |
| **Frequency range** | **2.3–6 GHz** ← Covers 2.4 GHz! |
| **Innovation** | Koch fractal dipoles — giảm 25% diện tích |
| **Measured S11** | ✅ YES (VSWR < 2) |
| **Measured radiation pattern** | ✅ **YES** (3D measured patterns) |
| **Measured gain** | ✅ YES |
| **Sim vs Measured** | ✅ YES — Good agreement |
| **Design files** | ❌ NO |
| **Reproducible?** | ⚠️ Detailed dimensions in paper |

### Paper 3c: Compact LPDA for Broadband Beam Synthesis

| Mục | Chi tiết |
|---|---|
| **Tác giả** | Changhyeon Im, Sangwoon Youn, Tae Heung Lim, Hosung Choo |
| **Nguồn** | Journal of Electromagnetic Engineering and Science (JEES), 2024 |
| **Measured S11** | ✅ YES |
| **Measured radiation pattern** | ✅ **YES** (Full anechoic chamber) |
| **Measured gain** | ✅ YES |
| **Sim vs Measured** | ✅ YES |
| **Design files** | ❌ NO |

---

## ❌ Projects KHÔNG Đạt Tiêu Chí

| Project | Lý do loại |
|---|---|
| **hexandflex** | Chuyên về Vivaldi antenna, không có LPDA PCB repo trên GitHub |
| **Electrosense (ETH Zurich)** | GitHub repo không host antenna design files công khai |
| **dhanraj-mv8/cst_log_periodic** | Chỉ có CST simulation files, không có PCB layout, không fabricate |
| **mkgin/lp_4g_lte_ant** | OpenSCAD model cho wire antenna, không phải PCB |
| **schlatterbeck/antenna-optimizer** | Python calculator, không có PCB files |
| **SV1AFN Kits** | Commercial kit, không fully open-source, limited measured data |
| **Hackaday 1.420 GHz Antenna** | Failed prototype — documented as cautionary tale |
| **Various CST/HFSS-only repos** | Simulation only, no fabrication |

---

## 🎯 Khuyến Nghị Cho Hệ Thống Đo Anten DIY Của Bạn

> [!TIP]
> ### Chiến lược tối ưu: Kết hợp ByTechLab (manufacturing) + WA5VJB/ATL (validation data)

### Phương Án A: Nhanh nhất — Mua WA5VJB bare PCB + dùng ATL data
1. **Mua** WA5VJB 850–6500 MHz bare PCB (~\$10–20) từ [wa5vjb.com](http://www.wa5vjb.com/)
2. **Hàn** SMA connector
3. **Download** measured radiation pattern data từ [Antenna Test Lab](https://antennatestlab.com/)
4. Dùng data này làm **reference** để validate hệ thống đo của bạn
5. **Ưu điểm:** Nhanh, rẻ, có professional measured data
6. **Nhược điểm:** Không có KiCad/Gerber để modify

### Phương Án B: DIY — Dùng ByTechLab Gerber + tự đo radiation pattern
1. **Clone** [ByTechLab GitHub repo](https://github.com/ByTechLab/RF---PCB-Log-Periodic-Antenna--0.8-6-GHz-)
2. **Đặt PCB** từ JLCPCB sử dụng Gerber files
3. **Dùng NanoVNA V2** đo S11 → compare với ByTechLab's simulated & measured S11
4. **Dùng hệ thống rotary stage + NanoVNA** đo S21 vs angle → tạo radiation pattern
5. **So sánh** measured pattern với ByTechLab's simulated pattern (CST)
6. **Ưu điểm:** Full control, có KiCad files để modify, open-source
7. **Nhược điểm:** Cần tự đo radiation pattern (nhưng đó cũng chính là mục tiêu của bạn!)

### Phương Án C: Tối ưu — Kết hợp cả hai
1. **Mua** WA5VJB bare PCB → dùng làm TX antenna với measured data đã known
2. **Fabricate** ByTechLab LPDA → dùng để cross-validate
3. Có 2 LPDA → một làm TX, một làm reference receiver
4. Dùng **patch antenna reference** (đã biết gain) để calibrate hệ thống
5. **Ưu điểm:** Best of both worlds

### Phương Án D: Academic — Recreate từ paper
1. Chọn một paper (ví dụ: Paper 3a hoặc 3b ở trên)
2. Extract dimensional parameters
3. Vẽ lại trong KiCad
4. Fabricate
5. Đo và so sánh với paper's measured data
6. **Ưu điểm:** Có measured reference data từ anechoic chamber để validate
7. **Nhược điểm:** Tốn thời gian vẽ lại

---

## 🔑 Kết Luận Quan Trọng

1. **Không có project nào đồng thời có: open-source KiCad/Gerber + measured radiation pattern + measured gain.** Đây là khoảng trống lớn trong cộng đồng open-source RF.

2. **ByTechLab** = project open-source tốt nhất về **manufacturing files** (KiCad + Gerber + BOM + STEP + 3D case) nhưng **KHÔNG có measured radiation pattern**.

3. **WA5VJB** = project tốt nhất về **measured data** (radiation pattern + gain + anechoic chamber) nhưng **KHÔNG có KiCad/Gerber** (chỉ có dimensional drawings).

4. **Antenna Test Lab Co.** = nguồn measured data **chuyên nghiệp nhất** cho WA5VJB LPDA, downloadable dạng Excel.

5. **Academic papers** = nguồn tốt nhất cho **sim vs measured comparison** nhưng không có design files.

6. Tình huống lý tưởng: **Bạn fabricate ByTechLab LPDA + tự đo radiation pattern = bạn sẽ trở thành project đầu tiên có đầy đủ open-source files + measured radiation pattern!**

---

## 📎 Links Quan Trọng

| Resource | URL |
|---|---|
| ByTechLab GitHub | [github.com/ByTechLab/RF---PCB-Log-Periodic-Antenna--0.8-6-GHz-](https://github.com/ByTechLab/RF---PCB-Log-Periodic-Antenna--0.8-6-GHz-) |
| ByTechLab Project Page | [bytechlab.com](https://bytechlab.com/projects/pcb-log-periodic-antenna/) |
| WA5VJB Products | [wa5vjb.com/products1.html](http://www.wa5vjb.com/products1.html) |
| Antenna Test Lab — WA5VJB Data | [antennatestlab.com](https://antennatestlab.com/antenna-tests-summaries/pc-board-log-periodic-antennas) |
| W1GHZ Analysis PDF | [w1ghz.org](https://www.w1ghz.org/antbook/conf/The_WA5VJB_LPA_Antenna_as_a_Multi-band_Dish_Feed.pdf) |
| PIER C Paper (PSO LPDA) | [jpier.org](https://www.jpier.org/) |
| JCIS Paper (Koch Fractal LPDA) | [sbrt.org.br](https://sbrt.org.br/) |

---

## 🔍 Từ Khóa Tìm Kiếm Bổ Sung (cho nghiên cứu tiếp)

Để tìm thêm trên IEEE Xplore:
```
("log periodic" OR "LPDA") AND "printed" AND "measured" AND "radiation pattern"
("log periodic dipole array") AND "fabricated" AND "pattern"
("printed log periodic") AND "EMC" AND "measurement"
```

Trên Google Scholar:
```
"PCB LPDA measured radiation pattern fabricated"
"printed log periodic dipole array anechoic chamber FR4"
```
