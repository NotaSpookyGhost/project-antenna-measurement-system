# Kết quả chạy lại sau khi gỡ mắc dây Pan

Mã nguồn kiểm tra: `6f1fd6d16c7078de3d39d2ef88caf1d8a958459b`. Exit code phần cứng:0.

- Pan0→360:13/13 điểm RF, không abort; đã trở về ZERO kiểm tra.
- Lưới3D nhỏ:6/6 điểm RF, không abort. Tilt đã thử0..10°.
- STOP VNA:4.3205356 giây, không phát hành raw đến muộn.
- 30 cặp encoder khi HOLD và các bước nhỏ Pan/Tilt đều đạt; không tăng số lần nhả driver khi quét.
- Cleanup đã đưa hai trục về ZERO kiểm tra và nhả motor/ngắt kết nối.

Lần chạy lại phần mềm: MATLAB147/147 +3/3 scripts; Python85/85 +7/7 bổ sung; firmware native5/5. Log tại `output/retest-6f1fd6d-20261023_162307/`.

Dữ liệu thực: `data/validation/acceptance_system_20261023_163312_UTC/result.mat`; chi tiết máy đọc được trong `summary.json` cùng thư mục với báo cáo này. Dữ liệu các lượt lỗi và lượt bị ảnh hưởng bởi mắc dây vẫn được giữ nguyên.

Kết quả này kiểm tra chức năng điều khiển/thu dữ liệu; không xác nhận độ chính xác RF đã hiệu chuẩn, góc cơ khí bằng chuẩn độc lập hoặc toàn hành trình Tilt.
