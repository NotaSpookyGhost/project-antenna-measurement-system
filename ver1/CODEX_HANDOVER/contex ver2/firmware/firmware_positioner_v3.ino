#include <Arduino.h>
#include <Wire.h>

// =========================================================================
//   PTIT ANTENNA POSITIONER V3.0 — MASTER CLOSED-LOOP FIRMWARE
//   Hệ Thống Điều Khiển Bàn Xoay Đo Bức Xạ Ăng-ten 2 Trục (Pan - Tilt)
//   Động cơ: 2x TMC2209 Standalone (1/8 vi bước, 25.0 bước / 1° góc anten)
//   Cảm biến: 2x AS5600 12-bit Closed-Loop (Dual Hardware I2C Wire0 & Wire1)
// =========================================================================

// --- CHÂN ĐIỀU KHIỂN MOTOR (TMC2209) ---
const int PIN_PAN_STEP = 25;
const int PIN_PAN_DIR  = 26;
const int PIN_PAN_EN   = 27; // Active LOW

const int PIN_TILT_STEP = 32;
const int PIN_TILT_DIR  = 33;
const int PIN_TILT_EN   = 14; // Active LOW

// --- CHÂN CẢM BIẾN AS5600 (DUAL I2C) ---
#define AS5600_ADDR        0x36
#define REG_RAW_ANGLE_H    0x0C
#define REG_AGC            0x1A

TwoWire I2C_Tilt = TwoWire(0);
const int PIN_TILT_SDA = 21;
const int PIN_TILT_SCL = 22;

TwoWire I2C_Pan  = TwoWire(1);
const int PIN_PAN_SDA  = 18;
const int PIN_PAN_SCL  = 19;

// --- HẰNG SỐ ĐỘNG HỌC ---
// Puly 16T:90T (5.625:1) | 1/8 vi bước (1600 xung/vòng) -> 25.0 bước / 1° anten
const float STEPS_PER_DEG = 25.0f;
const unsigned long CRUISE_DELAY_US = 2200; // ~18.18 deg/s
const unsigned long START_DELAY_US  = 4500;
const int RAMP_STEPS = 80;

// Góc anten logic hiện tại
float currentPanDeg = 0.0f;
float currentTiltDeg = 0.0f;

float zeroOffsetPan = 0.0f;
float zeroOffsetTilt = 0.0f;

// Đọc góc AS5600 an toàn với cơ chế tự khôi phục I2C bus
float readSensorDeg(TwoWire &bus, int sda, int scl) {
  for (int attempt = 0; attempt < 3; attempt++) {
    bus.beginTransmission(AS5600_ADDR);
    bus.write(REG_RAW_ANGLE_H);
    byte err = bus.endTransmission(true);
    if (err == 0) {
      if (bus.requestFrom((uint8_t)AS5600_ADDR, (uint8_t)2, (uint8_t)true) >= 2) {
        uint8_t h = bus.read();
        uint8_t l = bus.read();
        int16_t raw = ((h & 0x0F) << 8) | l;
        return (raw * 360.0f) / 4096.0f;
      }
    }
    delay(10);
    bus.begin(sda, scl, 100000);
    delay(10);
  }
  return -1.0f;
}

uint8_t readSensorAGC(TwoWire &bus) {
  bus.beginTransmission(AS5600_ADDR);
  bus.write(REG_AGC);
  if (bus.endTransmission(true) == 0) {
    if (bus.requestFrom((uint8_t)AS5600_ADDR, (uint8_t)1, (uint8_t)true) >= 1) {
      return bus.read();
    }
  }
  return 255;
}

// Báo cáo vị trí ra Serial
void printPosition() {
  float pDeg = readSensorDeg(I2C_Pan, PIN_PAN_SDA, PIN_PAN_SCL);
  float tDeg = readSensorDeg(I2C_Tilt, PIN_TILT_SDA, PIN_TILT_SCL);
  uint8_t pAGC = readSensorAGC(I2C_Pan);
  uint8_t tAGC = readSensorAGC(I2C_Tilt);

  Serial.printf("PAN:%6.2f TILT:%6.2f RAW_PAN:%6.2f (AGC:%3d) RAW_TILT:%6.2f (AGC:%3d)\n",
                currentPanDeg, currentTiltDeg, pDeg, pAGC, tDeg, tAGC);
}

