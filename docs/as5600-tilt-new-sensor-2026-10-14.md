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

### Sau khi tách riêng các bó dây

Người dùng tách tuyến dây motor và dây cảm biến rồi yêu cầu kiểm tra tiếp.
Trên firmware production V4.0_HOLD, không xung STEP: Pan hợp lệ **360/360**;
Tilt lần lượt **30/30** khi nhả trước bật, **248/300** khi giữ cả hai driver và
**0/30** sau khi nhả. Trong 300 POS khi giữ, bộ đếm nhả driver không thay đổi.
Tách tuyến dây chưa đủ để đạt acceptance; không kết luận rằng việc tách dây
làm lỗi nặng hơn từ một lượt thử, vì cảm biến đã biến động giữa các lượt trước.
Không chạy thử chuyển động Tilt hoặc quét 3D trong lượt này. Log và summary:
`data/validation/cable_separated_20261014_120439/`.

### Sau khi thêm điện trở kéo lên SDA Tilt 2,5 kΩ

Người dùng đã lắp thêm điện trở 2,5 kΩ. Chạy lại firmware production
`V4.0_HOLD` trên COM5, chỉ dùng `POS`, `PING` và `HOLD ON/OFF`, không phát xung
STEP, không nạp firmware và không dùng VNA. Kết quả: khi nhả trước giữ,
Pan/Tilt **30/30**; khi giữ cả hai driver, Pan **300/300**, Tilt **218/300**;
sau khi nhả, Pan/Tilt **30/30**. Bộ đếm nhả không thay đổi trong pha giữ;
khi kết thúc, cả hai driver đã nhả và COM5 đóng. Trong các mẫu Tilt hợp lệ,
AGC luôn bằng **128**; mẫu lỗi ghi AGC=255 là giá trị báo đọc thất bại.
Log và script kiểm tra: `data/validation/tilt_pullup_20261014/`.

So với lượt sau tách dây (Tilt 248/300 lúc giữ), kết quả không chứng minh
điện trở đã sửa được lỗi; mức lỗi có thể biến động giữa các lượt. Chưa đạt
điều kiện quét 3D thật. Cần kiểm tra điện áp 3,3 V/GND ngay tại module Tilt
khi driver bật và vị trí/tâm/khoảng cách nam châm để giải quyết AGC tối đa;
đường SDA/SCL 2 m cũng cần đo bằng thiết bị đo nếu các bước này không giải quyết
được lỗi giao tiếp.

### Sau khi người dùng gỡ thêm dây và cắm lại thiết bị

COM5 biến mất tạm thời khi người dùng thao tác dây; sau khi cắm lại, COM5 trở
lại với USB CH340, và cùng bài kiểm tra `POS`/`PING`/`HOLD ON/OFF` trên
`V4.0_HOLD` đã chạy hết. Không gửi STEP, GOTO, ZERO hoặc lệnh VNA.

| Trạng thái | Pan | Tilt |
|---|---:|---:|
| Nhả trước khi giữ | 30/30 | **0/30** |
| Giữ cả hai driver | 300/300 | **95/300** |
| Nhả sau khi giữ | 30/30 | **0/30** |

Khi đọc Tilt thất bại, POS trả `RAW_TILT:-1.00 (AGC:255)`. Trong 95 mẫu được
chấp nhận lúc giữ, góc thô Tilt trải từ 0,00° đến 354,64° dù không phát lệnh
quay; không xem những mẫu này là bằng chứng góc vật lý đúng. So với bài sau
kéo lên SDA 2,5 kΩ (Tilt 30/30, 218/300, 30/30), phản hồi Tilt hiện tệ hơn;
chưa biết chính xác những dây nào đã được gỡ, nên chưa gán nguyên nhân cho
thao tác đó. Kết thúc đã nhả driver và đóng COM5. Raw log và summary:
`data/validation/tilt_extra_wires_removed_20261014/`.

Trước khi thử lại, kiểm tra đúng bốn đường J3 Tilt (3,3 V, GND, SDA GPIO21,
SCL GPIO22), đo 3,3 V tại module, sau đó mới kiểm tra căn tâm/khe nam châm.
Không quét Tilt/3D khi tín hiệu còn mất ở trạng thái nhả.

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
