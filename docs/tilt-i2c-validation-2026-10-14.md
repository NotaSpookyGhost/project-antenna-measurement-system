# Tilt trở lại I²C — 14/10/2026

Người dùng đã rút dây Tilt từ khoảng 2 m xuống 1 m và tháo trở kéo lên
2,5 kΩ ngoài. SDA21/SCL22, nguồn 3,3 V/GND và OUT23 vẫn nối trong các bài
so sánh. Không thay dây giữa lượt I²C và PWM. “Không có trở ngoài” không có
nghĩa là bus không còn trở kéo: module và pull-up nội của ESP32 vẫn hiện diện.

## Kết quả phần cứng thực tế

| Bài | Kết quả Tilt |
| --- | --- |
| I²C đứng yên, nhả / giữ / nhả | 30/30 + 100/100 + 30/30 |
| PWM đứng yên, cùng dây, không trở ngoài | 30/30 + 100/100 + 30/30 |
| Quay Tilt bằng `PositionerController` MATLAB, I²C | 33/33 vị trí, 330/330 snapshot hợp lệ |

Người dùng xác nhận dải an toàn −90°..+90° tính từ vị trí cơ cấu hiện tại.
Bài MATLAB lấy ZERO thử tại vị trí này, đi 0 → +90 → 0 → −90 → 0 theo các
bước 5/10/15°. Không quay Pan, không dùng VNA. Mỗi vị trí có 10 lần đọc
encoder mới, giữ driver liên tục; kiểm tra lỗi encoder hiện có của controller
vẫn hoạt động. Encoder motor được unwrap giữa các bước rồi chia 5,625.

Sai lệch lớn nhất so với góc lệnh theo phép quy đổi này là **0,171°**.
Khi về ZERO cuối bài, encoder motor lệch **−0,17°**, tương đương **−0,030°**
ở đầu ra theo tỉ số truyền. Đây là góc suy ra từ encoder đuôi motor, chưa
phải phép đo độc lập góc bàn anten hoặc độ chính xác RF của pattern 3D.

Lượt script MATLAB đầu tiên dừng tại ZERO vì lỗi khởi tạo struct của script,
trước khi gửi lệnh quay. Log lỗi được giữ; lượt sửa sau đó đạt đủ 33 vị trí.

## Firmware vận hành

Theo yêu cầu bỏ PWM khi I²C đạt, firmware chính
`firmware/positioner_v3_hold/` hiện chỉ dùng I²C cho cả Pan và Tilt,
`FW:V4.0_HOLD`. Đã gỡ capture GPIO23, ghi cấu hình AS5600, environment
`tilt-pwm` và các script/test riêng của bản thử PWM. Lực giữ, STOP,
LOCK ZERO, watchdog 30 giây và kiểm tra mất encoder được giữ nguyên.

Lệnh cũ `TILT PWM ...` được từ chối rõ ràng để tránh bị bộ phân tích
`TILT <góc>` hiểu thành lệnh quay về 0°. Test native đã tái hiện lỗi đó
trước sửa và xác nhận sau sửa không phát STEP hoặc nhả motor.

Không cần OUT → GPIO23 để vận hành I²C. Có thể tháo riêng dây đó khi đã
tắt nguồn; giữ SDA21/SCL22/VCC/GND. Firmware không cấu hình đầu ra cảm biến
nữa; cấu hình PWM tạm của lượt thử trước sẽ mất khi ngắt nguồn cảm biến.
Không ghi OTP/BURN và không cần thay nam châm theo kết quả bài này.

Khởi động GUI và hiệu chuẩn thủ công lại sau reset/nhả: ESP32 thật / COM5 →
Connect → Nhả motor → căn cơ cấu → Khóa + ZERO. Dải an toàn −90..90 vừa
xác nhận chỉ có giá trị với ZERO thử hiện tại; xác nhận lại nếu đổi mốc.

## Dữ liệu và khôi phục bản thử cũ

Raw log, JSON, MAT và CSV nằm tại:
`data/validation/tilt_1m_no_external_pullup_20261014_165838/`.

- `comparison.json`, `stationary.log`: I²C/PWM đứng yên trước gỡ mã PWM.
- `motion_attempt_2/`: 33 vị trí MATLAB, snapshot và số liệu unwrap.
- `test_i2c_red.log`: test lệnh PWM cũ thất bại trước sửa.
- `test_as5600.log`, `test_hold.log`, `test_i2c_firmware.log`: ba test native đạt.
- `matlab_mock_regression.log`: 26 đạt, 0 lỗi, 0 bỏ dở.
- `i2c_only_upload.log`: build/nạp firmware chỉ I²C.
- `i2c_only_acceptance/`, `i2c_only_motion/`: xác minh bản cuối sau gỡ PWM.

Bản chỉ I²C sau khi nạp lại tiếp tục đạt **160/160** ở bài đứng yên và
**5/5 vị trí, 50/50 snapshot** cho lượt MATLAB 0 → 5 → 10 → 5 → 0.
Lượt ngắn này về mốc với chênh encoder motor +0,26°, tương đương +0,046°
theo tỉ số truyền. Kết thúc các bài, driver nhả và COM5 đóng.

Bản PWM cũ được bảo toàn tại commit `799e252` và ZIP
`pwm_trial_source_799e252.zip` trong folder dữ liệu trên, bao gồm firmware,
test và tài liệu. SHA256:
`F3F39680169300E75D6A48926C144F4C020E6CDC9A35C881311592827502415E`.
Tài liệu PWM trước đó là lịch sử thử nghiệm; lệnh environment đó không còn
áp dụng cho firmware vận hành hiện tại.
