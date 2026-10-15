#pragma once
#include <stdint.h>

// New accumulator for EACH request. Three consecutive fresh, agreeing packets
// are required; no previous-position cache may supply a missing measurement.
class AS5600Samples {
 public:
  bool add(bool transferred, uint8_t status, uint8_t high, uint8_t low) {
    if (!transferred || !(status & 0x20) || (high & 0xf0)) {
      count_ = 0;
      previous_ = -1;
      return false;
    }
    int raw = (static_cast<int>(high) << 8) | low;
    int distance = raw > previous_ ? raw - previous_ : previous_ - raw;
    if (distance > 2048) distance = 4096 - distance;
    count_ = previous_ >= 0 && distance <= 4 ? count_ + 1 : 1;
    previous_ = raw;
    return count_ >= 3;
  }
  float angleDeg() const { return count_ >= 3 ? previous_ * (360.0f / 4096.0f) : -1.0f; }
 private:
  int previous_ = -1;
  int count_ = 0;
};
