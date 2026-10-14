#pragma once
#include <stdint.h>
#include <string.h>
#ifdef ARDUINO_ARCH_ESP32
#define AS5600_PWM_ISR_ATTR IRAM_ATTR
#else
#define AS5600_PWM_ISR_ATTR
#endif
struct AS5600PWMFrame { uint32_t sequence=0, periodUs=0, highUs=0, stampUs=0; };
class AS5600PWMSamples {
 public:
  // 230 Hz selected: validate actual period, not a nominal 1 ms constant.
  bool add(uint32_t period,uint32_t high,uint32_t stamp,uint32_t now) {
    if (period<3900 || period>4850 || high>period || now-stamp>20000) return invalidate();
    int raw=static_cast<int>((static_cast<uint64_t>(high)*4351+period/2)/period)-128;
    // micros() quantizes both edges/period. Allow two encoded clock counts
    // at the endpoints, while rejecting stuck levels and invalid duty cycles.
    if (raw < -2 || raw > 4097) return invalidate();
    if (raw<0) raw=0;
    if (raw>4095) raw=4095;
    int distance=raw>previous_ ? raw-previous_ : previous_-raw;
    if (distance>2048) distance=4096-distance;
    count_=previous_>=0 && distance<=4 ? count_+1 : 1;
    previous_=raw;
    return count_>=3;
  }
  float angleDeg() const { return count_>=3 ? previous_*(360.0f/4096) : -1; }
 private:
  int previous_=-1, count_=0;
  bool invalidate() { previous_=-1; count_=0; return false; }
};
class AS5600PWMCapture {
 public:
  void AS5600_PWM_ISR_ATTR edge(bool high,uint32_t now) {
    if (high) {
      if (haveRise_) publish(now-rise_,haveFall_ ? fall_-rise_ : 0,now);
      rise_=now; haveRise_=true; haveFall_=false;
    } else if (haveRise_ && !haveFall_) {
      fall_=now; haveFall_=true;
    } else {
      publish(0,0,now); haveRise_=false; haveFall_=false;
    }
  }
  AS5600PWMFrame snapshot() const { return frame_; }
 private:
  uint32_t rise_=0, fall_=0;
  bool haveRise_=false, haveFall_=false;
  AS5600PWMFrame frame_;
  void AS5600_PWM_ISR_ATTR publish(uint32_t period,uint32_t high,uint32_t stamp) {
    frame_.periodUs=period; frame_.highUs=high; frame_.stampUs=stamp; ++frame_.sequence;
  }
};
#undef AS5600_PWM_ISR_ATTR
enum class AS5600PWMConfigResult { Ok, ReadFailed, RangeUnsupported, WriteFailed, VerifyFailed };
template<class Bus> AS5600PWMConfigResult configureAS5600PWM(Bus& bus) {
  uint8_t before[8], again[8];
  if (!bus.readRegisters(1,before,8) || !bus.readRegisters(1,again,8) ||
      memcmp(before,again,8)) return AS5600PWMConfigResult::ReadFailed;
  for(int i=0;i<6;i+=2) if ((before[i]&15) || before[i+1])
    return AS5600PWMConfigResult::RangeUnsupported;
  // Preserve factory/reserved/filter bits. NOM, OUTS=10, PWMF=01.
  uint8_t desired[2]={before[6],static_cast<uint8_t>((before[7]&~0xf3)|0x60)};
  if (!bus.writeRegisters(7,desired,2)) return AS5600PWMConfigResult::WriteFailed;
  if (!bus.readRegisters(1,again,8) || memcmp(before,again,6) ||
      again[6]!=desired[0] || again[7]!=desired[1]) return AS5600PWMConfigResult::VerifyFailed;
  uint8_t verified[8];
  if (!bus.readRegisters(1,verified,8) || memcmp(again,verified,8))
    return AS5600PWMConfigResult::VerifyFailed;
  return AS5600PWMConfigResult::Ok;
}
