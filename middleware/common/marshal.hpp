// Length-checked marshalling between JSON values and the fixed-width native records the COBOL,
// Fortran and SAS modules read/write. Money is carried as integer cents end to end — never a float.
// Field widths and the COMP-3 layout come from legacy-goat/contracts/data-model.md.
#pragma once

#include <cstdint>
#include <stdexcept>
#include <string>
#include <vector>

namespace lg::marshal {

// A contract violation (over-width field, malformed money). Adapters map this to HTTP 400.
struct field_error : std::invalid_argument {
  using std::invalid_argument::invalid_argument;
};

// --- money as integer cents ---

// Parse a JSON money string ("-?[0-9]{1,13}.[0-9]{2}") to signed cents.
inline int64_t parse_money(const std::string& s) {
  size_t i = 0;
  bool neg = false;
  if (i < s.size() && s[i] == '-') { neg = true; ++i; }
  size_t dot = s.find('.', i);
  if (dot == std::string::npos) throw field_error("money: missing decimal point");
  size_t int_len = dot - i;
  if (int_len < 1 || int_len > 13) throw field_error("money: integer part 1..13 digits");
  if (s.size() - dot - 1 != 2) throw field_error("money: needs exactly 2 fraction digits");
  int64_t cents = 0;
  for (size_t k = i; k < s.size(); ++k) {
    if (k == dot) continue;
    char c = s[k];
    if (c < '0' || c > '9') throw field_error("money: non-digit");
    cents = cents * 10 + (c - '0');
  }
  return neg ? -cents : cents;
}

// Format signed cents as a JSON money string with exactly 2 fraction digits.
inline std::string format_money(int64_t cents) {
  bool neg = cents < 0;
  uint64_t m = neg ? static_cast<uint64_t>(-(cents + 1)) + 1 : static_cast<uint64_t>(cents);
  std::string frac = std::to_string(m % 100);
  if (frac.size() < 2) frac.insert(frac.begin(), '0');
  std::string out = std::to_string(m / 100) + "." + frac;
  return neg ? "-" + out : out;
}

// --- COMP-3 packed decimal ---

// Pack signed `value` into a COMP-3 field of `digits` total digits.
// Sign nibble 0x0C (>=0) / 0x0D (<0); size is ceil((digits+1)/2) bytes.
inline std::string pack_comp3(int64_t value, int digits) {
  if (digits < 1 || digits > 18) throw field_error("comp3: digits out of range");
  bool neg = value < 0;
  uint64_t m = neg ? static_cast<uint64_t>(-(value + 1)) + 1 : static_cast<uint64_t>(value);
  std::vector<uint8_t> nb;
  if ((digits + 1) % 2 == 1) nb.push_back(0);  // leading pad nibble when digits is even
  std::vector<uint8_t> ds(digits, 0);
  for (int k = digits - 1; k >= 0; --k) { ds[k] = m % 10; m /= 10; }
  if (m != 0) throw field_error("comp3: value exceeds field width");
  for (uint8_t d : ds) nb.push_back(d);
  nb.push_back(neg ? 0x0D : 0x0C);
  std::string out;
  for (size_t k = 0; k + 1 < nb.size(); k += 2)
    out.push_back(static_cast<char>((nb[k] << 4) | nb[k + 1]));
  return out;
}

// Unpack a COMP-3 field of `digits` digits.
inline int64_t unpack_comp3(const std::string& bytes, int digits) {
  if (digits < 1 || digits > 18) throw field_error("comp3: digits out of range");
  size_t want = static_cast<size_t>((digits + 1 + 1) / 2);  // ceil((digits+1)/2)
  if (bytes.size() != want) throw field_error("comp3: wrong field length");
  std::vector<uint8_t> nb;
  for (unsigned char b : bytes) { nb.push_back(b >> 4); nb.push_back(b & 0x0F); }
  size_t start = ((digits + 1) % 2 == 1) ? 1 : 0;  // skip leading pad nibble when present
  int64_t val = 0;
  for (int k = 0; k < digits; ++k) val = val * 10 + nb[start + k];
  return (nb[start + digits] == 0x0D) ? -val : val;
}

// --- fixed-width text fields ---

// Left-justify into `width`, space-padded. Throws if `s` is wider than the field.
inline std::string pad_alnum(const std::string& s, size_t width) {
  if (s.size() > width) throw field_error("field wider than " + std::to_string(width));
  return s + std::string(width - s.size(), ' ');
}

// Drop trailing spaces from a fixed field.
inline std::string trim_alnum(const std::string& s) {
  size_t end = s.find_last_not_of(' ');
  return end == std::string::npos ? std::string() : s.substr(0, end + 1);
}

// Right-justify money cents into `width` columns (e.g. "         1500.00").
inline std::string money_text(int64_t cents, size_t width) {
  std::string s = format_money(cents);
  if (s.size() > width) throw field_error("money wider than " + std::to_string(width));
  return std::string(width - s.size(), ' ') + s;
}

// Parse a right-justified money text field back to cents (padding is leading spaces).
inline int64_t parse_money_text(const std::string& field) {
  size_t b = field.find_first_not_of(' ');
  if (b == std::string::npos) throw field_error("money field is blank");
  size_t e = field.find_last_not_of(' ');
  return parse_money(field.substr(b, e - b + 1));
}

// Zero-pad a non-negative integer into `width` columns (e.g. term_days I5 -> "00030").
inline std::string int_zeropad(int64_t value, size_t width) {
  if (value < 0) throw field_error("int_zeropad: negative");
  std::string s = std::to_string(value);
  if (s.size() > width) throw field_error("int wider than " + std::to_string(width));
  return std::string(width - s.size(), '0') + s;
}

// --- record buffer helpers ---

// Appends fields to a fixed-width record in copybook order; every put is bounds-checked.
class RecordWriter {
 public:
  RecordWriter& alnum(const std::string& s, size_t width) { buf_ += pad_alnum(s, width); return *this; }
  RecordWriter& comp3(int64_t value, int digits) { buf_ += pack_comp3(value, digits); return *this; }
  RecordWriter& money16(int64_t cents, size_t width = 16) { buf_ += money_text(cents, width); return *this; }
  RecordWriter& zint(int64_t value, size_t width) { buf_ += int_zeropad(value, width); return *this; }
  const std::string& str() const { return buf_; }

 private:
  std::string buf_;
};

// Reads fields from a fixed-width record by advancing a cursor; every get is bounds-checked.
class RecordReader {
 public:
  explicit RecordReader(std::string buf) : buf_(std::move(buf)) {}
  std::string alnum(size_t width) { return trim_alnum(take(width)); }
  std::string alnum_raw(size_t width) { return take(width); }
  int64_t comp3(int digits) { return unpack_comp3(take(static_cast<size_t>((digits + 2) / 2)), digits); }
  int64_t money16(size_t width = 16) { return parse_money_text(take(width)); }
  int64_t zint(size_t width) { return std::stoll(take(width)); }
  size_t remaining() const { return buf_.size() - pos_; }

 private:
  std::string take(size_t n) {
    if (pos_ + n > buf_.size()) throw field_error("record shorter than layout");
    std::string f = buf_.substr(pos_, n);
    pos_ += n;
    return f;
  }
  std::string buf_;
  size_t pos_ = 0;
};

}  // namespace lg::marshal
