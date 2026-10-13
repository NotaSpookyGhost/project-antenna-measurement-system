#include <Arduino.h>
#include <Wire.h>
#include <cmath>
#include <cstdio>

// Pin map and mechanics: CODEX_HANDOVER/AGENTS.md, sections 1 and 4.
constexpr uint8_t kAs5600Address = 0x36;
constexpr uint8_t kStatusRegister = 0x0B;
constexpr uint8_t kRawAngleRegister = 0x0C;
constexpr float kStepsPerAntennaDegree = 25.0f;
constexpr float kMotorDegreesPerAntennaDegree = 90.0f / 16.0f;
constexpr uint32_t kStepPeriodUs = 2200;
constexpr uint16_t kMaxChunkSteps = 125;  // 5 antenna degrees; check encoder between chunks.
constexpr uint32_t kI2cClockHz = 100000;

TwoWire panBus(1);
TwoWire tiltBus(0);

struct Axis {
  const char* name;
  uint8_t stepPin;
  uint8_t dirPin;
  uint8_t enablePin;
  TwoWire* bus;
  float positionDeg;
  float minDeg;
  float maxDeg;
  bool homed;
  float measuredMotorDeg;
  int lastRaw;
};

Axis pan = {"PAN", 25, 26, 27, &panBus, 0.0f, 0.0f, 360.0f, false, 0.0f, 0};
Axis tilt = {"TILT", 32, 33, 14, &tiltBus, 0.0f, 0.0f, 360.0f, false, 0.0f, 0};
bool diagnosticTiltHold = false;
uint32_t diagnosticTiltHoldUntil = 0;
bool diagnosticPanHold = false;
uint32_t diagnosticPanHoldUntil = 0;

bool readRegister(TwoWire& bus, uint8_t address, uint8_t* value) {
  bus.beginTransmission(kAs5600Address);
  bus.write(address);
  if (bus.endTransmission(false) != 0 || bus.requestFrom(kAs5600Address, uint8_t(1)) != 1) {
    return false;
  }
  *value = bus.read();
  return true;
}

bool readRawAngle(TwoWire& bus, int* raw) {
  bus.beginTransmission(kAs5600Address);
  bus.write(kRawAngleRegister);
  if (bus.endTransmission(false) != 0 || bus.requestFrom(kAs5600Address, uint8_t(2)) != 2) {
    return false;
  }
  const int high = bus.read();
  const int low = bus.read();
  *raw = ((high & 0x0F) << 8) | low;
  return true;
}

bool sensorReady(Axis& axis, int* raw) {
  uint8_t status = 0;
  return readRegister(*axis.bus, kStatusRegister, &status)
      && (status & 0x20) != 0  // AS5600 magnet detected.
      && readRawAngle(*axis.bus, raw);
}

void prompt() { Serial.print("ESP32-ANTENNA> "); }

void errorReply(const char* message) {
  Serial.print("ERR: ");
  Serial.println(message);
  prompt();
}

void printPosition() {
  int rawPan = -1;
  int rawTilt = -1;
  const bool panOk = sensorReady(pan, &rawPan);
  const bool tiltOk = sensorReady(tilt, &rawTilt);
  Serial.printf("PAN:%.2f TILT:%.2f RAW_PAN:%d RAW_TILT:%d MAG_PAN:%d MAG_TILT:%d HOLD_TILT:%d\n",
                pan.positionDeg, tilt.positionDeg, rawPan, rawTilt, panOk, tiltOk,
                digitalRead(tilt.enablePin) == LOW);
  Serial.printf(">>> Vi tri ang-ten: Pan = %.2f | Tilt = %.2f\n", pan.positionDeg, tilt.positionDeg);
  Serial.printf("    Encoder J4 (Pan): %.2f | Encoder J3 (Tilt): %.2f\n",
                panOk ? rawPan * 360.0f / 4096.0f : -1.0f,
                tiltOk ? rawTilt * 360.0f / 4096.0f : -1.0f);
  prompt();
}

