#include <cassert>
#include <cmath>
#include <iostream>
#include <vector>
#include "../../src/as5600_pwm.h"

struct ConfigBus {
  uint8_t registers[256] = {};
  std::vector<int> written;
  bool nack = false, writeNack = false, corruptReadback = false;
  bool readRegisters(uint8_t reg, uint8_t* out, int n) {
    if (nack) return false;
    for (int i=0;i<n;++i) out[i]=registers[reg+i];
    if (corruptReadback && !written.empty()) out[n-1]^=1;
    return true;
  }
  bool writeRegisters(uint8_t reg,const uint8_t* data,int n) {
    if (writeNack) return false;
    for (int i=0;i<n;++i) { written.push_back(reg+i); registers[reg+i]=data[i]; }
    return true;
  }
};

int main() {
  AS5600PWMSamples zero;
  assert(!zero.add(4351,128,10,10));
  assert(!zero.add(4351,128,20,20));
  assert(zero.add(4351,128,30,30));
  assert(zero.angleDeg()==0);
  assert(!zero.add(4351,128,30,30031)); // stale sample invalidates prior angle
  assert(zero.angleDeg()==-1);
  // A valid 232.56 Hz frame has a fractional 126.50 us zero pulse.
  // The microsecond timer can measure 126 or 127; neither is sensor failure.
  AS5600PWMSamples fractionalZero;
  assert(!fractionalZero.add(4300,126,1,1));
  assert(!fractionalZero.add(4300,127,2,2));
  assert(fractionalZero.add(4300,126,3,3));
  assert(fractionalZero.angleDeg()==0);
  AS5600PWMSamples fractionalMax;
  assert(!fractionalMax.add(4300,4174,1,1));
  assert(!fractionalMax.add(4300,4173,2,2));
  assert(fractionalMax.add(4300,4174,3,3));
  assert(std::fabs(fractionalMax.angleDeg()-4095*360.0f/4096)<.001f);
  AS5600PWMSamples maximum;
  for(int i=0;i<3;++i) maximum.add(4351,4223,i,i);
  assert(std::fabs(maximum.angleDeg()-4095*360.0f/4096)<.001f);
  assert(!maximum.add(1000,500,1,1)); // wrong frequency
  assert(!maximum.add(4351,0,1,1)); // missing magnet / stuck low
  assert(!maximum.add(4351,4351,1,1)); // stuck high
  AS5600PWMSamples wrapping;
  assert(!wrapping.add(4351,4223,1,1));
  assert(!wrapping.add(4351,128,2,2));
  assert(wrapping.add(4351,129,3,3));
  AS5600PWMSamples inconsistent;
  for(int i=0;i<12;++i) assert(!inconsistent.add(4351,i%2?2000:1000,i,i));

  AS5600PWMCapture capture;
  capture.edge(true,0xfffff000U);
  capture.edge(false,0xfffff000U+2176U);
  capture.edge(true,0xfffff000U+4351U);
  auto frame=capture.snapshot();
  assert(frame.sequence==1 && frame.periodUs==4351 && frame.highUs==2176);
  capture.edge(false,6000); capture.edge(false,6001); // duplicate falling edge
  assert(capture.snapshot().periodUs==0);

  ConfigBus bus;
  bus.registers[7]=0x15; bus.registers[8]=0x0c;
  assert(configureAS5600PWM(bus)==AS5600PWMConfigResult::Ok);
  assert(bus.registers[7]==0x15 && bus.registers[8]==0x6c);
  for(int reg:bus.written) assert(reg>=1 && reg<=8); // never OTP/BURN
  ConfigBus scaled; scaled.registers[2]=1;
  scaled.registers[1]=0xa0; // preserve factory/reserved upper nibble
  scaled.registers[4]=2; scaled.registers[6]=3;
  assert(configureAS5600PWM(scaled)==AS5600PWMConfigResult::Ok);
  assert(scaled.registers[1]==0xa0 && scaled.registers[2]==0);
  assert(scaled.registers[3]==0 && scaled.registers[4]==0 && scaled.registers[5]==0 && scaled.registers[6]==0);
  for(int reg:scaled.written) assert(reg>=1 && reg<=8);
  ConfigBus failed; failed.nack=true;
  assert(configureAS5600PWM(failed)==AS5600PWMConfigResult::ReadFailed);
  assert(failed.written.empty());
  ConfigBus badWrite; badWrite.writeNack=true;
  assert(configureAS5600PWM(badWrite)==AS5600PWMConfigResult::WriteFailed);
  ConfigBus badVerify; badVerify.corruptReadback=true;
  assert(configureAS5600PWM(badVerify)==AS5600PWMConfigResult::VerifyFailed);
  std::cout << "PWM endpoints/wrap/noise/stale/micros wrap/configuration/no OTP PASS\n";
}