// Điều khiển bước động cơ đồng bộ Bresenham
void stepDualMotors(long stepsPan, long stepsTilt) {
  if (stepsPan == 0 && stepsTilt == 0) return;

  // Bật Driver (Active LOW)
  digitalWrite(PIN_PAN_EN, LOW);
  digitalWrite(PIN_TILT_EN, LOW);
  delay(10);

  digitalWrite(PIN_PAN_DIR, stepsPan >= 0 ? HIGH : LOW);
  digitalWrite(PIN_TILT_DIR, stepsTilt >= 0 ? HIGH : LOW);
  delayMicroseconds(20);

  long absPan = abs(stepsPan);
  long absTilt = abs(stepsTilt);
  long maxSteps = max(absPan, absTilt);

  long accPan = 0;
  long accTilt = 0;

  for (long i = 0; i < maxSteps; i++) {
    unsigned long pulseDelay = CRUISE_DELAY_US;
    if (i < RAMP_STEPS) {
      pulseDelay = START_DELAY_US - (START_DELAY_US - CRUISE_DELAY_US) * i / RAMP_STEPS;
    } else if (i > maxSteps - RAMP_STEPS) {
      pulseDelay = CRUISE_DELAY_US + (START_DELAY_US - CRUISE_DELAY_US) * (i - (maxSteps - RAMP_STEPS)) / RAMP_STEPS;
    }

    bool stepP = false;
    bool stepT = false;

    accPan += absPan;
    if (accPan >= maxSteps) {
      accPan -= maxSteps;
      stepP = true;
    }

    accTilt += absTilt;
    if (accTilt >= maxSteps) {
      accTilt -= maxSteps;
      stepT = true;
    }

    if (stepP) digitalWrite(PIN_PAN_STEP, HIGH);
    if (stepT) digitalWrite(PIN_TILT_STEP, HIGH);
    delayMicroseconds(pulseDelay / 2);

    if (stepP) digitalWrite(PIN_PAN_STEP, LOW);
    if (stepT) digitalWrite(PIN_TILT_STEP, LOW);
    delayMicroseconds(pulseDelay / 2);

    if (i % 200 == 0) yield();
  }

  delay(50);
  // Tắt Enable sau khi quay xong để triệt tiêu nhiễu chopper cho đường I2C
  digitalWrite(PIN_PAN_EN, HIGH);
  digitalWrite(PIN_TILT_EN, HIGH);
  delay(150); // Chờ ổn định đường nguồn

  currentPanDeg += (float)stepsPan / STEPS_PER_DEG;
  currentTiltDeg += (float)stepsTilt / STEPS_PER_DEG;
}

