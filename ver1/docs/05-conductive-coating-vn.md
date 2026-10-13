# 05 — Vật Liệu Dẫn Điện & Dịch Vụ Mạ Tại Việt Nam

## Bối cảnh
Khi in 3D horn antenna, cần phủ lớp dẫn điện bên trong. Tại 2.4 GHz, skin depth trong đồng chỉ ~1.3 μm, nên chỉ cần lớp dẫn điện mỏng là đủ.

---

## Phương án 1 (KHUYÊN DÙNG): Băng Keo Lá Đồng

| Mục | Chi tiết |
|---|---|
| Tên | Copper Foil Tape (băng keo đồng) |
| Loại | Loại có keo dẫn điện (Conductive Adhesive) |
| Độ dày | 0.05–0.08 mm (gấp ~50 lần skin depth) |
| Conductivity | σ ≈ 5.8×10⁷ S/m (đồng nguyên chất) |
| Giá | 80.000–150.000 VNĐ / cuộn |
| Mua ở đâu | Shopee/Lazada: "băng keo đồng dẫn điện", "copper tape guitar shielding" |

### Cách dán:
1. In 3D 2 nửa kèn
2. Dán băng keo đồng miết phẳng vào bên trong
3. Tại các mối nối giữa dải: chấm hàn thiếc để đảm bảo thông mạch
4. Dùng VOM đo điện trở giữa các vùng → phải gần 0Ω

### Tại sao tốt hơn sơn:
- Đồng nguyên chất đặc → conductivity vượt trội mọi loại sơn
- Dán được ngay, không cần chờ khô
- Dễ sửa chữa nếu dán sai
- Rẻ hơn sơn dẫn điện chuyên dụng rất nhiều

---

## Phương án 2: Dịch Vụ Xi Mạ Nhựa ABS

| Mục | Chi tiết |
|---|---|
| Yêu cầu | In 3D bằng ABS (không phải PLA!) |
| Quy trình | Xử lý bề mặt → mạ hóa học đồng → mạ điện phân |
| Chi phí | 200.000–500.000 VNĐ/chi tiết |

### Tìm dịch vụ:
- **TP.HCM:** Q. Bình Tân, Q.12, Thuận An (Bình Dương) — xưởng xi mạ phụ tùng xe máy
- **Hà Nội:** Hoài Đức, Hà Đông, KCN Quang Minh
- **Từ khóa:** "Xi mạ nhựa ABS", "Xi mạ chóa đèn", "Xi mạ phụ tùng xe máy"

---

## Phương án 3: Sơn Dẫn Điện Nhập Khẩu

| Sản phẩm | Giá VN | Nguồn |
|---|---|---|
| MG Chemicals 843AR (Silver Coated Copper) | 1.5–2.5 triệu VNĐ | RS Components VN, Mouser, Digikey |
| MG Chemicals 841AR (Nickel) | 1.0–1.5 triệu VNĐ | RS Components VN |
| Sơn nickel/bạc Shopee | 200k–500k | Shopee (chất lượng không ổn định) |

### ⚠️ CẢNH BÁO:
**KHÔNG DÙNG:**
- Sơn xịt mạ kẽm lạnh
- Sơn nhũ đồng/nhũ vàng trang trí
- Sơn xịt mạ crom ATM/Bosny

→ Các loại này có hạt kim loại bọc trong keo cách điện → đo VOM ra HỞ MẠCH → không dẫn RF!

---

## Kết luận

**Băng keo đồng là giải pháp tốt nhất tại VN:** rẻ, dễ mua, conductivity tốt nhất, dễ thi công trên pyramidal horn (4 mặt phẳng).
