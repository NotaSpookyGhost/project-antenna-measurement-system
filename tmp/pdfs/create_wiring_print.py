from pathlib import Path
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, LongTable, TableStyle, Flowable
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
import pypdfium2 as pdfium
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/pdf/bang-noi-day-antenna.pdf'
OUT.parent.mkdir(parents=True, exist_ok=True)
pdfmetrics.registerFont(TTFont('ArialVN', 'C:/Windows/Fonts/arial.ttf'))
pdfmetrics.registerFont(TTFont('ArialVN-Bold', 'C:/Windows/Fonts/arialbd.ttf'))
pdfmetrics.registerFontFamily('ArialVN', normal='ArialVN', bold='ArialVN-Bold')
body = ParagraphStyle('body', fontName='ArialVN', fontSize=9, leading=12)
small = ParagraphStyle('small', parent=body, fontSize=8, leading=10.5)
title = ParagraphStyle('title', parent=body, fontName='ArialVN-Bold', fontSize=16, leading=20)
head = ParagraphStyle('head', parent=body, fontName='ArialVN-Bold', fontSize=9, leading=12)

class CheckBox(Flowable):
    def __init__(self):
        Flowable.__init__(self)
        self.width = self.height = 8
    def draw(self):
        self.canv.setStrokeColor(colors.black)
        self.canv.setLineWidth(.6)
        self.canv.rect(0, 0, 8, 8)

rows = [
('Nguồn 20 V','PD trigger +20 V','IN+ bộ hạ áp 3,3 V','Đúng cực; bộ hạ áp phải phù hợp đầu vào 20 V.'),
('Nguồn 20 V','PD trigger +20 V','VM / VMOT driver Pan','Nguồn công suất; không nhầm VIO.'),
('Nguồn 20 V','PD trigger +20 V','VM / VMOT driver Tilt','Nguồn công suất; không nhầm VIO.'),
('GND','PD trigger - / GND','IN- bộ hạ áp','Về điểm GND phân phối nguồn.'),
('GND','GND phân phối nguồn','GND driver Pan','Nối đủ chân GND công suất / logic theo module.'),
('GND','GND phân phối nguồn','GND driver Tilt','Nối đủ chân GND công suất / logic theo module.'),
('Logic 3,3 V','OUT+ bộ hạ áp (3,3 V)','VIO / VCC_IO driver Pan','Không nối vào 5VOUT.'),
('Logic 3,3 V','OUT+ bộ hạ áp (3,3 V)','VIO / VCC_IO driver Tilt','Không nối vào 5VOUT.'),
('Sensor Tilt','OUT+ bộ hạ áp (3,3 V)','J3 chân 1 → VCC AS5600 Tilt','Đo xác nhận 3,3 V trước khi nối tải.'),
('Sensor Pan','OUT+ bộ hạ áp (3,3 V)','J4 chân 1 → VCC AS5600 Pan','Đo xác nhận 3,3 V trước khi nối tải.'),
('GND sensor','OUT- / GND bộ hạ áp','J3 chân 2 → GND AS5600 Tilt','Chung GND nguồn và ESP32.'),
('GND sensor','OUT- / GND bộ hạ áp','J4 chân 2 → GND AS5600 Pan','Chung GND nguồn và ESP32.'),
('GND ESP32','GND phân phối nguồn','Chân GND ESP32','Đi dây riêng; tránh dòng motor qua bo ESP32.'),
('USB','USB máy tính','Cổng USB ESP32','Cấp nguồn và giao tiếp; không nối 20 V vào ESP32.'),
('Lệnh Pan','ESP32 GPIO25','STEP driver Pan','Xung bước.'),
('Lệnh Pan','ESP32 GPIO26','DIR driver Pan','Chiều quay.'),
('Lệnh Pan','ESP32 GPIO27','EN / ENN driver Pan','LOW = bật; HIGH = nhả.'),
('Lệnh Tilt','ESP32 GPIO32','STEP driver Tilt','Xung bước.'),
('Lệnh Tilt','ESP32 GPIO33','DIR driver Tilt','Chiều quay.'),
('Lệnh Tilt','ESP32 GPIO14','EN / ENN driver Tilt','LOW = bật; HIGH = nhả.'),
('I2C Tilt','ESP32 GPIO21','J3 chân 4 → SDA AS5600 Tilt','Giữ riêng với bus Pan.'),
('I2C Tilt','ESP32 GPIO22','J3 chân 3 → SCL AS5600 Tilt','Không đổi SDA với SCL.'),
('I2C Pan','ESP32 GPIO18','J4 chân 4 → SDA AS5600 Pan','Giữ riêng với bus Tilt.'),
('I2C Pan','ESP32 GPIO19','J4 chân 3 → SCL AS5600 Pan','Không đổi SDA với SCL.'),
('Motor Pan','Driver Pan: cuộn A, đầu 1','J1 chân 1 → motor A+','Màu bàn giao: đen. Xác nhận cặp cuộn.'),
('Motor Pan','Driver Pan: cuộn A, đầu 2','J1 chân 2 → motor A-','Màu bàn giao: xanh lá.'),
('Motor Pan','Driver Pan: cuộn B, đầu 1','J1 chân 3 → motor B+','Màu bàn giao: đỏ. Xác nhận cặp cuộn.'),
('Motor Pan','Driver Pan: cuộn B, đầu 2','J1 chân 4 → motor B-','Màu bàn giao: xanh lam.'),
('Motor Tilt','Driver Tilt: cuộn A, đầu 1','J2 chân 1 → motor A+','Màu bàn giao: đen. Xác nhận cặp cuộn.'),
('Motor Tilt','Driver Tilt: cuộn A, đầu 2','J2 chân 2 → motor A-','Màu bàn giao: xanh lá.'),
('Motor Tilt','Driver Tilt: cuộn B, đầu 1','J2 chân 3 → motor B+','Màu bàn giao: đỏ. Xác nhận cặp cuộn.'),
('Motor Tilt','Driver Tilt: cuộn B, đầu 2','J2 chân 4 → motor B-','Màu bàn giao: xanh lam.'),
]
story = [Paragraph('BẢNG KIỂM TRA NỐI DÂY ANTENNA', title),
 Paragraph('ESP32 DevKit V1 • 2 × TMC2209 • 2 × AS5600 • Firmware V4.0_HOLD', body),
 Spacer(1, 5*mm),
 Paragraph('<b>Trước khi kiểm tra:</b> Ngắt nguồn 20 V và USB; đỡ cơ cấu Tilt. Đánh dấu ô khi đã kiểm tra đúng cả hai đầu dây. Số GPIO là số in trên bo ESP32.', body),
 Spacer(1, 2*mm),
 Paragraph('<b>Giắc:</b> J1 = motor Pan; J2 = motor Tilt; J3 = sensor Tilt; J4 = sensor Pan. Đọc số chân khắc trên giắc; mặt hàn và mặt cắm bị đảo trái/phải. Không cắm lẫn giắc motor và sensor.', body),
 Spacer(1, 4*mm)]
