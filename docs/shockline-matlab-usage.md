# ShockLine trong app MATLAB

## Sử dụng

Giữ ShockLine chạy và kết nối USB với MS46122B. Trong ShockLine, kênh 1 cần
trace S11 và S21 và numeric transfer dạng ASCII. App không tạo lại trace,
preset, thay công suất hoặc thực hiện calibration.

Mở app như CODEX_GUIDE.md, chọn **Anritsu ShockLine**, nhập
`127.0.0.1:5001`, rồi **Connect**. Connect chỉ gửi truy vấn nhận dạng,
cấu hình và trạng thái; không trigger hoặc tự dừng quét. Địa chỉ có thể đổi
nếu cổng server của ShockLine đã được cấu hình khác.

Center/Span lấy từ máy được giữ 17 chữ số có nghĩa để tái tạo đúng band đã
calibration, không dùng num2str mặc định làm tròn. Sai số số học vài ULP khi đổi
MHz/Hz được chuẩn hóa về đúng biên; đây không phải nới giới hạn band. Nếu band
và số điểm vẫn trùng readback hiện tại, scan không ghi lại các thông số đó.
Bản sửa có hiệu lực với phiên app mở mới; không cần chỉnh tay Center/Span sau
mỗi lần kết nối. Kiểm thử offline gồm band thực đã gây lỗi, chặn yêu cầu vượt
biên 1 Hz, và fresh app Connect qua TCP giả lập; không dùng VNA hoặc motor thật.

Trong tab **Live RF S11/S21 Monitor**:

- **Read snapshot (HOLD)**: sau xác nhận, đưa kênh 1 sang HOLD và đọc dữ liệu
  hiện có; không tạo lượt quét mới. Không nối hoặc điều khiển motor.
- **Acquire new sweep**: đọc và hiển thị band/số điểm thực để xác nhận, sau đó
  HOLD và single trigger, đợi parser kết thúc sweep rồi đọc S11/S21.
  Không thay band, points, IFBW hoặc power trong thao tác đo tĩnh này.
- **Save MAT + CSV**: MAT có dữ liệu phức, frequency vector, model/serial/version,
  correction flag, IFBW, timestamp và nguồn snapshot/fresh. CSV chứa complex
  S11/S21 và dB; giữ file MAT đi kèm để giữ metadata.

Sau đo app để HOLD; HOLD không được coi là bảo đảm RF đã tắt.
Nút **ShockLine bình thường: trả quyền** bàn giao lại máy. Khi đang ngắt kết nối,
nút đổi thành **MATLAB đo: kết nối** để lấy lại quyền qua app, không tự trigger.

Khi bàn giao, Disconnect, đổi chế độ VNA hoặc đóng app bằng nút X, chọn:

- **Normal sweep**: đặt channel 1 CONT, xác nhận readback, gửi `RTL` cuối cùng
  rồi đóng socket. ShockLine tiếp tục quét với cấu hình hiện tại và dùng được
  giao diện tại máy. Không thay power, band, points hoặc calibration.
- **Keep HOLD**: đặt và xác nhận HOLD, gửi `RTL` rồi đóng socket. Giao diện
  ShockLine dùng được nhưng lượt quét vẫn dừng.
- **Cancel**: giữ phiên kết nối/app hiện tại.

Không gửi SCPI sau RTL vì lệnh mới có thể lấy quyền remote trở lại. Nút bàn giao
bị khóa khi scan/đo đang chạy. Nếu lỗi bàn giao, app báo chưa xác nhận và hướng
dẫn nhấn Esc trong ShockLine. Buộc tắt MATLAB/crash không bảo đảm chạy được
cleanup; dùng Esc để trả quyền rồi chọn Sweep theo nhu cầu. API disconnect/delete
cấp thấp vẫn chỉ đóng socket, không âm thầm kích hoạt RF; các hộp xác nhận thuộc
luồng giao diện tương tác.

Nghiệm thu bàn giao ngày 2026-11-16 khoảng 17:31 (giờ Bangkok): người dùng đã
duyệt cả triển khai và thử máy thật. Nút MATLAB đo kết nối thành công; nút
ShockLine bình thường → Normal sweep thực hiện CONT/readback/RTL/close.
Nhật ký app: `Sent RTL; socket closed. ShockLine: Normal sweep`.
Các nút ShockLine trở lại trạng thái có màu và marker 2.4 GHz cập nhật từ
-7.7327 sang -7.7269 dB ở hai lần quan sát liên tiếp. Windows chỉ còn socket
TIME_WAIT, không có kết nối điều khiển established tới port 5001.
Không đổi power, band, points, IFBW, calibration hoặc kết nối motor trong thử này.
29 selected MATLAB tests đã đạt trước sửa phát hiện cuối; sau bổ sung enforce HOLD,
12 protocol/provenance tests và GUI test đã chạy lại đạt. Reviewer đã phát hiện
nhánh Keep HOLD cần chủ động đặt HOLD từ CONT; nhánh này có regression và đã sửa.

