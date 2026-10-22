# BÀN GIAO ĐI DÂY VÀ YÊU CẦU THIẾT KẾ PCB - ANTENNA POSITIONER

Ngày lập: 18/10/2026. Ngôn ngữ: tiếng Việt. Bản: 1.1.

**Quyết định đã chốt: KHÔNG thêm điện trở ngoài trên các đường I2C hoặc EN.** Không thêm pull-up 4,7 kΩ cho SDA/SCL, pull-up 10 kΩ cho EN, điện trở nối tiếp I2C hay footprint điện trở dự phòng/DNP cho các đường này. Giữ các điện trở sẵn có trên module và cấu hình firmware hiện tại. Quyết định này không yêu cầu tháo điện trở trên module, điện trở cảm dòng Rsense hoặc biến trở chỉnh dòng của driver.

## 1. Mục đích và trạng thái

Tài liệu này tự chứa thông tin để gửi trực tiếp cho AI/kỹ sư thiết kế schematic và PCB điều khiển bàn xoay anten hai trục Pan/Tilt. Người nhận không cần truy cập repository để đọc các kết nối bên dưới.

**Trạng thái: bản bàn giao kết nối, đủ để lập schematic sơ bộ; chưa phải thiết kế đã kiểm chứng để đặt sản xuất.** Một số mã module, footprint, thông số dòng và điện áp chịu đựng còn thiếu, được liệt kê tại mục 12. Không tự điền các thông số đó như thể đã được chủ hệ thống xác nhận.

Phân loại thông tin:

- **Đã xác nhận:** GPIO từ firmware hiện hành và nâng cấp nguồn người dùng mô tả ngày 18/10/2026.
- **Đã chốt với người dùng:** bỏ phương án thêm điện trở ngoài cho I2C/EN, kể cả footprint tùy chọn; không hỏi lại để đưa phương án này vào thiết kế.
- **Theo tài liệu bàn giao:** số chân giắc J1-J4 và màu dây motor; cần đối chiếu giắc/dây thực tế trước khi sản xuất.
- **Giả định làm việc:** một tụ 1000 µF trên mỗi đường nguồn; ESP32 tiếp tục được cấp bằng USB riêng. Xác nhận lại hai điểm này khi duyệt schematic.
- **Đề xuất thiết kế:** bảo vệ, test point, linh kiện tùy chọn và bố trí PCB; chưa có xác nhận rằng chúng đã được lắp trên mạch hiện tại.

## 2. Hệ thống và nâng cấp nguồn đã thông báo

| Khối | Cấu hình cơ sở |
|---|---|
| MCU | ESP32 DevKit V1, dùng firmware `V4.0_HOLD` |
| Driver | Hai module TMC2209, điều khiển STEP/DIR/EN, standalone |
| Motor Pan | NEMA17, tài liệu trước ghi thân 48 mm; mã và dòng định mức chưa có |
| Motor Tilt | NEMA17 pancake, tài liệu trước ghi thân 23 mm; mã và dòng định mức chưa có |
| Encoder | Hai module AS5600, gắn đuôi motor; hai bus riêng |
| Nguồn motor | USB-C PD qua trigger, đầu ra danh định 20 VDC |
| Nguồn logic/sensor | Mini 560 Pro, đầu ra 3,3 V, cấp cho cả hai VIO driver và hai AS5600 |
| Nguồn ESP32 | USB riêng theo cấu hình cơ sở; không nối song song nguồn 3V3 ESP32 với đầu ra Mini 560 Pro |
| Tụ mới | Hai tụ hóa 1000 µF; giả định một tụ trên rail 20 V và một tụ trên rail 3,3 V |
| Truyền động | Puly motor 16T, puly đầu ra 90T; firmware dùng 25 xung/độ anten với 1/8 vi bước |
| NanoVNA | Thiết bị USB/RF độc lập; không đưa RF hoặc nguồn NanoVNA vào PCB điều khiển này |

Mục tiêu người dùng: giảm dây nối rời, chi phí thấp, dễ bảo trì và giảm nguy cơ chập/cháy.

**Giới hạn của cách cấp nguồn hiện tại:** nguồn 3,3 V riêng cho ngoại vi không tạo cách ly galvanic với ESP32. GND và các dây GPIO vẫn nối giữa hai phía. Lỗi bộ hạ áp hoặc trạng thái một phía mất nguồn vẫn có thể tác động tới ESP32 qua tín hiệu. Không mô tả mạch hiện tại là đã cách ly hoặc bảo vệ hoàn toàn.

