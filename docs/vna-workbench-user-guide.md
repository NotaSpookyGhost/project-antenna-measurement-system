# VNA Workbench — hướng dẫn sử dụng

Phạm vi: S11/S21 chiều thuận, SOL cho S11, SOLT T/R enhanced response cho S11/S21, Smith/LogMag/Phase/VSWR và scan anten 2D/3D. S21 là transmission; không phải gain anten dBi. Xem implementation log để biết chính xác phần đã kiểm chứng.

## Khởi động

Tại root repo, dùng Python3.13 hiện có tạo môi trường riêng nếu chưa có:

```powershell
& 'C:/Users/Spooky Laptop/AppData/Local/Programs/Python/Python313/python.exe' -m venv .venv-vna
& ./.venv-vna/Scripts/python.exe -m pip install -r python/requirements-vna.txt
matlab -batch "addpath('matlab/classes','matlab/app','matlab/tests','matlab/tests/fixtures'); run_vna_software_tests"
```

Không tạo lại môi trường đã có. Runtime được pin scikit-rf2.1.0 và pyserial3.5. MATLAB ưu tiên .venv-vna khi Python chưa Loaded; không tự tắt một Python session khác. Nếu báo BACKEND_UNAVAILABLE, xem executable trong thông báo, kiểm tra dependency và khởi động lại MATLAB. MATLAB trên máy này cảnh báo Python3.13 chưa được hỗ trợ chính thức; các đường gọi được ghi trong implementation log đã được thử thực tế. RAW/Mock không cần solver calibration.

Trong MATLAB mới:

```matlab
addpath('matlab/classes','matlab/app');
app=AntennaMeasurementApp();
```

Hai thiết bị mặc định Mock. Chọn Connect VNA ở bảng trái, sau đó mở tab VNA. Bật **Mock RF errors** để thử chuỗi hiệu chuẩn bằng mô hình lỗi deterministic. Mọi kết quả Mock có nhãn **MÔ PHỎNG** và được lưu provenance Mock; không dùng profile đó cho máy Real.

Để dựng lại ví dụ bằng wizard công khai và chụp giao diện, thêm matlab/tests vào path rồi gọi `demo=create_vna_workbench_mock_demo(tempname)`. Hàm chỉ dùng Mock, để lại app idle cho người xem và lưu ảnh cùng một bundle measurement vào folder đã truyền.

## Đo độc lập

Nhập Start/Stop MHz, 2..401 điểm và 1..16 averages. Dải giao diện ban đầu 50kHz..3GHz. Phần mềm hiển thị actual stop vì bước FIFO là integer Hz; actual stop có thể thấp hơn giá trị nhập. Không tự nội suy calibration sang lưới khác.

Single thu một nhóm averages; Continuous gửi nhóm tiếp theo sau khi nhóm trước hoàn tất. Averaging thực hiện trên complex S11/S21, không lấy trung bình dB. STOP hủy kết quả chưa publish và chờ sweep đang đọc kết thúc; không đóng COM giữa một read. Lỗi đo giữ trace hợp lệ trước đó và hiện nguyên nhân cạnh đồ thị.

Marker MHz snap vào mẫu gần nhất, trường hợp bằng khoảng cách chọn tần số thấp hơn. Smith và các đồ thị dùng cùng index. Phase/VSWR đổi ở popup bên dưới. Keep reference giữ một bản sao trace; Load reference đọc measurement.mat, reference khác band dùng lưới riêng.

Raw/Corrected chỉ chọn dữ liệu hiển thị. Raw luôn còn nguyên trong bộ đo. SOL chỉ sửa S11; S21 vẫn có nhãn RAW. TR luôn được ghi là chiều thuận/enhanced response. Điểm Smith ngoài vòng đơn vị không bị ép vào vòng; VSWR của |Γ|>1 không hợp lệ. dB của zero là -Inf và phase không xác định; giao diện hiển thị dấu phù hợp, file complex vẫn giữ zero.

## Hiệu chuẩn

