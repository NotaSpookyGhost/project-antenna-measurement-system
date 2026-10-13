# Kiểm tra độc lập bộ bàn giao ver 2 / ver 3 — 11/10/2026

## Cập nhật sửa MATLAB — khoảng 14:12

Theo yêu cầu người dùng, đã sửa giao tiếp MATLAB để dùng firmware v3 đang có trên thiết bị. Bộ đọc POS nhận được cả định dạng v3 (RAW là độ motor) và dạng chữ của firmware cũ (đọc độ từ dòng Encoder, không nhầm với RAW count). Chỉ cập nhật trạng thái sau khi nhận đủ bốn trường Pan/Tilt và hai encoder hợp lệ, tránh giữ lại số cũ từ phản hồi thiếu dữ liệu.

GUI và controller mặc định COM5. GUI cho phép Tilt khi nhận đúng giao thức v3 và Tilt encoder khả dụng; constructor controller vẫn giữ lựa chọn `TiltDisabled` tường minh. Đích Tilt ngoài [-5°, 95°] bị từ chối trước khi gửi lệnh, theo giới hạn thực tế của nguồn firmware v3. Không thay đổi firmware hoặc nới ngưỡng kiểm tra encoder. Người dùng chấp nhận mô hình encoder ở đuôi motor và sai số quy đổi qua tỉ số truyền 5.625; không coi sai lệch nhỏ tại motor là lý do khóa hệ thống v3 đã được kiểm tra.

Kiểm tra thực tế bằng MATLAB đã kết nối COM5, ZERO, Pan 10°, Tilt 5°, Tilt 0°, Pan 0° thành công; đọc được cả hai encoder sau mọi lệnh. Các callback GUI thật cũng kết nối thành công, hiển thị ONLINE và mở trục Tilt cho v3. Dữ liệu tại `data/validation/matlab_positioner_v3_20261011_141239/history.csv` và `history.mat`. Đã thêm tám test hồi quy cho giao thức tại `matlab/tests/TestPositionerResponse.m` và bài test phần cứng nhỏ `matlab/tests/test_real_positioner_v3.m`. Test GUI cũ kỳ vọng nhầm chiều quét giảm 180°→0° là CCW; đã sửa thành CW theo quy ước nhìn từ trên và kết quả xác nhận trước đó.

Sau sửa: tám test giao thức PASS; `matlab/run_all_matlab_tests.m` đạt 5/5 nhóm (PatternAnalyzer, orchestrator mock, direction/abort, NanoVNA thật với motor mock, GUI mock), exit 0. Bộ Python chạy lại đạt exit 0, 39 test. Bài COM5 v3 thực tế và callback GUI đạt exit 0. Test giới hạn Tilt 100° xác nhận bị từ chối trước khi phát lệnh chuyển động. Lần chạy test tổng có đọc VNA COM6; dữ liệu tại `data/scans/real_vna_semi_hw_20261011_141344`, chỉ là kiểm tra pipeline với motor mock, không phải pattern anten thực.

Rà soát bổ sung đã sửa trạng thái Tilt còn lưu sau disconnect: mỗi lần kết nối lại phần cứng, GUI khôi phục khóa trước khi đọc giao thức/encoder mới, rồi chỉ mở lại cho v3 hợp lệ. Chạy lại bài phần cứng và callback disconnect/reconnect trên COM5 cùng test GUI mock đều PASS, exit 0; dữ liệu mới tại `data/validation/matlab_positioner_v3_20261011_141635`. Rà soát độc lập không còn phát hiện lỗi cần sửa trong phần thay đổi.

Khoảng 14:21, đã bấm Start Scan qua callback GUI thật với Positioner Hardware COM5 và VNA Mock: Pan 0°→5°→10°, ba điểm hoàn tất, không abort, có encoder tại mọi điểm, rồi trả Pan về 0°. Exit 0; lưu `data/scans/real_v3_gui_mock_vna_20261011_142158/scan_data.mat`. Đây là quét motor thật với RF giả lập. Khi mở MATLAB mới phải `addpath('matlab/classes', 'matlab/app')` trước khi tạo app: chỉ thêm app path sẽ không resolve được các property controller có kiểu class. Đã cập nhật lệnh mở trong hướng dẫn.

Các đoạn bên dưới mô tả lần kiểm tra 14:02 **trước khi sửa MATLAB**, giữ lại để thể hiện nguyên nhân và số đo gốc.