## 3. Kiến trúc PCB đề xuất để lập bản đầu

Đề xuất dùng PCB carrier gắn module ESP32 DevKit V1, hai module TMC2209 và Mini 560 Pro hiện có. Đây là phương án đề xuất để giảm rủi ro và chi phí, chưa phải yêu cầu đã chốt. Nếu người dùng chọn tích hợp IC trực tiếp thì phải thiết kế lại nguồn, tản nhiệt, phần USB và footprint theo datasheet chính hãng.

```text
USB-C PD + trigger ngoài PCB
       +20 V / GND
             |
     [bảo vệ đầu vào: đề xuất]
             |
          VM_20V ------------------+------------------+
             |                    |                  |
        C_VM 1000 µF         VM driver Pan      VM driver Tilt
             |                    |                  |
            GND                  J1                 J2
             |
      Mini 560 Pro (IN=20 V, OUT=3,3 V)
             |
         V3V3_EXT -----------------+------------------+
             |                    |                  |
       C_LOGIC 1000 µF      VIO hai driver      VCC J3 và J4
             |
            GND

USB máy tính -> ESP32 DevKit V1
                    | GPIO điều khiển và hai bus encoder
                    | GND chung với hệ thống
Chân 3V3 ESP32: KHÔNG nối V3V3_EXT trong phương án này.
```

Trong sơ đồ trên, mỗi tụ được mắc ngang giữa rail tương ứng và GND. Hai rail 20 V và 3,3 V không được nối chung. Không mắc nối tiếp tụ trên dây nguồn.

## 4. Quy ước tên linh kiện và tên net

Các refdes sau là quy ước đề xuất cho schematic, không phải vị trí chân vật lý đã kiểm chứng.

| Refdes | Chức năng |
|---|---|
| U_ESP32 | Module ESP32 DevKit V1 |
| U_DRV_PAN | Module TMC2209 Pan |
| U_DRV_TILT | Module TMC2209 Tilt |
| U_BUCK | Mini 560 Pro 3,3 V |
| J_PWR | Đầu vào 20 VDC/GND từ PD trigger ngoài |
| J1 | Motor Pan, 4 chân |
| J2 | Motor Tilt, 4 chân |
| J3 | AS5600 Tilt, 4 chân |
| J4 | AS5600 Pan, 4 chân |
| C_VM | Tụ hóa 1000 µF trên rail 20 V |
| C_LOGIC | Tụ hóa 1000 µF trên rail 3,3 V |

| Net | Ý nghĩa |
|---|---|
| VIN_20V_RAW | +20 V từ J_PWR, trước khối bảo vệ đề xuất |
| VM_20V | +20 V sau khối bảo vệ; cấp VM driver và IN+ U_BUCK |
| V3V3_EXT | 3,3 V ngoài từ Mini 560 Pro; chỉ cấp ngoại vi theo cấu hình này |
| V3V3_ESP | 3,3 V do DevKit tạo từ USB; tách với V3V3_EXT |
| GND | Mass điện chung của nguồn, ESP32, driver và cảm biến |
| PAN_STEP / PAN_DIR / PAN_EN_N | Ba tín hiệu điều khiển Pan; EN active LOW |
| TILT_STEP / TILT_DIR / TILT_EN_N | Ba tín hiệu điều khiển Tilt; EN active LOW |
| PAN_SDA / PAN_SCL | Bus riêng cho AS5600 Pan |
| TILT_SDA / TILT_SCL | Bus riêng cho AS5600 Tilt |
| PAN_COIL_A1/A2, PAN_COIL_B1/B2 | Bốn đầu cuộn motor Pan, tên logic của thiết kế |
| TILT_COIL_A1/A2, TILT_COIL_B1/B2 | Bốn đầu cuộn motor Tilt, tên logic của thiết kế |

Hậu tố cuộn A1/A2/B1/B2 trong bảng này không xác định sẵn thứ tự chân trên module TMC2209. Phải ánh xạ theo sơ đồ chính xác của module mua thực tế.

## 5. Bảng net nguồn và tụ

