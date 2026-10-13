# Đối chiếu AP và positioner_v3_hold — 2026-10-11

Người dùng báo bàn anten lệch dấu zero vật lý khoảng 5–6° sau chuỗi quét 0→360°, bước 10°. Người dùng xác nhận firmware đang chạy là positioner_v3_hold. Đây là sai lệch tại đầu ra anten, không phải góc motor để tiếp tục chia cho tỉ số truyền. Nguồn xác nhận: `C:\Users\Spooky Laptop\.codex\sessions\2026\10\11\rollout-2026-10-11T14-00-41-01a129c3-81b6-7031-8d21-6e996bee4d9e.jsonl:1285`, `:1347`, `:1469`.

## Kết luận đã xác nhận

AP giữ cả hai chân EN ở LOW từ setup và không nhả sau các lệnh quay (`C:\Users\Spooky Laptop\Documents\ChatGPT\antennamatlab\AP\src\main.cpp:330`). Bản positioner_v3_hold cố ý nhả cả hai driver sau mỗi lần quay, chờ 150 ms, đọc encoder rồi mới bật lại (`C:\Users\Spooky Laptop\Documents\ChatGPT\antennamatlab\firmware\positioner_v3_hold\src\main.cpp:180`). Cách này mâu thuẫn với yêu cầu “Giữ liên tục đến khi bấm Nhả” đã được chốt trong phiên trước (`C:\Users\Spooky Laptop\.codex\sessions\2026\10\11\rollout-2026-10-11T14-00-41-01a129c3-81b6-7031-8d21-6e996bee4d9e.jsonl:620`).

Mô phỏng biên dịch và chạy hai mã nguồn thật với GPIO/thời gian giả lập cho chuỗi 10,20,…,360° từ zero thu được:

| Tiêu chí | AP | positioner_v3_hold |
|---|---:|---:|
| Xung cạnh lên STEP Pan | 9000 | 9000 |
| Lần tắt driver Pan trong chuỗi | 0 | 36 |
| Thời gian nhả trong mô phỏng | 0 ms | 5400 ms |

Nguồn số liệu: `C:\Users\Spooky Laptop\.superpowers\diagnosing-superpowers\01a129c3-81b6-7031-8d21-6e996bee4d9e\simulation-results.json:5`, `:6`, `:7`, `:13`, `:14`, `:15`; script tái hiện: `compare_pan_scan.py` cùng thư mục. Stub không mô hình hóa lực giữ, trượt đai hoặc sai số góc cơ khí. Vì vậy số liệu này chứng minh luồng nhả driver và số xung, không chứng minh nguyên nhân duy nhất của 5–6° lệch vật lý. Trong phần cứng thật, thời gian đọc I²C và thử lại có thể kéo dài cửa sổ nhả hơn mô phỏng.

## Những khác biệt còn lại

| Thành phần | AP | positioner_v3_hold |
|---|---|---|
| Quy đổi góc Pan | 25 xung/độ | 25 xung/độ |
| Chu kỳ hành trình danh định | 2200 µs | 2200 µs cộng chi phí xử lý vòng lặp |
| STEP mức HIGH | 6 µs | Khoảng nửa chu kỳ |
| Tăng/giảm tốc | Ramp co theo chiều dài lệnh; tối đa 100 bước | Ramp cố định 80 bước |
| Điều khiển dòng qua UART | Không có trong mã nguồn | Không có trong mã nguồn |
| Đọc encoder sau chuyển động | Đọc khi driver vẫn được bật | Nhả cả hai motor rồi đọc |

Nguồn: `C:\Users\Spooky Laptop\Documents\ChatGPT\antennamatlab\AP\src\main.cpp:30`, `:79`, `:115`, `:160`; `C:\Users\Spooky Laptop\Documents\ChatGPT\antennamatlab\firmware\positioner_v3_hold\src\main.cpp:35`, `:144`, `:167`, `:180`. Việc AP khai báo dependency TMCStepper trong platformio.ini không đồng nghĩa mã nguồn đã gọi cấu hình tăng dòng; main.cpp chỉ dùng STEP/DIR/EN.

