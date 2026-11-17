# Tích hợp ShockLine MS46122B vào app MATLAB

## Mục tiêu và bằng chứng

Người dùng muốn dùng MS46122B qua app MATLAB hiện có để đo kiểm anten.
ShockLine đang chạy trên cùng PC, TCP 127.0.0.1:5001. ID đã đọc:
`ANRITSU,MS46122B,2543302,V2025.4.3,V2.3.20`.
Đã nhận đủ 176 điểm S11 phức và danh sách tần số 1.000875–8 GHz.
Kênh 1 được đặt HOLD theo phê duyệt; chưa kích hoạt sweep mới.
Phản hồi ASCII dạng SCPI definite-length block có xuống dòng trong payload;
phải đọc đủ số byte header quy định, không dùng readline cho toàn bộ block.

## Phạm vi đề xuất để người dùng duyệt

1. Thêm lựa chọn Anritsu ShockLine vào app, địa chỉ mặc định
   `127.0.0.1:5001`; giữ Mock và NanoVNA riêng biệt.
2. Connect chỉ nhận dạng và đọc cấu hình/trạng thái; không tự cấu hình,
   trigger, reset, thay công suất hoặc thay hiệu chuẩn. Sai model hoặc lỗi
   phản hồi phải ngắt kết nối và báo lỗi, không chuyển sang mock âm thầm.
3. Có thao tác đo tĩnh S11/S21 không chuyển động motor. Đọc dữ liệu hiện có
   cần HOLD và hiển thị rõ đây là snapshot, chưa đảm bảo một sweep mới.
   Nếu cần đổi sang HOLD, giao diện giải thích và xin xác nhận trước.
4. Khi người dùng chủ động yêu cầu đo mới hoặc bắt đầu scan, hiển thị cấu hình
   tần số/số điểm và thao tác HOLD + single sweep để xác nhận trước khi gửi.
   Chỉ sửa thông số đã công bố; không tự sửa công suất, IFBW, calibration,
   preset hoặc thiết lập ngoài phạm vi này. Giữ nguyên định nghĩa trace.
5. Adapter tìm trace S11/S21 theo định nghĩa thực tế, đọc theo trace cụ thể
   hoặc phục hồi trace chọn cũ nếu cần chọn để đọc. Nếu thiếu trace thì báo lỗi;
   không tạo trace hoặc coi dữ liệu trống là phép đo hợp lệ.
6. Dùng danh sách tần số thực từ máy; kiểm tra đủ số điểm, giá trị hữu hạn,
   grid nhất quán giữa các góc và dữ liệu S11/S21 cùng một sweep đã dừng.
7. Ghi model/serial/version, địa chỉ, trạng thái correction, nguồn snapshot
   hoặc sweep mới vào dữ liệu lưu. Không gọi dữ liệu corrected là raw chưa
   hiệu chuẩn; không áp thêm hiệu chuẩn NanoVNA.
8. Disconnect chỉ đóng socket, giữ HOLD khi đang HOLD; không tự chạy lại,
   reset hay đổi trạng thái RF. Timeout/mất kết nối dừng phép đo và giữ dữ liệu
   đã hoàn thành; không tự thử lại lệnh ghi hoặc trigger không rõ kết quả.

### Điều kiện bổ sung sau rà soát thiết kế

- Snapshot là API riêng. `acquireSingle` dùng cho scan luôn phải đợi một sweep
  mới hoàn tất trước khi trả S11/S21, không được thay bằng dữ liệu snapshot cũ.
- Cả scan 2D và 3D phải kiểm tra frequency grid/số điểm/dữ liệu hữu hạn và lưu
  metadata thiết bị. Đường 2D hiện tự tạo linspace nên cần sửa theo readback thực.
- Một xác nhận trước scan trình đủ cấu hình, số vị trí và chuỗi sweep/motor của
  toàn lượt; không hỏi modal tại mỗi góc. Xác nhận phải xảy ra trước configureSweep
  và trước kết nối/di chuyển positioner trong luồng scan.
- Block lỗi, thiếu byte hoặc timeout phải đóng socket ngay; không gửi query tiếp
  trên luồng đã mất đồng bộ. Có regression test cho trường hợp newline trong
  payload và phản hồi bị cắt. Ưu tiên đọc theo trace cụ thể để khỏi đổi trace chọn.

## Lựa chọn kỹ thuật đề xuất của người triển khai

- Dùng `tcpclient` của MATLAB R2025b cho ShockLine, không thêm dependency
  Python/VISA cho thiết bị này. Kiểm tra tài liệu MathWorks trước triển khai.
- Giữ API VNAController để tương thích MeasurementOrchestrator; bổ sung adapter
  riêng cho ShockLine và điều chỉnh giao diện/metadata tối thiểu cần thiết.
- Giới hạn tần số dự kiến 1 MHz–8 GHz cho máy đang sử dụng; phải đọc/đối chiếu
  giới hạn thiết bị trước khi cho phép ghi cấu hình, không suy ra option chỉ từ ID.
- Không thêm S12/S22, hiệu chuẩn tự động, thiết lập công suất hoặc tính gain
  tuyệt đối trong lần tích hợp này. Mục tiêu đo S11 và S21 theo pipeline hiện tại.
- Không kết nối hay di chuyển ESP32 trong kiểm thử tích hợp VNA.

## Kiểm chứng và bàn giao

Viết kiểm thử offline cho socket/SCPI giả lập: block bị chia nhỏ, newline trong
payload, thiếu điểm, timeout, sai ID, thiếu trace, correction và grid thay đổi.
Chạy selected MATLAB mock suites trong CODEX_GUIDE cùng Python unit tests liên
quan; không chạy master runner/hardware tests. Kiểm tra GUI offline với Mock.
Chỉ sau khi người dùng duyệt riêng mới kết nối từ app tới VNA thật, đọc snapshot
và so với ShockLine. Sweep mới, thay cấu hình và scan motor cần phê duyệt riêng.
Không coi kiểm thử phần mềm là chứng nhận độ chính xác RF hoặc độ an toàn cơ khí.

## Tài liệu đối chiếu

- INSTRUCTIONS_FOR_CODEX.md, CODEX_GUIDE.md.
- docs/automatic-antenna-measurement-system-master-v4.md: S21 là observable
  chính của radiation pattern; S11 dùng diagnostic, không tự suy ra gain tuyệt đối.
- ShockLine Programming Manual 10410-00746 Rev. AC: dữ liệu SDATA yêu cầu HOLD,
  FREQ:DATA trả frequency list, CORR:STAT trả correction state.

Người dùng đã duyệt triển khai và kiểm thử offline ngày 2026-11-16. Phần mềm
đã được triển khai và kiểm thử theo execution ledger; nghiệm thu trên VNA thật
qua phiên bản app mới vẫn cần phê duyệt riêng.