| ID | Net | Từ | Đến | Trạng thái / yêu cầu |
|---|---|---|---|---|
| P01 | VIN_20V_RAW | J_PWR chân chức năng +20 V | Đầu vào khối bảo vệ đề xuất | Số chân cơ khí J_PWR chưa chốt |
| P02 | VM_20V | Đầu ra bảo vệ | U_DRV_PAN.VM/VMOT | Hiện tại nối nguồn trực tiếp; bản PCB đề xuất thêm bảo vệ |
| P03 | VM_20V | Đầu ra bảo vệ | U_DRV_TILT.VM/VMOT | Như P02 |
| P04 | VM_20V | Đầu ra bảo vệ | U_BUCK.IN+ | Kiểm tra đúng phiên bản Mini 560 Pro và giới hạn đầu vào |
| P05 | GND | J_PWR chân chức năng âm | U_BUCK.IN- | GND nguồn |
| P06 | GND | GND nguồn | U_DRV_PAN.GND | Nối đủ chân GND của module |
| P07 | GND | GND nguồn | U_DRV_TILT.GND | Nối đủ chân GND của module |
| P08 | GND | U_BUCK.OUT- | GND hệ thống | Kiểm tra sơ đồ module; không xem buck này là bộ nguồn cách ly |
| P09 | V3V3_EXT | U_BUCK.OUT+ | U_DRV_PAN.VIO/VCC_IO | Không nối vào 5VOUT của driver |
| P10 | V3V3_EXT | U_BUCK.OUT+ | U_DRV_TILT.VIO/VCC_IO | Không nối vào VM |
| P11 | V3V3_EXT | U_BUCK.OUT+ | J3.1 | VCC module AS5600 Tilt |
| P12 | V3V3_EXT | U_BUCK.OUT+ | J4.1 | VCC module AS5600 Pan |
| P13 | GND | GND hệ thống | J3.2 | GND AS5600 Tilt |
| P14 | GND | GND hệ thống | J4.2 | GND AS5600 Pan |
| P15 | GND | GND hệ thống | U_ESP32.GND | Dây/đường riêng, tránh dòng motor đi qua DevKit |
| P16 | USB riêng | USB máy tính | Cổng USB U_ESP32 | Giữ đường nạp firmware và giao tiếp sẵn có |
| C01 | VM_20V / GND | C_VM cực + / cực - | VM_20V / GND tương ứng | 1000 µF theo mô tả; điện áp chịu đựng chưa xác nhận |
| C02 | V3V3_EXT / GND | C_LOGIC cực + / cực - | V3V3_EXT / GND tương ứng | 1000 µF theo mô tả; điện áp chịu đựng và ảnh hưởng ổn định buck chưa xác nhận |

Nếu thêm ngắt quá áp đầu ra 3,3 V: tách net thành V3V3_BUCK_RAW trước bảo vệ và V3V3_EXT sau bảo vệ; xác định lại vị trí C_LOGIC theo datasheet mạch bảo vệ/buck. Không tự đặt tên giống nhau ở hai phía rồi vô tình bypass phần bảo vệ.

Đề xuất chọn tụ trên 20 V có điện áp chịu đựng ít nhất 35 V, đồng thời bảo đảm điện áp thực tế khi có xung nằm trong giới hạn của tất cả linh kiện. Tụ chịu 35 V không làm driver chịu được 35 V. Với tụ 3,3 V, chọn điện áp định mức có dự phòng phù hợp, kiểm tra ESR, dòng ripple, dòng nạp ban đầu và yêu cầu ổn định của đúng bộ hạ áp. Hai tụ 1000 µF không thay thế toàn bộ tụ decoupling cục bộ.

## 6. Bảng net tín hiệu - giữ nguyên để tương thích firmware

