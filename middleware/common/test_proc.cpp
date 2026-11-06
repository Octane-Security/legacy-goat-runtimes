// Unit tests for proc.hpp. Build: clang++ -std=c++17 -o test_proc test_proc.cpp && ./test_proc
#include "proc.hpp"

#include <cstdio>
#include <string>

using namespace lg::proc;

static int failures = 0;
#define CHECK(cond)                                                     \
  do {                                                                  \
    if (!(cond)) { std::printf("FAIL: %s (line %d)\n", #cond, __LINE__); ++failures; } \
  } while (0)

int main() {
  // small round-trip through cat
  {
    result r = run({"/bin/cat"}, "TRF0001  000000000042");
    CHECK(r.status == 0);
    CHECK(r.out == "TRF0001  000000000042");
  }
  // empty input
  {
    result r = run({"/bin/cat"}, "");
    CHECK(r.status == 0);
    CHECK(r.out.empty());
  }
  // large stdout must not deadlock against unread stdin (1 MiB through cat)
  {
    std::string big(1u << 20, 'x');
    result r = run({"/bin/cat"}, big);
    CHECK(r.status == 0);
    CHECK(r.out.size() == big.size());
  }
  // nonzero exit is reported
  {
    result r = run({"/bin/sh", "-c", "exit 3"}, "");
    CHECK(r.status == 3);
  }
  // exec failure surfaces as a nonzero (127) status, not a crash
  {
    result r = run({"/no/such/binary/legacygoat"}, "");
    CHECK(r.status == 127);
  }
  // max_out enforced
  {
    bool threw = false;
    try {
      run({"/bin/sh", "-c", "head -c 100000 /dev/zero"}, "", 1024);
    } catch (const spawn_error&) { threw = true; }
    CHECK(threw);
  }

  if (failures == 0) std::printf("all proc tests passed\n");
  return failures == 0 ? 0 : 1;
}
