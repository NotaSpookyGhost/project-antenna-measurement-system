# Ver2: quét Pan–Tilt và mốc hướng anten tùy chỉnh

Trạng thái: thiết kế đề xuất để người dùng duyệt; chưa triển khai mã điều khiển.

## Mục đích và yêu cầu người dùng

Đo pattern bằng cách giữ Tilt tại từng mức, quét Pan một vòng theo từng bước và đo VNA tại mỗi điểm, rồi chuyển sang mức Tilt tiếp theo. Người dùng tự chọn tư thế đặt ZERO: ví dụ anten nằm ngang có góc hình học 90° nhưng vị trí motor tại đó là 0°. Không buộc người dùng đặt anten thẳng đứng để hiệu chuẩn.

Giữ bản snapshot `ver1` làm mốc. Phát triển trên MATLAB, Python bridge và firmware hiện tại ở thư mục gốc; tiếp tục hỗ trợ quét 2D và tải dữ liệu 2D cũ.

## Quy ước góc

Tách hai đại lượng trong GUI và file đo:

- Góc motor tương đối với lần **Khóa + ZERO**, dùng trong lệnh ESP32.
- Góc hình học dùng để gắn điểm đo lên lưới cầu, do người dùng khai báo hướng và chiều của trục tại ZERO.

Đề xuất kỹ thuật: dùng góc cực Tilt `theta` với 0° hướng lên, 90° nằm ngang, 180° hướng xuống; Pan `phi` là góc phương vị. Đây là quy ước dựng hình; người dùng phải đặt anten/khung gá theo trục đo tương ứng.

`theta = TiltAtZeroDeg + TiltSign * TiltMotorDeg`

`phi = PanAtZeroDeg + PanSign * PanMotorDeg`

Mỗi dấu bằng +1 hoặc -1. Mặc định đề xuất: Tilt tại ZERO 90°, Pan tại ZERO 0°, cả hai dấu +1. Nhãn có tiếng Việt và mô tả hướng; không nhầm góc này với góc AS5600 ở đuôi motor. Encoder tiếp tục được lưu riêng, giữ nguyên thông tin tỉ số truyền.

Lựa chọn kỹ thuật sau rà soát: ở chế độ 3D chỉ nhận lưới có theta trong 0..180°. Nếu cấu hình vượt qua cực, hiển thị khoảng góc motor hợp lệ suy ra từ ZERO/dấu và yêu cầu chỉnh dải trước START; không âm thầm gập góc 270° thành hướng khác. Phi lưu cả giá trị chưa cuộn và giá trị modulo 360° phục vụ dựng hình. Biên độ mỗi lượt Pan tối đa 360°.

Ví dụ Tilt tại ZERO = 90°, dấu +1:

| Góc motor Tilt | Góc cực theta | Hướng |
|---:|---:|---|
| -90° | 0° | Lên |
| 0° | 90° | Ngang |
| +90° | 180° | Xuống |

Người dùng có thể đổi khai báo hướng ZERO khi hệ thống đứng yên; việc này chỉ đổi phép quy đổi, không gửi lệnh quay hoặc ZERO tới ESP32. Muốn đặt lại mốc cơ khí vẫn thực hiện Nhả → căn tay → Khóa + ZERO. Sau nhả/reset, trạng thái hiệu chuẩn cơ khí mất hiệu lực như bản hiện tại.

## Giao diện và cấu hình quét

Thêm chế độ **3D Pan × Tilt** bên cạnh hai chế độ 2D. Trong chế độ 3D:

- Nhập Start/Stop/Step độc lập cho Pan và Tilt, đơn vị góc motor tương đối ZERO. Hiển thị dải theta/phi suy ra trước khi START.
- Cấu hình “Góc cực Tilt tại ZERO”, “Góc Pan tại ZERO”, chiều tăng của từng góc.
- Cấu hình “Giới hạn hành trình theo ZERO” cho từng trục, do người dùng khai báo theo khung gá và dây. Đây là giới hạn góc motor riêng với hướng hình học; mỗi khoảng có độ rộng tối đa 360° và nằm trong khả năng firmware. Sau mỗi lần đặt lại ZERO cơ khí phải xác nhận lại khoảng hành trình trong thao tác Khóa + ZERO; không tự chuyển hành trình đã xác nhận của mốc cũ sang mốc mới.
- Cho chọn Pan một chiều hoặc luân phiên. Mặc định đề xuất luân phiên 0→360 rồi 360→0 để giảm xoắn dây, phù hợp yêu cầu giai đoạn 2 trong tài liệu master.
- Mặc định đề xuất lưới Pan 0:10:360 và Tilt -90:10:90 khi góc tại ZERO là 90°; người dùng có thể thu hẹp hoặc đổi bước. Giữ điểm Pan 360° trong dữ liệu thô để kiểm tra điểm đóng vòng, không tính nó như một hướng độc lập khi dựng lưới.
- Hiển thị tổng số điểm và hàng Tilt đang đo. Thiết lập bị khóa khi quét; Pause/Resume/STOP vẫn dùng được.
- Lưu cấu hình quét và quy ước ZERO vào metadata mỗi dataset. Ghi nhớ lựa chọn qua phiên GUI bằng file thiết lập cục bộ trong MATLAB `prefdir`; không lưu trạng thái “đã homing” để dùng lại sau reset.

Hai mức Tilt chỉ tạo hai lát cắt. GUI chỉ dựng bề mặt tại miền đã đo đủ hàng/cột; không tạo thêm dữ liệu ở vùng chưa đo. Trục hình vẽ và chú giải ghi rõ quy ước theta/phi.

## Thứ tự điều khiển

1. Kiểm tra toàn bộ lưới và giới hạn trước khi chuyển động. Kiểm tra kết nối, lực giữ, mốc ZERO, phản hồi cả hai encoder.
2. Chuyển Tilt đến mức đầu, rồi Pan tới điểm đầu của hàng. Chỉ một trục chuyển động mỗi lần trong chế độ quét này.
3. Kiểm tra phản hồi, chờ ổn định, lấy sweep S11/S21 mới và lưu cặp Pan/Tilt cùng encoder.
4. Đi qua các điểm Pan trong hàng; hết hàng thì đổi Tilt và chạy hàng kế tiếp theo chiều đã chọn. Chế độ một chiều đưa Pan về đầu hàng trong khi không ghi nhận phép đo ở hành trình quay về.
5. Hoàn tất thì giữ vị trí cuối và lực giữ. Không tự ZERO hay tự quay về home.

Pause/STOP có hiệu lực cả khi chuyển hàng Tilt, đổi chiều Pan và chờ ổn định. STOP giữ những điểm đã đo, giữ đồ thị và lực giữ; nếu dừng giữa chuyển động thì tuân theo yêu cầu hiệu chuẩn lại của bản hiện tại. Mất phản hồi một trong hai encoder thì dừng trước điểm đo tiếp theo, đánh dấu dữ liệu chưa hoàn thành. Không thay dữ liệu thiếu bằng mẫu cũ.

## Giới hạn firmware

Mã hiện tại chặn Tilt -5..95° ở MATLAB và firmware. Để hỗ trợ tư thế ZERO tùy chọn và quét tới 180°, đề xuất firmware mới công bố khả năng cùng giới hạn số học Tilt -180..180°, Pan -360..360°. Người dùng đã mô tả hai trục có hành trình cơ khí 360°; các giới hạn khai báo không thay thế việc kiểm tra dây/khung gá thực tế.

MATLAB đọc khả năng này và kiểm tra mọi mục tiêu trước quét. Firmware cũ vẫn được nhận diện với giới hạn -5..95°; không tự xem firmware cũ là bản mới. Firmware mới trả lỗi khi mục tiêu vượt giới hạn thay vì âm thầm cắt về 95°. Lực giữ, heartbeat 30 giây, STOP và ZERO giữ nguyên quy tắc hiện hành. Mọi thử động cơ thật chỉ thực hiện khi cơ cấu và cổng serial sẵn sàng.