int wrappedRawDelta(int after, int before) {
  int delta = after - before;
  if (delta > 2048) delta -= 4096;
  if (delta < -2048) delta += 4096;
  return delta;
}

bool stopRequested() {
  if (!Serial.available()) return false;
  String command = Serial.readStringUntil('\n');
  command.trim();
  return command.equalsIgnoreCase("STOP");
}

bool moveAxis(Axis& axis, float targetDeg) {
  if (!axis.homed) {
    errorReply("ZERO_REQUIRED");
    return false;
  }
  if (!std::isfinite(targetDeg) || targetDeg < axis.minDeg || targetDeg > axis.maxDeg) {
    errorReply("ANGLE_OUT_OF_RANGE");
    return false;
  }

  int before = 0;
  if (!sensorReady(axis, &before)) {
    digitalWrite(axis.enablePin, HIGH);
    axis.homed = false;
    errorReply("AS5600_NOT_READY");
    return false;
  }
  axis.measuredMotorDeg += wrappedRawDelta(before, axis.lastRaw) * 360.0f / 4096.0f;
  axis.lastRaw = before;
  if (fabsf(axis.measuredMotorDeg - axis.positionDeg * kMotorDegreesPerAntennaDegree) > 12.0f) {
    digitalWrite(axis.enablePin, HIGH);
    axis.homed = false;
    errorReply("POSITION_DRIFT_REZERO_REQUIRED");
    return false;
  }

  const float difference = targetDeg - axis.positionDeg;
  const int direction = difference >= 0.0f ? 1 : -1;
  int remainingSteps = lroundf(fabsf(difference) * kStepsPerAntennaDegree);
  if (remainingSteps == 0) return true;
  digitalWrite(axis.dirPin, direction > 0 ? HIGH : LOW);
  if (&axis == &tilt) {
    diagnosticTiltHold = false;
    digitalWrite(axis.enablePin, LOW);  // Hold against gravity between chunks.
  } else {
    diagnosticPanHold = false;
  }

  while (remainingSteps > 0) {
    if (stopRequested()) {
      axis.homed = false;
      errorReply("ABORTED_REZERO_REQUIRED");
      return false;
    }

    const int chunk = min(remainingSteps, int(kMaxChunkSteps));
    digitalWrite(axis.enablePin, LOW);  // TMC2209 EN is active low.
    delayMicroseconds(20);
    for (int i = 0; i < chunk; ++i) {
      digitalWrite(axis.stepPin, HIGH);
      delayMicroseconds(5);
      digitalWrite(axis.stepPin, LOW);
      delayMicroseconds(kStepPeriodUs - 5);
    }
    if (&axis == &pan) digitalWrite(axis.enablePin, HIGH);
    delay(20);  // Read AS5600 only after STEP pulses stop.

    int after = 0;
    if (!sensorReady(axis, &after)) {
      digitalWrite(axis.enablePin, HIGH);
      axis.homed = false;
      errorReply("AS5600_LOST_REZERO_REQUIRED");
      return false;
    }

    const float motorDelta = wrappedRawDelta(after, before) * 360.0f / 4096.0f;
    const float expectedDelta = direction * chunk * kMotorDegreesPerAntennaDegree / kStepsPerAntennaDegree;
    if (fabsf(motorDelta - expectedDelta) > max(8.0f, fabsf(expectedDelta) * 0.25f)) {
      digitalWrite(axis.enablePin, HIGH);
      axis.homed = false;
      Serial.printf("ERR: %s_ENCODER_MISMATCH measured=%.2f expected=%.2f REZERO_REQUIRED\n",
                    axis.name, motorDelta, expectedDelta);
      prompt();
      return false;
    }

    axis.positionDeg += direction * chunk / kStepsPerAntennaDegree;
    axis.measuredMotorDeg += motorDelta;
    if (fabsf(axis.measuredMotorDeg - axis.positionDeg * kMotorDegreesPerAntennaDegree) > 12.0f) {
      digitalWrite(axis.enablePin, HIGH);
      axis.homed = false;
      errorReply("POSITION_DRIFT_REZERO_REQUIRED");
      return false;
    }
    axis.lastRaw = after;
    before = after;
    remainingSteps -= chunk;
  }

  axis.positionDeg = targetDeg;
  return true;
}