data = [[Paragraph(x, head) for x in ['Đạt','Số','Nhóm','Từ / điểm đầu','Đến / đường qua giắc','Ghi chú kiểm tra']]]
for n, row in enumerate(rows, 1):
    data.append([CheckBox(), Paragraph(str(n), body), *[Paragraph(s, body) for s in row]])
table = LongTable(data, colWidths=[9*mm,9*mm,22*mm,43*mm,58*mm,45*mm], repeatRows=1, hAlign='LEFT')
table.setStyle(TableStyle([
 ('VALIGN',(0,0),(-1,-1),'MIDDLE'),('GRID',(0,0),(-1,-1),.4,colors.HexColor('#777777')),
 ('BACKGROUND',(0,0),(-1,0),colors.HexColor('#dedede')),
 ('LEFTPADDING',(0,0),(-1,-1),5),('RIGHTPADDING',(0,0),(-1,-1),5),
 ('TOPPADDING',(0,0),(-1,-1),7),('BOTTOMPADDING',(0,0),(-1,-1),7),
 ('ROWBACKGROUNDS',(0,1),(-1,-1),[colors.white,colors.HexColor('#f5f5f5')]),
]))
story.extend([table, Spacer(1,4*mm),
 Paragraph('<b>Ghi nhớ:</b> Để chân 3V3 ESP32 tách khỏi OUT+ bộ hạ áp trong cấu hình cấp nguồn này. OUT cảm biến / GPIO23 không cần cho firmware hiện tại. Màu dây motor chỉ theo tài liệu bàn giao; xác nhận cuộn bằng đồng hồ khi đã ngắt nguồn và tách motor khỏi driver. Tên chân đầu ra cuộn trên driver phải đối chiếu đúng module.', small),
 Spacer(1,2*mm),
 Paragraph('<b>Phạm vi:</b> Bảng kết nối theo tài liệu, chưa xác nhận dây thực tế. Chưa bao gồm thiết kế cầu chì, chống quá áp, chỉnh dòng Vref hay cấu hình vi bước. Không dùng bảng này để tự xác định các chân chưa được ghi rõ trên module.', small),
 Spacer(1,2*mm),
 Paragraph('Đối chiếu: firmware/positioner_v3_hold/src/main.cpp (GPIO); CODEX_HANDOVER/contex ver2/README_AI_MASTER_CONTEXT.md (J1-J4); docs/hardware-validation-2026-10-11.md (nguồn thực tế).', small),
 Spacer(1,4*mm),Paragraph('Người kiểm tra: .....................................  Ngày: ....................  Ghi chú: .....................................', body)])

def footer(c, doc):
    c.setFont('ArialVN', 8)
    c.setFillColor(colors.HexColor('#555555'))
    c.drawString(12*mm, 10*mm, 'Bảng nối dây | 18/10/2026 | In A4 dọc, tỷ lệ 100%')
    c.drawRightString(A4[0]-12*mm, 10*mm, f'Trang {doc.page}')

doc = SimpleDocTemplate(str(OUT), pagesize=A4, leftMargin=12*mm, rightMargin=12*mm, topMargin=12*mm, bottomMargin=18*mm, title='Bảng kiểm tra nối dây Antenna', author='Antenna measurement project')
doc.build(story, onFirstPage=footer, onLaterPages=footer)
pdf = pdfium.PdfDocument(str(OUT))
for i, page in enumerate(pdf):
    page.render(scale=1.3).to_pil().save(str(ROOT / f'tmp/pdfs/wiring-page-{i+1}.png'))
text='\n'.join(p.extract_text() for p in PdfReader(OUT).pages)
assert len(pdf) == 2, f'Unexpected page count: {len(pdf)}'
assert all(s in text for s in ['GPIO25', 'GPIO14', 'GPIO21', 'GPIO19', 'J1 chân 1', 'J4 chân 1', '32'])
print(f'Created: {OUT}\nPages: {len(pdf)}; rows: {len(rows)}; text checks passed')
