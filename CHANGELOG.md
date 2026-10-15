# Ghi chú cập nhật

## 15/10/2026 — Bản MATLAB Pan/Tilt 3D và NanoVNA

### Tính năng

- Quét Pan × Tilt theo lưới 3D tùy chỉnh, xem các lát cắt 2D và mô hình 3D,
  xuất rồi nạp lại bộ dữ liệu đo. Mốc ZERO cơ khí được giữ xuyên suốt lượt quét.
- Giao diện **Gia tốc...** cho phép chỉnh độ dài ramp của từng động cơ khi
  đang rảnh: Pan 100–600 bước, Tilt 75–300 bước. Ít bước hơn nghĩa là tăng
  tốc nhanh hơn; firmware cũng kiểm tra giới hạn và áp dụng hai trục cùng lúc.
  Mặc định vẫn là Pan 150 và Tilt 100 bước.
- Có thể mở giao diện bằng `Open Antenna App.vbs` trên Windows với MATLAB
  R2025b đã cài đặt.

### Sửa lỗi và cải thiện

- Chuẩn hóa kết quả NanoVNA theo chỉ số tần số FIFO để tần số, S11 và S21
  luôn khớp nhau dù gói tin đến lệch thứ tự. Sweep thiếu hoặc trùng điểm
  được báo lỗi rõ ràng; kiểm tra tính nhất quán tần số khi quét 3D vẫn giữ.
- Khi quét dừng sớm, biểu đồ Cartesian vẫn hiển thị được một điểm và GUI
  báo nguyên nhân lỗi gốc, đồng thời giữ các điểm đã đo để phân tích/xuất.
- Điều chỉnh profile Pan chạy chậm hơn, thời gian chờ lệnh theo từng trục,
  và ramp cho chuyển động ngắn không vượt độ dốc tăng tốc đã chọn.
- Tiếp tục bảo vệ bằng phản hồi AS5600, giữ motor khi cần và yêu cầu
  hiệu chuẩn lại ZERO sau khi nhả/reset. Tilt dùng I2C trong firmware chính;
  các thử nghiệm PWM cũ được lưu trong hồ sơ xác minh.

### Xác minh và dữ liệu kèm theo

- 64 bài kiểm tra MATLAB Mock, bộ kiểm tra Python NanoVNA và 5 bộ kiểm tra
  C++ firmware đã đạt. Bản build PlatformIO và lần nạp COM5 đã được xác
  nhận hash; thử giao thức `RAMP` trên COM5 không gửi lệnh quay motor.
- Có kèm dữ liệu quét thô, log, hình kiểm chứng và các bản sao flash ESP32
  trong `data/`. Xem `CODEX_GUIDE.md` và `docs/` để biết điều kiện của từng
  phép đo; các log thất bại lịch sử vẫn được giữ nguyên để đối chiếu.

**Lưu ý vận hành:** Sau khi nạp/reset ESP32 phải đặt lại ZERO cơ khí trước
khi quét. Giá trị ramp trở về 150/100 sau reset. Các bài kiểm tra tự động
nêu trên dùng Mock; chúng không thay cho phép xác nhận toàn bộ quét RF 3D
trên thiết bị thật.
