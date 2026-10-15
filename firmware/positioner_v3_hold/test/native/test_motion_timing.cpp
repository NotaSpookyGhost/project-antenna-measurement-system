#include <cassert>
#include <iostream>
#include "../../src/main.cpp"

static void prepare() {
  currentPanDeg = currentTiltDeg = 0;
  holdRequested = true;
  calibrationRequired = false;
  setDriversEnabled(true);
  lastHostActivityMs = millis();
  injectStopAtUs = 0; stopInjected = false;
  heartbeatEveryUs = nextHeartbeatAtUs = 0;
  Serial.input.clear(); Serial.output.clear();
  for (auto& times : risingEdgeTimes) times.clear();
}

static void nearInterval(unsigned long long actual, unsigned long long expected) {
  assert(actual + 30 >= expected && actual <= expected + 30);
}

static void profile(int pin, size_t count, unsigned long start, unsigned long cruise, size_t ramp) {
  const auto& t = risingEdgeTimes[pin];
  assert(t.size() == count);
  nearInterval(t[1]-t[0], start);
  nearInterval(t[ramp+1]-t[ramp], cruise);
  // Halfway through the independently specified ramp, speed must be intermediate.
  nearInterval(t[ramp/2+1]-t[ramp/2], (start+cruise)/2);
  assert(t.back()-t[t.size()-2] > cruise);
}

int main() {
  setup();
  prepare();
  auto begin = ticksUs;
  assert(gotoPosition(90,0));
  double seconds = (ticksUs-begin)/1e6;
  std::cout << "Pan 90 duration: " << seconds << " s\n" << std::flush;
  assert(seconds > 11.9 && seconds < 12.1);
  profile(PIN_PAN_STEP,2250,9000,5000,150);
  assert(risingEdgeTimes[PIN_TILT_STEP].empty());
  assert(currentPanDeg == 90 && holdRequested && driversEnabled);

  prepare(); begin = ticksUs;
  assert(gotoPosition(0,90));
  seconds = (ticksUs-begin)/1e6;
  assert(seconds > 5.3 && seconds < 5.4);
  profile(PIN_TILT_STEP,2250,5000,2200,100);
  assert(risingEdgeTimes[PIN_PAN_STEP].empty());

  prepare();
  assert(gotoPosition(10,20));
  assert(risingEdgeTimes[PIN_PAN_STEP].size() == 250);
  assert(risingEdgeTimes[PIN_TILT_STEP].size() == 500);
  nearInterval(risingEdgeTimes[PIN_TILT_STEP][251]-risingEdgeTimes[PIN_TILT_STEP][250],5000);
  assert(currentPanDeg == 10 && currentTiltDeg == 20);

  prepare(); begin = ticksUs;
  assert(gotoPosition(-5,0));
  seconds = (ticksUs-begin)/1e6;
  // A short move stays on the bounded ramp instead of jumping to cruise.
  assert(seconds > 1.05 && seconds < 1.20);
  assert(risingEdgeTimes[PIN_PAN_STEP].size() == 125);
  assert(pins[PIN_PAN_DIR] == LOW && currentPanDeg == -5);
  prepare(); begin = ticksUs;
  assert(gotoPosition(0,0));
  assert(risingEdgeTimes[PIN_PAN_STEP].empty() && risingEdgeTimes[PIN_TILT_STEP].empty());
  assert(ticksUs-begin < 1000);

  prepare();
  const auto releases = releaseCount;
  injectStopAtUs = ticksUs + 500000;
  assert(!gotoPosition(90,0));
  assert(currentPanDeg > 0 && currentPanDeg < 90);
  assert(calibrationRequired && holdRequested && driversEnabled && releaseCount == releases);

  prepare(); begin = ticksUs;
  heartbeatEveryUs = 5000000;
  nextHeartbeatAtUs = ticksUs + heartbeatEveryUs;
  assert(gotoPosition(360,0));
  assert(ticksUs-begin > 45000000 && ticksUs-begin < 46000000);
  assert(risingEdgeTimes[PIN_PAN_STEP].size() == 9000);
  assert(holdRequested && driversEnabled && releaseCount == releases);
  assert(Serial.output.find("ESP32-ANTENNA>") == std::string::npos);
  prepare();
  assert(!gotoPosition(360,0));
  assert(currentPanDeg > 0 && currentPanDeg < 360);
  assert(calibrationRequired && !holdRequested && !driversEnabled);
  std::cout << "Axis timing, pulse counts, STOP and long-move heartbeat PASS\n";
}