## Kết luận

Firmware v3 trong `CODEX_HANDOVER/contex ver2/firmware/firmware_positioner_v3.ino` build thành công bằng PlatformIO. ESP32 đang kết nối COM5 trả về đúng định dạng POS của nguồn v3. Ba chu kỳ thực tế `ZERO → GOTO 10 5 → GOTO 0 0` hoàn tất, cả hai encoder phản hồi, không ghi nhận lỗi/timeout I²C trong các phản hồi. Không nạp lại firmware trong lần kiểm tra này; nhận diện firmware theo giao thức phản hồi, không theo hash flash.

Kết quả này xác nhận chuyển động nhỏ hai trục với cơ chế tắt driver trước khi đọc encoder. Nó thay thế cách hiểu rằng Tilt không hoạt động được ở mọi firmware. Tuy nhiên, MATLAB GUI hiện tại chưa tương thích với POS của v3; đây là lỗi tích hợp đã tái hiện trực tiếp, độc lập với chuyển động motor.

## Nguồn đã đối chiếu

- `CODEX_HANDOVER/contex ver2/docs/walkthrough_v2.md`: nghiệm thu 13:28, COM9, kiểm tra ±250 bước riêng từng motor.
- `CODEX_HANDOVER/contex ver2/ver3/walkthrough_v3.md`: nghiệm thu 13:54, COM5, jog và hành trình Pan 10° / Tilt 5° rồi về gốc. Bản trong `contex ver2/docs/walkthrough_v3.md` có cùng nội dung.
- `CODEX_HANDOVER/contex ver2/README_AI_MASTER_CONTEXT.md`: nêu hiện tượng I²C lỗi khi EN bật và giải pháp tắt EN trước khi đọc.
- Folder `ver3/` chứa README, báo cáo Markdown và script Python; không có log serial thô riêng hoặc bảng nhiều lần đo. Các số đo cũ được lưu trong báo cáo, chưa thể kiểm tra lại trực tiếp từ log gốc.

## Xác minh mới

Thời gian chạy phần cứng khoảng 14:02 trên COM5, 115200 baud. Cổng được nhận diện CH340 VID:PID 1A86:7523; NanoVNA vẫn được liệt kê ở COM6. Kết nối Python đặt DTR/RTS false trước khi mở cổng. Chờ prompt sau mỗi lệnh, yêu cầu DONE khi GOTO, kiểm tra vị trí logic và encoder ở đích/về gốc. Lưu đầy đủ phản hồi tại:

- `data/validation/positioner_v3_recheck_20261011_140230/serial_transcript.json`
- `data/validation/positioner_v3_recheck_20261011_140230/summary.json`

Mốc encoder trước chu kỳ: Pan 72.60°, Tilt 48.43°; AGC Pan 48, Tilt 128. Góc RAW là góc motor, không phải trực tiếp góc mặt anten. Giá trị quy đổi dưới đây dùng tỉ số truyền danh định 90/16 = 5.625.

| Chu kỳ | Hành trình encoder Pan | Hành trình encoder Tilt | Sai lệch về gốc Pan, góc motor | Sai lệch về gốc Tilt, góc motor |
| --- | ---: | ---: | ---: | ---: |
| 1 | 55.98° | 24.26° | -0.18° | 0.00° |
| 2 | 56.16° | 24.26° | -0.09° | 0.00° |
| 3 | 56.16° | 24.26° | -0.09° | +0.09° |

Sai lệch về gốc lớn nhất tương đương khoảng 0.032° Pan và 0.016° Tilt theo tỉ số truyền. Đây là ước lượng từ encoder đuôi motor; không phải phép đo độc lập góc mặt anten. Test dùng ngưỡng hành trình lệch không quá 20% so với tỉ số truyền, sai lệch về gốc không quá 1° anten, encoder khả dụng và đủ DONE/prompt.

Hành trình Tilt đo được 24.26° motor, trong khi lệnh Tilt 5° tương ứng danh định 28.125° motor: lệch khoảng -13.74%, tương đương chỉ khoảng 4.31° theo tỉ số truyền. Pan gần giá trị danh định 56.25°. Vì vậy, độ lặp lại về gốc tốt chưa chứng minh độ chính xác góc tuyệt đối hoặc không mất bước. Chưa xác định nguyên nhân lệch Tilt; không thể khẳng định do dây đai, tải hoặc encoder chỉ từ dữ liệu này.

