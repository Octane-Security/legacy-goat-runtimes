// Fortran adapter: fronts the risk/fee module over REST. Marshals risk.compute-fee JSON to the
// fixed-text RISK-FEE record (records/fortran-fee-io.md) and drives the compiled Fortran binary over
// stdin/stdout. Non-vulnerable: every field length-checked (marshal.hpp). Binary at /app/riskfee.
#include "httplib.h"
#include "json.hpp"

#include "marshal.hpp"
#include "proc.hpp"

#include <string>

using json = nlohmann::json;
using namespace lg::marshal;

namespace {

std::string S(const json& j, const char* k) { return j.at(k).get<std::string>(); }

std::string fit(std::string s, size_t n) {
  while (!s.empty() && (s.back() == '\n' || s.back() == '\r')) s.pop_back();
  if (s.size() < n) s.append(n - s.size(), ' ');
  return s.substr(0, n);
}

// risk.compute-fee.request -> RISK-FEE-REQUEST (51 chars).
std::string build_request(const json& j) {
  RecordWriter w;
  w.alnum(S(j, "transfer_id"), 20)
      .money16(parse_money(S(j, "amount")), 16)
      .alnum(S(j, "currency"), 3)
      .alnum(S(j, "account_type"), 3)
      .zint(j.at("term_days").get<long long>(), 5)
      .alnum(S(j, "rate_code"), 4);
  return w.str();
}

// RISK-FEE-REPLY (76 chars) -> risk.compute-fee.response.
json parse_reply(const std::string& rec) {
  RecordReader r(rec);
  json out;
  out["transfer_id"] = r.alnum(20);
  out["fee"] = format_money(r.money16(16));
  out["interest"] = format_money(r.money16(16));
  out["net_amount"] = format_money(r.money16(16));
  out["status"] = r.alnum(8);
  return out;
}

void fail(httplib::Response& res, int code, const std::string& msg) {
  res.status = code;
  res.set_content(json({{"error", msg}}).dump(), "application/json");
}

}  // namespace

int main() {
  httplib::Server svr;

  svr.Get("/healthz", [](const httplib::Request&, httplib::Response& res) {
    res.set_content("ok", "text/plain");
  });

  svr.Post("/compute-fee", [](const httplib::Request& req, httplib::Response& res) {
    try {
      std::string record = build_request(json::parse(req.body));
      lg::proc::result pr = lg::proc::run({"/app/riskfee"}, record + "\n");
      if (pr.status != 0) return fail(res, 502, "riskfee exited " + std::to_string(pr.status));
      res.set_content(parse_reply(fit(pr.out, 76)).dump(), "application/json");
    } catch (const field_error& e) {
      fail(res, 400, e.what());
    } catch (const std::exception& e) {
      fail(res, 400, std::string("bad request: ") + e.what());
    }
  });

  svr.listen("0.0.0.0", 8080);
  return 0;
}
