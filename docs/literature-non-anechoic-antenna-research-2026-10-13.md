# Bài báo tiếp nối hướng đo anten ngoài buồng hấp thụ RF

Tra cứu ngày 2026-10-13. Dành cho hệ NanoVNA, MATLAB, bộ quay Pan/Tilt và anten mảng 2,4 GHz. Đây là danh mục chọn lọc, không phải tổng quan hệ thống hay xác nhận tính mới của đề tài. Năm ghi theo ấn bản tạp chí/hội nghị, không theo ngày công cụ tìm kiếm thu thập PDF.

Bài nền: Olencki và cộng sự, **A Low-Cost System for Far-Field Non-Anechoic Measurements of Antenna Performance Figures**, IEEE Access, 2023. [DOI](https://doi.org/10.1109/ACCESS.2023.3268116). Xem thêm bản khảo sát hệ thống `research-non-anechoic-antenna-measurements-2026-10-13.md`.

## Danh mục chọn lọc

### 1. Time-Gating method with automatic calibration for accurate measurements of electrically small antenna radiation patterns in Non-Anechoic environments

- **Measurement 208, 112477, 2023.** Bekasiewicz, Koziel và Czyz.
- [DOI](https://doi.org/10.1016/j.measurement.2023.112477) · [PDF kho Gdańsk](https://mostwiedzy.pl/pl/publication/download/1/time-gating-method-with-automatic-calibration-for-accurate-measurements-of-electrically-small-antenn_77049.pdf).
- Tự tối ưu khoảng gate bằng pattern tham chiếu đã biết; thử trên bốn anten nhỏ. Hữu ích để hiểu hiệu chuẩn gate thay cho chọn bằng mắt. Cần phân biệt tự chọn tham số với không cần dữ liệu tham chiếu.
- Mức đọc: bản tóm tắt và mô tả phương pháp từ bài gốc.

### 2. Filter-Hilbert method for automatic correction of non-anechoic antenna measurements with embedded self-calibration mechanism

- **Measurement 222, 113705, 2023.** Bekasiewicz và Waladi.
- [DOI](https://doi.org/10.1016/j.measurement.2023.113705) · [nhà xuất bản](https://www.sciencedirect.com/science/article/pii/S0263224123012691).
- Bộ lọc Hilbert thích nghi với điều kiện truyền sóng; bài báo báo cáo ba anten, 25 thí nghiệm, 15 tần số. Có thể dùng làm thuật toán đối chứng cho time gating cơ bản.
- Mức đọc: metadata, highlights và abstract nhà xuất bản; chưa tái lập thuật toán.

### 3. Multi-taper-based automatic correction of non-anechoic antenna measurements

- **Metrologia 61, 012101, 2024**; xuất bản online tháng 12/2023. Dzwonkowski, Waladi và Bekasiewicz.
- [DOI](https://doi.org/10.1088/1681-7575/ad10bd) · [PDF kho cơ quan tác giả](https://ppm.edu.pl/seam/resource/rest/download/GUM6a74a12082a84aa2989ef123c64bc678?cid=411213&entityId=GUMbe2ee24f67ec4e99a58f731673b71900&entityType=article).
- Dùng nhiều hàm taper để tách thành phần truyền trực tiếp khỏi phản xạ và nhiễu; thử Vivaldi ở hai nơi đo. Không đồng nhất multitaper với đo nhiều vị trí: đây là cách xử lý dữ liệu bằng nhiều hàm cửa sổ/cơ sở.
- Mức đọc: abstract và phần kết luận bản bài gốc được lập chỉ mục.

### 4. Accurate Post-Processing of Spatially-Separated Antenna Measurements Realized in Non-Anechoic Environments

- **ICCS 2024, LNCS 14834, 19–27.** Bekasiewicz, Waladi, Dhaene và Czaplewski.
- [DOI](https://doi.org/10.1007/978-3-031-63759-9_3) · [University of Ghent](https://biblio.ugent.be/publication/01J824RTFBVZJSBB4R2FCR01H7) · [PDF hội nghị](https://www.iccs-meeting.org/archive/iccs2024/papers/148340017.pdf).
- Căn chỉnh đáp ứng trong miền thời gian rồi kết hợp phép đo ở các vị trí khác nhau; sáu thử nghiệm trong phòng làm việc. Cần thêm dịch chuyển vị trí; quay góc đơn thuần không cung cấp dữ liệu tương đương.
- Mức đọc: abstract và metadata cơ quan tác giả/hội nghị.

### 5. Single-Frequency Phaseless Data-Based Echo Suppression for Antenna Pattern Measurement in a Nonideal Chamber

- **IEEE Transactions on Antennas and Propagation 72(1), 197–211, 2024**; online 2023. Wang và cộng sự.
- [DOI](https://doi.org/10.1109/TAP.2023.3324129) · [PDF Aalborg University](https://vbn.aau.dk/files/698057243/Single-Frequency_Phaseless_Data_Based_Echo_Suppression_for_Antenna_Pattern_Measurement_in_a_Non-ideal_Chamber_new_VBN.pdf).
- Khử echo từ biên độ tại một tần số bằng phép đo nhiều vị trí. Đáng khảo sát khi băng thông hữu dụng hạn chế. Thử nghiệm thêm tấm kim loại trong buồng để tạo phản xạ: chưa phải bằng chứng hoạt động trong mọi phòng thường.
- Mức đọc: abstract, phần mở đầu và metadata bản tác giả.

### 6. On Efficient Echo Suppression With Phaseless Data in the Joint Frequency and Spatial Domain for Antenna Pattern Measurement in a Nonanechoic Chamber

- **IEEE Transactions on Antennas and Propagation 72(3), 2968–2973, 2024.** Wang và cộng sự.
- [DOI](https://doi.org/10.1109/TAP.2024.3352274) · [Aalborg University](https://vbn.aau.dk/en/publications/on-efficient-echo-suppression-with-phaseless-data-in-the-joint-fr).
- Kết hợp dữ liệu biên độ theo tần số và vị trí để tái dựng pattern. Bài này dùng cả thông tin dải tần; không gộp nó với phương pháp một tần số của mục 5.
- Mức đọc: abstract và metadata cơ quan tác giả.

### 7. Framework for reliable and automatic multi-frequency correction of non-anechoic antenna measurements

- **Measurement 251, 117239, 2025.** Bekasiewicz, Dzwonkowski và Waladi.
- [DOI](https://doi.org/10.1016/j.measurement.2025.117239) · [nhà xuất bản](https://www.sciencedirect.com/science/article/pii/S0263224125005986).
- Tự điều chỉnh cấu hình xử lý theo tần số, anten và nơi đo; tối ưu dựa trên sai khác với mô phỏng điện từ. Tự động hóa không có nghĩa độc lập với đáp ứng tham chiếu. Đáng đọc để thiết kế việc chọn span và số điểm.
- Mức đọc: abstract và các đoạn phương pháp/kết quả được nhà xuất bản lập chỉ mục; không tuyên bố đã tái lập toàn văn.

### 8. Unsupervised SVD-Based Correction of Antenna Measurements in Nonanechoic Environments

- **IEEE Antennas and Wireless Propagation Letters 24(9), 3134–3138, 2025.** Waladi, Bekasiewicz, Li và Leifsson.
- [DOI](https://doi.org/10.1109/LAWP.2025.3584521) · [bản bài gốc trên ResearchGate](https://www.researchgate.net/publication/393213087_Unsupervised_SVD-Based_Correction_of_Antenna_Measurements_in_Nonanechoic_Environments).
- SVD xử lý S21 phức, tự điều chỉnh cấu hình. Có thử bốn patch hẹp băng; span tối ưu khoảng 0,3–1 GHz. Đối chứng patch là mô phỏng EM. Không suy ra rằng thuật toán hoạt động với span 10 MHz hoặc đã được kiểm chứng trên NanoVNA/mảng 2,4 GHz.
- Mức đọc: bản bài gốc do nhóm nghiên cứu đọc, gồm phần thử nghiệm và bảng cấu hình; chưa tìm được bản kho trường trong đợt tra cứu.

### 9. Multisetup Correction of Antenna Radiation Patterns Obtained From Phaseless Nonanechoic Measurements

- **IEEE Antennas and Wireless Propagation Letters 24(11), 3910–3914, 2025.** Waladi, Piekarz, Sorocki và Bekasiewicz.
- [DOI](https://doi.org/10.1109/LAWP.2025.3596814) · [AGH University](https://badap.agh.edu.pl/publikacja/165362).
- Làm trơn robust và kết hợp dữ liệu biên độ ở nhiều bố trí. Vẫn quét trên một dải tần. Abstract mô tả thử Vivaldi ở hai cấu hình; cần xem thêm toàn văn trước khi chuyển sang anten mảng.
- Mức đọc: abstract và metadata kho trường; chưa đọc toàn văn.

### 10. Automatic Correction of Non-Anechoic Antenna Measurements Using Complex Morlet Wavelets

- **IEEE Antennas and Wireless Propagation Letters 23, 2521–2525, 2024.** Bekasiewicz và Waladi.
- [DOI](https://doi.org/10.1109/LAWP.2024.3398656) · [kho Gdańsk](https://mostwiedzy.pl/pl/publication/automatic-correction-of-non-anechoic-antenna-measurements-using-complex-morlet-wavelets%2C162940-1).
- Tự định vị và điều chỉnh wavelet Morlet theo thành phần truyền trực tiếp. Có thể so sánh với gate thông thường trên S21 nhiều tần số; chưa chứng minh trên cấu hình NanoVNA của dự án.
- Mức đọc: metadata và abstract cơ quan tác giả.

### 11. Correction of non-anechoic antenna measurements using matrix pencil algorithm with adaptively adjusted setup

- **Expert Systems with Applications 288, 128277, 2025.** Bekasiewicz.
- [DOI](https://doi.org/10.1016/j.eswa.2025.128277) · [nhà xuất bản](https://www.sciencedirect.com/science/article/pii/S0957417425018962).
- Tự điều chỉnh cấu hình matrix-pencil dựa trên tối ưu với mô hình thay thế cập nhật từ mô phỏng EM. Có thể làm đối chứng cho SVD/gating; cần ghi rõ sự phụ thuộc vào mô hình tham chiếu.
- Mức đọc: metadata và mô tả phương pháp/abstract nhà xuất bản.

## Nhận định cho dự án — suy luận, chưa phải kết luận tính mới

Các công trình cho thấy hướng này tiếp tục phát triển tới 2025. Chỉ thay VNA bằng NanoVNA, thêm MATLAB hoặc triển khai IFFT/gate không đủ tự khẳng định đóng góp mới về thuật toán.

Các câu hỏi đáng kiểm tra tiếp:

1. Với anten mảng 2,4 GHz và băng thông/SNR thực tế của NanoVNA, miền điều kiện nào cho phép khôi phục pattern đáng tin? Đối chiếu gating, SVD và phép đo nhiều vị trí.
2. Có thể chọn cấu hình xử lý từ dữ liệu đo, giảm phụ thuộc vào pattern mô phỏng đã biết, mà vẫn vượt các phương pháp tự động năm 2025 không? Đây là câu hỏi so sánh với prior art, không phải khoảng trống đã xác nhận.
3. Khi giới hạn tổng thời gian đo, nên dành thời gian cho thêm tần số, thêm góc hay thêm vị trí? So sánh cùng ngân sách đo và kiểm chứng trên môi trường/anten không dùng để chọn tham số.

Kết quả cần phân biệt sai số pattern tương đối, HPBW, SLL, FBR, gain tuyệt đối và độ lặp. Độ lặp tốt không tự chứng minh độ chính xác. Nếu fit tham số theo mô phỏng, không dùng chính pattern đó làm bằng chứng duy nhất cho độ chính xác.

Thứ tự đọc gợi ý: bài nền 2023 → mục 1 → mục 8 → mục 5 → mục 7; các mục còn lại cung cấp thuật toán đối chứng và hướng mở rộng dữ liệu.
