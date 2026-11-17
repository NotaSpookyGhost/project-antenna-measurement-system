# Biên bản kiểm tra nghiệm thu — hoàn tất 2026-10-23

Kiểm tra bắt đầu ngày 22/10, tiếp tục và chốt bằng chứng ngày 23/10/2026 (Asia/Bangkok). Các kết quả bên dưới thuộc cùng commit; không chạy lại toàn bộ bộ test vì mã nguồn không đổi.

## Phiên bản và phạm vi

- Commit kiểm tra: `aeb1b9f67805d2004c694f63e8a835b0003a8112`.
- Baseline: `7ea2f9e55568c154f2689091c49566858dce3309`.
- Diff: `git diff 7ea2f9e...aeb1b9f`; một commit, 133 file, gồm cả VNA Workbench và motor journal chưa commit từ trước.
- Đã fetch origin; `origin/main` tại `86edc79` merge PR #2 có cây nội dung giống commit kiểm tra (`git diff --quiet aeb1b9f origin/main`, exit 0).
- Ưu tiên thay đổi runtime ngày 22/10: live plot, surface 3D, calibration backend, VNA transport và xuất dữ liệu.
- Không sửa mã nguồn sản phẩm, không mở cổng phần cứng thật, không điều khiển motor, không sửa dữ liệu đo gốc. Probe dùng dữ liệu tổng hợp và serial giả trong bộ nhớ.

## Kết luận

**REQUEST CHANGES — Chưa đạt nghiệm thu.** Có 5 lỗi xác nhận được: 1 P1 và 4 P2. Bộ test có sẵn chưa bao phủ các trường hợp này. Cần sửa và chạy lại các probe cùng bộ regression trước khi chấp nhận phiên bản.

## Standards — Tính đúng và quy tắc dự án

### 1. [P1] Gộp nhầm hai cực Bắc/Nam của đồ thị 3D

- Mã: `matlab/classes/ScanGeometry.m:89–93`.
- `poleValues` gom mọi mẫu θ=0° và θ=180°, sau đó gán cùng trung bình cho cả hai hàng cực.
- Tái hiện: cực Bắc 0 dB, cực Nam −20 dB bị dựng thành cùng −5.192746210 dB. Nếu chỉ đo cực Bắc, cực Nam chưa đo cũng bị điền thành 0 dB.
- Hệ quả: hình búp sóng 3D sai đối với anten bất đối xứng; hiển thị cả hướng chưa đo. Đây là lỗi dựng hình, probe không chứng minh dữ liệu raw bị ghi sai.
- Yêu cầu: `docs/ver2-pan-tilt-3d.md:61–63` yêu cầu điểm chưa đo để trống và chỉ gộp các mẫu tương đương khi dựng hình.
- Sửa: tính trung bình các mẫu theo từng cực θ riêng; giữ NaN cho cực chưa có dữ liệu.

### 2. [P2] Bỏ sót búp phụ tại biên lưới tròn không lặp điểm đóng vòng

- Mã: `matlab/classes/PatternAnalyzer.m:168–175`.
- Điều kiện `max(angles)-min(angles)>=359.999` coi lưới `0:359` là sector và loại phần tử đầu/cuối khỏi ứng viên local peak.
- Tái hiện: đỉnh chính 0 dB tại 180°, búp phụ −10 dB tại 0°, các láng giềng của búp phụ −20 dB. Kết quả trả NaN thay vì −10 dB tại 0°.
- Lưới `0:1:359` đang được dùng trong `matlab/tests/test_pattern_analyzer.m:33`.
- Yêu cầu: master §14.3, `docs/automatic-antenna-measurement-system-master-v4.md:1183–1186`, tìm local maxima ngoài main lobe.
- Sửa: xác định topology vòng tròn rõ ràng, hỗ trợ cả lưới có và không lặp điểm đóng vòng, đồng thời giữ quy tắc biên sector. Thêm test búp phụ tại biên.

## Spec — Hợp đồng xử lý lỗi VNA

Hợp đồng tại `CODEX_GUIDE.md:18–19`: transport failure phải dùng mã `TRANSPORT`, đánh dấu controller offline và vô hiệu hiệu chuẩn. `matlab/classes/VNAController.m:338–339` hiện chỉ xử lý job `FAILED/TRANSPORT`.

