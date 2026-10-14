#include <Arduino.h>
#include "as5600_sample.h"
#ifdef TILT_PWM_ENABLED
#include "as5600_pwm.h"
#endif
#ifdef ARDUINO_ARCH_ESP32
#include "as5600_bus.h"
using SensorBus = AS5600Bus;
#else
#include <Wire.h> // Native test transport; exercises the same sample validator.
using SensorBus = TwoWire;
#endif

// =========================================================================
//   PTIT ANTENNA POSITIONER V4.0 — PAN/TILT SCANS + CONTINUOUS HOLD
//   Hệ Thống Điều Khiển Bàn Xoay Đo Bức Xạ Ăng-ten 2 Trục (Pan - Tilt)
//   Động cơ: 2x TMC2209 Standalone (1/8 vi bước, 25.0 bước / 1° góc anten)
//   Cảm biến: 2x AS5600 12-bit telemetry (dedicated GPIO I2C buses)
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

SensorBus I2C_Tilt(0);
const int PIN_TILT_SDA = 21;
const int PIN_TILT_SCL = 22;

#ifdef TILT_PWM_ENABLED
const int PIN_TILT_PWM = 23;
const char* FW_VERSION = "V4.1_PWM_HOLD";
AS5600PWMCapture tiltPWMCapture;
bool tiltPWMConfigured = false;
#ifdef ARDUINO_ARCH_ESP32
portMUX_TYPE tiltPWMMux = portMUX_INITIALIZER_UNLOCKED;
void IRAM_ATTR onTiltPWMEdge() {
  uint32_t now=micros();
  bool high=digitalRead(PIN_TILT_PWM)==HIGH;
  portENTER_CRITICAL_ISR(&tiltPWMMux);
  tiltPWMCapture.edge(high,now);
  portEXIT_CRITICAL_ISR(&tiltPWMMux);
}
#endif
AS5600PWMFrame getTiltPWMFrame() {
#ifdef ARDUINO_ARCH_ESP32
  portENTER_CRITICAL(&tiltPWMMux);
#endif
  AS5600PWMFrame frame=tiltPWMCapture.snapshot();
#ifdef ARDUINO_ARCH_ESP32
  portEXIT_CRITICAL(&tiltPWMMux);
#endif
  return frame;
}
float readTiltPWM() {
  if (!tiltPWMConfigured) return -1;
  uint32_t sequence=getTiltPWMFrame().sequence;
  uint32_t started=micros();
  AS5600PWMSamples samples; // only frames arriving AFTER this request count
  while (micros()-started<35000) {
    AS5600PWMFrame frame=getTiltPWMFrame();
    if (frame.sequence!=sequence) {
      if (frame.sequence-sequence!=1) samples.add(0,0,0,0);
      sequence=frame.sequence;
      if (samples.add(frame.periodUs,frame.highUs,frame.stampUs,micros())) return samples.angleDeg();
    }
    delay(1);
  }
  return -1;
}
#else
const char* FW_VERSION = "V4.0_HOLD";
#endif

SensorBus I2C_Pan(1);
const int PIN_PAN_SDA  = 18;
const int PIN_PAN_SCL  = 19;

// --- HẰNG SỐ ĐỘNG HỌC ---
// Puly 16T:90T (5.625:1) | 1/8 vi bước (1600 xung/vòng) -> 25.0 bước / 1° anten
const float STEPS_PER_DEG = 25.0f;
const unsigned long CRUISE_DELAY_US = 2200; // ~18.18 deg/s
const unsigned long START_DELAY_US  = 5000;
const long RAMP_STEPS = 100;

// Góc anten logic hiện tại
float currentPanDeg = 0.0f;
float currentTiltDeg = 0.0f;

const unsigned long HOLD_LEASE_MS = 30000UL;
bool holdRequested = false;
bool calibrationRequired = true;
unsigned long lastHostActivityMs = 0;
float cachedPanSensorDeg = -1.0f;
float cachedTiltSensorDeg = -1.0f;
uint8_t cachedPanAGC = 255;
uint8_t cachedTiltAGC = 255;
bool driversEnabled = false;
unsigned long releaseCount = 0;

