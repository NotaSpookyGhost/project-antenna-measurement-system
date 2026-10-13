# Bản chốt giai đoạn 1 (`ver1`)

Bản này lưu trạng thái mã và cấu hình tại ngày 13-10-2026 để có thể tiếp tục phát triển giai đoạn 2 mà vẫn giữ được mốc giai đoạn 1. Các file được sao chép từ **working tree** tại thời điểm tạo snapshot, bao gồm cả sửa đổi chưa có trong commit nền `3a1e885064ee4a42ca42c0e86d692ba917aa0101`. `manifest.json` ghi kích thước và SHA-256 của từng file; tệp manifest không tự liệt kê chính nó.

## Thành phần

- `matlab/`: GUI, lớp điều khiển/đo, bài kiểm thử và cấu hình MATLAB.
- `python/`: NanoVNA bridge, driver, kiểm thử và công cụ liên quan.
- `firmware/positioner_v3_hold/`: firmware ESP32 đang dùng cho COM5, mã AS5600 và các bài kiểm tra. Các firmware khác trong `firmware/` được giữ để đối chiếu.
- `AP/` và `CODEX_HANDOVER/`: mã tham chiếu đã dùng khi so sánh/chuyển giao; **không phải** firmware đang nạp.
- `docs/`, `CODEX_GUIDE.md`, `INSTRUCTIONS_FOR_CODEX.md`, `AGENTS.md`, `README.md`, `.gitignore`: tài liệu, quy trình và cấu hình nguồn.
- `artifacts/positioner-v3.2.bin`: ảnh firmware đã build tại thời điểm chốt, hữu ích khi cần khôi phục đúng bản nhị phân. Mã nguồn và `platformio.ini` vẫn là cơ sở để tiếp tục phát triển.

Dữ liệu quét/validation trong `data/`, log, môi trường ảo, cache và phần còn lại của `.pio` không được sao chép. Chúng vẫn ở thư mục làm việc gốc; không xóa hay thay đổi chúng. Tài liệu audit riêng của phiên làm việc không nằm trong snapshot.

## Chạy lại

Môi trường đã dùng: MATLAB R2025b; Python 3.13.13 với `pyserial` 3.5; PlatformIO Core 6.2.0. `firmware/positioner_v3_hold/platformio.ini` chọn board `esp32doit-devkit-v1`, Arduino, cổng nạp COM5 và Serial 115200. NanoVNA thực dùng COM6; kiểm tra lại Device Manager trước khi kết nối.

Từ thư mục `ver1`, mở MATLAB và chạy:

```matlab
addpath('matlab/classes', 'matlab/app');
app = AntennaMeasurementApp();
```

Chế độ Mock cho phép thử GUI không cần thiết bị. Để điều khiển động cơ thật, chọn Positioner **ESP32 (thật)**, cổng COM5 và Connect. Cần hiệu chuẩn tay bằng **Nhả motor** → chỉnh cả hai trục → **Khóa + ZERO** trước khi quét. Chọn VNA Real/COM6 chỉ khi đo RF bằng thiết bị thật. Xem `CODEX_GUIDE.md` và `docs/as5600-fix-2026-10-13.md` trước khi chạy phần cứng.

Build firmware từ mã nguồn trong thư mục `ver1`:

```powershell
pio run -d firmware/positioner_v3_hold
```

Để nạp, đóng GUI/Serial Monitor, đỡ cơ cấu vì ESP32 reset sẽ tạm nhả motor, rồi dùng `run -d firmware/positioner_v3_hold -t upload`. Chỉ nạp khi chủ động thay firmware hiện tại.

Kiểm tra phần mềm không điều khiển phần cứng:

```powershell
matlab -batch "addpath('matlab/classes'); results=runtests({'matlab/tests/TestPositionerResponse.m','matlab/tests/TestManualHoming.m','matlab/tests/TestScanStopGUI.m'}); assertSuccess(results)"
python -X utf8 -m unittest discover -s python/tests -p 'test_*.py'
```

Các script tên `test_real_*`, `python/test_saa2n.py`, `matlab/test_python_bridge.m` và MATLAB master runner có thể mở cổng hoặc làm motor chuyển động. Chỉ chạy khi thiết bị đã sẵn sàng.

## Trạng thái cần nhớ

Pan đã đọc encoder hợp lệ trong lần thử 0–360° bước 10° và giữ lực liên tục ở lần kiểm tra trước khi chốt bản này. Đây là kết quả phản hồi encoder ở đuôi motor, chưa phải phép đo độc lập độ lệch cơ khí của bàn anten so với dấu zero. Tilt còn mất tín hiệu từng lúc khi driver bật với dây AS5600 khoảng 2 m, nguồn 3,3 V, chưa kiểm tra điện trở kéo lên ngoài. Không dùng `ver1` để khẳng định lỗi phần cứng Tilt đã hết.

Phát triển tiếp ở mã gốc của repository hoặc nhánh mới; giữ `ver1` như mốc tham chiếu. Nếu cần kiểm tra toàn vẹn, so SHA-256 của từng file với `manifest.json`.