### 3. [P2] Mất mã TRANSPORT khi cấu hình sweep bất đồng bộ

- Mã: `python/nanovna_bridge.py:406–407`.
- `_configure_job()` đổi mọi lỗi cấu hình thành `VNAError('INVALID_REQUEST', status)`, kể cả `ERROR:TRANSPORT`.
- Tái hiện lỗi ghi serial trong cấu hình: job `FAILED/INVALID_REQUEST`; driver đã đóng, MATLAB bỏ qua `markTransportLost()` vì mã sai.
- Sửa: giữ đúng loại lỗi qua lớp cấu hình và job; kiểm tra trạng thái controller sau lỗi cấu hình.

### 4. [P2] Lỗi serial lúc clear FIFO bỏ qua cleanup và phân loại transport

- Mã: `python/nanovna_bridge.py:279–282` (cùng nhánh ở `acquire_sweep`).
- Driver gọi `clear_fifo()` trước `_read_fifo()`. `serial.SerialException` tại đây không phải `TransportError`, rơi vào nhánh lỗi chung.
- Tái hiện bằng driver thật với serial giả: job `FAILED/INVALID_SWEEP`, `driver_connected=True` sau lỗi ghi. MATLAB không cập nhật offline hoặc vô hiệu calibration theo hợp đồng.
- Sửa: chuẩn hóa SerialException và đóng transport cho toàn bộ thao tác acquisition, không chỉ vòng đọc FIFO.

### 5. [P2] STOP che mất lỗi transport đồng thời

- Mã: `python/vna_jobs.py:67` và `:94`.
- Sau acquisition, cancellation được xét trước status; khối finally xóa lỗi khi cancel đang bật.
- Tái hiện có đồng bộ bằng event: STOP trong lúc FIFO read gặp lỗi serial. Driver đóng nhưng job chỉ trả `CANCELLED`, không kèm thông tin transport loss. MATLAB tiếp tục giữ trạng thái connected và có thể giữ calibration ACTIVE.
- Sửa: tiếp tục loại bỏ raw đến muộn của job bị hủy, đồng thời truyền transport loss độc lập với trạng thái cancellation; cập nhật phía MATLAB để tiếp nhận.

## Bằng chứng kiểm thử

- Python regression của repo: **81/81 PASS**, 4.033 s, exit 0. Log `python-tests-committed.txt`.
- MATLAB allowlist: **134/134 unit tests và 3/3 scripts PASS**, không rò timer VNA; 139.1468 s testing time, exit 0. Log `matlab-verified.txt`; mã thoát trong `matlab-verified-exit.txt`.
- Probe MATLAB: xác nhận 3 biểu hiện thuộc 2 lỗi geometry/SLL. Đầu log `matlab-verified.txt`; script `repro_geometry.m`.
- Probe transport bổ sung: **3/3 contract assertions FAIL**, exit 1, đúng với 3 lỗi nêu trên. Script kiểm tra Git blob của nguồn trùng commit trước khi chạy. Log `repro-transport-verified.txt`, script `repro_transport.py`.
- `git diff --check 7ea2f9e...aeb1b9f -- matlab python`: PASS, exit 0. Kiểm tra toàn diff còn cảnh báo whitespace ở tài liệu/log bằng chứng cũ; không dùng các cảnh báo này làm lý do chặn nghiệm thu.
- Các probe bổ sung nằm riêng trong `output/review-2026-10-22/`; chưa được thêm vào bộ regression của sản phẩm.
- Kiểm tra lại ngày 23/10: fetch origin, cây nội dung `origin/main` vẫn trùng commit được review; `git diff HEAD -- matlab python` rỗng. Bằng chứng cũ vẫn áp dụng đúng phiên bản. Không có tiến trình MATLAB kiểm thử còn chạy.

## Giới hạn

Đây là nghiệm thu phần mềm. Không xác nhận độ chính xác RF thực, chuyển động cơ khí, encoder thực hoặc độ tươi FIFO trên NanoVNA thật. MATLAB có cảnh báo Python 3.13 không được hỗ trợ; ghi nhận theo log chạy, không chuyển cảnh báo thành kết luận rằng mọi tích hợp đều được hỗ trợ.

Tổng hai trục: Standards 2 lỗi (nặng nhất P1); Spec 3 lỗi (nặng nhất P2).
