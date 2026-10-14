#pragma once
#include <Arduino.h>

// Dedicated, single-master AS5600 buses ONLY. AS5600 has an input-only SCL and
// does not stretch the clock (DS000365, I2C Interface). Driving SCL high avoids
// the unreliable weak-pullup clock observed with both TMC2209 drivers enabled.
// SDA remains open drain. Do not reuse for slaves that stretch SCL or multi-master.
class AS5600Bus {
 public:
  explicit AS5600Bus(int) {}
  void begin(int sda, int scl, int) {
    sda_ = sda; scl_ = scl;
    releaseData(); digitalWrite(scl_, HIGH); pinMode(scl_, OUTPUT);
  }
  void setTimeOut(int) {} // Every GPIO transaction has a fixed, bounded length.
  // Only volatile full-turn/CONF setup writes are supported. No BURN/OTP.
  bool writeRegisters(uint8_t reg,const uint8_t* data,int count) {
    if (!((reg==7 && count==2) || (reg==1 && count==6))) return false;
    stop();
    bool ok=start() && writeByte(0x6c) && writeByte(reg);
    for(int i=0;ok && i<count;++i) ok=writeByte(data[i]);
    stop(); return ok;
  }
  bool readRegisters(uint8_t reg, uint8_t* data, int count) {
    releaseData();
    for (int i = 0; i < 9 && !sampleData(); ++i) {
      clockLow(); delayMicroseconds(25); clockHigh();
    }
    stop();
    bool ok = start() && writeByte(0x6c) && writeByte(reg) &&
              start() && writeByte(0x6d);
    if (ok) for (int i = 0; i < count; ++i) data[i] = readByte(i < count - 1);
    stop(); // Also recover the bus after a failed START or NACK.
    return ok;
  }
 private:
  int sda_ = -1, scl_ = -1;
  void releaseData() { pinMode(sda_, INPUT_PULLUP); }
  void dataLow() { digitalWrite(sda_, LOW); pinMode(sda_, OUTPUT_OPEN_DRAIN); }
  void clockLow() { digitalWrite(scl_, LOW); pinMode(scl_, OUTPUT); }
  void clockHigh() { digitalWrite(scl_, HIGH); pinMode(scl_, OUTPUT); delayMicroseconds(25); }
  int sampleData() {
    int high = 0;
    for (int i = 0; i < 5; ++i) { high += digitalRead(sda_); delayMicroseconds(1); }
    return high >= 3;
  }
  bool start() {
    releaseData(); clockHigh();
    if (!sampleData()) return false;
    dataLow(); delayMicroseconds(25); clockLow(); return true;
  }
  void stop() { dataLow(); clockHigh(); releaseData(); delayMicroseconds(25); }
  bool writeByte(uint8_t value) {
    for (int bit = 7; bit >= 0; --bit) {
      if (value & (1 << bit)) releaseData(); else dataLow();
      delayMicroseconds(25); clockHigh(); clockLow();
    }
    releaseData(); delayMicroseconds(25); clockHigh();
    bool ack = sampleData() == LOW; clockLow(); return ack;
  }
  uint8_t readByte(bool ack) {
    uint8_t value = 0; releaseData();
    for (int bit = 0; bit < 8; ++bit) {
      delayMicroseconds(25); clockHigh();
      value = (value << 1) | sampleData(); clockLow();
    }
    if (ack) dataLow(); else releaseData();
    delayMicroseconds(25); clockHigh(); clockLow(); releaseData(); return value;
  }
};