| ID | Net | Chân ESP32 | Đầu còn lại | Chức năng |
|---|---|---|---|---|
| S01 | PAN_STEP | GPIO25 | U_DRV_PAN.STEP | Xung bước Pan |
| S02 | PAN_DIR | GPIO26 | U_DRV_PAN.DIR | Chiều Pan |
| S03 | PAN_EN_N | GPIO27 | U_DRV_PAN.EN/ENN | LOW bật; HIGH nhả |
| S04 | TILT_STEP | GPIO32 | U_DRV_TILT.STEP | Xung bước Tilt |
| S05 | TILT_DIR | GPIO33 | U_DRV_TILT.DIR | Chiều Tilt |
| S06 | TILT_EN_N | GPIO14 | U_DRV_TILT.EN/ENN | LOW bật; HIGH nhả |
| S07 | TILT_SDA | GPIO21 | J3.4 -> AS5600 Tilt.SDA | Dữ liệu encoder Tilt |
| S08 | TILT_SCL | GPIO22 | J3.3 -> AS5600 Tilt.SCL | Clock encoder Tilt |
| S09 | PAN_SDA | GPIO18 | J4.4 -> AS5600 Pan.SDA | Dữ liệu encoder Pan |
| S10 | PAN_SCL | GPIO19 | J4.3 -> AS5600 Pan.SCL | Clock encoder Pan |

Quy định tương thích:

- Dùng số GPIO, không dùng số thứ tự chân header DevKit. Chưa có ánh xạ header vật lý vì chưa chốt phiên bản DevKit 30/38 chân và kích thước.
- Không nối SDA/SCL Pan với SDA/SCL Tilt. Hai AS5600 có cùng địa chỉ 7-bit 0x36; firmware hiện dùng hai bus riêng, không có I2C mux.
- AS5600 OUT, PWM và GPIO23 không tham gia vận hành hiện tại. Không tự thêm dây OUT vào một net đang dùng.
- Không thêm điện trở kéo lên hoặc điện trở nối tiếp ngoài cho I2C; không thêm điện trở kéo lên EN. Giữ điện trở có sẵn trên module. Không tạo footprint dự phòng cho phương án đã loại bỏ này.
- SDA hiện được firmware vận hành open-drain; SCL được firmware GPIO lái HIGH/LOW trên bus AS5600 chuyên dụng. Không giả định đây là bus I2C đa thiết bị thông thường, không tự thêm slave clock-stretching hoặc buffer chưa kiểm tra tương thích.
- Nếu thêm buffer/cách ly/level shifter, phải kiểm tra chiều truyền, open-drain SDA, cách lái SCL và trạng thái mất nguồn; giữ hành vi firmware hoặc ghi rõ thay đổi firmware cần thiết.

## 7. Giắc motor và cảm biến

### 7.1. Bảng J1-J4

| Giắc | Chân | Net PCB | Nối bên ngoài | Màu theo bàn giao |
|---|---:|---|---|---|
| J1 - Motor Pan | 1 | PAN_COIL_A1 | Motor Pan đầu A+ | Đen |
| J1 - Motor Pan | 2 | PAN_COIL_A2 | Motor Pan đầu A- | Xanh lá |
| J1 - Motor Pan | 3 | PAN_COIL_B1 | Motor Pan đầu B+ | Đỏ |
| J1 - Motor Pan | 4 | PAN_COIL_B2 | Motor Pan đầu B- | Xanh lam |
| J2 - Motor Tilt | 1 | TILT_COIL_A1 | Motor Tilt đầu A+ | Đen |
| J2 - Motor Tilt | 2 | TILT_COIL_A2 | Motor Tilt đầu A- | Xanh lá |
| J2 - Motor Tilt | 3 | TILT_COIL_B1 | Motor Tilt đầu B+ | Đỏ |
| J2 - Motor Tilt | 4 | TILT_COIL_B2 | Motor Tilt đầu B- | Xanh lam |
| J3 - Sensor Tilt | 1 | V3V3_EXT | AS5600 Tilt.VCC | Chưa xác nhận |
| J3 - Sensor Tilt | 2 | GND | AS5600 Tilt.GND | Chưa xác nhận |
| J3 - Sensor Tilt | 3 | TILT_SCL | AS5600 Tilt.SCL | Chưa xác nhận |
| J3 - Sensor Tilt | 4 | TILT_SDA | AS5600 Tilt.SDA | Chưa xác nhận |
| J4 - Sensor Pan | 1 | V3V3_EXT | AS5600 Pan.VCC | Chưa xác nhận |
| J4 - Sensor Pan | 2 | GND | AS5600 Pan.GND | Chưa xác nhận |
| J4 - Sensor Pan | 3 | PAN_SCL | AS5600 Pan.SCL | Chưa xác nhận |
| J4 - Sensor Pan | 4 | PAN_SDA | AS5600 Pan.SDA | Chưa xác nhận |

