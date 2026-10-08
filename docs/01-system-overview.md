# 01 — Tổng Quan Hệ Thống Đo Anten DIY

## Mục tiêu
Đo radiation pattern của anten hoạt động quanh 2.4 GHz.

## Thiết bị
| Thiết bị | Model | Vai trò |
|---|---|---|
| VNA | NanoVNA V2 | Đo S21 giữa TX và DUT |
| TX Antenna | Pyramidal Horn (tự chế) | Anten phát cố định |
| DUT | Anten cần đo | Trên rotary stage |
| Reference | Patch antenna (gain đã biết) | Calibration |
| Rotary Stage | Motor + controller | Quay DUT theo góc |

## Phương pháp đo

### Phương pháp 1: Gain Comparison (Relative)
```
1. Đặt Reference Antenna tại vị trí DUT
2. Đo S21_ref tại tần số f
3. Thay Reference bằng DUT
4. Quay DUT từ 0° → 360°, mỗi bước ghi S21_DUT(θ)
5. Gain_DUT(θ) = Gain_ref + [S21_DUT(θ) - S21_ref] (dB)
```

### Phương pháp 2: Absolute Gain (với Horn antenna)
```
Friis equation: S21 = G_TX + G_DUT + 20·log10(λ/(4πR))

Vì G_TX (horn) tính chính xác từ kích thước:
→ G_DUT = S21 - G_TX - 20·log10(λ/(4πR))
→ Không cần reference antenna!
```

### Cross-validation
- Đo gain DUT bằng **cả 2 phương pháp**
- So sánh kết quả → validate hệ thống
- Sai lệch < 1–2 dB = hệ thống đáng tin cậy

## Link Budget @ 2.4 GHz

| Thông số | Giá trị |
|---|---|
| NanoVNA output | ~0 dBm |
| NanoVNA noise floor | ~-90 dBm |
| Dynamic range S21 | ~70–80 dB |
| FSPL @ 2m | ~46 dB |
| Horn gain (TX) | ~15 dBi |
| Received (DUT 0 dBi, main lobe) | 0 + 15 - 46 + 0 = **-31 dBm** ✅ |
| Received (DUT -20 dBi, null) | 0 + 15 - 46 - 20 = **-51 dBm** ✅ |
| Margin at null | ~40 dB ✅ |

## Khoảng cách Far-field

Far-field distance: $R_{ff} = \frac{2D^2}{\lambda}$

| Antenna | D (max dimension) | R_ff @ 2.4 GHz |
|---|---|---|
| Horn (200mm aperture) | 200 mm | 0.64 m |
| Patch (~60mm) | 60 mm | 0.06 m |
| LPDA (~300mm) | 300 mm | 1.44 m |

→ Khoảng cách đo **≥ 2m** là an toàn cho hầu hết antenna.
