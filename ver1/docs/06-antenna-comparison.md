# 06 — So Sánh Tổng Hợp Tất Cả Antenna

## Bảng so sánh master

| Tiêu chí | Pyramidal Horn | Double Ridged Horn | LPDA (ByTechLab) | Vivaldi (ifrht) | Vivaldi (csondurr) | Patch (reference) |
|---|---|---|---|---|---|---|
| **Loại** | Horn waveguide | Horn ridged | PCB array | PCB tapered slot | PCB + Balun | PCB patch |
| **Bandwidth** | 2.2–3.3 GHz | 2–6 GHz | 0.8–6 GHz | 0.8–3 GHz | 2–6 GHz | ~100 MHz |
| **Gain @ 2.4 GHz** | **15–18 dBi** | 10–12 dBi | ~6 dBi | ~8 dBi | ~7 dBi | ~6–8 dBi |
| **Gain calculable?** | ✅ **±0.3 dB** | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Chế tạo** | 3D print + Cu tape | 3D print + coat | PCB order | PCB order | PCB order | Đã có |
| **Chi phí (VNĐ)** | ~150k | ~300k | ~150k | ~100k | ~150k | \$0 |
| **Thời gian** | 1 ngày | 2 ngày | 3–5 ngày (ship) | 3–5 ngày | 3–5 ngày | Có sẵn |
| **Phù hợp TX?** | ✅✅✅ | ✅✅ | ✅ | ✅✅ | ✅✅ | ✅ |
| **Absolute meas.?** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Mở rộng 0–8 GHz?** | ❌ (chỉ 1 band) | ⚠️ 2–6 GHz | ⚠️ 0.8–6 GHz | ❌ 0.8–3 GHz | ⚠️ 2–6 GHz | ❌ |

## Chiến lược đề xuất

### Giai đoạn 1: Hiện tại (NanoVNA V2, 2.4 GHz)
| Ưu tiên | Antenna | Vai trò |
|---|---|---|
| 1 | **Pyramidal Horn** (tự chế) | TX antenna + absolute gain reference |
| 2 | **Patch reference** (đã có) | Calibration cross-check |

### Giai đoạn 2: Mở rộng (VNA xịn, 0–8 GHz)
| Ưu tiên | Antenna | Vai trò |
|---|---|---|
| 1 | **ByTechLab LPDA** (PCB) | TX wideband 0.8–6 GHz |
| 2 | **Pyramidal Horn** (giữ lại) | Reference chính xác cho band 2.2–3.3 GHz |
| 3 | **Vivaldi** (tùy chọn) | TX thay thế, gain cao hơn LPDA |

## Open-source projects đã xác minh

### LPDA Projects
| Project | URL | Files | Fabricated | Measured |
|---|---|---|---|---|
| ByTechLab LPDA 0.8–6 GHz | [GitHub](https://github.com/ByTechLab/RF---PCB-Log-Periodic-Antenna--0.8-6-GHz-) | KiCad+Gerber+STEP | ✅ | S11 only |
| WA5VJB Cheap Antennas | [wa5vjb.com](http://www.wa5vjb.com/) | PDF drawings | ✅ | S11+Pattern+Gain |
| WA5VJB @ AntennaTestLab | [antennatestlab.com](https://antennatestlab.com/) | Excel data | ✅ | Full 3D pattern |

### Vivaldi Projects
| Project | URL | Files | Freq | Fabricated |
|---|---|---|---|---|
| ifrht/vivaldi-antenna | [GitHub](https://github.com/ifrht/vivaldi-antenna) | KiCad+Gerber | 0.8–3 GHz | ✅ |
| csondurr wideband-vivaldi | [GitHub](https://github.com/csondurr/wideband-vivaldi-antenna-balun) | CST+Gerber | 2–6 GHz | ❌ |
| MyriadRF vivaldi | [GitHub](https://github.com/myriadrf/vivaldi-antenna) | KiCad+Gerber | 5.5/10 GHz | ✅ |
| HugoTronics Antipodal | [GitHub](https://github.com/HugoTronics/Vivaldi-Antipodal-Antenna-Design) | DXF+CST+STL | 4G/5G | ✅ |

### Horn Antenna Projects
| Project | URL | Files | Freq | Type |
|---|---|---|---|---|
| ByTechLab Ridged Horn | [bytechlab.com](https://bytechlab.com/2020/07/3d-printed-double-ridged-horn-antenna/) | STL+STEP+PDF | 2–6 GHz | Double Ridged |
| Instructables Pyramidal | [instructables.com](https://www.instructables.com/DIY-Horn-Antenna-for-the-Wi-Fi-Band-245-GHz/) | PDF template | 2.45 GHz | Pyramidal |
| dnemec Parametric | [GitHub](https://github.com/dnemec/pyramidal_horn_antenna_design) | Python+F360 | Any freq | Pyramidal |

### Design Tools
| Tool | URL | Free? |
|---|---|---|
| changpuak.ch Vivaldi Calculator | [changpuak.ch](https://www.changpuak.ch/electronics/ap_vivaldi_antenna.php) | ✅ |
| changpuak.ch Cantenna Calculator | [changpuak.ch](https://www.changpuak.ch/electronics/cantenna.php) | ✅ |
| MATLAB Antenna Toolbox | [mathworks.com](https://www.mathworks.com/help/antenna/ref/vivaldi.html) | Cần license |
| OpenEMS | [GitHub](https://github.com/thliebig/openEMS) | ✅ |
