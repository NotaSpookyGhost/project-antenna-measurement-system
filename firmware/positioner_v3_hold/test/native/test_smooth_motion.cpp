#include <cassert>
#include <iostream>
#include "../../src/main.cpp"

int main() {
  setup();
  // Confirmed physical wiring: the Az encoder is on 21/22, Tilt on 18/19.
  assert(PIN_PAN_SDA == 21 && PIN_PAN_SCL == 22);
  assert(PIN_TILT_SDA == 18 && PIN_TILT_SCL == 19);
  holdRequested = true;
  calibrationRequired = false;
  setDriversEnabled(true);
  lastHostActivityMs = millis();
  assert(gotoPosition(0, 20));
  const auto& edges = risingEdgeTimes[PIN_TILT_STEP];
  assert(edges.size() == 500);
  auto interval = [&](size_t i) { return edges[i + 1] - edges[i]; };
  // Conservative shared speed envelope, even for Tilt-only movement.
  assert(interval(0) >= 11950 && interval(0) <= 12050);
  assert(interval(100) >= 5950 && interval(100) <= 6050);
  // Ease acceleration in rather than applying full ramp slope at the start.
  assert(interval(0) - interval(5) < interval(45) - interval(50));
  for (size_t i = 0; i + 1 < edges.size(); ++i) assert(interval(i) >= 5950);
  assert(pins[PIN_TILT_STEP] == LOW && pins[PIN_PAN_STEP] == LOW);
  const auto count = risingEdges[PIN_TILT_STEP];
  for (int i = 0; i < 100; ++i) loop();
  assert(risingEdges[PIN_TILT_STEP] == count && driversEnabled);
  risingEdgeTimes[PIN_PAN_STEP].clear();
  nextStepHighDelayUs = 100000;
  lastHostActivityMs = millis();
  assert(gotoPosition(2, 20));
  const auto& delayed = risingEdgeTimes[PIN_PAN_STEP];
  assert(delayed.size() == 50);
  assert(delayed[1] - delayed[0] >= 100000);
  for (size_t i = 1; i + 1 < delayed.size(); ++i)
    assert(delayed[i + 1] - delayed[i] >= 5950);
  std::cout << "Smooth speed envelope, eased ramp, exact count and idle STEP PASS\n";
}