bool jogAxis(Axis& axis, float deltaDeg) {
  if (!std::isfinite(deltaDeg) || fabsf(deltaDeg) > 5.0f || fabsf(deltaDeg) < 0.04f) {
    errorReply("JOG_LIMIT_5_DEGREES");
    return false;
  }
  int before = 0;
  if (!sensorReady(axis, &before)) {
    errorReply("AS5600_NOT_READY");
    return false;
  }
  const int direction = deltaDeg > 0.0f ? 1 : -1;
  const int steps = lroundf(fabsf(deltaDeg) * kStepsPerAntennaDegree);
  digitalWrite(axis.dirPin, direction > 0 ? HIGH : LOW);
  if (&axis == &pan) diagnosticPanHold = false;
  digitalWrite(axis.enablePin, LOW);
  delayMicroseconds(20);
  for (int i = 0; i < steps; ++i) {
    digitalWrite(axis.stepPin, HIGH);
    delayMicroseconds(5);
    digitalWrite(axis.stepPin, LOW);
    delayMicroseconds(kStepPeriodUs - 5);
  }
  digitalWrite(axis.enablePin, HIGH);  // Diagnostic jog releases before the I2C check.
  delay(20);
  int after = 0;
  if (!sensorReady(axis, &after)) {
    axis.homed = false;
    errorReply("AS5600_LOST_REZERO_REQUIRED");
    return false;
  }
  const float measured = wrappedRawDelta(after, before) * 360.0f / 4096.0f;
  const float expected = direction * steps * kMotorDegreesPerAntennaDegree / kStepsPerAntennaDegree;
  axis.homed = false;  // A manual jog invalidates the old absolute reference.
  if (fabsf(measured - expected) > max(8.0f, fabsf(expected) * 0.25f)) {
    Serial.printf("ERR: %s_JOG_MISMATCH measured=%.2f expected=%.2f\n", axis.name, measured, expected);
    prompt();
    return false;
  }
  Serial.printf("JOG OK %s %.2f measured_motor=%.2f\n", axis.name, deltaDeg, measured);
  prompt();
  return true;
}

