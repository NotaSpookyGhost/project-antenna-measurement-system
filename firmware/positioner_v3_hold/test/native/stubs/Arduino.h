#pragma once
#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <cstdint>
#include <vector>

using byte = unsigned char;
using std::max;
using std::min;
using std::isfinite;
constexpr int HIGH = 1;
constexpr int LOW = 0;
constexpr int OUTPUT = 1;
inline int pins[64] = {};
inline unsigned long long ticksUs = 0;
inline int readsWithMotorEnabled = 0;
inline unsigned long long injectStopAtUs = 0;
inline bool stopInjected = false;
inline int disableTransitions[64] = {};
inline int risingEdges[64] = {};
inline std::vector<unsigned long long> risingEdgeTimes[64];
inline unsigned long long heartbeatEveryUs = 0;
inline unsigned long long nextHeartbeatAtUs = 0;

inline void pinMode(int, int) {}
inline void digitalWrite(int pin, int value) {
  if (pins[pin] == LOW && value == HIGH) {
    risingEdges[pin]++;
    risingEdgeTimes[pin].push_back(ticksUs);
    if (pin == 27 || pin == 14) disableTransitions[pin]++;
  }
  pins[pin] = value;
}
inline void delay(unsigned long ms) { ticksUs += 1000ULL * ms; }
void maybeInjectStop();
inline void delayMicroseconds(unsigned long us) { ticksUs += us; maybeInjectStop(); }
inline unsigned long millis() { return static_cast<unsigned long>(ticksUs / 1000ULL); }
inline unsigned long micros() { ticksUs += 10; maybeInjectStop(); return static_cast<unsigned long>(ticksUs); }
inline void yield() {}

class String {
 public:
  std::string value;
  String() = default;
  String(const char* s) : value(s) {}
  String(std::string s) : value(std::move(s)) {}
  void trim() {
    auto first = value.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) { value.clear(); return; }
    auto last = value.find_last_not_of(" \t\r\n");
    value = value.substr(first, last - first + 1);
  }
  void toUpperCase() {
    std::transform(value.begin(), value.end(), value.begin(),
                   [](unsigned char c) { return std::toupper(c); });
  }
  bool equalsIgnoreCase(const char* other) const {
    String copy = *this;
    copy.toUpperCase();
    String expected(other);
    expected.toUpperCase();
    return copy.value == expected.value;
  }
  bool startsWith(const char* prefix) const { return value.rfind(prefix, 0) == 0; }
  String substring(size_t from) const { return String(value.substr(from)); }
  float toFloat() const { return std::strtof(value.c_str(), nullptr); }
  long toInt() const { return std::strtol(value.c_str(), nullptr, 10); }
  size_t length() const { return value.size(); }
  const char* c_str() const { return value.c_str(); }
  bool operator==(const char* other) const { return value == other; }
  bool operator!=(const char* other) const { return value != other; }
};

class SerialStub {
 public:
  std::string input;
  std::string output;
  void begin(int) {}
  int available() const { return static_cast<int>(input.size()); }
  int read() { if (input.empty()) return -1; int c = input.front(); input.erase(0, 1); return c; }
  String readStringUntil(char marker) {
    auto n = input.find(marker);
    if (n == std::string::npos) { auto text = input; input.clear(); return String(text); }
    auto text = input.substr(0, n);
    input.erase(0, n + 1);
    return String(text);
  }
  void print(const char* s) { output += s; }
  void println(const char* s) { output += s; output += '\n'; }
  void printf(const char* format, ...) {
    char buffer[512];
    va_list args;
    va_start(args, format);
    std::vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    output += buffer;
  }
};
inline SerialStub Serial;
inline void maybeInjectStop() {
  if (heartbeatEveryUs && ticksUs >= nextHeartbeatAtUs) {
    Serial.input += "KEEPALIVE\n";
    nextHeartbeatAtUs = ticksUs + heartbeatEveryUs;
  }
  if (injectStopAtUs && !stopInjected && ticksUs >= injectStopAtUs) {
    Serial.input += "STOP\n";
    stopInjected = true;
  }
}