## Scan anten

### Chọn cách quét AZ, Tilt và 3D

Bản `V4.0_HOLD_CONTINUOUS_AXES` đã được nạp và kiểm tra hash trên ESP32 COM4
ngày 2026-11-20. Truy vấn POS xác nhận cả hai capability, cả hai encoder hợp
lệ, HOLD=0 và CAL_REQUIRED=1. Bản sao flash 4 MB trước khi nạp được lưu tại
`../setup-logs/esp32-COM4-before-axes-20261120.bin`. Kiểm tra sau nạp dùng POS,
chưa chạy quét RF khi bàn xoay chuyển động.

Chọn **Anritsu ShockLine**, rồi chọn **Azimuth (AZ)**, **Elevation (EL)** hoặc
**3D Pan × Tilt**. Menu bên cạnh **Points** có
hai lựa chọn **Dừng đo từng điểm** và **Quét liên tục**. Mặc định là dừng từng
điểm. AZ/EL dùng Start, Stop, Angle Step của màn hình chính. Thông số 3D
và hành trình được đặt trong **3D / ZERO**.

Ở chế độ AZ hoặc EL liên tục, app đo tại góc đầu rồi quay trục đã chọn suốt
lượt quét và lấy mẫu khi đang quay. Trục còn lại giữ nguyên góc. CSV/MAT
lưu góc lệnh, góc đo và góc đầu/cuối sweep. Chế độ 3D đo điểm đầu hàng khi
bàn xoay đã ổn định, sau đó cho
Pan quay tới cuối hàng bằng một lệnh. Các sweep S11/S21 mới được thu trong
lúc Pan đang quay. Tilt đổi giữa các hàng. Cấu hình Pan luân phiên vẫn áp dụng.
Mỗi sweep tần số được kích riêng để đọc S11/S21 cùng một sweep hoàn chỉnh.

Firmware `firmware/positioner_v3_hold` phiên bản `V4.0_HOLD_CONTINUOUS_AXES` cần
được nạp vào ESP32. Firmware trả capability `CONT_PAN_CAP:1`, `CONT_TILT_CAP:1`
và telemetry encoder hai trục mỗi khoảng 100 ms khi chạy `PANSCAN` hoặc
`TILTSCAN`. Sau khi nạp, kết nối
lại, đặt **Khóa + ZERO** và xác nhận hành trình cơ khí trong **3D / ZERO**.
App kiểm tra capability trước khi bắt đầu hàng quét liên tục.
PlatformIO được pin ở Espressif32 7.1.3 theo môi trường build đã kiểm tra.
Từ root `clonetest`, build bằng `pio run -d firmware/positioner_v3_hold`.
Khi đã kết nối ESP32, nạp bằng `pio run -d firmware/positioner_v3_hold -t upload --upload-port COMx`,
thay `COMx` bằng cổng thực tế của bàn xoay.

CSV và MAT lưu góc Pan encoder đầu/cuối mỗi sweep, thời gian bắt đầu/kết thúc
và góc giữa sweep. Góc Pan được giải cuộn encoder phía motor theo tỉ số
90/16, neo tại góc đầu hàng. Chiều encoder được suy ra từ chuyển động đầu
hàng. `PanAngles` và `ColumnIndex` giữ lưới dự định, còn `MeasuredPanAngles`
và `PhiDeg` mô tả vị trí gán cho sweep. Đồ thị mặt 3D gom mẫu vào ô lưới dự
định, và lát cắt dùng góc đo thực.

Luồng encoder/I2C/UART chạy trên tác vụ core 0, trong khi core 1 tạo STEP.
Góc RF được chốt trước trigger và sau phản hồi `*OPC?`, trước khi tải trace.
Khoảng góc này còn bao gồm độ trễ đồng bộ TCP và độ phân giải telemetry
100 ms. Mỗi sweep tần số chứa nhiều thời điểm đo RF trong khoảng góc đó.
Các cột `encoder_start_device_ms` và `encoder_end_device_ms` giữ thời gian
uptime ESP32 của mẫu encoder. Đồng hồ này độc lập với thời gian host của
sweep, và để trống tại điểm đứng yên đầu hàng. Trong Mock, đồng hồ encoder
tính tương đối từ đầu hàng.

