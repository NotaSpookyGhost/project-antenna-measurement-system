# Nhật ký encoder và kiểm tra Pan về ZERO

## Cách dùng

1. Mở lại app MATLAB để nạp mã mới.
2. Chọn ESP32 thật, kết nối, căn mốc do bạn chọn và bấm **Khóa + ZERO**. App ghi nhớ encoder Pan tại mốc này.
3. Chạy quét2D hoặc3D. Với ESP32 thật, nhật ký tự lưu cả khi **VNA đang Mock**.
4. Xem tab System & Hardware Logs: dòng **Nhật ký motor tự lưu** cho biết đường dẫn file. Mỗi lần Pan về0° có dòng báo độ lệch so với cùng ZERO gốc.

Các file nằm trong `data/logs/motor/motor_<thời-gian>_<id>.jsonl`. Mỗi lần quét có file riêng. Mỗi bản ghi được đóng file ngay sau khi ghi, nên nhật ký motor vẫn còn khi đóng app mà chưa bấm Export Dataset. Dữ liệu S11/S21 vẫn được lưu bằng Export Dataset như trước.

## App ghi những gì?

- Trước và sau mỗi lệnh tới điểm Pan/Tilt: góc lệnh, hai encoder, chỉ số điểm/hàng quét, HOLD, trạng thái mốc ZERO và bộ đếm nhả motor.
- Bước lỗi: giữ mã lỗi, thông báo và phản hồi POS gần nhất, kể cả phản hồi bị từ chối vì encoder không hợp lệ. Những góc đã chấp nhận và phản hồi POS thô là hai phần riêng.
- Khi Pan về0°: encoder gốc, mã mốc ZERO, chênh lệch encoder qua biên0/360 và độ lệch quy đổi sang góc anten.
- Chế độ RF/positioner, đơn vị encoder và kết quả kết thúc lượt quét. File dữ liệu xuất có thêm `Metadata.MotorJournalPath` để tìm lại nhật ký tương ứng.

Không cần quét xong mới có nhật ký. Bước motor gây lỗi được ghi ngay cả khi chưa đo/lưu điểm RF đó.

## Hiểu cảnh báo

Với phần cứng hiện tại, độ lệch quy đổi = độ lệch encoder motor /5.625. App cảnh báo khi Pan về0° lệch quá **1° anten ước tính**. Đây là ngưỡng chẩn đoán mới, không phải chứng nhận độ chính xác đo góc. Các điều kiện dừng vì encoder không khớp, mất giữ motor hoặc vượt hành trình vẫn giữ nguyên.

App **giữ nguyên ZERO ban đầu**, không tự ZERO mỗi vòng và không phát lệnh bù góc. Hành trình0→360→0 vẫn do cấu hình của bạn quyết định. Chỉ lệnh thành công tới Pan0° mới được kiểm tra khép mốc; Pan360° không bị coi là cùng góc encoder trục motor với Pan0°.

Mốc theo dõi bị hủy khi nhả/ngắt kết nối, khi POS báo mất giữ/mất hiệu chuẩn, khi bộ đếm nhả thay đổi hoặc keepalive không còn xác nhận HOLD. Lần Khóa + ZERO/Pan home thành công tiếp theo tạo mốc mới. App không nhận một lần quét mới hay phản hồi HOLD ON làm mốc thay thế. Nếu không có mốc hợp lệ, nhật ký ghi `reference_unavailable` thay vì báo đã về chuẩn.

Encoder nằm trên trục motor và chỉ trả góc modulo360. Phép kiểm tra này không độc lập xác minh góc bàn anten, không đo được trượt sau encoder và có thể không phân biệt độ lệch bằng nguyên vòng trục motor. Nhật ký từng bước hỗ trợ điều tra các trường hợp đó.

## Mock và lỗi ghi file

Mock positioner cũ dùng encoder mô phỏng với hệ số1; file ghi rõ `legacy_mock_encoder_degrees`. Phần cứng dùng `motor_shaft_degrees` và hệ số5.625. Mock RF không làm phản hồi motor thật biến thành mô phỏng.

Quét với positioner thật tự bật nhật ký. Khi dùng Mock positioner từ MATLAB/kiểm thử, đặt `orchestrator.MotorLogDirectory` tới thư mục mong muốn để bật. Nếu không tạo/ghi được bản ghi trước lệnh, lệnh quay tiếp theo không được gửi. Khi một lỗi motor đã xảy ra, lỗi ghi nhật ký phụ không thay thế mã lỗi motor gốc.

## Kiểm chứng phần mềm

Bộ kiểm thử bao gồm encoder qua biên359.9→0.1°, sai lệch tăng dần trên cùng mốc, phân biệt Pan360°/0°, nhiều lượt quét không đổi mốc, release/re-ZERO, bước lỗi chưa có điểm RF, lỗi ghi file và cấu hình MATLAB coi warning là error. Các bài này dùng Mock hoặc fixture cấm mở cổng COM.

Bản sửa bổ sung bằng chứng để chẩn đoán lỗi Pan ở cuối lần quét ngày17/10; chưa xác nhận nguyên nhân cơ khí và chưa thực hiện bài quay thật/endurance mới. Kết quả gate và nhật ký mẫu: `docs/verification/motor-journal-2026-10-17/`.
