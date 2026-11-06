// Unit tests for marshal.hpp. Build: clang++ -std=c++17 -o test_marshal test_marshal.cpp && ./test_marshal
#include "marshal.hpp"

#include <cassert>
#include <cstdio>
#include <string>

using namespace lg::marshal;

static int failures = 0;
#define CHECK(cond)                                                     \
  do {                                                                  \
    if (!(cond)) { std::printf("FAIL: %s (line %d)\n", #cond, __LINE__); ++failures; } \
  } while (0)

template <typename F>
static bool throws(F f) {
  try { f(); return false; } catch (const field_error&) { return true; }
}

int main() {
  // COMP-3 exact layout: 150000 cents in S9(13)V99 (15 digits) -> 8 bytes 00 00 00 00 01 50 00 0C
  {
    std::string p = pack_comp3(150000, 15);
    CHECK(p.size() == 8);
    const unsigned char want[8] = {0x00, 0x00, 0x00, 0x00, 0x01, 0x50, 0x00, 0x0C};
    for (int i = 0; i < 8; ++i) CHECK(static_cast<unsigned char>(p[i]) == want[i]);
  }
  // COMP-3 negative sign nibble is 0x0D
  {
    std::string p = pack_comp3(-1, 15);
    CHECK((static_cast<unsigned char>(p.back()) & 0x0F) == 0x0D);
  }
  // COMP-3 round-trip across a range
  for (int64_t v : {int64_t(0), int64_t(1), int64_t(-1), int64_t(150000), int64_t(-1230099),
                    int64_t(999999999999999), int64_t(-999999999999999)}) {
    CHECK(unpack_comp3(pack_comp3(v, 15), 15) == v);
  }
  // COMP-3 overflow throws (16 digits into a 15-digit field)
  CHECK(throws([] { pack_comp3(int64_t(1000000000000000), 15); }));
  // COMP-3 even-digit field carries a leading pad nibble, still round-trips
  CHECK(unpack_comp3(pack_comp3(1234, 4), 4) == 1234);

  // money parse/format
  CHECK(parse_money("1500.00") == 150000);
  CHECK(parse_money("0.01") == 1);
  CHECK(parse_money("-12.00") == -1200);
  CHECK(parse_money("9999999999999.99") == 999999999999999);
  CHECK(format_money(150000) == "1500.00");
  CHECK(format_money(1) == "0.01");
  CHECK(format_money(-1200) == "-12.00");
  CHECK(format_money(0) == "0.00");
  // money round-trip
  for (const char* s : {"1500.00", "0.00", "0.01", "-12.34", "9999999999999.99"})
    CHECK(format_money(parse_money(s)) == s);
  // malformed money rejected
  for (const char* s : {"1500", "1500.0", "1500.000", "12345678901234.00", "1500.0a", ".00"})
    CHECK(throws([&] { parse_money(s); }));

  // money_text 16-col right-justified + round-trip
  CHECK(money_text(150000, 16) == "         1500.00");
  CHECK(parse_money_text("         1500.00") == 150000);
  CHECK(throws([] { money_text(999999999999999, 10); }));  // wider than field

  // alnum pad/trim + width check
  CHECK(pad_alnum("USD", 3) == "USD");
  CHECK(pad_alnum("US", 3) == "US ");
  CHECK(trim_alnum("US  ") == "US");
  CHECK(throws([] { pad_alnum("USDX", 3); }));
  CHECK(int_zeropad(30, 5) == "00030");

  // full TRANSFER-REQUEST (85 bytes) round-trip
  {
    std::string rec = RecordWriter()
                          .alnum("TRF20260925000001", 20)
                          .alnum("000000000042", 12)
                          .alnum("000000000043", 12)
                          .comp3(150000, 15)
                          .alnum("USD", 3)
                          .alnum("0000000007", 10)
                          .alnum("2026-09-25T14:00:00Z", 20)
                          .str();
    CHECK(rec.size() == 85);
    RecordReader r(rec);
    CHECK(r.alnum(20) == "TRF20260925000001");
    CHECK(r.alnum(12) == "000000000042");
    CHECK(r.alnum(12) == "000000000043");
    CHECK(r.comp3(15) == 150000);
    CHECK(r.alnum(3) == "USD");
    CHECK(r.alnum(10) == "0000000007");
    CHECK(r.alnum(20) == "2026-09-25T14:00:00Z");
    CHECK(r.remaining() == 0);
  }

  // full TRANSFER-REPLY (127 bytes) size
  {
    std::string rec = RecordWriter()
                          .alnum("TRF20260925000001", 20)
                          .alnum("POSTED", 8)
                          .alnum("", 40)
                          .alnum("P0000000000000000001", 20)
                          .alnum("P0000000000000000002", 20)
                          .comp3(850000, 15)
                          .comp3(1150000, 15)
                          .alnum("CHK", 3)
                          .str();
    CHECK(rec.size() == 127);
  }

  if (failures == 0) std::printf("all marshal tests passed\n");
  return failures == 0 ? 0 : 1;
}