void setDriversEnabled(bool enabled) {
  if (driversEnabled && !enabled) releaseCount++;
  driversEnabled = enabled;
  digitalWrite(PIN_PAN_EN, enabled ? LOW : HIGH);
  digitalWrite(PIN_TILT_EN, enabled ? LOW : HIGH);
}

// Bounded reads, never release the motors or reuse an old angle on I2C failure.
bool readSensorRegisters(SensorBus &bus, uint8_t reg, uint8_t* data, int count) {
#ifdef ARDUINO_ARCH_ESP32
  return bus.readRegisters(reg, data, count);
#else
  bus.beginTransmission(AS5600_ADDR);
  bus.write(reg);
  if (bus.endTransmission(true) == 0) {
    if (bus.requestFrom((uint8_t)AS5600_ADDR, (uint8_t)count, (uint8_t)true) == count) {
      for (int i=0; i<count; ++i) data[i] = bus.read();
      return true;
    }
  }
  return false;
#endif
}

#ifdef TILT_PWM_ENABLED
struct TiltConfigRegisters {
  bool readRegisters(uint8_t reg,uint8_t* data,int count) {
    return readSensorRegisters(I2C_Tilt,reg,data,count);
  }
  bool writeRegisters(uint8_t reg,const uint8_t* data,int count) {
    if (!((reg==7 && count==2) || (reg==1 && count==6))) return false;
#ifdef ARDUINO_ARCH_ESP32
    return I2C_Tilt.writeRegisters(reg,data,count);
#else
    I2C_Tilt.beginTransmission(AS5600_ADDR); I2C_Tilt.write(reg);
    for(int i=0;i<count;++i) I2C_Tilt.write(data[i]);
    return I2C_Tilt.endTransmission(true)==0;
#endif
  }
};
void configureTiltPWM() {
  tiltPWMConfigured=false;
  TiltConfigRegisters registers;
  AS5600PWMConfigResult result=configureAS5600PWM(registers);
  if (result==AS5600PWMConfigResult::Ok) {
    tiltPWMConfigured=true;
    calibrationRequired=true;
    Serial.println("TILT PWM CONFIG OK TEMPORARY 230HZ; SENSOR POWER CYCLE REQUIRES CONFIG");
  } else {
    const char* reason=result==AS5600PWMConfigResult::ReadFailed ? "I2C_READ" :
      result==AS5600PWMConfigResult::WriteFailed ? "I2C_WRITE" : "READBACK";
    Serial.printf("ERR: TILT_PWM_CONFIG_%s; USE SHORT CONFIGURATION WIRES\n",reason);
  }
}
void printTiltPWMRegisters() {
  uint8_t data[8]={0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff};
  bool ok=readSensorRegisters(I2C_Tilt,1,data,8);
  uint8_t conf[2]={0xff,0xff};
  bool confOk=readSensorRegisters(I2C_Tilt,7,conf,2);
  Serial.printf("PWM_REG READ_OK:%d ZPOS:%02X%02X MPOS:%02X%02X MANG:%02X%02X CONF:%02X%02X SINGLE_OK:%d SINGLE_CONF:%02X%02X\n",
    ok,data[0],data[1],data[2],data[3],data[4],data[5],data[6],data[7],confOk,conf[0],conf[1]);
}
#endif

float readSensorDeg(SensorBus &bus) {
  AS5600Samples samples;
  for (int attempt=0; attempt<16; ++attempt) {
    uint8_t data[3] = {0xff, 0xff, 0xff};
    bool transferred = readSensorRegisters(bus, 0x0b, data, 3);
    if (samples.add(transferred, data[0], data[1], data[2])) return samples.angleDeg();
    delayMicroseconds(200);
  }
  return -1.0f;
}

uint8_t readSensorAGC(SensorBus &bus) {
  uint8_t value = 255;
  return readSensorRegisters(bus, REG_AGC, &value, 1) ? value : 255;
}

struct SensorSnapshot {
  uint32_t requestId;
  float pan = -1;
  float tilt = -1;
  uint8_t panAGC = 255;
  uint8_t tiltAGC = 255;
};

