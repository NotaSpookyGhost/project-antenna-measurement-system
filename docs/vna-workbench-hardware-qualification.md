# VNA hardware qualification — NOT_RUN

Tài liệu này là quy trình cho người vận hành, không phải bằng chứng đo thật. Lượt triển khai chỉ chạy software/Mock. Không có motor motion, COM probe hoặc firmware flash được cấp bởi runbook này.

## Hồ sơ mỗi lần thử

Tạo folder mới, không ghi đè: timestamp UTC, operator, instrument label, ảnh/mã thiết bị, identity registers/firmware, cổng kết nối, kit và characterized model files + hashes, cable/adapter IDs, RF path ID, reference plane, band, actual grid, averages, engine/adapter versions và HEAD code. Lưu cả raw, calibration profile và corrected output.

Trước đo Real, người phụ trách xác nhận cấu hình và ngưỡng chấp nhận. Máy SAA-2N này chỉ đo S11/S21 chiều thuận; TR là enhanced response, không full two-port và không antenna gain dBi.

## Trình tự stationary VNA

1. Giữ positioner ở Mock/offline, không phát lệnh motor. Operator nối VNA và xác nhận COM thực; không tự scan tất cả các COM để tìm máy.
2. Thu nhiều sweep RAW trên một DUT ổn định; kiểm tra đủ indices, actual grid, không reference zero/nonfinite, không trace lặp bất thường. Lưu mọi lần fail.
3. Thu O/S/L với cùng RF plane, kiểm tra S11 bằng một chuẩn độc lập có characterized gamma nếu có. Với TR, terminate Port2 ở50Ω trong O/S/L, sau đó thu THRU. Capture averages4 theo mặc định và lưu raw từng chuẩn trong profile.
4. Solve/Apply/Save. Đóng session, reconnect, Load (READY), xác nhận path rồi Apply; cùng raw cho kết quả giống trong sai số số học. Không tự lấy onboard calibration làm correction FIFO.
5. So với NanoVNA-QT dùng cùng kit/cáp/grid/reference plane và quy trình PC calibration tương ứng. Dùng một DUT ổn định và attenuator hoặc thru kiểm tra; độc lập với standards dùng fit. Lưu QT version/settings/export cùng kết quả app, không chỉ screenshot.
6. Lặp lại tháo/nối, kiểm tra độ lặp lại và độ nhạy cable movement. Không chỉ đo lại đúng ba chuẩn fit để tuyên bố độ chính xác.
7. Thử Single/Continuous/STOP/close khi read đang chạy. Đo thời gian yêu cầu STOP→terminal bằng timestamp; không đóng COM trong read. Mục tiêu thiết kế<=15s theo read timeout hiện có, chưa được xác nhận trên máy thật. Nếu quá hạn, giữ trạng thái busy và điều tra; không mở connection thứ hai.
8. Thử sai band/path/profile engine/mode và reconnect; correction không được tự fallback RAW khi scan policy SOL/TR. Lưu evidence lỗi và trace cũ được giữ.

## Tiêu chí đề xuất cần người phụ trách chấp nhận

Đây là gate tương thích phần mềm, không phải specification độ chính xác của nhà sản xuất:

| Đại lượng app so với reference tương ứng | Ngưỡng đề xuất |
|---|---|
| max complex \|ΔΓ\| | <=0.02 |
| S21 magnitude | <=0.5dB |
| Circular S21 phase difference | <=5° khi S21 của cả hai >-40dB |
| Save/load apply trên cùng raw | max complex delta<=1e-12 |
| STOP latency | ghi actual, mục tiêu thiết kế<=15s |

Không có characterized standard/reference phù hợp thì trạng thái NOT_QUALIFIED. Không hạ ngưỡng sau khi thấy kết quả để pass. Ghi cả uncertainty/giới hạn match phía nhận, drift và các điểm bị loại theo rule đã chấp nhận trước.

## Sau stationary qualification

Scan Real2D/3D cần quy trình ZERO/hold/encoder/travel hiện có và authorization cho motion cụ thể. Stationary RF pass không chứng minh góc anten, gain tuyệt đối hoặc cơ khí3D. Chỉ ghi A9 VERIFIED khi có raw/reference logs và người phụ trách chấp nhận kết quả thực.

Status hiện tại: **NOT_RUN**; operator/reference/physical accuracy/STOP latency trên thiết bị thật chưa được kiểm chứng trong đợt code này.
