# Bàn giao VNA Workbench cho model triển khai

Ngày 2026-10-15. Các prompt dưới đây được giữ làm lịch sử bàn giao. Implementation M1–M5 và bằng chứng hiện tại: [nhật ký triển khai](../../vna-workbench-implementation-log.md), [hướng dẫn sử dụng](../../vna-workbench-user-guide.md). Kiểm chứng phần cứng: NOT_RUN.

## Tài liệu phải đi cùng nhau

1. [Thiết kế, sơ đồ kiến trúc, schema và giới hạn RF](../specs/2026-10-15-vna-workbench-design.md).
2. [14 task triển khai, API và tiêu chí kiểm tra](2026-10-15-vna-workbench-plan.md).
3. Repo AGENTS.md, INSTRUCTIONS_FOR_CODEX.md, CODEX_GUIDE.md và master-v4 như kế hoạch yêu cầu.

Root repo: C:\Users\Spooky Laptop\Documents\ChatGPT\antennamatlab.
Baseline lúc khảo sát: branch codex/ver2-pan-tilt-3d, HEAD 7ea2f9e55568c154f2689091c49566858dce3309. Đọc lại trạng thái hiện tại; không reset theo tài liệu.

## Cách giao việc đề xuất

Dùng cùng một model triển khai tuần tự từng mốc. Bắt đầu M1 để kiểm chứng SOL/TR và save/load trước khi sửa app lớn. Sau mỗi mốc, gửi bảng test và diff; người dùng có thể giao tiếp mốc sau bằng các prompt ngắn bên dưới. Không cần model tự đổi kiến trúc hoặc mở thêm agent.

| Mốc | Phạm vi | Điều kiện nhận bàn giao |
|---|---|---|
| M1 | Tasks1–4 | independent SOL/TR fixture pass, profile cross-process roundtrip, MATLAB Python smoke |
| M2 | Tasks5–7 | worker/STOP/lease/context và MATLAB façade pass |
| M3 | Tasks8–10 | Smith/live/wizard trong Mock, screenshots, no leaked resources |
| M4 | Tasks11–13 | calibrated 2D/3D, raw/corrected preservation, export và legacy load |
| M5 | Task14 | selected regressions, hướng dẫn, hardware runbook và status trung thực |

Nếu muốn giao toàn bộ một lần, thay dòng “Phạm vi lượt này: M1” trong prompt bằng “M1 đến M5, tuần tự theo gate”. Không bỏ test để hoàn thành nhanh.

## Prompt đầu tiên — có thể copy nguyên khối

~~~text
Hãy triển khai VNA Workbench trong repo hiện tại theo hai tài liệu:
- docs/superpowers/specs/2026-10-15-vna-workbench-design.md
- docs/superpowers/plans/2026-10-15-vna-workbench-plan.md

Phạm vi lượt này: M1, Tasks 1–4. Hoàn thành cả mốc và kiểm chứng, chưa sửa GUI/scan ngoài những helper/environment được liệt kê trong mốc.

Dùng using-superpowers, executing-plans và matlab-control khi áp dụng. Đọc AGENTS.md, INSTRUCTIONS_FOR_CODEX.md, CODEX_GUIDE.md và yêu cầu master-v4 trước khi sửa. Đọc HEAD/status/diff hiện tại; không reset, không đè thay đổi người khác, không tự đổi model hoặc tạo agent/chat.

Làm từng task: test thể hiện yêu cầu → chạy xác nhận lỗi → implementation tối thiểu → test pass → cập nhật implementation log. Các API/schema/constants/acceptance trong spec và plan là hợp đồng. Không đổi meaning S11/S21 raw, không fabricated S12/S22, không gọi TR là full two-port calibration.

M1 phải chạy fixture numerical trên scikit-rf 2.1.0 thật, gồm OnePort và TwoPortOnePath với ideal OSL mirrored S22=gamma nội bộ. Oracle phải là independent forward error formula, không chỉ gọi cùng engine embed/apply. Save/load .vnacal.json phải giữ raw standards, kit models và coefficients, verify bằng process mới.

Chỉ tests mock/fake/offline. Không mở COM, không chạy hardware scripts, không di chuyển motor/flash firmware. Không cần hỏi lại các lựa chọn triển khai đã chốt; nếu API thư viện không đúng giả định thì kiểm tra source pinned version và sửa adapter trong phạm vi spec. Nếu phải đổi schema/semantics/acceptance hoặc không chạy được MATLAB, báo blocker cụ thể, không đánh dấu pass.

Ghi docs/vna-workbench-implementation-log.md với files đã đổi, commands thực tế, versions, exit codes, test counts và giới hạn. Dùng temporary directories cho test, giữ dữ liệu đo thật. Không push/merge.

Kết thúc báo:
1. Task nào hoàn thành/chưa hoàn thành.
2. File/API chính đã thêm/sửa.
3. Test nào đã chạy và kết quả thực tế.
4. Sai lệch so với kế hoạch và lý do, nếu có.
5. Mốc tiếp theo; hardware luôn NOT_RUN nếu chưa có phép thử thật.
~~~

## Prompt tiếp các mốc

**M2:**
> Tiếp M2, Tasks5–7 của kế hoạch VNA Workbench. Đọc implementation log và diff hiện tại trước, giữ kết quả M1. Hoàn thành worker cancellation/complex averaging, MATLAB calibration façade, controller lease/generation và mock model; chạy tests của mốc và regression liên quan. Chưa làm GUI. Chỉ mock/fake, không COM.

**M3:**
> Tiếp M3, Tasks8–10. Tích hợp tab VNA, Smith/metrics, Single/Continuous/STOP và wizard SOL/TR đúng spec. Dùng shared controller/calibration, không mở connection thứ hai. Kiểm tra lifecycle bằng fake jobs và chụp giao diện Mock. Chỉ software tests.

**M4:**
> Tiếp M4, Tasks11–13. Tích hợp calibration vào scan 2D/3D, actual frequency grid, partial preservation, exports và views. Giữ raw, geometry schema và cơ khí guards. Kiểm tra BUSY/preflight trước connect positioner, close trong scan callback và analysis source nhất quán. Không hardware.

**M5:**
> Hoàn thành Task14: chạy explicit software regression allowlist, kiểm tra diff/data artifacts, viết user guide và hardware qualification runbook. Báo A1–A8 theo bằng chứng thực tế; A9 riêng. Không tự chạy phần cứng hoặc hạ ngưỡng nghiệm thu.

## Mẫu implementation log

~~~text
Mốc/task:
HEAD ban đầu:
Files:
API/schema thay đổi:
Environment versions:
Command | Exit code | Pass/Fail/Skipped | Evidence path
Numeric max error / persistence delta:
GUI/lifecycle evidence:
Regression:
Deviation và lý do:
Blocker:
Hardware: NOT_RUN
Next task:
~~~

## Những quyết định không được tự thay

- Driver FIFO hiện tại + scikit-rf + MATLAB GUI; không fork/nhúng nguyên NanoVNA-QT/Saver.
- S11/S21 là raw mãi; corrected riêng, source analysis rõ.
- SOL sửa S11; SOLT T/R enhanced response cho chiều thuận, không full two-port.
- Calibration lưu .vnacal.json self-contained, không phụ thuộc pickle.
- Actual integer Hz grid, exact profile match.
- Một VNA lease; wizard giữ lease giữa các chuẩn; close chờ worker/scan unwind.
- Calibration thiếu/sai khi policy SOL/TR thì dừng có thông báo, không tự RAW.
- Mock pass không chứng minh độ chính xác máy thật; không làm giả test results.

