#include <cassert>
#include <iostream>
#include "../../src/as5600_sample.h"

static bool add(AS5600Samples& samples, int raw, int status=0x20, bool ok=true) {
  return samples.add(ok, status, raw >> 8, raw & 255);
}
int main() {
  AS5600Samples stable;
  assert(!add(stable, 1000)); assert(!add(stable, 1001)); assert(add(stable, 1000));
  assert(stable.angleDeg() == 1000 * (360.0f/4096));
  // Corruption/NACK/missing magnet invalidates even an already qualified value.
  assert(!add(stable, 0xffff)); assert(stable.angleDeg() == -1);
  for (int i=0;i<16;++i) assert(!add(stable, 1000, 0));
  assert(!add(stable, 1000)); assert(!add(stable, 1000));
  assert(!add(stable, 1000, 0x20, false));
  assert(!add(stable, 1000)); assert(stable.angleDeg() == -1);
  AS5600Samples wrapping;
  assert(!add(wrapping, 4095)); assert(!add(wrapping, 0)); assert(add(wrapping, 1));
  AS5600Samples inconsistent;
  for (int i=0;i<16;++i) assert(!add(inconsistent, i%2 ? 800 : 1023));
  AS5600Samples nextRequest;
  assert(nextRequest.angleDeg() == -1); assert(!add(nextRequest, 1000));
  std::cout << "AS5600 corrupted packet / missing magnet / fresh consensus / wrap PASS\n";
}
