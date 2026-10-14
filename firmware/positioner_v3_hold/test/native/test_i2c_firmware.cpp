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

int main() {
  setup();
  assert(Serial.output.find("FW:V4.0_HOLD") != std::string::npos);
  command("LOCK ZERO");
  command("TILT 5");
  assert(currentTiltDeg == 5);
  const int tiltPulses = risingEdges[PIN_TILT_STEP];
  const int panPulses = risingEdges[PIN_PAN_STEP];
  const auto releases = releaseCount;
  for (const auto* retired : {"TILT PWM CHECK", "TILT PWM CONFIG", "TILT PWM REG"}) {
    const auto response = command(retired);
    assert(response.find("ERR: UNSUPPORTED_COMMAND") != std::string::npos);
    assert(currentTiltDeg == 5 && currentPanDeg == 0);
    assert(risingEdges[PIN_TILT_STEP] == tiltPulses);
    assert(risingEdges[PIN_PAN_STEP] == panPulses);
    assert(driversEnabled && releaseCount == releases);
  }
  assert(command("POS").find("ENC_TILT_VALID:1") != std::string::npos);
  command("TILT 0");
  assert(currentTiltDeg == 0);
  command("HOLD OFF");
  assert(!driversEnabled);
  std::cout << "I2C firmware / retired PWM commands cannot move or release motors PASS\n";
}
