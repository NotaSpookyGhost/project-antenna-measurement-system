#include <Arduino.h>
#include <Wire.h>

// ╔════════════════════════════════════════════════════════════════════════╗
// ║      CHƯƠNG TRÌNH TEST & CHẨN ĐOÁN SỐNG / CHẾT CẢM BIẾN AS5600        ║
// ║      Chạy trực tiếp qua thư viện Wire (Không phụ thuộc thư viện ngoài) ║
// ╚════════════════════════════════════════════════════════════════════════╝

#define AS5600_ADDR        0x36
#define REG_STATUS         0x0B
#define REG_RAW_ANGLE_H    0x0C
#define REG_RAW_ANGLE_L    0x0D
#define REG_AGC            0x1A

// Cổng 1: Jack J3 (Trục Tilt) -> SDA=21, SCL=22
TwoWire I2C_Tilt = TwoWire(0);
const int PIN_TILT_SDA = 21;
const int PIN_TILT_SCL = 22;

// Cổng 2: Jack J4 (Trục Pan)  -> SDA=18, SCL=19
TwoWire I2C_Pan = TwoWire(1);
const int PIN_PAN_SDA  = 18;
const int PIN_PAN_SCL  = 19;

bool tilt_alive = false;
bool pan_alive  = false;

// Đọc 1 byte thanh ghi
uint8_t readRegister8(TwoWire &bus, uint8_t reg) {
  bus.beginTransmission(AS5600_ADDR);
  bus.write(reg);
  if (bus.endTransmission(false) != 0) return 0xFF; // Lỗi
  bus.requestFrom((uint8_t)AS5600_ADDR, (uint8_t)1);
  if (bus.available()) return bus.read();
  return 0xFF;
}

// Đọc góc 12-bit (0 - 4095)
int16_t readRawAngle(TwoWire &bus) {
  bus.beginTransmission(AS5600_ADDR);
  bus.write(REG_RAW_ANGLE_H);
  if (bus.endTransmission(false) != 0) return -1;
  bus.requestFrom((uint8_t)AS5600_ADDR, (uint8_t)2);
  if (bus.available() >= 2) {
    uint8_t h = bus.read();
    uint8_t l = bus.read();
    return ((h & 0x0F) << 8) | l;
  }
  return -1;
}

// Kiểm tra toàn diện cảm biến trên 1 bus
bool checkSensor(TwoWire &bus, const char* name, int sda, int scl) {
  Serial.println();
  Serial.print("--- KIỂM TRA "); Serial.print(name); 
  Serial.print(" (SDA="); Serial.print(sda); 
  Serial.print(", SCL="); Serial.print(scl); Serial.println(") ---");

  // 1. Kiểm tra kết nối I2C ACK
  bus.beginTransmission(AS5600_ADDR);
  byte error = bus.endTransmission();

  if (error != 0) {
    Serial.println("❌ [KẾT QUẢ: CHẾT hoặc MẤT KẾT NỐI]");
    Serial.println("   -> Không nhận diện được địa chỉ 0x36 trên đường I2C!");
    Serial.println("   -> Nguyên nhân: Cảm biến bị cháy / Chập 3.3V / Đứt dây SDA-SCL.");
    return false;
  }

  Serial.println("✅ [I2C OK]: Đã bắt tay thành công với AS5600 (Địa chỉ 0x36)!");

  // 2. Đọc thanh ghi STATUS (0x0B)
  uint8_t status = readRegister8(bus, REG_STATUS);
  bool md = (status & 0x20) != 0; // Magnet Detected
  bool ml = (status & 0x10) != 0; // Magnet too Low (quá xa)
  bool mh = (status & 0x08) != 0; // Magnet too High (quá gần)

  Serial.print("   - Trạng thái nam châm: ");
  if (md) {
    Serial.print("ĐÃ PHÁT HIỆN NAM CHÂM");
    if (mh) Serial.print(" (CẢNH BÁO: Quá gần chip!)");
    else if (ml) Serial.print(" (CẢNH BÁO: Quá xa chip!)");
    else Serial.print(" (Khoảng cách HOÀN HẢO)");
  } else {
    Serial.print("CHƯA BẮT ĐƯỢC NAM CHÂM (Đưa nam châm lại gần cảm biến)");
  }
  Serial.println();

  // 3. Đọc thanh ghi AGC (0x1A) - Cường độ từ trường
  uint8_t agc = readRegister8(bus, REG_AGC);
  Serial.print("   - Giá trị AGC (Khuếch đại): "); Serial.print(agc);
  Serial.println(" / 255 (Lý tưởng từ 60 đến 180)");

  // 4. Đọc góc ban đầu
  int16_t raw = readRawAngle(bus);
  if (raw >= 0) {
    float deg = (raw * 360.0f) / 4096.0f;
    Serial.print("   - Góc đọc được ban đầu: "); Serial.print(deg, 2); Serial.println("°");
    Serial.println("🎉 [KẾT LUẬN]: CẢM BIẾN SỐNG TỐT 100%!");
    return true;
  } else {
    Serial.println("⚠️ Lỗi đọc thanh ghi góc!");
    return false;
  }
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("\n========================================================");
  Serial.println("     BẮT ĐẦU CHẨN ĐOÁN SỐNG / CHẾT CẢM BIẾN AS5600      ");
  Serial.println("========================================================");

  // Khởi động 2 cổng I2C
  I2C_Tilt.begin(PIN_TILT_SDA, PIN_TILT_SCL, 100000);
  I2C_Pan.begin(PIN_PAN_SDA, PIN_PAN_SCL, 100000);

  // Kiểm tra lần lượt
  tilt_alive = checkSensor(I2C_Tilt, "CẢM BIẾN TILT (Jack J3)", PIN_TILT_SDA, PIN_TILT_SCL);
  pan_alive  = checkSensor(I2C_Pan,  "CẢM BIẾN PAN  (Jack J4)", PIN_PAN_SDA,  PIN_PAN_SCL);

  Serial.println("\n========================================================");
  Serial.println(" ĐANG ĐỌC GÓC THỜI GIAN THỰC (Xoay thử nam châm bằng tay)...");
  Serial.println("========================================================");
}

void loop() {
  static unsigned long lastPrint = 0;
  if (millis() - lastPrint >= 300) { // Cập nhật mỗi 300ms
    lastPrint = millis();

    Serial.print(">> ");
    
    // Đọc Tilt
    if (tilt_alive) {
      int16_t rawTilt = readRawAngle(I2C_Tilt);
      if (rawTilt >= 0) {
        float degTilt = (rawTilt * 360.0f) / 4096.0f;
        Serial.print("[TILT: "); Serial.print(degTilt, 1); Serial.print("°]  ");
      } else {
        Serial.print("[TILT: LỖI ĐỌC]  ");
      }
    } else {
      Serial.print("[TILT: MẤT KẾT NỐI]  ");
    }

    // Đọc Pan
    if (pan_alive) {
      int16_t rawPan = readRawAngle(I2C_Pan);
      if (rawPan >= 0) {
        float degPan = (rawPan * 360.0f) / 4096.0f;
        Serial.print("[PAN: "); Serial.print(degPan, 1); Serial.print("°]");
      } else {
        Serial.print("[PAN: LỖI ĐỌC]");
      }
    } else {
      Serial.print("[PAN: MẤT KẾT NỐI]");
    }

    Serial.println();
  }
}