### 7.2. Ánh xạ đầu ra driver

| Khối driver | Đầu ra cầu H chức năng | Net đến giắc |
|---|---|---|
| Pan | Cặp cuộn A: đầu 1 / đầu 2 | PAN_COIL_A1 / PAN_COIL_A2 |
| Pan | Cặp cuộn B: đầu 1 / đầu 2 | PAN_COIL_B1 / PAN_COIL_B2 |
| Tilt | Cặp cuộn A: đầu 1 / đầu 2 | TILT_COIL_A1 / TILT_COIL_A2 |
| Tilt | Cặp cuộn B: đầu 1 / đầu 2 | TILT_COIL_B1 / TILT_COIL_B2 |

Phải tra đúng symbol/footprint/schematic module để ánh xạ nhãn như OA1/OA2/OB1/OB2 hoặc A1/A2/B1/B2 hoặc 1A/1B/2A/2B. Không suy ra cặp cuộn chỉ từ vị trí liền kề hay tên gần giống nhau. Kiểm tra cặp cuộn motor bằng đồng hồ khi đã ngắt nguồn và tách khỏi driver. A+/A- ở đây là quy ước hai đầu cuộn, không phải nguồn DC hoặc GND.

Số chân giắc dựa vào số khắc thực tế. Bản vẽ phải ghi rõ nhìn từ mặt cắm hay mặt hàn. Nếu PCB dùng đầu nối nội bộ ra giắc vách hộp, đặt refdes riêng cho header nội bộ và cung cấp bảng dây harness 1:1; không gán nhầm footprint giắc vách lên PCB.

Ưu tiên giắc có khóa, chống cắm ngược và loại motor không cắm lọt vào loại sensor. Nếu thay loại giắc, vẫn giữ bảng chức năng trên hoặc xuất bảng chuyển đổi đầy đủ được người dùng duyệt.

## 8. Cấu hình driver và nguồn cần xử lý trong schematic

| Hạng mục | Yêu cầu |
|---|---|
| Vi bước | Đạt 1/8 vi bước đầu vào STEP để giữ hệ số 25 xung/độ; kiểm chứng MS1/MS2 theo đúng module. Tài liệu cũ ghi để hở, nhưng không dùng câu đó thay cho sơ đồ module |
| UART/PDN | Firmware cơ sở dùng standalone, chưa có đường UART điều khiển driver. Không tự nối UART vào GPIO chưa được phân bổ |
| Vref/dòng | Chỉnh riêng Pan và Tilt theo motor, Rsense và module; chưa có giá trị để chốt |
| EN lúc reset | Kiểm tra trạng thái EN theo module hiện có khi MCU reset/không có USB và báo kết quả; không thêm điện trở EN ngoài. Nếu phát hiện vấn đề thực tế, báo riêng để xem xét, không tự thay đổi quyết định đã chốt |
| Giữ motor | Firmware giữ cả hai driver trong vận hành; thiết kế nhiệt phải tính tải giữ lâu, không chỉ lúc quay |
| Chân ESP32 EN | Chân reset ESP32; khác hoàn toàn EN/ENN của hai TMC2209. Không nối chung |
| Module AS5600 | Cần ảnh/mã module để kiểm tra chân cấp 3,3 V, pull-up sẵn có và các chân phụ; không suy diễn từ pin IC trần |

## 9. Các bảo vệ đề xuất cho bản PCB

Đây là yêu cầu để người thiết kế đề xuất phương án và tính linh kiện; chưa phải BOM đã chốt.