1. Nối đúng máy và cáp dự định dùng. RF path… khai báo instrument label, RF path ID, reference plane; đây là thông tin người vận hành xác nhận, COM không phải unique hardware ID.
2. Chọn Calibration… và SOL hoặc SOLT T/R. Nhập band/points, averages mặc định4. Chọn ideal50Ω có nhãn giả định, hoặc import characterized Open/Short/Load .s1p và THRU .s2p. File kit phải đúng từng actual Hz và real50Ω; lỗi không được fallback sang ideal.
3. Start collection giữ lease VNA cho toàn wizard. Lần lượt gắn OPEN, SHORT, LOAD và bấm đúng nút Capture. Với TR, Port2 cần terminate50Ω trong O/S/L. THRU nối hai mặt phẳng tham chiếu đã khai báo.
4. Chờ mỗi capture hoàn tất trước khi đổi đầu chuẩn. Có thể thu lại; cần Solve lại. Solver từ chối thiếu chuẩn, lưới khác, reference zero, nonfinite hoặc hệ suy biến.
5. Solve → Apply và xác nhận đúng RF path. Nối lại DUT trước khi đo. Save cal ghi .vnacal.json gồm raw standards, kit models, hệ số và provenance. Profile mặc định NOT_CHECKED: khớp lại các chuẩn vừa dùng để fit không thay một phép kiểm tra độc lập.

Wizard giữ VNA trong lúc thay chuẩn. Capture lỗi cho phép retry hoặc Close; lease chỉ giải phóng sau khi job terminal. Đổi cáp/đầu nối phải đánh dấu lại; không tiếp tục dùng lẫn standards trước/sau thay đổi.

Load cal luôn về READY. Workbench lấy band/points từ actual grid trong profile, còn Apply cần xác nhận đúng máy/cáp/reference plane. Đổi grid/path/model/firmware hoặc reconnect khiến profile stale/inactive; trở lại band cũ không tự bật correction. Đổi averages không làm stale. Tuổi profile được lưu, không có hạn sử dụng giả tự động.

JSON có hash để phát hiện hỏng file và solver kiểm lại hệ số khi nạp; hash không phải chứng nhận độ chính xác hoặc chữ ký tin cậy. Giữ file raw/models để migration có chủ đích nếu đổi phiên bản engine; app từ chối profile engine/schema khác. Không dùng pickle.

Nếu FIFO/serial mất kết nối giữa sweep, job kết thúc bằng mã `TRANSPORT`; app chuyển VNA về OFFLINE và calibration thành stale. Kiểm tra cáp/nguồn rồi kết nối lại trước khi Apply hoặc đo tiếp. Lỗi callback vẽ đồ thị không dùng mã này: menu **Lỗi live plot** ở thanh trạng thái quyết định tiếp tục, thử lại hay dừng scan.

## Dùng cho scan anten

Popup cạnh Points ở bảng trái chọn RAW, SOL hoặc SOLT T/R. Mặc định RAW. SOL/TR là yêu cầu bắt buộc: thiếu profile ACTIVE, sai grid/context sẽ dừng trước khi initialize positioner hoặc move. Workbench/wizard đang giữ VNA cũng chặn scan trước positioner.

Scan chụp một profile snapshot bất biến, dùng averages1 mỗi góc. S11/S21 luôn raw; CorrectedS11/CorrectedS21 riêng. Phân tích/đồ thị dùng corrected S21 chỉ với TR; SOL dùng raw S21. RF error giữa scan giữ các rows đã hoàn thành, kể cả một điểm; HPBW/SLL/FBR không đủ dữ liệu là NaN. ZERO/hold/encoder/travel gates của positioner vẫn bắt buộc.

Đóng cửa sổ đang chạy yêu cầu abort/cancel, chờ scan stack và worker thoát trước khi xóa controller. Không cố mở connection thứ hai trong thời gian STOPPING.

## File xuất

Save measurement tạo folder UTC_UUID dưới data/vna/:

- measurement.mat: raw/corrected complex, provenance và original profile JSON.
- sweep.csv: mọi frequency, raw/corrected real/imag, dB và channel state; ô corrected trống nếu kênh chưa sửa.
- metadata.json: metadata JSON hữu hạn, không derived arrays Inf/NaN.
- s11_raw.s1p và s11_corrected.s1p khi có; Touchstone Hz/S/RI/R50, 17 significant digits.
- calibration.vnacal.json nếu measurement dùng profile.

Không xuất DUT.s2p với S12/S22 chưa đo. CSV/MAT giữ forward S21. Các file .mat dành cho dataset do app tạo và lưu cục bộ; load reference/dataset không tự activate calibration.

Scan MAT giữ full frequency matrices. CSV giữ nghĩa raw của các cột cũ và thêm corrected/analysis/source/profile fields. Dataset legacy được xem RAW/UNKNOWN_RAW_LEGACY, không tự áp profile hiện tại vào dữ liệu cũ.

## Kiểm chứng phần cứng

[Quy trình qualification](vna-workbench-hardware-qualification.md) ghi thiết bị, kit/cáp, independent standards, QT reference và tiêu chí so sánh đề xuất. Test phần mềm/Mock không thay phép thử đó. Không chạy hardware scripts hoặc master runner trong bộ kiểm tra thường ngày.
