#include <Arduino.h>
#include <Wire.h>

// CHẨN ĐOÁN GỐC RỄ: TẠI SAO BẬT MOTOR THÌ I2C BỊ LỖI?

const int PIN_PAN_EN   = 27;
const int PIN_TILT_EN  = 14;

TwoWire I2C_Tilt = TwoWire(0);
TwoWire I2C_Pan  = TwoWire(1);

#define AS5600_ADDR 0x36

int16_t readRaw(TwoWire &bus) {
  bus.beginTransmission(AS5600_ADDR);
  bus.write(0x0C);
  if (bus.endTransmission(true) != 0) return -1;
  if (bus.requestFrom((uint8_t)AS5600_ADDR, (uint8_t)2, (uint8_t)true) >= 2) {
    uint8_t h = bus.read();
    uint8_t l = bus.read();
    return ((h & 0x0F) << 8) | l;
  }
  return -2;
}

void printBoth(const char* label) {
  int16_t t = readRaw(I2C_Tilt);
  int16_t p = readRaw(I2C_Pan);
  Serial.printf("%-30s | Tilt: %s (%4d) | Pan: %s (%4d)\n",
    label,
    t >= 0 ? "OK " : "ERR", t,
    p >= 0 ? "OK " : "ERR", p);
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("\n=== THÍ NGHIỆM TÁCH BẠCH NGUYÊN NHÂN LỖI I2C ===");

  I2C_Tilt.begin(21, 22, 100000);
  I2C_Pan.begin(18, 19, 100000);
  delay(200);

  // Bước 0: Chưa cấu hình bất kỳ chân motor nào
  printBoth("0. Chưa chạm chân Motor");

  // Bước 1: Chỉ pinMode EN Pan
  pinMode(PIN_PAN_EN, OUTPUT);
  digitalWrite(PIN_PAN_EN, HIGH); // Tắt
  delay(100);
  printBoth("1. EN Pan = HIGH (Tắt)");

  digitalWrite(PIN_PAN_EN, LOW);  // Bật
  delay(100);
  printBoth("2. EN Pan = LOW  (Bật)");

  digitalWrite(PIN_PAN_EN, HIGH); // Tắt lại
  delay(100);

  // Bước 2: Chỉ pinMode EN Tilt
  pinMode(PIN_TILT_EN, OUTPUT);
  digitalWrite(PIN_TILT_EN, HIGH); // Tắt
  delay(100);
  printBoth("3. EN Tilt = HIGH (Tắt)");

  digitalWrite(PIN_TILT_EN, LOW);  // Bật
  delay(100);
  printBoth("4. EN Tilt = LOW  (Bật)");

  digitalWrite(PIN_TILT_EN, HIGH); // Tắt lại
  delay(100);
  printBoth("5. EN Tilt = HIGH (Tắt lại)");

  Serial.println("================================================");
}

void loop() {
  delay(2000);
}