| Khối | Đề xuất / điều kiện lựa chọn |
|---|---|
| Đầu vào 20 V | Cầu chì và đế có định mức DC phù hợp, đặt trước các nhánh cần bảo vệ. Chọn dòng theo tải thực, dòng nạp tụ và khả năng chịu dòng của dây/giắc/trace |
| Ngược cực | Đề xuất MOSFET hoặc giải pháp phù hợp; tính tổn hao và điện áp chịu đựng |
| Xung VM | Đánh giá xung cắm nguồn và năng lượng hồi từ motor khi giảm tốc/disable. Chọn tụ, kẹp/xả theo năng lượng và điện áp kẹp thực, không chọn TVS chỉ theo tên '24 V' |
| Quá áp 3,3 V | Đề xuất bảo vệ độc lập chống lỗi buck; phải chịu được kịch bản đầu vào 20 V truyền sang đầu ra và giữ điện áp tải trong giới hạn cho phép. Không coi cầu chì hoặc tụ hóa là bộ ngắt quá áp |
| Hai nguồn độc lập | Kiểm tra USB có/không, 20 V có/không, bật/tắt sai thứ tự. Tránh cấp ngược qua STEP/DIR/EN/SDA/SCL và pull-up vào phía mất nguồn |
| Cách ly nếu yêu cầu | Nếu muốn cách ly galvanic thực sự, phải thiết kế lại cả nguồn phía cách ly lẫn mọi đường tín hiệu qua ranh giới; GND hai phía cũng phải tách. Đây là thay đổi kiến trúc, cần duyệt riêng |
| Driver | Bố trí tụ VM cục bộ sát driver; kiểm tra tụ trên module đã đủ chưa. Tụ 1000 µF ở đầu vào xa không tự thay thế tụ tại driver |
| Sensor | Decoupling cục bộ phù hợp; nếu đề xuất ESD điện dung thấp thì kiểm tra tương thích trước. Không thêm pull-up, điện trở nối tiếp hay footprint điện trở dự phòng trên I2C; không thêm điện trở EN ngoài |
| Tản nhiệt | Dự phòng khoảng trống tản nhiệt, thông gió/quạt nếu tính nhiệt yêu cầu; không dùng dòng quảng cáo tối đa IC làm dòng liên tục của module |
| Dừng khẩn | Nếu thêm ngắt nguồn cứng, đánh giá Tilt rơi khi mất torque. STOP firmware là dừng giữ lực, không tương đương ngắt điện khẩn |

Tài liệu hãng TMC2209 nêu dải nguồn hoạt động đến 29 V, khuyến nghị tối thiểu 100 µF gần driver và lưu ý năng lượng hồi về nguồn. Khi chốt linh kiện, tra thêm absolute maximum, giới hạn module và dung sai/xung để có biên dự phòng. Nguồn DC danh định 20 V không tự bảo đảm mọi xung thấp hơn giới hạn driver.

## 10. Bố trí PCB, ký hiệu và điểm đo

- Giữ đường công suất và vòng dòng chopper ngắn; đặt tụ driver sát chân nguồn/return. Tách vùng buck/driver khỏi vùng ESP32 và đầu nối encoder.
- Dùng mặt phẳng GND và đường hồi có kiểm soát; tránh dòng motor đi chung đoạn mảnh với GND sensor/MCU. Không cắt GND plane tùy tiện hoặc chỉ áp dụng hình sao mà bỏ qua vòng dòng tần số cao.
- Tính bề rộng trace, via và copper theo dòng liên tục, dòng sự cố, độ dày đồng và nhiệt độ cho phép. Chưa có dòng nên chưa chốt bề rộng bằng mm.
- Không route SDA/SCL sát hoặc song song dài với đầu ra motor, switch node buck. Giảm vòng tín hiệu và giữ đường hồi GND gần tín hiệu.
- Dây encoder Tilt từng giảm lỗi khi rút từ khoảng 2 m xuống 1 m và bỏ trở kéo lên 2,5 kΩ ngoài. Đây là kinh nghiệm cấu hình cũ; phải đo lại dạng sóng, tổng pull-up và điện dung cáp với PCB mới, không coi 1 m là chiều dài I2C được bảo đảm.
- Đặt đầu nối nguồn/motor và sensor ở vùng dễ phân biệt; in nhãn PAN/TILT, MOTOR/SENSOR, số chân 1, cực nguồn và pinout trên silkscreen.
- Để tiếp cận được cổng USB ESP32, nút BOOT/EN, biến trở driver, cầu chì và chân đo.
- Nếu dùng radio ESP32, tuân thủ keepout anten của đúng module/DevKit; không tự phủ đồng bên dưới anten.
- Chốt lỗ bắt vít, kích thước bo, độ cao tụ 1000 µF, khoảng trống tản nhiệt và chiều cắm module theo hộp thật.

