# Đối chiếu Anritsu MS46122B — 2026-10-26

**Kết luận:** ứng dụng hiện tại chưa kết nối trực tiếp được với MS46122B; có thể tích hợp bằng backend Anritsu và điều chỉnh hợp đồng dữ liệu, hiệu chuẩn, giao diện. Phần quét góc và phân tích S11/S21 có thể tái sử dụng.

## Đối chiếu trực tiếp với mã nguồn dự án

Đánh giá ngày 2026-10-26, dựa trên mã trong checkout hiện tại. Kết luận: **chưa tương thích trực tiếp khi cắm máy; có thể tích hợp bằng một backend Anritsu và sửa hợp đồng dữ liệu/hiệu chuẩn liên quan**. Đây là nghiên cứu mã và tài liệu; chưa thử kết nối MS46122B, chưa xác nhận driver/phiên bản ShockLine trên PC, chưa đo RF hay điều khiển positioner.

### Bằng chứng hiện trạng

| Hạng mục | Bằng chứng trong repo | Ý nghĩa |
|---|---|---|
| Anritsu trong yêu cầu | [master-v4](automatic-antenna-measurement-system-master-v4.md), dòng 30 và 100 | Ghi rõ MS46122B là future backend; máy dự kiến là MS46122B-010. Đây là kế hoạch, không chứng minh option của máy thực tế. |
| Driver MATLAB | [VNAController.m](../matlab/classes/VNAController.m), dòng 59, 117, 358 | Chế độ Real nạp Python bridge NanoVNA và gọi các API cố định. |
| Nạp Python | [vnaPythonBackend.m](../matlab/classes/vnaPythonBackend.m), dòng 23 | Import cố định python.nanovna_bridge. |
| Nhận dạng máy | [nanovna_bridge.py](../python/nanovna_bridge.py), dòng 84–94 | Tạo NanoVNA_V2, yêu cầu device variant 0x02; không phải driver VNA tổng quát. |
| GUI | [AntennaMeasurementApp.m](../matlab/app/AntennaMeasurementApp.m), dòng 473–480 | Chỉ có Mock SAA-2N và Real USB COM6; chưa có lựa chọn Anritsu/địa chỉ socket. |
| Giới hạn đo | [VNARequest.m](../matlab/classes/VNARequest.m), dòng 8, 23–32; [vna_contracts.py](../python/vna_contracts.py), dòng 22–24, 34–37, 54 | 50 kHz–3 GHz, 2–401 điểm, Hz nguyên; lưới tính bằng bước làm tròn xuống theo NanoVNA. |
| Lưới quét anten | [MeasurementOrchestrator.m](../matlab/classes/MeasurementOrchestrator.m), dòng 225, 295, 583, 621 | So sánh chính xác với lưới tự tính. Backend trả lưới Anritsu khác sẽ bị từ chối dù dữ liệu RF hợp lệ. |
| Hiệu chuẩn | [VNACalibration.m](../matlab/classes/VNACalibration.m), dòng 92–117 | RAW/SOL/TR, đầu vào mặc định là raw; chưa có trạng thái instrument-corrected cho Anritsu. |
| Nhãn dữ liệu | [MeasurementOrchestrator.m](../matlab/classes/MeasurementOrchestrator.m), dòng 418 và 673 | Device bị ghi cố định SAA-2N; cần đổi sang nhận dạng thực tế. |
| Phụ thuộc kiểu controller | [AntennaMeasurementApp.m](../matlab/app/AntennaMeasurementApp.m), dòng 22; [MeasurementOrchestrator.m](../matlab/classes/MeasurementOrchestrator.m), dòng 20 | Thuộc tính có kiểu VNAController; không thể thay bằng một class độc lập bất kỳ mà không thay lớp tích hợp. |

Tìm trong thư mục matlab/ và python/ hiện hành không thấy triển khai Anritsu/MS461, SCPI, visadev hay tcpclient. Bằng chứng quyết định là đường Real đang nối cứng tới NanoVNA; tên VNAController không có nghĩa là hỗ trợ mọi hãng.

### Phần tái sử dụng và phần cần bổ sung

