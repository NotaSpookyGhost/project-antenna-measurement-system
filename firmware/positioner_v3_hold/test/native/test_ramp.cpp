#include <cassert>
#include <string>
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
  assert(command("POS").find("RAMP_CAP:1 RAMP_PAN:150 RAMP_TILT:100") != std::string::npos);
  const int panBefore = risingEdges[PIN_PAN_STEP];
  const int tiltBefore = risingEdges[PIN_TILT_STEP];

  assert(command("RAMP 100 75").find("RAMP OK PAN:100 TILT:75") != std::string::npos);
  assert(risingEdges[PIN_PAN_STEP] == panBefore && risingEdges[PIN_TILT_STEP] == tiltBefore);
  assert(command("POS").find("RAMP_PAN:100 RAMP_TILT:75") != std::string::npos);

  for (const char* invalid : {"RAMP 99 75", "RAMP 100 74", "RAMP 601 75",
                              "RAMP 100 301", "RAMP 100", "RAMP 100 75 EXTRA"}) {
    assert(command(invalid).find("ERR: RAMP_RANGE") != std::string::npos);
    assert(command("POS").find("RAMP_PAN:100 RAMP_TILT:75") != std::string::npos);
  }
  assert(risingEdges[PIN_PAN_STEP] == panBefore && risingEdges[PIN_TILT_STEP] == tiltBefore);

  command("LOCK ZERO");
  assert(gotoPosition(5, 0));
  const auto& shortPan = risingEdgeTimes[PIN_PAN_STEP];
  assert(shortPan.size() == 125);
  // A short move must not compress the selected ramp into a steeper one.
  assert(shortPan[63] - shortPan[62] > 6000);
  command("LOCK ZERO");
  for (auto& times : risingEdgeTimes) times.clear();
  assert(gotoPosition(90, 0));
  const auto& pan = risingEdgeTimes[PIN_PAN_STEP];
  assert(pan.size() == 2250);
  assert(pan[1] - pan[0] >= 9000 && pan[1] - pan[0] <= 9030);
  assert(pan[101] - pan[100] >= 5000 && pan[101] - pan[100] <= 5030);

  assert(gotoPosition(90, 90));
  const auto& tilt = risingEdgeTimes[PIN_TILT_STEP];
  assert(tilt.size() == 2250);
  assert(tilt[1] - tilt[0] >= 5000 && tilt[1] - tilt[0] <= 5030);
  assert(tilt[76] - tilt[75] + 30 >= 2200 && tilt[76] - tilt[75] <= 2230);
}