| Test point đề xuất | Net / mục đích |
|---|---|
| TP_VIN / TP_VM | Trước/sau bảo vệ nguồn 20 V |
| TP_3V3_EXT / TP_3V3_ESP | Đo riêng hai nguồn 3,3 V |
| TP_GND | Điểm kẹp đo gần nguồn, driver và sensor |
| TP_PAN_EN / TP_TILT_EN | Trạng thái enable |
| TP_PAN_STEP / TP_TILT_STEP | Kiểm tra xung STEP |
| TP_PAN_SDA/SCL | Hai tín hiệu bus Pan |
| TP_TILT_SDA/SCL | Hai tín hiệu bus Tilt |
| TP_VREF_PAN / TP_VREF_TILT | Nếu module cho phép đo Vref an toàn |

## 11. Hồ sơ AI thiết kế cần xuất và kiểm tra

1. Schematic có refdes, tên net và bảng pin-to-pin rõ ràng; phân biệt cấu hình hiện tại với bảo vệ mới đề xuất.
2. BOM có mã hãng, điện áp/dòng/công suất, package, footprint, linh kiện DNP và lý do chọn phần bảo vệ.
3. Bản vẽ vị trí module/giắc có kích thước và hướng cắm; ảnh chân thực tế được đối chiếu với symbol và footprint.
4. Tệp dự án CAD gốc (KiCad hoặc công cụ được người dùng chọn), PDF schematic và hình PCB hai mặt.
5. Báo cáo ERC/DRC; mọi cảnh báo được xử lý hoặc giải thích cụ thể. Không tự bỏ kiểm tra để coi thiết kế là đạt.
6. Gerber/drill, BOM và CPL/Pick-and-place nếu lắp ráp, chỉ sau khi các thông tin chặn ở mục 12 đã được xác nhận và bản thiết kế được duyệt.
7. Quy trình bring-up có nguồn giới hạn dòng: kiểm tra không chập -> rail không tải -> module/sensor -> driver chưa nối motor -> nối motor khi đã tắt nguồn -> thử giữ -> thử chuyển động nhỏ trong vùng cơ khí an toàn.
8. Kiểm tra cắm chỉ USB, chỉ 20 V, cả hai và rút từng nguồn; kiểm tra rail/GPIO không cấp ngược ngoài giới hạn linh kiện.
9. Kiểm tra đứng yên khi cả hai driver giữ lực, độ tin cậy encoder, ripple/xung VM và 3,3 V, nhiệt độ sau giữ lâu; không kết luận chỉ bằng một lần đo DC hoặc một mẫu góc hợp lệ.

## 12. Những thông tin còn cần xác nhận trước khi chốt PCB

| Mục | Hiện biết | Cần bổ sung |
|---|---|---|
| ESP32 | DevKit V1 | Ảnh hai mặt, số chân 30/38, kích thước, bước/hàng chân, mã bo |
| TMC2209 | Hai module standalone | Hãng/phiên bản, sơ đồ module, chân header, Rsense, footprint, chiều linh kiện |
| Mini 560 Pro | Người dùng xác nhận 3,3 V | Ảnh đúng module, pinout IN/OUT, kích thước, giới hạn đầu vào, tài liệu và dòng cho phép |
| Tụ nguồn | Hai tụ 1000 µF | Xác nhận một tụ/rail; điện áp in trên từng tụ, kích thước, khoảng chân, series/ESR nếu có |
| Cấp nguồn ESP32 | Giả định giữ USB riêng | Xác nhận không chuyển sang cấp ESP32 bằng 3,3 V ngoài |
| Motor | Pan và Tilt NEMA17 | Mã từng motor, dòng pha định mức, điện trở cuộn, chế độ dòng giữ/chạy |
| Nguồn PD | Danh định 20 V | Model nguồn và trigger, dòng định mức thật, chiều dài/tiết diện dây |
| AS5600 | Hai module 3,3 V, bus riêng | Ảnh/module, pull-up và sơ đồ cấp nguồn hiện có |
| Giắc | J1-J4 bốn chân theo bàn giao | Loại/size, số chân thực, mặt nhìn, vách hộp hay PCB, mã đầu nối chống cắm nhầm |
| PCB/hộp | Chưa có kích thước | Kích thước bo, lỗ vít, vị trí giắc, số lớp, đồng, khoảng trống và ngân sách |
| Bảo vệ | Mục tiêu giảm chập/cháy | Chọn mức bảo vệ, dòng cầu chì, phương án quá áp 3,3 V và VM sau khi tính toán |
| Công cụ CAD | Chưa chốt | KiCad hoặc công cụ người dùng chọn |