void processCommand(String command) {
  command.trim();
  if (command.length() == 0) return;
  command.toUpperCase();

  if (command == "POS" || command == "HEALTH") {
    printPosition();
    return;
  }
  if (command == "LINES") {
    Serial.printf("SDA_PAN:%d SCL_PAN:%d SDA_TILT:%d SCL_TILT:%d HOLD_TILT:%d HOLD_PAN:%d\n",
                  digitalRead(18), digitalRead(19), digitalRead(21), digitalRead(22),
                  digitalRead(tilt.enablePin) == LOW, digitalRead(pan.enablePin) == LOW);
    prompt();
    return;
  }
  if (command == "ZERO") {
    int rawPan = 0;
    int rawTilt = 0;
    pan.homed = sensorReady(pan, &rawPan);
    tilt.homed = sensorReady(tilt, &rawTilt);
    if (!pan.homed) {
      errorReply("PAN_AS5600_NOT_READY");
      return;
    }
    pan.positionDeg = 0.0f;
    pan.measuredMotorDeg = 0.0f;
    pan.lastRaw = rawPan;
    if (tilt.homed) {
      tilt.positionDeg = 0.0f;
      tilt.measuredMotorDeg = 0.0f;
      tilt.lastRaw = rawTilt;
    }
    Serial.println(tilt.homed ? "ZERO SET OK" : "ZERO SET PAN ONLY; WARN: TILT_AS5600_NOT_READY");
    prompt();
    return;
  }
  if (command == "STOP") {
    digitalWrite(pan.enablePin, HIGH);
    diagnosticPanHold = false;
    Serial.println("STOP OK; TILT HOLD MAINTAINED");
    prompt();
    return;
  }
  if (command == "HOLD PAN") {
    digitalWrite(pan.enablePin, LOW);
    diagnosticPanHold = true;
    diagnosticPanHoldUntil = millis() + 90000;
    Serial.println("DIAGNOSTIC PAN HOLD ACTIVE FOR 90 SECONDS");
    prompt();
    return;
  }
  if (command == "RELEASE PAN") {
    digitalWrite(pan.enablePin, HIGH);
    diagnosticPanHold = false;
    Serial.println("PAN HOLD RELEASED");
    prompt();
    return;
  }
  if (command == "HOLD TILT") {
    digitalWrite(tilt.enablePin, LOW);
    diagnosticTiltHold = true;
    diagnosticTiltHoldUntil = millis() + 90000;
    Serial.println("DIAGNOSTIC TILT HOLD ACTIVE FOR 90 SECONDS");
    prompt();
    return;
  }
  if (command == "RELEASE") {
    digitalWrite(tilt.enablePin, HIGH);
    diagnosticTiltHold = false;
    Serial.println("TILT HOLD RELEASED");
    prompt();
    return;
  }

  float first = 0.0f;
  float second = 0.0f;
  if (sscanf(command.c_str(), "JOG PAN %f", &first) == 1) {
    jogAxis(pan, first);
    return;
  }
  if (sscanf(command.c_str(), "JOG TILT %f", &first) == 1) {
    jogAxis(tilt, first);
    return;
  }
  if (sscanf(command.c_str(), "PAN %f", &first) == 1) {
    if (moveAxis(pan, first)) {
      Serial.printf("DONE PAN:%.2f TILT:%.2f\n", pan.positionDeg, tilt.positionDeg);
      prompt();
    }
    return;
  }
  if (sscanf(command.c_str(), "TILT %f", &first) == 1) {
    if (moveAxis(tilt, first)) {
      Serial.printf("DONE PAN:%.2f TILT:%.2f\n", pan.positionDeg, tilt.positionDeg);
      prompt();
    }
    return;
  }
  if (sscanf(command.c_str(), "GOTO %f %f", &first, &second) == 2) {
    if (moveAxis(pan, first) && moveAxis(tilt, second)) {
      Serial.printf("DONE PAN:%.2f TILT:%.2f\n", pan.positionDeg, tilt.positionDeg);
      prompt();
    }
    return;
  }
  errorReply("UNKNOWN_COMMAND");
}

void setup() {
  digitalWrite(pan.enablePin, HIGH);
  digitalWrite(tilt.enablePin, HIGH);
  pinMode(pan.enablePin, OUTPUT);
  pinMode(tilt.enablePin, OUTPUT);
  pinMode(pan.stepPin, OUTPUT);
  pinMode(tilt.stepPin, OUTPUT);
  pinMode(pan.dirPin, OUTPUT);
  pinMode(tilt.dirPin, OUTPUT);
  digitalWrite(pan.stepPin, LOW);
  digitalWrite(tilt.stepPin, LOW);

  panBus.begin(18, 19, kI2cClockHz);
  tiltBus.begin(21, 22, kI2cClockHz);
  panBus.setTimeOut(50);
  tiltBus.setTimeOut(50);

  Serial.begin(115200);
  Serial.setTimeout(50);
  Serial.println("ESP32-ANTENNA FW 1.0; ZERO before motion; encoder guarded");
  prompt();
}

void loop() {
  if (diagnosticPanHold && int32_t(millis() - diagnosticPanHoldUntil) >= 0) {
    digitalWrite(pan.enablePin, HIGH);
    diagnosticPanHold = false;
    Serial.println("DIAGNOSTIC PAN HOLD TIMEOUT; RELEASED");
    prompt();
  }
  if (diagnosticTiltHold && int32_t(millis() - diagnosticTiltHoldUntil) >= 0) {
    digitalWrite(tilt.enablePin, HIGH);
    diagnosticTiltHold = false;
    Serial.println("DIAGNOSTIC TILT HOLD TIMEOUT; RELEASED");
    prompt();
  }
  if (!Serial.available()) return;
  processCommand(Serial.readStringUntil('\n'));
}