SensorSnapshot readSensors(uint32_t requestId) {
  SensorSnapshot result;
  result.requestId = requestId;
  result.pan = readSensorDeg(I2C_Pan);
#ifdef TILT_PWM_ENABLED
  result.tilt = readTiltPWM();
#else
  result.tilt = readSensorDeg(I2C_Tilt);
#endif
  result.panAGC = result.pan >= 0 ? readSensorAGC(I2C_Pan) : 255;
#ifndef TILT_PWM_ENABLED
  result.tiltAGC = result.tilt >= 0 ? readSensorAGC(I2C_Tilt) : 255;
#endif
  return result;
}

void refreshSensors() {
  // GPIO reads have fixed retry limits and no driver waits. Read on the command
  // core, after motion has finished; there can be no late snapshot during motion.
  const SensorSnapshot result = readSensors(0);
  cachedPanSensorDeg = result.pan;
  cachedTiltSensorDeg = result.tilt;
  cachedPanAGC = result.panAGC;
  cachedTiltAGC = result.tiltAGC;
}

void printPosition() {
  refreshSensors();
  Serial.printf("PAN:%6.2f TILT:%6.2f RAW_PAN:%6.2f (AGC:%3d) RAW_TILT:%6.2f (AGC:%3d) HOLD_CAP:1 HOLD:%d CAL_REQUIRED:%d SENSOR_CACHED:0 ENC_PAN_VALID:%d ENC_TILT_VALID:%d RELEASES:%lu FW:%s SCAN3D_CAP:1 PAN_MIN:-360 PAN_MAX:360 TILT_MIN:-180 TILT_MAX:180\n",
                currentPanDeg, currentTiltDeg, cachedPanSensorDeg, cachedPanAGC,
                cachedTiltSensorDeg, cachedTiltAGC, holdRequested,
                calibrationRequired, cachedPanSensorDeg >= 0, cachedTiltSensorDeg >= 0, releaseCount,FW_VERSION);
#ifdef TILT_PWM_ENABLED
  AS5600PWMFrame frame=getTiltPWMFrame();
  Serial.printf("ENC_TILT_SOURCE:PWM AGC_TILT_AVAILABLE:0 PWM_CONFIG:%d PWM_PIN:%d PWM_PERIOD_US:%lu PWM_AGE_US:%lu\n",
                tiltPWMConfigured,PIN_TILT_PWM,(unsigned long)frame.periodUs,
                (unsigned long)(frame.sequence ? micros()-frame.stampUs : 0xffffffffU));
#endif
}

// Accumulate complete lines without Stream's blocking timeout in the pulse loop.
char motionLine[64];
size_t motionLineLength = 0;
bool motionLineOverflow = false;
bool pollMotionStop() {
  while (Serial.available()) {
    char c = static_cast<char>(Serial.read());
    if (c == '\n') {
      motionLine[motionLineLength] = '\0';
      String cmd(motionLine);
      cmd.trim();
      cmd.toUpperCase();
      const bool valid = !motionLineOverflow;
      motionLineLength = 0;
      motionLineOverflow = false;
      if (valid && cmd == "STOP") return true;
      if (valid && (cmd == "PING" || cmd == "KEEPALIVE")) lastHostActivityMs = millis();
      // Other commands cannot alter motion; host sends one transaction at a time.
    } else if (motionLineLength < sizeof(motionLine) - 1) {
      motionLine[motionLineLength++] = c;
    } else {
      motionLineOverflow = true;
    }
  }
  if (holdRequested && millis() - lastHostActivityMs >= HOLD_LEASE_MS) {
    setDriversEnabled(false);
    holdRequested = false;
    return true;
  }
  return false;
}