Datasheet TMC2209 xác định ENN=1 là disable/freewheel và dòng ở standalone liên quan VREF. Nguồn chính thức: https://www.analog.com/media/en/technical-documentation/data-sheets/tmc2209_datasheet_rev1.09.pdf (mục Standalone Operation). Không có căn cứ từ mã nguồn để nói AP đã lập trình mức dòng cao hơn. Nếu yếu ngay giữa lúc đang phát xung, cửa sổ nhả sau bước chưa đủ để giải thích toàn bộ hiện tượng; chưa đo dòng, nguồn và EN tại thời điểm đó.

## Encoder và kiểm chứng vị trí

Dù có nhãn CLOSED-LOOP, AP đọc encoder để in ra, sau đó gán `currentPan=targetP`; không tính sai số hoặc phát xung bù (`C:\Users\Spooky Laptop\Documents\ChatGPT\antennamatlab\AP\src\main.cpp:160`). Bản positioner_v3_hold cũng cập nhật góc theo số xung đã phát (`C:\Users\Spooky Laptop\Documents\ChatGPT\antennamatlab\firmware\positioner_v3_hold\src\main.cpp:185`). Góc logic đúng không bảo đảm bàn anten đúng khi bị trôi hoặc mất bước.

AS5600 0.6.7 trong AP trả giá trị đọc lần trước nếu I²C lỗi; hàm readAngleSafe của AP không kiểm tra lastError (`C:\Users\Spooky Laptop\Documents\ChatGPT\antennamatlab\AP\.pio\libdeps\onehorse32dev\AS5600\AS5600.cpp:319`, `C:\Users\Spooky Laptop\Documents\ChatGPT\antennamatlab\AP\src\main.cpp:58`). Do đó các số encoder được in ra ở AP chưa tự chứng minh việc đọc còn hợp lệ khi driver bật. Điều này không phủ nhận quan sát thực tế của người dùng rằng AP giữ khỏe và khép vòng tốt hơn.

MATLAB hiện gọi ZERO ở đầu mỗi scan, tức đặt lại mốc logic tại vị trí đang đứng thay vì quay về mốc vật lý ban đầu (`C:\Users\Spooky Laptop\Documents\ChatGPT\antennamatlab\matlab\classes\MeasurementOrchestrator.m:142`, `C:\Users\Spooky Laptop\Documents\ChatGPT\antennamatlab\matlab\classes\PositionerController.m:301`). Hành vi này có thể che khuất sai lệch qua nhiều lần scan; nó không sửa được góc cơ khí đã trôi.

## Thiếu sót của lần xác minh trước

Bài thử native chỉ kiểm tra EN ở cuối lệnh, vì vậy vẫn PASS dù motor nhả giữa lệnh. Bài thử phần cứng Pan 1° rồi về 0° kiểm tra góc do firmware báo và HoldingActive, chưa đo dấu zero vật lý hoặc quét đủ vòng. Nguồn: `C:\Users\Spooky Laptop\.codex\sessions\2026\10\11\rollout-2026-10-11T14-00-41-01a129c3-81b6-7031-8d21-6e996bee4d9e.jsonl:946`, `:1135`. Kết quả đó đủ cho giao thức nhưng chưa đủ để nghiệm thu giữ liên tục và độ chính xác đầu ra.

Trong lượt đối chiếu này, AP build thành công bằng PlatformIO (AS5600 0.6.7, TMCStepper 0.7.3); không nạp firmware, không mở COM5, không chạy scan vật lý thêm. Nguồn build: `C:\Users\Spooky Laptop\.codex\sessions\2026\10\11\rollout-2026-10-11T14-00-41-01a129c3-81b6-7031-8d21-6e996bee4d9e.jsonl:1454`.

SHA256 các nguồn đã đối chiếu:

- AP/src/main.cpp: `7C99BCA4D0867665A0E051CF15F5B85F96C2A766BD18B0098FCB963E9C578DAC`
- firmware/positioner_v3_hold/src/main.cpp: `05CB01C22098251A5A63B7055D3590F97D362D78C0DA5469903B081BC440B474`
