# Ver2: kiểm thử thiết bị thật và sửa STOP/restart

Kiểm tra ngày 13–14/10/2026 theo yêu cầu của người dùng. ESP32 CH340 ở COM5,
SAA-2N ở COM6. Firmware `FW:V4.0_HOLD` đã nạp thành công bằng PlatformIO,
esptool xác nhận hash dữ liệu flash. SHA-256 của firmware.bin:
`2651EE33A4D74026C9B8ADE6B5101342C9D6053447FDFB3C4B3B855DA2E4DCF2`.

## Kết quả đạt

- SAA-2N: INDICATE trả `0x32`, device variant 2, protocol 1, hardware revision 2,
  thanh ghi phiên bản firmware 1.2; đủ 11/11 bản ghi FIFO ở 2395–2405 MHz.
- MATLAB → Python → VNA thật: 20 lượt sweep, đủ S11/S21 phức hữu hạn; ngắt và
  kết nối lại đạt.
- Pan: quét đồng bộ với RF thật tại 0/5/10° đạt; quét 0..360° bước 10° hoàn thành
  **37/37 điểm**, mọi điểm có encoder hợp lệ, không tăng bộ đếm nhả driver.
  Vòng 37 điểm mất 86,93 giây trong bài kiểm tra này.
- Pan đã quay về góc lệnh 0°. Người dùng xác nhận bàn anten **về đúng dấu vật lý**.
  Đây là quan sát của người dùng, chưa phải phép đo sai số bằng dụng cụ đo góc.
- Giao thức HOLD ON/OFF, CAL RELEASE, LOCK ZERO, PING và tự nhả sau 30 giây
  không nhận tín hiệu host đạt qua bài smoke không có xung STEP.
- STOP giữa hai điểm giữ hai điểm đã thu và giữ motor. Sau bản sửa, đọc POS
  và quét lại bằng **cùng ZERO** đạt trên ESP32 thật, với cả VNA Mock và VNA Real.
- Quét 3D bị từ chối trước chuyển động/RF khi thiếu encoder; bài negative test
  có fixture cấm `moveTo` để cảm biến hồi phục giữa các lần đọc cũng không gây quay.

Các lượt quét thiết lập ZERO kiểm tra tại tư thế hiện tại. Anten chưa được xác
nhận hiệu chuẩn RF trong bài này; S21 quan sát khoảng −68..−76 dB. Các chỉ số
HPBW/SLL từ dữ liệu này không được dùng làm kết quả pattern anten đã kiểm định.

## Lỗi STOP đã sửa

Trước bản sửa, `requestAbort()` đặt cờ hủy ngay cả khi motor/serial đang rảnh và
gửi STOP mà không nhận hết phản hồi. Lần POS đầu tiên của lượt quét tiếp theo có
thể nhận prompt `STOP OK`, hoặc bị ném `PositionerController:Aborted` vì cờ cũ.
Bài regression thật thất bại tại POS sau idle STOP trước khi sửa.

Bản sửa giữ STOP bất đồng bộ khi có chuyển động/giao dịch đang chờ. Khi rảnh,
STOP là một giao dịch riêng: nhận hết phản hồi xác nhận, không mang cờ hủy sang
POS tiếp theo. Không flush giao dịch đang hoạt động và không ZERO tự động.
Regression: `matlab/tests/test_real_idle_stop_restart.m`.

## Tilt còn chưa đạt

Raw POS từ ESP32 đã báo `RAW_TILT:-1.00`, `ENC_TILT_VALID:0` trước khi qua MATLAB,
cả với v3.2 trước nạp và v4.0 sau nạp. Không phải chỉ số góc bị regex MATLAB bỏ sót.

| Trạng thái driver | Pan hợp lệ | Tilt hợp lệ |
|---|---:|---:|
| Nhả, trước bật | 25/25 | 0/25 |
| Giữ cả hai | 100/100 | 0/100 |
| Nhả, sau bật | 25/25 | 0/25 |

Bài acceptance cả hai encoder không đạt. Tilt không được cho quay trong các
bài kiểm tra này. Cần kiểm tra đường SDA/SCL, nguồn/GND, kết nối và nam châm
của AS5600 Tilt để phân biệt nguyên nhân cụ thể; dữ liệu hiện có chưa xác định
được riêng linh kiện hay dây nào lỗi. Không bỏ kiểm tra encoder để làm quét 3D
đạt giả. Hành trình Tilt cơ khí đầy đủ cũng chưa được xác nhận.

Ảnh và mô tả của người dùng xác định tư thế ZERO: giá nằm ngang, anten mảng
dựng đứng, mặt hướng về người dùng → **theta tại ZERO = 90°, phi tại ZERO = 0°**.
Góc lệnh motor tương đối vẫn là 0° cho cả hai trục.

### Kiểm tra lại sau khi người dùng cắm lại dây motor Tilt

Ngày 14/10, người dùng phát hiện đã rút nhầm dây motor Tilt và cắm lại, rồi yêu
cầu kiểm tra lại. Kết quả mới: khi giữ cả hai motor, Pan **100/100**, Tilt
**0/100** phản hồi hợp lệ. Đối chiếu thêm ba trạng thái nhả/giữ/nhả, mỗi trạng
thái 20 lần: Pan **60/60**, Tilt **0/60**. Raw POS vẫn báo `RAW_TILT:-1.00`,
`ENC_TILT_VALID:0` cả khi nhả và giữ. Không phát xung STEP cho Tilt; kết thúc
bài kiểm tra đã nhả driver và đóng cổng. Việc cắm lại dây motor chưa khôi phục
phản hồi AS5600; vẫn cần kiểm tra đường cảm biến và nam châm riêng.

Log mới: `data/validation/as5600_v32_20261014_104550/stationary.log` và
`data/validation/tilt_replug_20261014_104652/raw_pos.log` / `summary.json`.

## Dữ liệu và kiểm tra phần mềm

Sau bản sửa: **51/51 test MATLAB** (hình học, giới hạn, engine/data/GUI 3D,
giao thức, homing, STOP và fixture cấm chuyển động) và **39/39 test Python** đạt.
Rà soát độc lập không còn phát hiện cần sửa trong thay đổi STOP và interlock.

Dữ liệu gốc giữ tại `data/validation/ver2_hardware_20261013_232703/`:

- `matlab_real.log`, `vna_repeated_sweeps.mat`, `pan_small.mat`, `pan_full.mat`,
  `pan_full_dataset/`, `pan_stopped.mat`: VNA/Pan thật, gồm lần restart thất bại trước sửa.
- `encoder_states.log`, `encoder_states.json`: 150 POS trong ba trạng thái.
- `idle_stop_red/`, `idle_stop_green/`, `real_stop_green/`: regression trước/sau sửa.
- `real_3d_gate_interlocked/`: negative test có khóa chuyển động trong fixture.
- `final_mock.log`, `python_unit.log`: bộ regression phần mềm sau sửa.

Log acceptance encoder riêng: `data/validation/as5600_v32_20261013_232835/stationary.log`.
Bản `ver1` không đổi: đã đối chiếu SHA-256 của cả 135 file trong manifest.
Chỉ mã/test/tài liệu được commit; dữ liệu đo thô giữ ngoài commit.
