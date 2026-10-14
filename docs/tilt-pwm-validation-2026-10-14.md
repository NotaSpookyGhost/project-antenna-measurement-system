# Tilt AS5600 PWM — kiểm tra phần cứng ngày 14/10/2026

Người dùng đã nối OUT Tilt vào GPIO23, xác nhận giữ SDA21/SCL22.
Thử riêng cảm biến, không VNA, không STEP/GOTO/ZERO motor. Firmware trên
COM5 là V4.1_PWM_HOLD, không dùng I2C để đọc góc Tilt trong POS.

## Cấu hình và sửa giả định ban đầu

Bài đầu và ba lần thử lại báo CONFIG_READBACK, chưa xác nhận PWM hoạt động.
Bổ sung lệnh **chỉ đọc** TILT PWM REG cho thấy sáu lần đọc liên tiếp
ZPOS=0x0A48, MPOS=0x0A47, MANG=0, CONF=0. Bản đầu giả định các mốc bằng0
và từ chối dải này; không thể quy toàn bộ lỗi ban đầu cho phần cứng từ đó.

Bản cập nhật đưa low12 bits của ZPOS/MPOS/MANG về0 bằng ghi tạm, giữ nguyên
reserved bits, rồi đặt CONF cho PWM230Hz/NOM. Đọc lại cả dải và CONF hai lần
trước khi cho phép feedback. Write allowlist chỉ0x01..0x06 và0x07..0x08;
không ghi0xFF/BURN, không đổi ZERO cơ khí. GPIO23 là input trở kháng cao.
Thay đổi có native red/green tests, kiểm tra hold/STOP/no STEP, hai build
PlatformIO thành công và rà soát độc lập không còn phát hiện lỗi quan trọng.

## Kết quả thật

| Trạng thái | Mẫu hợp lệ | Span góc encoder motor trong pha | Chu kỳ xung |
|---|---:|---:|---:|
| Nhả trước khi giữ | 30/30 | 0,26° | 4274–4276 µs |
| Giữ cả hai driver | 100/100 | 0,27° | 4274–4276 µs |
| Nhả sau khi giữ | 30/30 | 0,35° | 4274–4276 µs |

Trong pha giữ bộ đếm nhả driver không đổi. Script xác nhận nhả khi kết thúc
và đóng COM5. Mở lại COM5 bằng probe chỉ đọc vẫn có PWM_CONFIG:1,
ENC_TILT_VALID:1. Không ghi OTP. Mốc logic cần Khóa + ZERO trước quét.

Các pha có góc khác nhau (231,24° mẫu đầu lúc nhả; 229,57° khi giữ;
229,75° sau nhả). Không phát xung STEP không có nghĩa motor không thể dịch
khi kích hoạt lực giữ. Chưa đo độc lập góc bàn anten, chuyển động Tilt,
backlash, nam châm hoặc quét3D. AGC=255 trong bản PWM là unavailable,
không dùng làm kết luận từ trường khỏe/yếu.

Evidence trước sửa: `data/validation/tilt_pwm_20261014_162826/`.
Evidence acceptance: `data/validation/tilt_pwm_20261014_164042/` —
`raw.log`, `summary.json`, `loaded_probe.log`. Giữ nguyên các log thất bại.
