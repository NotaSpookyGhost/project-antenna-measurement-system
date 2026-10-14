#define TILT_PWM_ENABLED 1
#include <cassert>
#include <iostream>
#include "../../src/main.cpp"
static std::string command(const char* line) {
  Serial.output.clear(); Serial.input+=line; Serial.input+='\n'; loop(); return Serial.output;
}
int main() {
  setup();
  auto pos=command("POS");
  assert(pos.find("ENC_TILT_SOURCE:PWM")!=std::string::npos);
  assert(pos.find("ENC_TILT_VALID:0")!=std::string::npos); // wired I2C cannot mask missing PWM
  assert(pos.find("AGC_TILT_AVAILABLE:0")!=std::string::npos);
  int pulses=risingEdges[25]+risingEdges[32];
  assert(command("TILT PWM CONFIG").find("TILT PWM CONFIG OK")!=std::string::npos);
  assert(risingEdges[25]+risingEdges[32]==pulses);
  // Already captured frames cannot satisfy a later POS request.
  uint32_t start=static_cast<uint32_t>(ticksUs);
  tiltPWMCapture.edge(true,start);
  for(int i=0;i<3;++i) {
    tiltPWMCapture.edge(false,start+i*4351+2176);
    tiltPWMCapture.edge(true,start+(i+1)*4351);
  }
  ticksUs+=3*4351;
  assert(command("POS").find("ENC_TILT_VALID:0")!=std::string::npos);
  assert(command("HOLD ON").find("HOLD ON OK")!=std::string::npos);
  assert(command("TILT PWM CONFIG").find("RELEASE_FIRST")!=std::string::npos);
  assert(command("TILT PWM CHECK").find("ENC_TILT_VALID:0")!=std::string::npos);
  assert(pins[27]==LOW && pins[14]==LOW);
  assert(command("STOP").find("STOP OK")!=std::string::npos);
  assert(pins[27]==LOW && pins[14]==LOW);
  command("HOLD OFF"); assert(pins[27]==HIGH && pins[14]==HIGH);
  command("HOLD ON"); delay(31000); loop();
  assert(pins[27]==HIGH && pins[14]==HIGH && calibrationRequired);
  assert(risingEdges[25]+risingEdges[32]==pulses);
  std::cout << "PWM POS contract/missing feedback/no STEP/released CONFIG/hold STOP PASS\n";
}
