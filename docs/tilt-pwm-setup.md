# Thử AS5600 Tilt bằng PWM — 14/10/2026

Firmware thử: PlatformIO environment `tilt-pwm`, `FW:V4.1_PWM_HOLD`.
Pan vẫn dùng I2C. Tilt chỉ đọc PWM; mất xung sẽ báo encoder không hợp lệ.
Chế độ này không thay đổi lực giữ, STOP, ZERO thủ công hay watchdog 30 giây.
GPIO23 chưa được dùng trong source hiện tại; kiểm tra chân trên đúng bo ESP32.

Bản thử đã được nạp trên COM5. Kiểm tra đứng yên sau nạp xác nhận cấu hình
PWM thành công (`PWM_CONFIG:1`), nhưng chưa có cạnh xung OUT trên GPIO23.
Chưa xác nhận bài PWM phần cứng đạt; bước tiếp theo là đấu OUT rồi chạy
bài 30/100/30. Khi ngắt nguồn để đấu, cấu hình tạm sẽ cần được đặt lại.

## Đấu dây

Ngắt nguồn 20 V và USB trước khi đấu; đỡ cơ cấu vì motor sẽ mất lực giữ.

| AS5600 Tilt | ESP32 / hộp |
|---|---|
| VCC | Nguồn **3,3 V** hiện có |
| GND | GND chung |
| **OUT** | **GPIO23**, thêm một dây tín hiệu |
| SDA | GPIO21, giữ để cấu hình tạm |
| SCL | GPIO22, giữ để cấu hình tạm |

Chọn chân **OUT** ở hàng VCC/OUT/GND của module; không chọn GPO/PGO ở hàng
DIR/SCL/SDA/GPO. Không nối OUT vào SDA21/SCL22 vì các chân đó còn phát tín hiệu
cấu hình I2C. Không nối OUT vào 5 V hoặc thêm điện trở kéo lên trên OUT.
Trở SDA 2,5 kΩ đang lắp có thể giữ cho giai đoạn cấu hình.

OUT/GND nên đi thành một cặp xoắn, tách khỏi cáp motor, có độ chùng cho Tilt.
Nguồn 3,3 V và GND phải tới module, kể cả khi chỉ đọc PWM.

## Nạp bản thử

Đóng GUI/Serial Monitor. Từ thư mục repository trong PowerShell:

```powershell
& 'C:\Users\Spooky Laptop\.platformio\penv\Scripts\platformio.exe' run -d firmware/positioner_v3_hold -e tilt-pwm -t upload
```

ESP32 thử cấu hình lúc khởi động với driver nhả. CONF dùng OUTS=10,
PWMF=01 (230 Hz), NOM; giữ nguyên các bit lọc/reserved. Chỉ chấp nhận range
full-turn ZPOS/MPOS/MANG=0 và đọc lại CONF xác nhận. Không ghi ZERO của chip,
không gửi lệnh BURN/OTP. Mất nguồn cảm biến sẽ trở lại cấu hình đã lưu trước
đó (thường analog), nên cần cấu hình lại. Sau reset ESP32, kiểm tra PWM_CONFIG.

## Kiểm tra đứng yên

Bật nguồn 20 V, cắm USB; giữ nguyên vị trí trong lúc script chạy:

```powershell
python -X utf8 firmware/positioner_v3_hold/test/hardware_pwm.py --port COM5 --configure
```

Script nhả, cấu hình tạm, đọc 30 mẫu lúc nhả / 100 lúc giữ / 30 sau khi nhả,
sau đó nhả và đóng COM5. Không phát STEP/GOTO/ZERO, không dùng VNA.
Đạt khi tất cả mẫu Tilt hợp lệ, span góc motor trong mỗi pha không quá 2°,
và driver không tự nhả trong pha giữ. Đây chưa phải phép đo sai số bàn anten.

Có thể dùng Serial Monitor 115200 baud/LF thay script, từng lệnh:

```text
HOLD OFF
TILT PWM CONFIG
TILT PWM CHECK
```

Kết quả cấu hình đúng: `TILT PWM CONFIG OK TEMPORARY 230HZ`.
Trong CHECK/POS cần `PWM_CONFIG:1`, `ENC_TILT_SOURCE:PWM`,
`ENC_TILT_VALID:1`, `PWM_PERIOD_US` khoảng 4350. `AGC:255` ở trường Tilt
trong bản PWM là **không có dữ liệu AGC**, được ghi rõ `AGC_TILT_AVAILABLE:0`.
Không diễn giải số này thành từ trường yếu hoặc sensor bị hỏng.

Nếu `ERR: TILT_PWM_CONFIG_I2C_READ/WRITE/READBACK`: cấu hình I2C chưa thành
công. Kiểm tra VCC/GND và tạm dùng đoạn SDA/SCL ngắn, vẫn giữ OUT về GPIO23.
Chỉ thay dây khi đã ngắt nguồn; cấu hình lại sau khi cấp nguồn. Nếu không thể
đưa ESP32 và cảm biến gần nhau để cấu hình, cần một bộ cấu hình I2C đặt gần
cảm biến hoặc phương án khác; bản thử này không bỏ qua lỗi cấu hình.

Nếu `PWM_CONFIG:1` nhưng `ENC_TILT_VALID:0`: kiểm tra OUT/GND, nguồn, nam châm
và dạng xung. PWM chưa được chứng minh ổn định trên dây 2 m của cơ cấu này.

## Dùng trong MATLAB

Chỉ sau khi bài đứng yên đạt: mở `AntennaMeasurementApp`, chọn ESP32 thật /
COM5, nhả motor → căn dấu → Khóa + ZERO. POS vẫn dùng RAW_TILT và validity
như trước nên MATLAB không cần thay API. Kiểm tra lại PWM_CONFIG sau khi GUI
mở cổng, vì mở cổng/reset có thể kích hoạt cấu hình lại. Chưa chạy Tilt rộng
hoặc 3D cho tới khi xác nhận góc di chuyển và phản hồi PWM.

## Quay về I2C

```powershell
& 'C:\Users\Spooky Laptop\.platformio\penv\Scripts\platformio.exe' run -d firmware/positioner_v3_hold -e esp32doit-devkit-v1 -t upload
```

Bản mặc định tiếp tục đọc RAW_ANGLE qua I2C; chân OUT có thể để nối GPIO23
ở trạng thái input. Cấp lại nguồn cảm biến sẽ bỏ cấu hình PWM tạm.

Nguồn: [ams OSRAM AS5600 datasheet, register map và PWM timing](https://www.mouser.com/datasheet/2/588/AS5600_DS000365_5_00-1877365.pdf).