- **Tái sử dụng về nguyên lý:** điều khiển ESP32/encoder và trình tự quay → ổn định → đo; các thuật toán PatternAnalyzer tính polar/HPBW/SLL/FBR từ S21; các phép tính Smith/VSWR/phase từ S11 phức; cấu trúc ma trận theo góc và tần số trong DataManager. Việc tái sử dụng cần kiểm thử tích hợp, không có nghĩa mọi file giữ nguyên.
- **Backend mới:** kết nối ShockLine, nhận dạng model/serial/options, cấu hình sweep, trigger và đợi sweep mới hoàn tất, đọc S11/S21 phức cùng tần số thực, xử lý timeout/mất kết nối/STOP. Không thay COM6 bằng một COM khác để giải quyết khác biệt giao thức.
- **Giữ hợp đồng điều phối:** controller hiện có claim/release/lease; scan dùng configureSweep/acquireSingle, workbench dùng beginSweep/pollSweep/cancelSweep. Backend phải phục vụ cả hai đường này để GUI và scan không tranh máy.
- **Giới hạn theo máy:** dải 2.4 GHz dự án quan tâm nằm trong dải của các phiên bản MS46122B nêu trong tài liệu hãng. Phải chặn dưới 1 MHz cho Anritsu và chỉ mở trên 3 GHz theo option thực tế; đồng thời sửa validator MATLAB/Python nếu chúng vẫn nằm trên đường dữ liệu mới. Không chỉ đổi giới hạn ở ô GUI.
- **Lưới tần số:** lấy/readback lưới thực và dùng nhất quán khi quét, đối chiếu profile, đặt marker và xuất dữ liệu. Không mặc định công thức floor-grid của NanoVNA áp dụng được cho Anritsu.
- **Hiệu chuẩn và truy vết:** phân biệt raw, corrected trong ShockLine và corrected phía MATLAB. Không áp lại profile NanoVNA lên dữ liệu đã được Anritsu hiệu chuẩn; không ghi dữ liệu corrected vào trường mang nghĩa raw. Cần lưu hãng/model/serial, software version, option, cal state, reference plane, công suất và IF bandwidth; mở rộng trạng thái phân tích/xuất file tương ứng. Các trường nhận dạng hiện tại chủ yếu là register byte của NanoVNA.
- **S12/S22:** MS46122B có khả năng đo đủ hai chiều, nhưng pipeline hiện tại chỉ tiêu thụ S11/S21. Đo pattern chiều thuận không bắt buộc phải mở rộng đủ bốn S-parameter; cần mở rộng riêng nếu muốn khai thác full two-port.

### Hướng tích hợp đề xuất

