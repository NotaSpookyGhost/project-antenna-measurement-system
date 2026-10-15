#pragma once
#include "Arduino.h"
#include <cstdint>

inline uint16_t sensorRaw[2] = {300, 800};
inline uint8_t sensorAgc[2] = {90, 110};
inline uint8_t sensorStatus[2] = {0x20, 0x20};
inline bool failWhenEnabled = false;
inline uint8_t sensorConfig[2][8] = {};

class TwoWire {
 public:
  explicit TwoWire(int bus) : bus_(bus) {}
  void begin(int, int, int) {}
  void setTimeOut(int) {}
  void beginTransmission(uint8_t) { writeIndex_=0; }
  void write(uint8_t value) {
    if (writeIndex_++==0) reg_=value;
    else if (reg_>=1 && reg_+writeIndex_-2<=8) sensorConfig[bus_][reg_+writeIndex_-3]=value;
  }
  byte endTransmission(bool) {
    if (pins[27] == LOW || pins[14] == LOW) {
      ++readsWithMotorEnabled;
      if (failWhenEnabled) return 4;
    }
    return 0;
  }
  int requestFrom(uint8_t, uint8_t length, bool) { readIndex_ = 0; return length; }
  int read() {
    if (reg_>=1 && reg_<=8) return sensorConfig[bus_][reg_-1+readIndex_++];
    if (reg_ == 0x1A) return sensorAgc[bus_];
    if (reg_ == 0x0b) {
      int index = readIndex_++;
      if (index == 0) return sensorStatus[bus_];
      return index == 1 ? (sensorRaw[bus_] >> 8) : (sensorRaw[bus_] & 0xff);
    }
    return readIndex_++ == 0 ? (sensorRaw[bus_] >> 8) : (sensorRaw[bus_] & 0xff);
  }
 private:
  int bus_;
  int reg_ = 0;
  int readIndex_ = 0;
  int writeIndex_ = 0;
};
