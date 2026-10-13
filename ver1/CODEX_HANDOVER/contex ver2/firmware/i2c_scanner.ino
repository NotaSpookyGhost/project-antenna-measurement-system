#include <Wire.h>

// I2C Scanner - quet ca 2 bus tim thiet bi con song
// Bus Tilt: SDA=21, SCL=22 (Jack J3)
// Bus Pan:  SDA=18, SCL=19 (Jack J4)

TwoWire I2C_Tilt = TwoWire(0);
TwoWire I2C_Pan  = TwoWire(1);

void scanBus(TwoWire &bus, const char* name) {
  Serial.print("\n=== QUET BUS: ");
  Serial.print(name);
  Serial.println(" ===");

  int found = 0;
  for (uint8_t addr = 1; addr < 127; addr++) {
    bus.beginTransmission(addr);
    byte err = bus.endTransmission();
    if (err == 0) {
      Serial.print("  [TIM THAY] Thiet bi tai 0x");
      if (addr < 16) Serial.print("0");
      Serial.println(addr, HEX);
      found++;
    }
  }

  if (found == 0) {
    Serial.println("  [KHONG CO THIET BI NAO] - I2C bus im lang hoan toan");
    Serial.println("  -> AS5600 bi chay / mat GND / day SDA-SCL dut?");
  } else {
    Serial.print("  Tong: ");
    Serial.print(found);
    Serial.println(" thiet bi tim thay.");
    if (found > 0) {
      // Kiem tra cu the AS5600
      bus.beginTransmission(0x36);
      byte e = bus.endTransmission();
      if (e == 0) {
        Serial.println("  -> AS5600 o 0x36: CON SONG!");
      } else {
        Serial.println("  -> AS5600 (0x36): KHONG PHAN HOI - co the bi chay");
      }
    }
  }
}

void setup() {
  Serial.begin(115200);
  delay(1500);

  Serial.println("\n========================================");
  Serial.println(" I2C BUS SCANNER - PTIT POSITIONER v1  ");
  Serial.println(" Bus 0 (Tilt): SDA=21, SCL=22 - J3     ");
  Serial.println(" Bus 1 (Pan):  SDA=18, SCL=19 - J4     ");
  Serial.println(" AS5600 addr: 0x36                      ");
  Serial.println("========================================");

  I2C_Tilt.begin(21, 22, 100000);
  I2C_Pan.begin(18, 19, 100000);
  delay(500);

  scanBus(I2C_Tilt, "TILT SDA=21 SCL=22 (Jack J3)");
  scanBus(I2C_Pan,  "PAN  SDA=18 SCL=19 (Jack J4)");

  Serial.println("\n========================================");
  Serial.println(" XONG. Quet lai moi 8 giay...           ");
  Serial.println("========================================");
}

void loop() {
  delay(8000);
  Serial.println("\n--- QUET LAI (8s interval) ---");
  scanBus(I2C_Tilt, "TILT");
  scanBus(I2C_Pan,  "PAN");
}
