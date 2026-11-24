#include <cassert>
#include <iostream>
#include "../../src/main.cpp"

static void command(const char* text) {
  Serial.output.clear();
  Serial.input = std::string(text) + "\n";
  loop();
}

int main() {
  setup();
  command("POS");
  assert(Serial.output.find("CONT_PAN_CAP:1") != std::string::npos);
  command("PANSCAN 2");
  assert(risingEdges[PIN_PAN_STEP] == 0);
  command("LOCK ZERO");
  command("PANSCAN 2");
  assert(risingEdges[PIN_PAN_STEP] == 50);
  assert(Serial.output.find("SCAN 1 ") != std::string::npos);
  assert(scanSequence > 2);
  assert(Serial.output.find("DONE PAN:") != std::string::npos);
  assert(holdRequested && !calibrationRequired && !continuousPan);
  command("PANSCAN invalid");
  assert(risingEdges[PIN_PAN_STEP] == 50);
  command("TILTSCAN 2");
  assert(risingEdges[PIN_TILT_STEP] == 50);
  assert(Serial.output.find("SCAN 1 ") != std::string::npos);
  assert(Serial.output.find("DONE PAN:") != std::string::npos);
  injectStopAtUs = ticksUs + 300000;
  stopInjected = false;
  command("PANSCAN 30");
  assert(Serial.output.find("ABORTED PAN:") != std::string::npos);
  assert(calibrationRequired && holdRequested && !continuousPan);
  assert(pins[PIN_PAN_STEP] == LOW && pins[PIN_TILT_STEP] == LOW);
  injectStopAtUs = 0;
  command("LOCK ZERO");
  const int before = risingEdges[PIN_PAN_STEP];
  failWhenEnabled = true;
  command("PANSCAN 2");
  assert(risingEdges[PIN_PAN_STEP] == before);
  assert(calibrationRequired && !continuousPan);
  std::cout << "Continuous telemetry, STOP, encoder failure, target parsing PASS\n";
}