Một sweep RF có thể phủ một khoảng góc khi anten quay. Bước góc là khoảng
lấy mẫu mong muốn. Khi VNA chậm hơn nhịp này, app tiếp tục quét, bỏ qua các
mốc đã đi qua và lưu góc encoder thực cùng góc đầu/cuối mỗi sweep. App báo
mẫu thưa hơn bước đã chọn và ghi `ResolutionLimited` trong metadata. Điểm
cuối mỗi lượt được đo một lần, các ô lưới chưa có dữ liệu giữ trống.
Nếu cần đo tại từng góc đứng yên cách nhau đúng bước đã nhập, chọn
**Dừng đo từng điểm**. Giảm thời gian sweep trên VNA cũng giúp tăng mật độ mẫu.
STOP dừng Pan và giữ motor. Sau khi ngắt chuyển động cần đặt lại ZERO.
Trong chế độ liên tục, dùng STOP để dừng lượt quét. Pause dành cho chế độ
dừng từng điểm.

Kiểm thử phần mềm gồm `matlab/tests/TestContinuousScan.m` và native test
`firmware/positioner_v3_hold/test/native/test_continuous.cpp`. Chế độ này cần
được kiểm tra trên bàn xoay và MS46122B thực tế để xác định độ chính xác góc
và thời gian sweep phù hợp với cấu hình RF đang dùng.

Đặt center/span/points và geometry như trước, xác nhận toàn bộ lượt scan trước
khi app kết nối motor hoặc cấu hình VNA. Chế độ motor Mock vẫn là mô phỏng góc,
không được dùng kết quả đó làm búp sóng anten đo thật. Scan thật cần mechanical
ZERO và encoder/travel đã được xác minh theo tài liệu positioner hiện hành.

Scan cấu hình band/points, HOLD, rồi lấy một sweep mới tại mỗi góc. Không tự
đổi power, IFBW hoặc calibration. Giới hạn ghi band được giữ trong band đọc
lúc Connect, tối đa 16.001 points. Đây là giới hạn bảo thủ, không phải phát hiện
option phần cứng. Nếu cần band rộng hơn, đặt trong ShockLine rồi reconnect.

App dùng frequency vector thực, kiểm tra đầy đủ số điểm và grid nhất quán.
Correction/IFBW thay đổi giữa các góc sẽ dừng scan và giữ các điểm đã commit.
Không chỉnh ShockLine đồng thời khi app đang đo: socket không khóa được giao
diện hãng, và correction flag không phát hiện được mọi thay đổi bộ calibration.
Dữ liệu correction=1 được ghi đúng trạng thái này, không áp calibration NanoVNA.
Giá trị S21 chưa tự trở thành gain anten tuyệt đối.

Lỗi framing/timeout đóng socket, không gửi lệnh tiếp trên luồng mất đồng bộ và
không tự retry trigger. STOP được xử lý giữa các thao tác đồng bộ; một lần đọc
TCP có timeout 10 giây. App không bảo đảm ngắt tức thì một sweep đang chạy.

## Kiểm thử và trạng thái bàn giao

Triển khai đã được kiểm tra offline bằng MATLAB R2025b, byte stream giả lập,
GUI Mock, và máy chủ TCP loopback riêng (không dùng cổng 5001/5025). Có kiểm
tra giữ một điểm scan khi mất kết nối tại lượt thứ hai. Các selected MATLAB
regressions và Python unit suite đã đạt; các artifact mock sinh ra giữ riêng.

Nghiệm thu snapshot trên máy thật ngày 2026-11-16 đã được người dùng duyệt:
app kết nối ONLINE với MS46122B serial 2543302, đọc đủ 176 điểm S11/S21,
correction=1 và giữ HOLD; không trigger sweep mới, không kết nối motor.
S11 phức trùng hoàn toàn snapshot SCPI trước đó. Nội suy dB tại 2.4 GHz cho
-7.139022 dB, khớp marker ShockLine hiển thị -7.139 dB. Tại điểm thực 2.4007 GHz:
S11=-7.157472 dB, S21=-49.866315 dB. MAT/CSV và comparison.json lưu tại
`data/validation/shockline_matlab_acceptance_20261116/`.
Sweep mới hoặc scan motor thật chưa được nghiệm thu và cần phê duyệt riêng.

Mở app bằng `Open Antenna App.vbs` (dùng `-r` tương tác). Không dùng `-batch`
cho phiên app sử dụng thật: MATLAB không cho hiện questdlg chặn trong chế độ đó.

Nguồn: ShockLine Programming Manual 10410-00746 Rev. AC
https://dl.cdn-anritsu.com/en-us/test-measurement/files/Manuals/Programming-Manual/10410-00746AC.pdf
và MathWorks tcpclient/read (các API có trong R2025b):
https://www.mathworks.com/help/matlab/ref/tcpclient.html
https://www.mathworks.com/help/matlab/ref/tcpclient.read.html