Được phép dựng schematic logic và placement sơ bộ khi còn các mục trên, với placeholder được đánh dấu rõ. Chưa được coi footprint module, định mức dòng, BOM bảo vệ hay tệp sản xuất là đã chốt.

## 13. Nguồn tham chiếu và thứ tự ưu tiên

Thông tin nâng cấp ngày 18/10/2026 được cung cấp trực tiếp bởi người dùng: Mini 560 Pro 3,3 V cấp các tải cần 3,3 V; thêm hai tụ 1000 µF trên hai đường nguồn. Giả định một tụ/rail và USB riêng cho ESP32 đã được nêu rõ ở đầu tài liệu.

Nguồn nội bộ dùng để đối chiếu (không cần gửi kèm để hiểu netlist):

- `firmware/positioner_v3_hold/src/main.cpp`: GPIO, firmware V4.0_HOLD, standalone 1/8 vi bước và 25 xung/độ.
- `firmware/positioner_v3_hold/src/as5600_bus.h`: cách điều khiển SDA/SCL thực tế, SCL lái HIGH/LOW.
- `CODEX_HANDOVER/contex ver2/README_AI_MASTER_CONTEXT.md`, mục 4: pinout J1-J4 theo bàn giao; các kết luận vận hành cũ không phải cấu hình firmware mới.
- `docs/hardware-validation-2026-10-11.md`: nguồn ngoại vi từ buck 3,3 V; ESP32 USB riêng, GND chung.
- `docs/tilt-i2c-validation-2026-10-14.md`: vận hành I2C, OUT23 không cần; kinh nghiệm cáp/pull-up.
- `docs/automatic-antenna-measurement-system-master-v4.md`: encoder ở motor, homing thủ công, kiến trúc đo.

Nguồn chính hãng để người thiết kế tra và ghi lại revision:

- [TMC2209 datasheet Rev. 1.09](https://www.analog.com/media/en/technical-documentation/data-sheets/tmc2209_datasheet_rev1.09.pdf): nguồn, tụ cục bộ, protection, vi bước, current control và layout.
- [ESP32 datasheet](https://documentation.espressif.com/esp32_datasheet_en.html): giới hạn điện, GPIO và trạng thái nguồn. Footprint carrier vẫn phải theo đúng DevKit mua thực tế.

Ưu tiên: thay đổi được người dùng xác nhận mới nhất -> GPIO trong firmware hiện hành -> schematic/datasheet đúng mã linh kiện -> tài liệu bàn giao cũ. Khi có mâu thuẫn, nêu cụ thể và hỏi chủ hệ thống; không tự nối theo sơ đồ cũ ghi nuôi toàn bộ ngoại vi bằng chân 3V3 ESP32.

## 14. Lời giao việc có thể dùng nguyên văn cho AI thiết kế

> Hãy thiết kế schematic và PCB cho hệ thống trong tài liệu này. Trước tiên lập lại danh sách net, xác định symbol/footprint nào đã đủ thông tin và mục nào còn thiếu. Giữ nguyên GPIO và chức năng J1-J4 để tương thích firmware. KHÔNG thêm điện trở ngoài cho I2C hoặc EN, kể cả pull-up, điện trở nối tiếp I2C hay footprint dự phòng/DNP; phương án này đã được người dùng loại bỏ. Giữ điện trở có sẵn trên module và không hỏi lại về việc thêm trở I2C/EN. Đề xuất carrier dùng module sẵn có, bảo vệ nguồn 20 V và 3,3 V, xử lý bật/tắt hai nguồn độc lập và tản nhiệt. Phân biệt dữ kiện đã xác nhận với giả định/đề xuất. Không tự chọn dòng cầu chì, Vref, chân header DevKit hoặc footprint TMC2209/Mini 560 Pro khi chưa có dữ liệu đúng module. Hai rail 3,3 V ESP32 và 3,3 V ngoại vi không nối song song; cấu hình GND chung này chưa phải cách ly galvanic. Xuất schematic sơ bộ, BOM dự kiến, bố trí sơ bộ và các câu hỏi còn chặn trước; chỉ chốt tệp sản xuất sau khi thông tin còn thiếu và thiết kế được người dùng duyệt.
