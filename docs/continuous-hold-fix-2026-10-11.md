# Sửa giữ motor liên tục và giữ mốc ZERO — v3.1

## Thay đổi

- Bỏ hoàn toàn thao tác nhả driver giữa các bước, khi đọc POS và khi bấm LOCK ZERO lúc đang giữ. Khởi động vẫn nhả; kết nối MATLAB giữ cả hai trục; Nhả/Disconnect và mất heartbeat 30 giây mới nhả.
- STEP HIGH 6 µs, chu kỳ cruise 2200 µs và ramp 5000→2200 µs co theo chiều dài lệnh (tối đa 100 bước), dựa trên AP. Số xung vẫn 25/độ. AP gốc không bị sửa. Không thay đổi dòng TMC2209/VREF.
- Nhận STOP không chặn luồng phát xung; giữ motor sau STOP, đánh dấu cần căn ZERO lại nếu ngắt giữa chuyển động. Watchdog có hiệu lực cả trong lệnh quay dài. MATLAB gửi KEEPALIVE không phản hồi trong lệnh dài.
- Không ZERO tự động ở đầu scan. Lần quét tiếp theo di chuyển theo đúng mốc đã căn bằng tay. Không còn đặt lại mốc tại vị trí đang đứng sau lần quét trước.
- Chỉ lấy một snapshot vị trí cho mỗi bước. Góc theo số xung và góc encoder đuôi motor được ghi riêng; encoder lỗi là NaN với EncoderValid=false, không giả làm số đo hợp lệ. Metadata nói rõ góc bàn anten chưa được đo độc lập.
- Khi thử thực tế, Wire/I2C có lúc vượt timeout và làm MATLAB mất POS ở khoảng 200°. Đã chuyển đọc I2C sang worker riêng, mỗi POS đợi tối đa 200 ms; chỉ nhận kết quả đúng mã yêu cầu. Kết quả trễ của lần đọc cũ bị loại. Lỗi I2C không làm nhả driver.
- Giữ sửa đồ thị STOP trước đó: điểm đo/đồ thị đang có được giữ, lần quét tiếp theo hiện lại tab đồ thị.

## Giới hạn phải phân biệt

AS5600 trên thiết bị hiện tại vẫn có thể mất tín hiệu khi driver bật. Chế độ này tiếp tục quét theo số xung, có cảnh báo rõ; không phải điều khiển kín đã xác minh. Các kiểm tra sai lệch encoder khi có hai lần đọc hợp lệ vẫn còn. Không bù góc bằng dữ liệu lỗi, không tăng dòng driver bằng phỏng đoán.

RELEASES là bộ đếm nhả EN của firmware, không phải phép đo điện áp chân EN hay lực giữ. 9.000 xung và góc logic 360° không tự chứng minh bàn anten khép vòng chính xác. Sai lệch 5–6° người dùng báo là tại bàn anten, không được chia thêm cho tỉ số truyền. Cần đối chiếu dấu zero vật lý để nghiệm thu độ chính xác cơ khí.

## Cách dùng

Mở lại GUI để nạp lớp MATLAB mới. Chọn Positioner ESP32 (thật), COM5, Connect; Nhả motor; căn hai trục theo dấu vật lý; Khóa + ZERO. Chọn AZ, Start 0, Stop 360, Step 10. VNA Mock chỉ dành cho thử motor; RF thật cần VNA thật. Giữ dấu zero đó qua các lần quét. Nếu STOP giữa chuyển động hoặc đã nhả motor, căn và ZERO lại.

## Lệnh kiểm chứng

```powershell
g++ -std=c++17 -Wall -Wextra -I firmware/positioner_v3_hold/test/native/stubs firmware/positioner_v3_hold/test/native/test_hold.cpp -o "$env:TEMP\antenna_v3_hold_test.exe"
& "$env:TEMP\antenna_v3_hold_test.exe"
& 'C:\Users\Spooky Laptop\.platformio\penv\Scripts\platformio.exe' run -d firmware/positioner_v3_hold
matlab -batch "addpath('matlab/classes','matlab/app'); r=runtests({'matlab/tests/TestPositionerResponse.m','matlab/tests/TestManualHoming.m','matlab/tests/TestScanStopGUI.m'}); assertSuccess(r)"
```

`matlab/tests/test_real_continuous_hold.m` là bài thử phần cứng chủ động, không nằm trong master runner: lấy vị trí hiện tại làm ZERO, quay Pan 0→360 bước 10°, quét lại 350→360 cùng mốc, rồi về 0. Chỉ chạy khi cơ cấu an toàn. Nó ghi log/MAT vào `data/validation/continuous_hold_*`; RF mô phỏng.

## Kết quả kiểm chứng

- Regression native đã FAIL trên mã cũ tại kiểm tra số lần nhả EN; sau sửa PASS: 9.000 xung cho 0→360 bước 10°, không nhả cả Pan/Tilt giữa các bước, POS và LOCK ZERO. I2C lỗi không đổi EN; STOP và lease trong lúc quay được kiểm tra.
- Regression MATLAB giữ mốc đã FAIL trên mã cũ (hai lần quét gọi ZERO hai lần); sau sửa hai lần quét không gọi ZERO, dữ liệu encoder mất tín hiệu được đánh dấu đúng.
- Bộ MATLAB gồm 21 tests parser/manual homing/STOP/GUI PASS. Các script quét xuôi/ngược, abort và mock end-to-end 73 điểm cũng PASS.
- PlatformIO build/upload COM5 PASS, esptool xác minh hash. Bản cuối dùng 22.072 byte RAM tĩnh và 320.241 byte flash.
- Thử MATLAB + motor thật + VNA Mock: 37/37 điểm 0→360 bước 10° trong 38,01 giây; RELEASES=0 ở mọi điểm. Quét tiếp 350→360 với cùng ZERO và về góc logic 0° PASS. Log/MAT: `data/validation/continuous_hold_20261011_203941/`. Không đo độ lệch tại bàn anten.
- Bài thử trước khi tách I2C bị lỗi phản hồi POS khoảng 200°; log thất bại được giữ nguyên để đối chiếu, không tính là PASS.
- Bản cuối qua lại bài no-motion HOLD/RELEASE/LOCK ZERO và watchdog 30 giây; log `hold_lease_smoke.log` trong thư mục trên. STOP giữa lệnh PAN 5 dừng ở góc logic 0,68°, giữ HOLD:1, CAL_REQUIRED:1 và bộ đếm RELEASES không tăng; log `stop_smoke.log`. Bài thử kết thúc bằng HOLD OFF, đã đóng COM5. Người dùng cần căn ZERO lại trước lần đo tiếp theo.

SHA256 nguồn cuối: `16789C4A8D842952ED50FA3F2593E1D236AA13EB9FE84D307B5EC5453BADB567`.
SHA256 firmware.bin đã nạp: `C0DB42D7F2416A8B852A061DA767A49B0794A1BC559593C29FCBCAEFD525BCC0`.
AP giữ nguyên SHA256 `7C99BCA4D0867665A0E051CF15F5B85F96C2A766BD18B0098FCB963E9C578DAC`.
