# Kiểm tra sau đi lại dây và nạp lại firmware — 14/10/2026

Người dùng yêu cầu kiểm tra hai AS5600 khi nhả/giữ motor, quay cả hai trục
+90° rồi trở về. Trong lượt làm việc, người dùng cho biết đã nạp code thử
khác và yêu cầu khôi phục firmware ESP32 dùng với MATLAB.

## Firmware đã khôi phục

Đã build và nạp environment `esp32doit-devkit-v1` trong
`firmware/positioner_v3_hold/` lên COM5. Upload hoàn tất, esptool xác minh
hash các vùng ghi. POS sau reset trả `FW:V4.0_HOLD`, HOLD, trạng thái encoder
và capability Pan/Tilt đúng giao thức `PositionerController` MATLAB.

Bản flash trước nạp được lưu đủ 4.194.304 byte tại
`data/validation/rewired_both_20261014_2013/restored_firmware/pre_restore_flash.bin`.
SHA256 backup: `c271bc6963e922915050e234e7885cd72a9a35a0280b4dd274c93bd131ff9bf2`.
SHA256 firmware.bin đã nạp: `37c86f8edfa7bec59b09f0d3eda1917a0d743aa86c13fd0d8af051102779322d`.
Ảnh ứng dụng trước nạp tại offset 0x10000 khác firmware.bin đã build;
không suy ra nguyên nhân lỗi motor chỉ từ khác biệt binary này.

## Đứng yên sau nạp lại

| Trạng thái | Pan hợp lệ | Tilt hợp lệ | Span Pan motor | Span Tilt motor |
|---|---:|---:|---:|---:|
| Nhả trước giữ | 30/30 | 30/30 | 0,09° | 0,00° |
| Giữ | 100/100 | 100/100 | 0,00° | 0,08° |
| Nhả sau giữ | 30/30 | 30/30 | 0,00° | 0,00° |

Span được tính trong từng trạng thái, không trộn góc trước/sau đổi lực giữ.
Không có lệnh quay trong bài đứng yên. Raw POS và JSON ở
`restored_firmware/stationary.log` và `stationary.json`.

## Chuyển động sau nạp lại

Bài hai trục tạo ZERO thử tại tư thế hiện tại, dự định tăng từng bước
5/10° cho Pan rồi Tilt đến 90°, sau đó giảm về 0°. Kiểm tra encoder và
giới hạn hành trình được giữ nguyên.

Pan thất bại ngay ở lệnh 5°: encoder đổi **3,60°**, kỳ vọng **28,125°**
motor theo tỉ số truyền 90/16. Bài dừng, không tiếp tục Pan đến 90° và
không tự quay về sau mismatch. Log/data: `restored_firmware/motion.*`.
Trước nạp lại, bài tương tự cũng dừng ở 5° với encoder đổi 3,61°.
Nạp lại firmware chưa giải quyết lỗi Pan. Chưa xác định cấu hình vi bước,
đấu cuộn dây, driver, lực giữ hoặc cơ khí nào là nguyên nhân.

Sau đó kiểm tra riêng Tilt, giữ Pan đứng yên, với hành trình đã được người
dùng yêu cầu. Tilt hoàn thành **21/21 vị trí**, **210/210 snapshot hợp lệ**:
0, 5, 10, 20, …, 90, 80, …, 10, 5, 0°.
Không tăng bộ đếm nhả driver trong chuyển động.

- Sai lệch tích lũy lớn nhất suy ra từ encoder motor / 5,625: **0,1244°**.
- Sai lệch về gốc encoder motor: **+0,17°**.
- Sai lệch về gốc đầu ra suy ra: **+0,0302°**.

Đây là góc suy ra từ encoder đuôi motor, chưa phải đo độc lập góc bàn anten.
Data và log: `restored_firmware/tilt_only/matlab_tilt_motion.*`.

Các bài kết thúc bằng nhả motor và đóng COM5. Các ZERO thử không được dùng
như mốc đo anten tiếp theo; cần căn cơ cấu và Khóa + ZERO lại trong GUI.
Firmware source không thay đổi. Quét 3D thật vẫn chưa đạt vì lỗi Pan.