## Build và kiểm thử phần mềm

| Kiểm tra | Kết quả mới |
| --- | --- |
| PlatformIO build nguồn handover v3 trong project tạm, board esp32doit-devkit-v1, Arduino | SUCCESS; RAM 21,960 bytes, Flash 318,553 bytes — khớp số liệu báo cáo v3 |
| PlatformIO build `firmware/positioner` hiện tại | SUCCESS; RAM 22,040 bytes, Flash 319,805 bytes; đây là firmware khác v3 |
| Python `python -X utf8 -m unittest discover -s python/tests -p 'test_*.py'` | 39 tests, OK, exit 0 |
| MATLAB `test_pattern_analyzer.m` | 7/7 PASS |
| MATLAB `test_orchestrator_mock.m` | PASS, 73 điểm, lưu/xuất/đọc lại dữ liệu |
| MATLAB `test_scan_direction_and_abort.m` | PASS: hướng quét, abort, giữ dữ liệu một phần, khóa Tilt |
| MATLAB controller thực tế kết nối COM5, chỉ gửi POS | Tái hiện lỗi ConnectionFailed do định dạng POS không tương thích |

Các dòng FAIL trong stdout Python là các tình huống lỗi giả lập mà unit test chủ động tạo để kiểm tra xử lý lỗi; kết quả unittest tổng là OK. Dữ liệu giả lập được ghi vào `fifo_freshness_20261011_140143`, `s11_loads_20261011_140143`, `thru_20261011_140144`; scan MATLAB mock tại `data/scans/sim_azimuth_20261011_140210`. Không dùng chúng làm bằng chứng RF phần cứng.

## Các khác biệt cần biết trước khi tích hợp

1. **POS không tương thích.** V3 trả `PAN: ... TILT: ... RAW_PAN: ... (AGC:...) RAW_TILT: ... (AGC:...)`. `PositionerController.queryPositionInternal` yêu cầu dòng `Vi tri ang-ten: Pan = ...` và dòng `Encoder ... Pan ...`; v3 không phát các dòng đó. Thử kết nối thật COM5 đã trả: `Could not connect to ESP32 on COM5: ESP32 did not return a valid POS response with Pan and AS5600 encoder data.`
2. **Firmware vận hành khác nhau.** V3 chạy hai trục đồng thời bằng Bresenham, có ramp tuyến tính theo số bước, tắt cả hai EN và đợi 150 ms trước đọc. Firmware workspace chạy Pan rồi Tilt, kiểm tra từng chặng và giữ EN Tilt khi đọc. Kết quả lỗi I²C trước đây phù hợp với khác biệt này; chưa đo điện để khẳng định nhiễu nguồn đã được sửa tận gốc.
3. **Cổng mặc định cũ.** GUI và `firmware/positioner/platformio.ini` còn COM9; cổng thực tế hiện là COM5. Không upload firmware workspace chỉ để đổi cổng: firmware đó khác bản v3 đang chạy.
4. **V3 chưa có điều khiển hiệu chỉnh từ encoder.** Biến vị trí logic được tăng từ số xung đã phát; encoder được đọc để báo cáo, không tham gia hiệu chỉnh hay quyết định DONE. Tên/comment “closed-loop” trong báo cáo không phản ánh một vòng điều khiển góc thực hiện trong nguồn này. V3 cũng chưa xử lý STOP trong vòng phát xung; yêu cầu abort của MATLAB chưa được đáp ứng trên firmware v3.
5. **Script bàn giao chưa tự đánh giá PASS/FAIL.** `ver3/test_positioner.py` dùng sleep cố định rồi in phản hồi và luôn in thông báo thành công nếu chạy hết; không assert DONE, encoder, sai số hay timeout. Không dùng riêng dòng thành công đó làm bằng chứng nghiệm thu.

Không thay đổi mã nguồn điều khiển, không mở khóa Tilt trong GUI, không chạy SCAN góc lớn hoặc quét RF trong lần kiểm tra này. Ver 2 được đối chiếu từ dữ liệu bàn giao; không flash lại firmware chẩn đoán để tái chạy nó. Phạm vi xác minh thực tế v3 là ba chu kỳ nhỏ ở Pan 10° / Tilt 5°, chưa phải xác minh toàn dải 2D/3D hoặc vận hành dài hạn.