Giữ VNAController làm lớp API chung và đưa lựa chọn NanoVNA/Anritsu vào backend; giữ Mock tách biệt. Đối với Anritsu, dùng giao tiếp SCPI tới ShockLine theo topology của hãng. MATLAB có [tcpclient](https://www.mathworks.com/help/matlab/ref/tcpclient.html), được giới thiệu từ R2014b; có thể dùng nó cho TCP socket. Phương án VISA socket qua visadev cần Instrument Control Toolbox và VISA driver phù hợp theo [MathWorks](https://www.mathworks.com/help/matlab/import_export/troubleshooting-tcpip-client-interface.html). Chưa xác nhận các dependency này trên máy hiện tại, và không cần dùng những thuộc tính chỉ bổ sung ở R2026b cho dự án R2025b.

Ưu tiên xác minh một sweep tĩnh tại 2.4 GHz: đúng ID, đúng frequency vector, đủ complex S11/S21, dữ liệu mới sau trigger, số liệu khớp ShockLine với cùng calibration/settings. Sau đó kiểm tra STOP/mất kết nối và mock hồi quy; cuối cùng mới thử scan góc nhỏ với positioner đã đủ điều kiện. Kiểm tra bằng tải/thru/chuẩn độc lập cần có tiêu chí sai số và noise floor phù hợp, không lấy việc phần mềm chạy được làm chứng nhận độ chính xác RF.

MS46122B không tự biến S21 thành gain anten tuyệt đối. Theo [hướng dẫn workbench](vna-workbench-user-guide.md), phép suy ra gain vẫn cần reference/hiệu chuẩn đường đo và bố trí đo phù hợp.

Không sửa mã vận hành hoặc chạy kiểm thử phần cứng trong lần nghiên cứu này.


Phạm vi: nghiên cứu tài liệu chính hãng và mã nguồn; chưa kết nối hoặc kiểm thử MS46122B thật. Phần này ghi nhận khả năng thiết bị, không chứng nhận ứng dụng hiện tại đã hỗ trợ.

## Kết quả từ tài liệu Anritsu

MS46122B có S11, S21, S12, S22; phù hợp về loại dữ liệu với phép đo phản xạ và truyền qua anten. Ba tùy chọn tần số hiện được liệt kê là **-010: 1 MHz–8 GHz; -020: 1 MHz–20 GHz; -043: 1 MHz–43,5 GHz**. Không thể suy ra tùy chọn đã lắp chỉ từ tên MS46122B. Datasheet cũng ghi 2–16.001 điểm, quét linear/log/CW/segmented, và IVI-C hỗ trợ MATLAB. Nguồn: [Technical Data Sheet 11410-00995 Rev. W, tr. 2, 14, 16](https://www.anritsu.com/en-US/test-measurement/support/downloads/brochures-datasheets-and-catalogs/dwl18337).

Đường giao tiếp thực tế là **MATLAB → TCP socket trên PC chạy ShockLine → phần mềm/driver ShockLine → USB → MS46122B**. Máy phân tích nối USB với PC; đây không phải cổng COM NanoVNA. Cùng PC thì dùng `127.0.0.1:5001`; ShockLine phải chạy trước. Kiểm tra địa chỉ qua Main Menu → System → Network Interface. Nguồn: [ShockLine Programming Manual 10410-00746 Rev. AC, mục 1-6, tr. 1-10 đến 1-14](https://www.anritsu.com/en-US/test-measurement/support/downloads/manuals/dwl18848).

## Điểm kỹ thuật để viết adapter

Cổng 5001 là giá trị mặc định, có thể được người vận hành thay đổi; cần đọc cấu hình Network Interface thực tế trước khi kết nối (Programming Manual, lệnh SYSTem:COMMunicate:TCPIP:PORT).

Tài liệu lập trình hiện tải từ đường dẫn chính hãng là **10410-00746 Rev. AC, April 2025**; không nên mặc định tài liệu cũ 10410-00338 là bản hiện hành.

- `*IDN?` xác minh máy; lệnh socket kết thúc bằng LF.
- `:CALC1:DATA:SDAT?` trả dữ liệu phức real/imag của trace được chọn; tài liệu yêu cầu **Hold**.
- `:SENS1:FREQ:DATA?` trả danh sách tần số thực.
- `:SENS1:CORR:STAT?` đọc trạng thái hiệu chỉnh RF. Không được mặc định dữ liệu từ máy là RAW chưa hiệu chuẩn.
- `:SENS:HOLD:FUNC HOLD` kết hợp `:TRIG:SING` thực hiện một lượt rồi dừng; bộ phân tích lệnh chờ kết thúc lượt. Đây là cơ sở cho chuỗi quay–ổn định–đo.

Nguồn cho các lệnh trên: [ShockLine Programming Manual, mục 1-6; tr. 5-157, 5-509, 5-511, 5-533](https://www.anritsu.com/en-US/test-measurement/support/downloads/manuals/dwl18848). Các lệnh là tham chiếu thiết kế, chưa được thử trên máy của người dùng.

## Suy luận tích hợp và điều kiện kiểm chứng

Đề xuất adapter dùng `tcpclient` MATLAB cho SCPI socket; IVI-C là phương án khác. `tcpclient` có trong tài liệu MATLAB từ R2014b. Chọn VISA/`visadev` sẽ cần Instrument Control Toolbox; chưa kiểm tra license hoặc driver cài trên PC này. Nguồn: [MathWorks tcpclient](https://www.mathworks.com/help/matlab/ref/tcpclient.html), [MathWorks TCP/IP troubleshooting](https://www.mathworks.com/help/matlab/import_export/troubleshooting-tcpip-client-interface.html).

Phải bảo toàn dữ liệu phức và tần số thực, phân biệt hiệu chuẩn từ ShockLine với SOL/TR phía ứng dụng để tránh hiệu chỉnh hai lần. Cần kiểm tra trạng thái cal, tham số sweep, timeout, đọc đủ block dữ liệu và mất kết nối. Việc cài ShockLine/driver thành công trên Windows hiện tại, model option, độ chính xác RF, tốc độ thực và hành vi STOP vẫn cần thử nghiệm tại máy; tài liệu không thay thế các phép thử đó.