// Điều khiển bước động cơ đồng bộ Bresenham
bool stepDualMotors(long stepsPan, long stepsTilt) {
  if (pollMotionStop()) { calibrationRequired = true; return false; }
  if (stepsPan == 0 && stepsTilt == 0) return true;

  // Bật Driver (Active LOW)
  setDriversEnabled(true);
  delay(10);

  digitalWrite(PIN_PAN_DIR, stepsPan >= 0 ? HIGH : LOW);
  digitalWrite(PIN_TILT_DIR, stepsTilt >= 0 ? HIGH : LOW);
  delayMicroseconds(20);

  long absPan = abs(stepsPan);
  long absTilt = abs(stepsTilt);
  long maxSteps = max(absPan, absTilt);

  long accPan = 0;
  long accTilt = 0;
  long completedPan = 0;
  long completedTilt = 0;
  bool interrupted = false;
  const long ramp = min(maxSteps / 4, RAMP_STEPS);
  unsigned long nextStepTime = micros();

  for (long i = 0; i < maxSteps; i++) {
    if (pollMotionStop()) { interrupted = true; break; }
    unsigned long pulseDelay = CRUISE_DELAY_US;
    if (ramp > 0 && i < ramp) {
      pulseDelay = START_DELAY_US - (START_DELAY_US - CRUISE_DELAY_US) * i / ramp;
    } else if (ramp > 0 && i > maxSteps - ramp) {
      pulseDelay = START_DELAY_US - (START_DELAY_US - CRUISE_DELAY_US) * (maxSteps - i) / ramp;
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
    delayMicroseconds(6);

    if (stepP) digitalWrite(PIN_PAN_STEP, LOW);
    if (stepT) digitalWrite(PIN_TILT_STEP, LOW);
    if (stepP) completedPan++;
    if (stepT) completedTilt++;
    nextStepTime += pulseDelay;
    while (static_cast<int32_t>(micros() - nextStepTime) < 0) {
      if (pollMotionStop()) { interrupted = true; break; }
    }
    if (interrupted) break;
  }

  // EN stays LOW through settle, POS reads, STOP, and the next movement.
  delay(100);

  currentPanDeg += (stepsPan >= 0 ? 1.0f : -1.0f) * completedPan / STEPS_PER_DEG;
  currentTiltDeg += (stepsTilt >= 0 ? 1.0f : -1.0f) * completedTilt / STEPS_PER_DEG;
  if (interrupted) calibrationRequired = true;
  return !interrupted;
}

bool gotoPosition(float targetPan, float targetTilt) {
  if (!isfinite(targetPan) || !isfinite(targetTilt) || abs(targetPan) > 360.0f || abs(targetTilt) > 180.0f) {
    Serial.println("ERR: ANGLE_RANGE; PAN -360..360 TILT -180..180");
    return false;
  }

  float dPan = targetPan - currentPanDeg;
  float dTilt = targetTilt - currentTiltDeg;

  long stepsPan = lround(dPan * STEPS_PER_DEG);
  long stepsTilt = lround(dTilt * STEPS_PER_DEG);

  bool completed = stepDualMotors(stepsPan, stepsTilt);

  Serial.printf("%s PAN:%6.2f TILT:%6.2f\n", completed ? "DONE" : "ABORTED", currentPanDeg, currentTiltDeg);
  return completed;
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
  I2C_Tilt.setTimeOut(25);
  I2C_Pan.setTimeOut(25);

#ifdef TILT_PWM_ENABLED
#ifdef ARDUINO_ARCH_ESP32
  pinMode(PIN_TILT_PWM,INPUT); // high impedance even while OUT is still analog
  attachInterrupt(digitalPinToInterrupt(PIN_TILT_PWM),onTiltPWMEdge,CHANGE);
#endif
  configureTiltPWM(); // drivers are still released; temporary CONF only
#endif

  delay(300);

  Serial.println("\n==================================================================");
  Serial.println("  POSITIONER V4.0: PAN/TILT SCANS + VALIDATED AS5600 TELEMETRY");
  Serial.println("  TMC2209 STEALTHCHOP2 (20V) + PULLEY 16:90 (25.0 BƯỚC/ĐỘ)");
  Serial.println("==================================================================");

  Serial.println(">>> CAL REQUIRED: align both axes and use LOCK ZERO.");
  printPosition();
  Serial.print("ESP32-ANTENNA> ");
}

void loop() {
  if (holdRequested && millis() - lastHostActivityMs >= HOLD_LEASE_MS) {
    setDriversEnabled(false);
    holdRequested = false;
    calibrationRequired = true;
    Serial.println("WARN: HOLD LEASE EXPIRED; MOTORS RELEASED; CAL REQUIRED");
  }

  if (!Serial.available()) return;
  // Discard an unfinished non-command fragment left by a moving client.
  motionLineLength = 0;
  motionLineOverflow = false;
  String cmd = Serial.readStringUntil('\n');
  cmd.trim();
  if (cmd.length() == 0) return;
  cmd.toUpperCase();
  if (holdRequested) lastHostActivityMs = millis();
  if (cmd == "KEEPALIVE") return; // No reply: safe inside an in-flight command.

  if (cmd == "PING") {
    Serial.println(holdRequested ? "PONG" : "ERR: HOLD_NOT_ACTIVE");
  }
  else if (cmd == "HOLD ON") {
    setDriversEnabled(true);
    holdRequested = true;
    Serial.printf("HOLD ON OK CAL_REQUIRED:%d\n", calibrationRequired);
  }
  else if (cmd == "HOLD OFF" || cmd == "CAL RELEASE") {
    setDriversEnabled(false);
    holdRequested = false;
    calibrationRequired = true;
    Serial.println(cmd == "HOLD OFF" ? "HOLD OFF OK" : "CAL RELEASE OK");
  }
  else if (cmd == "LOCK ZERO") {
      setDriversEnabled(true);
      holdRequested = true;
      delay(100);
      currentPanDeg = 0.0f;
      currentTiltDeg = 0.0f;
      calibrationRequired = false;
      Serial.println("LOCK ZERO OK");
      printPosition();
  }
  else if (cmd == "STOP") {
    Serial.println("STOP OK");
  }
  else if (cmd == "POS") {
    printPosition();
  }
#ifdef TILT_PWM_ENABLED
  else if (cmd == "TILT PWM CONFIG") {
    if (driversEnabled) Serial.println("ERR: RELEASE_FIRST; USE HOLD OFF");
    else configureTiltPWM();
  }
  else if (cmd == "TILT PWM CHECK") {
    printPosition();
  }
  else if (cmd == "TILT PWM REG") {
    printTiltPWMRegisters(); // read-only diagnosis; never changes CONF/OTP
  }
#endif
  else if (cmd == "ZERO" || cmd == "0") {
    if (calibrationRequired) {
      Serial.println("ERR: CAL_REQUIRED; USE LOCK ZERO");
    } else {
      currentPanDeg = 0.0f;
      currentTiltDeg = 0.0f;
      Serial.println("ZERO SET OK");
      printPosition();
    }
  }
  else if (calibrationRequired) {
    Serial.println("ERR: CAL_REQUIRED; USE LOCK ZERO");
  }
  else if (cmd.startsWith("GOTO ")) {
    float p, t;
    if (sscanf(cmd.c_str() + 5, "%f %f", &p, &t) == 2) {
      gotoPosition(p, t);
    } else {
      Serial.println("ERR: INVALID_GOTO");
    }
  }
  else if (cmd.startsWith("PAN ")) {
    gotoPosition(cmd.substring(4).toFloat(), currentTiltDeg);
  }
  else if (cmd.startsWith("TILT ")) {
    gotoPosition(currentPanDeg, cmd.substring(5).toFloat());
  }
  else if (cmd.startsWith("M1 ")) {
    stepDualMotors(cmd.substring(3).toInt(), 0);
    printPosition();
  }
  else if (cmd.startsWith("M2 ")) {
    stepDualMotors(0, cmd.substring(3).toInt());
    printPosition();
  }
  else if (cmd == "SCAN") {
    Serial.println("=== QUÉT TEST 4 ĐIỂM PROFILING ===");
    if (gotoPosition(45.0f, 20.0f)) { delay(1000);
      if (gotoPosition(90.0f, 45.0f)) { delay(1000);
        if (gotoPosition(180.0f, 60.0f)) { delay(1000);
          gotoPosition(0.0f, 0.0f);
        }
      }
    }
    Serial.println("=== KẾT THÚC QUÉT ===");
  }
  else {
    float p, t;
    if (sscanf(cmd.c_str(), "%f %f", &p, &t) == 2) {
      gotoPosition(p, t);
    } else {
      Serial.println("Lệnh: POS | HOLD ON/OFF | CAL RELEASE | LOCK ZERO | PING | ZERO | GOTO/PAN/TILT");
    }
  }
  if (holdRequested) lastHostActivityMs = millis();
  Serial.print("ESP32-ANTENNA> ");
}
