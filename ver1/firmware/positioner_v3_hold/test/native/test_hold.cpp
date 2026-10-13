#include <cassert>
#include <iostream>
#include "../../src/main.cpp"

static std::string command(const char* line) {
  Serial.output.clear();
  Serial.input += line;
  Serial.input += '\n';
  loop();
  return Serial.output;
}

static void expect(const std::string& text, const char* token) {
  if (text.find(token) == std::string::npos) {
    std::cerr << "Missing " << token << " in: " << text << '\n';
    std::abort();
  }
}

int main() {
  setup();
  assert(pins[27] == HIGH && pins[14] == HIGH);
  expect(command("POS"), "HOLD_CAP:1 HOLD:0 CAL_REQUIRED:1");

  expect(command("HOLD ON"), "HOLD ON OK CAL_REQUIRED:1");
  assert(pins[27] == LOW && pins[14] == LOW);
  expect(command("PAN 2"), "ERR: CAL_REQUIRED");
  expect(command("CAL RELEASE"), "CAL RELEASE OK");
  assert(pins[27] == HIGH && pins[14] == HIGH);

  // Physical hand positioning changes both absolute encoders while released.
  sensorRaw[0] = 1200;
  sensorRaw[1] = 1800;
  expect(command("LOCK ZERO"), "LOCK ZERO OK");
  assert(pins[27] == LOW && pins[14] == LOW);
  assert(!calibrationRequired && holdRequested);
  const int panReleases = disableTransitions[27];
  const int tiltReleases = disableTransitions[14];
  expect(command("PAN 2"), "DONE PAN:");
  assert(pins[27] == LOW && pins[14] == LOW);
  assert(disableTransitions[27] == panReleases);
  assert(disableTransitions[14] == tiltReleases);
  expect(command("POS"), "SENSOR_CACHED:0 ENC_PAN_VALID:1 ENC_TILT_VALID:1");
  assert(readsWithMotorEnabled > 0);
  // A successful I2C transfer containing FF/FF is not a valid 12-bit angle.
  const uint16_t savedTilt = sensorRaw[0];
  sensorRaw[0] = 0xffff;
  command("POS");
  assert(cachedTiltSensorDeg == -1.0f);
  assert(cachedPanSensorDeg >= 0.0f);
  sensorRaw[0] = savedTilt;
  sensorStatus[1] = 0;
  command("POS");
  assert(cachedPanSensorDeg == -1.0f && cachedTiltSensorDeg >= 0.0f);
  sensorStatus[1] = 0x20;
  // Even an explicit re-zero while held must not release the driver.
  expect(command("LOCK ZERO"), "LOCK ZERO OK");
  assert(disableTransitions[27] == panReleases);
  assert(disableTransitions[14] == tiltReleases);
  const int pulseStart = risingEdges[25];
  for (int angle = 10; angle <= 360; angle += 10) {
    expect(command(("PAN " + std::to_string(angle)).c_str()), "DONE PAN:");
    expect(command("POS"), "HOLD:1 CAL_REQUIRED:0");
  }
  assert(risingEdges[25] - pulseStart == 9000);
  assert(currentPanDeg == 360.0f);
  assert(disableTransitions[27] == panReleases);
  assert(disableTransitions[14] == tiltReleases);
  // A failed read cannot cause a release or return yesterday's valid angle.
  failWhenEnabled = true;
  expect(command("POS"), "SENSOR_CACHED:0 ENC_PAN_VALID:0 ENC_TILT_VALID:0");
  assert(cachedPanSensorDeg == -1 && cachedTiltSensorDeg == -1);
  expect(command("LOCK ZERO"), "LOCK ZERO OK");
  assert(disableTransitions[27] == panReleases);
  assert(disableTransitions[14] == tiltReleases);
  failWhenEnabled = false;
  expect(command("PAN 2"), "DONE PAN:");

  injectStopAtUs = ticksUs + 50000;
  stopInjected = false;
  expect(command("PAN 20"), "ABORTED PAN:");
  assert(stopInjected && currentPanDeg > 2.0f && currentPanDeg < 20.0f);
  assert(calibrationRequired && holdRequested);
  assert(pins[27] == LOW && pins[14] == LOW);
  expect(command("CAL RELEASE"), "CAL RELEASE OK");
  expect(command("LOCK ZERO"), "LOCK ZERO OK");
  injectStopAtUs = 0;

  // A healthy MATLAB client extends the lease. A dead client releases both.
  delay(29000);
  expect(command("PING"), "PONG");
  delay(29000);
  Serial.output.clear();
  loop();
  assert(pins[27] == LOW && pins[14] == LOW);
  delay(2000);
  loop();
  assert(pins[27] == HIGH && pins[14] == HIGH);
  assert(calibrationRequired && !holdRequested);
  expect(command("GOTO 10 5"), "ERR: CAL_REQUIRED");
  expect(command("HOLD ON"), "CAL_REQUIRED:1");
  assert(pins[27] == LOW && pins[14] == LOW);
  expect(command("HOLD OFF"), "HOLD OFF OK");
  assert(pins[27] == HIGH && pins[14] == HIGH);
  // The lease also applies INSIDE a long move, not just when loop() returns.
  expect(command("LOCK ZERO"), "LOCK ZERO OK");
  lastHostActivityMs = millis() - 29500UL;
  assert(!gotoPosition(360, 0));
  assert(!holdRequested && calibrationRequired && currentPanDeg < 10);
  assert(pins[27] == HIGH && pins[14] == HIGH);
  // In-flight heartbeats renew the lease without introducing extra prompts.
  expect(command("LOCK ZERO"), "LOCK ZERO OK");
  lastHostActivityMs = millis() - 29500UL;
  Serial.input = "KEEPALIVE\n";
  assert(gotoPosition(10, 0));
  assert(holdRequested && !calibrationRequired);
  expect(command("HOLD OFF"), "HOLD OFF OK");
  std::cout << "Firmware hold/release/manual ZERO/lease simulation PASS\n";
}
