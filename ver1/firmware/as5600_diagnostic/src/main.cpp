// Stationary diagnostic only. No STEP pulses, no sensor configuration writes.
#include <Arduino.h>
#include <Wire.h>
TwoWire pan(1), tilt(0);
const int SDA_P = 18, SCL_P = 19, SDA_T = 21, SCL_T = 22;
uint32_t lastHost = 0;
int holdMask = 0;
bool pushClock = false; // Diagnostic only: AS5600 SCL is input, no clock stretching.
bool filteredData = false;
unsigned int halfPeriodUs = 25;
int sampleData(int pin) {
  if (!filteredData) return digitalRead(pin);
  int high=0;
  for (int i=0;i<5;++i) {high+=digitalRead(pin);delayMicroseconds(1);}
  return high>=3;
}
void hold(int mask) {
  holdMask = mask;
  digitalWrite(27, (mask & 1) ? LOW : HIGH);
  digitalWrite(14, (mask & 2) ? LOW : HIGH);
}
void releaseLine(int pin) { pinMode(pin, INPUT_PULLUP); }
void lowLine(int pin) {
  digitalWrite(pin, LOW);
  pinMode(pin, pushClock && (pin == SCL_P || pin == SCL_T) ? OUTPUT : OUTPUT_OPEN_DRAIN);
}
bool clockHigh(int pin) {
  if (pushClock) { digitalWrite(pin, HIGH); pinMode(pin, OUTPUT); delayMicroseconds(halfPeriodUs); return true; }
  releaseLine(pin);
  uint32_t t = micros();
  while (!digitalRead(pin)) if (micros() - t > 1000) return false;
  delayMicroseconds(halfPeriodUs); return true;
}
void stopBit(int sda, int scl) { lowLine(sda); clockHigh(scl); releaseLine(sda); delayMicroseconds(halfPeriodUs); }
bool startBit(int sda, int scl) {
  releaseLine(sda); if (!clockHigh(scl)) return false;
  if (!sampleData(sda)) return false;
  lowLine(sda); delayMicroseconds(halfPeriodUs); lowLine(scl); return true;
}
bool writeByte(int sda, int scl, uint8_t value) {
  for (int b = 7; b >= 0; --b) {
    if (value & (1 << b)) releaseLine(sda); else lowLine(sda);
    delayMicroseconds(halfPeriodUs); if (!clockHigh(scl)) return false; lowLine(scl);
  }
  releaseLine(sda); delayMicroseconds(halfPeriodUs);
  if (!clockHigh(scl)) return false;
  bool ack = sampleData(sda) == LOW; lowLine(scl); return ack;
}
int readByte(int sda, int scl, bool ack) {
  int value = 0; releaseLine(sda);
  for (int b = 0; b < 8; ++b) {
    delayMicroseconds(halfPeriodUs); if (!clockHigh(scl)) return -1;
    value = (value << 1) | sampleData(sda); lowLine(scl);
  }
  if (ack) lowLine(sda); else releaseLine(sda);
  delayMicroseconds(halfPeriodUs); if (!clockHigh(scl)) return -1;
  lowLine(scl); releaseLine(sda); return value;
}
int softRead(int sda, int scl, uint8_t reg, uint8_t* data, int count) {
  if (!startBit(sda, scl)) return -10;
  if (!writeByte(sda, scl, 0x6c)) { stopBit(sda,scl); return -11; }
  if (!writeByte(sda, scl, reg)) { stopBit(sda,scl); return -12; }
  if (!startBit(sda, scl) || !writeByte(sda, scl, 0x6d)) { stopBit(sda,scl); return -13; }
  for (int i=0;i<count;++i) {
    int v=readByte(sda,scl,i<count-1);
    if (v<0) { stopBit(sda,scl); return -14; }
    data[i]=v;
  }
  stopBit(sda,scl); return 0;
}
int wireRead(TwoWire& bus, bool repeated, uint8_t reg, uint8_t* data, int count) {
  bus.beginTransmission(0x36); bus.write(reg);
  int err=bus.endTransmission(!repeated);
  if(err) return -err;
  int n=bus.requestFrom((uint8_t)0x36,(uint8_t)count,(uint8_t)true);
  if(n!=count) return -20-n;
  for(int i=0;i<count;++i) data[i]=bus.read();
  return 0;
}
// Experimental: every call starts fresh; never accepts the previous POS value.
int qualifiedRead(int sda, int scl, uint8_t* data, int& attempts) {
  int previous=-1, streak=0;
  for (attempts=1; attempts<=16; ++attempts) {
    releaseLine(sda);
    for (int i=0;i<9 && !sampleData(sda);++i) {
      lowLine(scl); delayMicroseconds(halfPeriodUs); clockHigh(scl);
    }
    stopBit(sda,scl);
    int err=softRead(sda,scl,0x0b,data,3);
    if(err || !(data[0]&0x20) || (data[1]&0xf0)) {streak=0;previous=-1;continue;}
    int raw=(data[1]<<8)|data[2];
    int delta=abs(raw-previous); delta=min(delta,4096-delta);
    streak=previous>=0 && delta<=4 ? streak+1 : 1;
    previous=raw;
    if(streak>=3) return 0;
    delayMicroseconds(200);
  }
  return -30;
}
void diagnose(int mode, int hz) {
  pan.end(); tilt.end();
  pushClock = mode >= 4;
  halfPeriodUs = mode == 7 ? 500000 / hz : 25;
  filteredData = mode >= 5;
  if(mode>=3) {
    releaseLine(SDA_P); releaseLine(SCL_P); releaseLine(SDA_T); releaseLine(SCL_T);
  } else {
    pan.begin(SDA_P,SCL_P,hz); tilt.begin(SDA_T,SCL_T,hz);
    pan.setTimeOut(10); tilt.setTimeOut(10);
  }
  int good[2]={0,0};
  for(int sample=0;sample<5;++sample) {
    for(int axis=0;axis<2;++axis) {
      uint8_t data[3]={255,255,255}; int sda=axis?SDA_T:SDA_P, scl=axis?SCL_T:SCL_P;
      int highSDA=0,highSCL=0;
      for(int j=0;j<100;++j) { highSDA+=digitalRead(sda);highSCL+=digitalRead(scl);delayMicroseconds(2); }
      uint32_t t=micros();
      uint8_t reg=mode==2?0x0e:0x0b; int len=mode==2?2:3;
      int attempts=1;
      int err=mode>=6?qualifiedRead(sda,scl,data,attempts):(mode>=3?softRead(sda,scl,reg,data,len):wireRead(axis?tilt:pan,mode==1,reg,data,len));
      uint16_t raw=mode==2?((data[0]&15)<<8)|data[1]:((data[1]&15)<<8)|data[2];
      if(err==0) good[axis]++;
      Serial.printf("SAMPLE mask=%d mode=%d hz=%d axis=%d n=%d err=%d bytes=%02x,%02x,%02x raw=%u us=%lu idle=%d,%d\n",holdMask,mode,hz,axis,sample,err,data[0],data[1],data[2],raw,micros()-t,highSDA,highSCL);
      if(mode>=6) Serial.printf("ATTEMPTS %d\n",attempts);
    }
    delay(50); lastHost=millis();
  }
  Serial.printf("SUMMARY mask=%d mode=%d hz=%d good=%d,%d/5\n",holdMask,mode,hz,good[0],good[1]);
}
void setup() {
  Serial.begin(115200);
  pinMode(27,OUTPUT);pinMode(14,OUTPUT);hold(0);
  pinMode(25,OUTPUT);pinMode(32,OUTPUT);digitalWrite(25,LOW);digitalWrite(32,LOW);
  delay(1200);Serial.println("AS5600 DIAGNOSTIC: NO MOTION; H 0..3; D mode hz; lease 30s");Serial.print("DIAG> ");
}
void loop() {
  if(holdMask && millis()-lastHost>=30000) {hold(0);Serial.println("LEASE RELEASE");}
  if(!Serial.available()) return;
  String cmd=Serial.readStringUntil('\n'); cmd.trim(); lastHost=millis();
  int mask,mode,hz;
  if(sscanf(cmd.c_str(),"H %d",&mask)==1 && mask>=0 && mask<=3) {hold(mask);Serial.printf("HOLD MASK %d\n",mask);}
  else if(sscanf(cmd.c_str(),"D %d %d",&mode,&hz)==2 && mode>=0 && mode<=7 && hz>=10000 && hz<=400000) diagnose(mode,hz);
  else Serial.println("ERR");
  Serial.print("DIAG> ");
}
