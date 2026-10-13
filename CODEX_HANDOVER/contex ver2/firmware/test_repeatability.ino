#include <Arduino.h>
#include <Wire.h>

// BÀI TEST ĐỘ TIN CẬY 100% CLOSED-LOOP (CÓ TỰ KHÔI PHỤC BUS I2C VÀ RETRY)

const int PIN_PAN_STEP = 25;
const int PIN_PAN_DIR  = 26;
const int PIN_PAN_EN   = 27;

const int PIN_TILT_STEP = 32;
const int PIN_TILT_DIR  = 33;
const int PIN_TILT_EN   = 14;

TwoWire I2C_Tilt = TwoWire(0);
const int PIN_TILT_SDA = 21;
const int PIN_TILT_SCL = 22;

TwoWire I2C_Pan  = TwoWire(1);
const int PIN_PAN_SDA  = 18;
const int PIN_PAN_SCL  = 19;

#define AS5600_ADDR 0x36

// Đọc góc an toàn có retry và tự reset bus nếu lỗi
float readDegSafe(TwoWire &bus, int sda, int scl) {
  for (int attempt = 0; attempt < 3; attempt++) {
    bus.beginTransmission(AS5600_ADDR);
    bus.write(0x0C);
    byte err = bus.endTransmission(true);
    if (err == 0) {
      if (bus.requestFrom((uint8_t)AS5600_ADDR, (uint8_t)2, (uint8_t)true) >= 2) {
        uint8_t h = bus.read();
        uint8_t l = bus.read();
        int16_t raw = ((h & 0x0F) << 8) | l;
        return (raw * 360.0f) / 4096.0f;
      }
    }
    // Nếu lỗi, thử reset lại bus I2C
    delay(10);
    bus.begin(sda, scl, 100000);
    delay(10);
  }
  return -1.0f;
}

void stepSafe(int stepPin, int dirPin, int enPin, long steps) {
  digitalWrite(enPin, LOW);
  delay(10);
  digitalWrite(dirPin, steps >= 0 ? HIGH : LOW);
  delayMicroseconds(20);

  long n = abs(steps);
  for (long i = 0; i < n; i++) {
    digitalWrite(stepPin, HIGH);
    delayMicroseconds(1600);
    digitalWrite(stepPin, LOW);
    delayMicroseconds(1600);
    if (i % 100 == 0) yield();
  }
  delay(50);
  digitalWrite(enPin, HIGH); // Tắt giữ nhiệt & dập nhiễu
  delay(150);
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("\n========================================================");
  Serial.println("  TEST ĐỘ CHÍNH XÁC & LẶP LẠI (REPEATABILITY) PAN & TILT ");
  Serial.println("========================================================");

  I2C_Tilt.begin(PIN_TILT_SDA, PIN_TILT_SCL, 100000);
  I2C_Pan.begin(PIN_PAN_SDA, PIN_PAN_SCL, 100000);

  pinMode(PIN_PAN_STEP, OUTPUT);
  pinMode(PIN_PAN_DIR,  OUTPUT);
  pinMode(PIN_PAN_EN,   OUTPUT);
  digitalWrite(PIN_PAN_EN, HIGH);

  pinMode(PIN_TILT_STEP, OUTPUT);
  pinMode(PIN_TILT_DIR,  OUTPUT);
  pinMode(PIN_TILT_EN,   OUTPUT);
  digitalWrite(PIN_TILT_EN, HIGH);

  delay(200);

  float p0 = readDegSafe(I2C_Pan, PIN_PAN_SDA, PIN_PAN_SCL);
  float t0 = readDegSafe(I2C_Tilt, PIN_TILT_SDA, PIN_TILT_SCL);
  Serial.printf("Gốc ban đầu: Pan = %6.2f° | Tilt = %6.2f°\n\n", p0, t0);

  // Chu kỳ 1: Quay Pan +250 bước rồi về -250 bước
  Serial.println("--- [TEST 1: CHU KỲ PAN 250 BƯỚC (+10° anten)] ---");
  stepSafe(PIN_PAN_STEP, PIN_PAN_DIR, PIN_PAN_EN, 250);
  float p1 = readDegSafe(I2C_Pan, PIN_PAN_SDA, PIN_PAN_SCL);
  Serial.printf("  Sau khi quay +250 bước: Pan = %6.2f° (Delta = %+6.2f°)\n", p1, p1 - p0);

  stepSafe(PIN_PAN_STEP, PIN_PAN_DIR, PIN_PAN_EN, -250);
  float p2 = readDegSafe(I2C_Pan, PIN_PAN_SDA, PIN_PAN_SCL);
  Serial.printf("  Sau khi trả  -250 bước: Pan = %6.2f° (Sai số lặp: %+6.2f°)\n\n", p2, p2 - p0);

  // Chu kỳ 2: Quay Tilt +250 bước rồi về -250 bước
  Serial.println("--- [TEST 2: CHU KỲ TILT 250 BƯỚC (+10° anten)] ---");
  stepSafe(PIN_TILT_STEP, PIN_TILT_DIR, PIN_TILT_EN, 250);
  float t1 = readDegSafe(I2C_Tilt, PIN_TILT_SDA, PIN_TILT_SCL);
  Serial.printf("  Sau khi quay +250 bước: Tilt = %6.2f° (Delta = %+6.2f°)\n", t1, t1 - t0);

  stepSafe(PIN_TILT_STEP, PIN_TILT_DIR, PIN_TILT_EN, -250);
  float t2 = readDegSafe(I2C_Tilt, PIN_TILT_SDA, PIN_TILT_SCL);
  Serial.printf("  Sau khi trả  -250 bước: Tilt = %6.2f° (Sai số lặp: %+6.2f°)\n\n", t2, t2 - t0);

  Serial.println("========================================================");
  Serial.println("                    KẾT QUẢ TỔNG HỢP                    ");
  Serial.println("========================================================");
}

void loop() {
  delay(1000);
}
