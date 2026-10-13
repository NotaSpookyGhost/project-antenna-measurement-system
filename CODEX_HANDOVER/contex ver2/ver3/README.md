# THƯ MỤC NGHIỆM THU VER 3 — ANTENNA POSITIONER 2-AXIS

Thư mục này lưu trữ toàn bộ dữ liệu, nhật ký kiểm tra và công cụ thực thi của đợt nghiệm thu **Ver 3.0** (Ngày 11/10/2026 trên máy Spooky Laptop, cổng **COM5**).

---

## 📁 Danh sách tệp tin trong mục `ver3/`

1. **[`walkthrough_v3.md`](./walkthrough_v3.md)**  
   Báo cáo nghiệm thu chi tiết:
   - Quá trình biên dịch và flash firmware `firmware_positioner_v3.ino` bằng PlatformIO.
   - Trạng thái 2 cảm biến từ tính AS5600 (Góc thô, chỉ số AGC).
   - Kiểm tra chuyển động vi bước đơn trục (`M1`, `M2`) và đồng bộ 2 trục (`GOTO`).
   - Phân tích sai số lặp lại cơ học (Zero Step Loss, sai số lặp $\le 0.35^\circ$).
   - Cơ chế Smart EN Cycling dập xung nhiễu chopper trên bus I2C.

2. **[`test_positioner.py`](./test_positioner.py)**  
   Script Python chạy kiểm tra nhanh toàn bộ chức năng của bàn xoay qua cổng COM5 với 1 dòng lệnh:
   ```bash
   python test_positioner.py
   ```

---

## 🚀 Trạng thái hệ thống hiện tại
- **Firmware nạp trên ESP32:** `contex ver2/firmware/firmware_positioner_v3.ino`
- **Cổng COM kết nối:** `COM5` (115200 Baud)
- **Tình trạng:** Sẵn sàng 100% cho các bài đo trường bức xạ 2D/3D liên kết với MATLAB (`matlab/measure_pattern_2d_3d.m`).
