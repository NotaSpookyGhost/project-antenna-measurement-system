# Tham khảo hệ đo anten không dùng buồng không phản xạ

Ngày tra cứu: 2026-10-13. Phạm vi: hệ VNA + cơ cấu quay, đo pattern trong phòng thường hoặc không gian mở; phân biệt kết quả nghiên cứu với thông tin nhà cung cấp. Chưa thay đổi code hoặc chạy phần cứng.

## 1. Wagih–Moody, CAMA 2021: gần hệ hiện tại nhất

**Đã xác minh trong bài gốc:** R&S ZVB4, tay máy Arduino Braccio, MATLAB, dipole nửa bước sóng; khoảng cách 1,5 m trong phòng lab thường. Đo patch 2,4/3,3 GHz. Chi phí dưới 300 USD **không gồm VNA**. Phương pháp mô tả không có time gating; hấp thụ cục bộ được nêu là hướng nghiên cứu tiếp.

Ở 3,3 GHz, búp chính lệch dưới 1,5 dB so với CST nhưng vùng sau lệch 7–10 dB do máy tính/VNA gần đó. Phân cực chéo cũng sai đáng kể. Tác giả khuyên không gian rộng, cách sàn/tường lớn hơn khoảng cách hai anten. So sánh buồng có dùng phantom cơ thể: không phải chuẩn free-space tuyệt đối.

**Suy luận cho dự án:** cấu hình hiện tại có tiền lệ thực tế cho đo búp chính sơ bộ; chưa đủ căn cứ đo chính xác null, búp sau và phân cực chéo.

Nguồn: [bài đầy đủ tại University of Glasgow](https://eprints.gla.ac.uk/272178/1/272178.pdf), [hồ sơ công bố](https://eprints.gla.ac.uk/272178/), DOI 10.1109/CAMA49227.2021.9703629.

## 2. Olencki và cộng sự, IEEE Access 2023: VNA giá thấp + time gating

**Đã xác minh toàn văn:** LibreVNA 100 kHz–6 GHz, đầu quay tự chế, đo S21 và xử lý time gating. Phòng thường 5,5 × 4,5 × 3,1 m chứa thiết bị, hai anten cách 1,6 m. Vivaldi dùng span **1 GHz**; monopole dùng **2 GHz**. Mỗi phép đo lặp năm lần; hiệu chỉnh cửa sổ bằng mô phỏng hoặc dữ liệu tham chiếu buồng.

Chi phí công bố khoảng 3.630 USD. Hệ được đối chiếu buồng và VNA chuyên nghiệp. Gating phải bổ sung hiệu chỉnh biên độ: thí nghiệm gain Vivaldi báo sai lệch trung bình 0,12 dB sau hiệu chỉnh đầy đủ, 1,42 dB khi chưa xử lý, nhưng 2,07 dB nếu gating thiếu hiệu chỉnh biên độ. Đây là kết quả riêng của thí nghiệm, không phải độ chính xác bảo đảm cho NanoVNA.

**Suy luận:** tiền lệ mạnh cho hướng giữ VNA/cơ cấu quay rồi thêm xử lý, nhưng span lớn và hiệu chuẩn là điều kiện thiết yếu.

Nguồn: [toàn văn tại kho nghiên cứu Gdańsk](https://mostwiedzy.pl/pl/publication/download/1/a-low-cost-system-for-far-field-non-anechoic-measurements-of-antenna-performance-figures_79139.pdf), DOI 10.1109/ACCESS.2023.3268116, đặc biệt mục III–V.

## 3. Bekasiewicz và cộng sự, Measurement 2023: hiệu chuẩn gate tự động

Nghiên cứu sử dụng anten có pattern tham chiếu để tối ưu khoảng thời gian giữ lại, thay cho chọn gate thủ công. Đã thử bốn anten nhỏ và nhiều vị trí đo, xem xét aliasing và nhiễu bên ngoài. Bài này cho thấy “có IFFT + gate” chưa tự đảm bảo kết quả: lựa chọn cửa sổ và hiệu chuẩn môi trường cũng là một phần của hệ đo. Không suy rộng kết quả sang cặp anten mảng 2,4 GHz chưa được đặc trưng của dự án.

Nguồn: [bài gốc trên ScienceDirect](https://www.sciencedirect.com/science/article/pii/S0263224123000416), [PDF tại Reykjavik University](https://iris.ru.is/ws/files/213566124/1-s2.0-S0263224123000416-main.pdf), DOI 10.1016/j.measurement.2023.112477.

## 4. Các hệ thương mại/prototype do nhà cung cấp mô tả

- **Geozondas:** [trang hệ time domain](https://geozondas.com/low_cost.php) là nguồn của hình người dùng gửi. TDAMS1/10 dùng oscilloscope lấy mẫu GZ10M, đầu phát xung GZ1117DN-50, positioner và anten tham chiếu UWB. Hãng cũng có [hệ frequency domain](https://geozondas.com/frequency_domain.html) dùng Anritsu MS46322B và gating. Vì vậy không cần đồng nhất “không buồng” với “bắt buộc phát xung”. Tuyên bố hiệu năng của hãng chưa thay thế kiểm chứng độc lập.
- **NanoFarfield:** [nhà phát triển](https://www.antenit.com/nanofarfield/) mô tả hỗ trợ NanoVNA/LiteVNA/LibreVNA và demo gating; [trang dự án Crowd Supply](https://www.crowdsupply.com/antenom-antenna-technologies/nanofarfield) khuyến nghị không gian ngoài trời/sân thượng ít phản xạ. Đây là thông tin sản phẩm đang phát triển, không phải công bố độc lập về độ chính xác toàn hệ.
- **NSI-MI:** [tài liệu Time Domain Analysis](https://www.nsi-mi.com/products/software-products/mi-3000/time-domain-analysis) yêu cầu phản xạ có độ trễ phân biệt được và dữ liệu tần số cách đều; nêu ví dụ 100 MHz tương ứng khoảng 3 m phân giải chiều dài đường truyền. Gating không tách được mọi phản xạ ở mọi bố trí.

## Hướng áp dụng đề xuất — suy luận kỹ thuật

1. Giữ cấu trúc VNA + hai anten + quay góc để lập baseline. Ưu tiên khu vực thoáng, nâng cao anten, tránh máy tính/vật kim loại sát anten, đánh giá độ lặp khi thay đổi vị trí.
2. Thử time gating ở một góc, trên băng thông thực sự hữu dụng của cặp anten và VNA. Không coi tăng số điểm hoặc zero-padding là tăng phân giải vật lý.
3. So sánh raw/gated với tham chiếu hoặc nhiều bố trí đo; lưu S21 phức nguyên bản. Xác nhận riêng pattern tương đối và gain tuyệt đối vì gating làm thay đổi biên độ.
4. Chỉ triển khai gating toàn bộ scan sau khi chứng minh tách được LoS/phản xạ. Nếu anten hẹp băng không cho độ phân giải đủ, ưu tiên cải thiện bố trí, hấp thụ cục bộ hoặc đo kiểm tham chiếu bên ngoài.

Các con số giá và sai số ở trên là số công bố tại thời điểm nghiên cứu, không phải báo giá hiện tại hay thông số bảo đảm của hệ người dùng.