Khoảng ±180°/±360° trên là khả năng số học của giao thức, không mặc nhiên cho phép quay liên tục hoặc đi qua chặn cơ khí. Giới hạn phần mềm có hiệu lực là giao của khả năng firmware và hành trình người dùng đã xác nhận theo ZERO. Với cấu hình thật chưa khai báo lại, giữ khoảng tương thích Pan 0..360°, Tilt -5..95°; lưới mặc định 3D -90..90° sẽ báo cần khai báo hành trình phù hợp thay vì chạy ngay. Thiết lập rộng hơn do người dùng lựa chọn; mock có thể thử toàn bộ lưới. Không cần giả định cơ cấu có slip ring hay quay vô hạn.

Tilt hiện còn mất phản hồi với dây AS5600 2 m khi driver bật. Triển khai và test mock có thể hoàn tất độc lập; quét 3D thật vẫn phải đạt điều kiện encoder cả hai trục. Không tuyên bố thay đổi phần mềm đã sửa lỗi điện của cảm biến.

## Dữ liệu, đồ thị và tương thích

Dữ liệu 3D có schema version riêng: mỗi điểm chứa Pan/Tilt motor, theta/phi, encoder và validity của cả hai trục, chỉ số hàng/cột và thời gian. S11/S21 vẫn là ma trận phức [điểm × tần số]; giữ toàn bộ sweep trong MAT. Metadata chứa lưới dự kiến, các điểm đã hoàn tất, chế độ chiều quét, quy ước ZERO và lý do dừng.

CSV xuất cả hai góc motor lẫn theta/phi, RF ở tần số chọn và phản hồi encoder. JSON/TXT mô tả đầy đủ quy ước và mức hoàn thành. Tải lại MAT tái dựng được đồ thị theo metadata của lần đo đó, không dùng thiết lập GUI hiện tại.

Chuẩn hóa S21 theo đỉnh chung của toàn bộ các điểm hợp lệ; không chuẩn hóa riêng từng vòng Pan. Màu dùng dB tương đối; bán kính đề xuất dùng biên độ tương đối `10^(dB/20)`, ghi rõ trên đồ thị. Công thức hình học: x=r sin(theta) cos(phi), y=r sin(theta) sin(phi), z=r cos(theta). Điểm thiếu là NaN. Điểm đóng vòng/pole trùng hướng giữ nguyên trong raw; khi dựng hình gộp biên độ tuyến tính của các điểm cùng hướng rồi chuyển sang dB. Không trung bình pha giữa các hướng trùng.

Chế độ 2D tiếp tục tính chỉ số lát cắt như cũ. Trong 3D chỉ báo đỉnh toàn cục kèm cặp góc; HPBW/SLL/FBR chỉ tính trên lát cắt Pan người dùng chọn, có nhãn góc Tilt. Bề mặt 3D cũ suy ra từ cos(theta) được gắn nhãn mô hình ước lượng trong chế độ 2D; chế độ 3D dùng dữ liệu đo hai trục.

Quy ước này mô tả pattern theo cấu hình gá và phân cực phép đo. Không tự suy ra gain tuyệt đối, hiệu chỉnh phân cực hay tái dựng vector trường điện từ.

## Điều kiện nghiệm thu phần mềm

- Test phép đổi góc với ZERO nằm ngang, hướng lên, hướng tùy chỉnh và cả hai chiều; đảo phép đổi không làm dịch mốc cơ khí.
- Test thứ tự lệnh cho nhiều hàng Tilt, Pan luân phiên và một chiều, endpoint và từ chối toàn bộ lưới vượt giới hạn trước chuyển động.
- Test Pause/STOP giữa hàng và khi đổi Tilt, mất encoder từng trục, dữ liệu chưa hoàn thành và quét lần tiếp theo.
- Test lưu/tải 3D, chuẩn hóa chung, điểm thiếu/đóng vòng/pole và đọc lại dataset 2D cũ.
- Test GUI giữ đồ thị khi STOP, đúng nhãn/góc/tiến độ, các cấu hình ZERO không tự làm motor chuyển động.
- Test firmware native cho giới hạn mới và phát hiện khả năng; build PlatformIO. Giữ các regression test 2D/hold/AS5600 hiện có.

Các quyết định ghi “đề xuất” là lựa chọn kỹ thuật của người triển khai, chưa phải xác nhận của người dùng.
