#pragma once
#include "Arduino.h"
#include <cstdint>

inline uint16_t sensorRaw[2] = {300, 800};
inline uint8_t sensorAgc[2] = {90, 110};
inline uint8_t sensorStatus[2] = {0x20, 0x20};
inline bool failWhenEnabled = false;

class TwoWire {
 public:
  explicit TwoWire(int bus) : bus_(bus) {}
  void begin(int, int, int) {}
  void setTimeOut(int) {}
  void beginTransmission(uint8_t) {}
  void write(uint8_t reg) { reg_ = reg; }
  byte endTransmission(bool) {
    if (pins[27] == LOW || pins[14] == LOW) {
      ++readsWithMotorEnabled;
      if (failWhenEnabled) return 4;
    }
    return 0;
  }
  int requestFrom(uint8_t, uint8_t length, bool) { readIndex_ = 0; return length; }
  int read() {
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
};
