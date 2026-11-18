# ShockLine trong app MATLAB

## Sử dụng

Giữ ShockLine chạy và kết nối USB với MS46122B. Trong ShockLine, kênh 1 cần
trace S11 và thông số truyền đã chọn (S21 hoặc S12), numeric transfer dạng ASCII. App không tạo lại trace,
preset, thay công suất hoặc thực hiện calibration.

Mở app như CODEX_GUIDE.md, chọn **Anritsu ShockLine**, chọn **Transmission**:
**S21: 1 → 2** hoặc **S12: 2 → 1**, nhập
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

S21 phát Port 1, thu Port 2; S12 phát Port 2, thu Port 1. Nếu cả hai trace đã có,
có thể đổi lựa chọn khi không đo; app chỉ truy vấn tìm trace, không tự tạo lại.
Thiếu trace được chọn sẽ báo lỗi và giữ lựa chọn trước đó. Lựa chọn bị khóa
khi quét hoặc đang đọc RF. Đồ thị và MAT/CSV ghi đúng S21 hoặc S12; dữ liệu
S12 được lưu ở trường `S12`, không ghi dưới tên S21. Lượt so sánh anten tham
chiếu phải dùng cùng chiều đo và cấu hình. Phần S12 đã kiểm tra offline,
chưa nghiệm thu trên phần cứng thật.

Trong tab **Live RF Monitor**:

- **Read snapshot (HOLD)**: sau xác nhận, đưa kênh 1 sang HOLD và đọc dữ liệu
  hiện có; không tạo lượt quét mới. Không nối hoặc điều khiển motor.
- **Acquire new sweep**: đọc và hiển thị band/số điểm thực để xác nhận, sau đó
  HOLD và single trigger, đợi parser kết thúc sweep rồi đọc S11 và S21/S12 đã chọn.
  Không thay band, points, IFBW hoặc power trong thao tác đo tĩnh này.
- **Save MAT + CSV**: MAT có dữ liệu phức, frequency vector, model/serial/version,
  correction flag, IFBW, timestamp và nguồn snapshot/fresh. CSV chứa complex
  S11 và S21/S12 đã chọn, cùng dB; giữ file MAT đi kèm để giữ metadata.

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
