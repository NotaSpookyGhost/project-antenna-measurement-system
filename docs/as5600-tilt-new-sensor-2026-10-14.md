# Kiểm tra AS5600 Tilt mới — 14/10/2026

Người dùng đã thay cảm biến Tilt và yêu cầu kiểm tra lại. Không sửa source
firmware/MATLAB đang dùng; không phát xung STEP hoặc chạy quét trong bài này.

## Các lần kiểm tra

1. Acceptance đầu tiên với V4.0_HOLD: Tilt 0/100 lần POS khi giữ motor. Log:
   `data/validation/as5600_v32_20261014_113755/stationary.log`.
2. Dùng bản firmware chẩn đoán tạm, được sao chép trong thư mục validation.
   Bản này cấm cả gotoPosition và stepDualMotors, gồm lệnh M1/M2 trực tiếp.
   Đọc raw STATUS/RAW_ANGLE và ghi giai đoạn NACK, không bỏ kiểm tra mẫu hợp lệ.
3. Sau chẩn đoán, nạp lại firmware production không chỉnh sửa, xác nhận
   `FW:V4.0_HOLD` qua POS. Mọi cổng đã đóng và driver đã nhả khi kết thúc.

| Bài thử | Trạng thái | Pan | Tilt |
|---|---|---:|---:|
| Giao dịch raw chẩn đoán | Nhả driver | 20/20 giao dịch thành công | 20/20, có MD |
| Giao dịch raw chẩn đoán | Giữ driver | 18/20 truyền thành công; có cả packet sai 12 bit | 0/20 truyền thành công |
| POS production, sau khôi phục | Nhả trước bật | 20/20 góc hợp lệ | 20/20 |
| POS production, sau khôi phục | Giữ cả hai | 100/100 góc hợp lệ | **98/100** |
| POS production, sau khôi phục | Nhả sau bật | 20/20 góc hợp lệ | 20/20 |

Raw diagnostics là giao dịch đơn. Một POS production có thử lại và cần ba mẫu
mới liên tiếp đồng thuận; hai loại số đếm không tương đương. Kết quả cũng biến
động giữa các lần thử: không bỏ qua lần acceptance đầu thất bại để kết luận ổn định.

Tilt ở lần raw driver ON: 19 ADDRESS_WRITE_NACK, 1 REGISTER_NACK. Vì không đọc
được STATUS trong các giao dịch này, MD:0 của packet lỗi không chứng minh nam
châm biến mất. Trong trạng thái nhả, STATUS 0x33 có MD=1 và ML=1. Khi trở lại
production, AGC Tilt = 128. Theo datasheet hãng, ML báo từ trường quá yếu và
AGC tối đa trong chế độ 3,3 V là 128. Nguồn: [ams OSRAM AS5600 datasheet, trang
18 và 20](https://www.mouser.com/datasheet/2/588/AS5600_DS000365_5_00-1877365.pdf).

## Kết luận và bước tiếp theo

Cảm biến mới có hoạt động và đã nhận diện nam châm, nhưng chưa đạt mức 100/100
khi driver giữ. Có bằng chứng lỗi giao tiếp I²C và từ trường yếu; chưa có phép
đo điện áp hoặc dạng sóng để xác định chính xác dây, nguồn hay nhiễu nào gây lỗi.
Không coi việc thay cảm biến là đã sửa xong toàn bộ Tilt và không bypass guard
encoder để quét 3D.

Kiểm tra từng yếu tố: căn tâm/khoảng cách nam châm để loại cờ ML; dùng tạm dây
cảm biến ngắn và tách khỏi dây motor để so sánh OFF/ON; kiểm tra nguồn/GND tại
module khi driver bật. SDA Tilt hiện ở GPIO21, SCL ở GPIO22. Không thay nhiều
yếu tố cùng lúc nếu cần xác định nguyên nhân.

Toàn bộ source/binary chẩn đoán và log giữ tại
`data/validation/tilt_new_sensor_diag_20261014_114010/`:
`diagnostic.log`, `diagnostic_summary.json`, `restore.log`, `restored_pos.log`,
`production_recheck.log`, `production_recheck.json` và `diagnose_and_restore.py`.
Firmware chẩn đoán tạm nằm ngoài thư mục source production và ngoài commit.