void gotoPosition(float targetPan, float targetTilt) {
  if (targetTilt < -5.0f) targetTilt = -5.0f;
  if (targetTilt > 95.0f) targetTilt = 95.0f;

  float dPan = targetPan - currentPanDeg;
  float dTilt = targetTilt - currentTiltDeg;

  long stepsPan = lround(dPan * STEPS_PER_DEG);
  long stepsTilt = lround(dTilt * STEPS_PER_DEG);

  stepDualMotors(stepsPan, stepsTilt);

  Serial.printf("DONE PAN:%6.2f TILT:%6.2f\n", currentPanDeg, currentTiltDeg);
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  // Cấu hình chân Motor
  pinMode(PIN_PAN_STEP, OUTPUT);
  pinMode(PIN_PAN_DIR,  OUTPUT);
  pinMode(PIN_PAN_EN,   OUTPUT);
  digitalWrite(PIN_PAN_EN, HIGH); // Mặc định tắt driver

  pinMode(PIN_TILT_STEP, OUTPUT);
  pinMode(PIN_TILT_DIR,  OUTPUT);
  pinMode(PIN_TILT_EN,   OUTPUT);
  digitalWrite(PIN_TILT_EN, HIGH); // Mặc định tắt driver

  // Khởi động 2 cổng I2C
  I2C_Tilt.begin(PIN_TILT_SDA, PIN_TILT_SCL, 100000);
  I2C_Pan.begin(PIN_PAN_SDA, PIN_PAN_SCL, 100000);
  delay(300);

  Serial.println("\n==================================================================");
  Serial.println("  HỆ THỐNG 2 TRỤC ĂNG-TEN STANDALONE + CLOSED-LOOP AS5600 (V3.0)");
  Serial.println("  TMC2209 STEALTHCHOP2 (20V) + PULLEY 16:90 (25.0 BƯỚC/ĐỘ)");
  Serial.println("==================================================================");

  zeroOffsetPan = readSensorDeg(I2C_Pan, PIN_PAN_SDA, PIN_PAN_SCL);
  zeroOffsetTilt = readSensorDeg(I2C_Tilt, PIN_TILT_SDA, PIN_TILT_SCL);

  Serial.println(">>> [ZERO] ĐÃ GHIM VỊ TRÍ HIỆN TẠI THÀNH GỐC 0.00°!");
  printPosition();
  Serial.print("ESP32-ANTENNA> ");
}

void loop() {
  if (Serial.available()) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim();
    if (cmd.length() == 0) return;

    if (cmd.equalsIgnoreCase("POS")) {
      printPosition();
    }
    else if (cmd.equalsIgnoreCase("ZERO") || cmd == "0") {
      currentPanDeg = 0.0f;
      currentTiltDeg = 0.0f;
      zeroOffsetPan = readSensorDeg(I2C_Pan, PIN_PAN_SDA, PIN_PAN_SCL);
      zeroOffsetTilt = readSensorDeg(I2C_Tilt, PIN_TILT_SDA, PIN_TILT_SCL);
      Serial.println("ZERO SET OK");
      printPosition();
    }
    else if (cmd.startsWith("GOTO ") || cmd.startsWith("goto ")) {
      float p, t;
      if (sscanf(cmd.c_str() + 5, "%f %f", &p, &t) == 2) {
        gotoPosition(p, t);
      }
    }
    else if (cmd.startsWith("PAN ") || cmd.startsWith("pan ")) {
      float p = cmd.substring(4).toFloat();
      gotoPosition(p, currentTiltDeg);
    }
    else if (cmd.startsWith("TILT ") || cmd.startsWith("tilt ")) {
      float t = cmd.substring(5).toFloat();
      gotoPosition(currentPanDeg, t);
    }
    else if (cmd.startsWith("M1 ") || cmd.startsWith("m1 ")) {
      long s = cmd.substring(3).toInt();
      stepDualMotors(s, 0);
      printPosition();
    }
    else if (cmd.startsWith("M2 ") || cmd.startsWith("m2 ")) {
      long s = cmd.substring(3).toInt();
      stepDualMotors(0, s);
      printPosition();
    }
    else if (cmd.equalsIgnoreCase("SCAN")) {
      Serial.println("=== QUÉT TEST 4 ĐIỂM PROFILING ===");
      gotoPosition(45.0f, 20.0f); delay(1000);
      gotoPosition(90.0f, 45.0f); delay(1000);
      gotoPosition(180.0f, 60.0f); delay(1000);
      gotoPosition(0.0f, 0.0f);
      Serial.println("=== KẾT THÚC QUÉT ===");
    }
    else {
      float p, t;
      if (sscanf(cmd.c_str(), "%f %f", &p, &t) == 2) {
        gotoPosition(p, t);
      } else {
        Serial.println("Lệnh: POS | ZERO | GOTO <p> <t> | PAN <g> | TILT <g> | M1 <s> | M2 <s> | SCAN");
      }
    }
    Serial.print("ESP32-ANTENNA> ");
  }
}
