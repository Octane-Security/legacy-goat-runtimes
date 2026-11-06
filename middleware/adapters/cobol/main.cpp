// COBOL adapter: fronts the COBOL core programs over REST. Translates REST/JSON to the fixed-width
// TEXT interchange records (transfer-io.cpy / core-ops.cpy) and drives the compiled COBOL binaries
// over stdin/stdout. Non-vulnerable by construction: every field is length-checked (marshal.hpp),
// and the adapter runs no SQL of its own. The COBOL binaries live at /app/<name>. One program runs
// at a time, so concurrent requests never interleave their reads and rewrites of the account master.
#include "httplib.h"
#include "json.hpp"

#include "marshal.hpp"
#include "proc.hpp"

#include <cctype>
#include <functional>
#include <mutex>
#include <string>

using json = nlohmann::json;
using namespace lg::marshal;

namespace {

std::string S(const json& j, const char* k) { return j.at(k).get<std::string>(); }

// Strip a trailing newline from a module reply and pad/truncate to the record width.
std::string fit(std::string s, size_t n) {
  while (!s.empty() && (s.back() == '\n' || s.back() == '\r')) s.pop_back();
  if (s.size() < n) s.append(n - s.size(), ' ');
  return s.substr(0, n);
}

// core.post-transfer.request -> TRANSFER-REQUEST (163 bytes).
std::string build_transfer_request(const json& j) {
  const json& a = j.at("actor");
  RecordWriter w;
  w.alnum(S(j, "transfer_id"), 20)
      .alnum(S(j, "from_account"), 12)
      .alnum(S(j, "to_account"), 12)
      .money16(parse_money(S(j, "amount")), 16)
      .alnum(S(j, "currency"), 3)
      .alnum(S(j, "requested_by"), 40)
      .alnum(S(j, "requested_at"), 20)
      .alnum(S(a, "staff_id"), 10)
      .alnum(S(a, "role"), 10)
      .alnum(S(a, "branch"), 4)
      .money16(parse_money(S(j, "require_approval_over")), 16);
  return w.str();
}

// TRANSFER-REPLY (159 bytes) -> core.post-transfer.response.
json parse_transfer_reply(const std::string& rec) {
  RecordReader r(rec);
  json out;
  out["transfer_id"] = r.alnum(20);
  out["status"] = r.alnum(8);
  std::string reason = r.alnum(40);
  if (!reason.empty()) out["reason"] = reason;
  std::string dp = r.alnum(20);
  if (!dp.empty()) out["debit_posting"] = dp;
  std::string cp = r.alnum(20);
  if (!cp.empty()) out["credit_posting"] = cp;
  std::string fb = r.alnum_raw(16);  // right-justified money (leading spaces); blank when REJECTED
  if (fb.find_first_not_of(' ') != std::string::npos)
    out["from_balance"] = format_money(parse_money_text(fb));
  std::string tb = r.alnum_raw(16);
  if (tb.find_first_not_of(' ') != std::string::npos)
    out["to_balance"] = format_money(parse_money_text(tb));
  std::string at = r.alnum(3);
  if (!at.empty()) out["account_type"] = at;
  std::string tier = r.alnum(16);
  if (!tier.empty()) out["tier_label"] = tier;
  return out;
}

// staff.authenticate.request -> AUTH-REQUEST (74 bytes).
std::string build_auth_request(const json& j) {
  RecordWriter w;
  w.alnum(S(j, "staff_id"), 10).alnum(S(j, "password"), 64);
  return w.str();
}

// AUTH-REPLY (55 bytes) -> staff.authenticate.response.
json parse_auth_reply(const std::string& rec) {
  RecordReader r(rec);
  json out;
  out["authenticated"] = (r.alnum(1) == "Y");
  std::string role = r.alnum(10);
  if (!role.empty()) out["role"] = role;
  std::string br = r.alnum(4);
  if (!br.empty()) out["branch"] = br;
  std::string reason = r.alnum(40);
  if (!reason.empty()) out["reason"] = reason;
  return out;
}

// The resolved acting staff, as every smaller core-ops record carries it (core-ops.cpy XX-ACTOR-*).
void put_actor(RecordWriter& w, const json& j) {
  const json& a = j.at("actor");
  w.alnum(S(a, "staff_id"), 10).alnum(S(a, "role"), 10).alnum(S(a, "branch"), 4);
}

// Money from a right-justified text field; absent when the field is blank.
void put_money(json& out, const char* key, RecordReader& r) {
  std::string m = r.alnum_raw(16);
  if (m.find_first_not_of(' ') != std::string::npos) out[key] = format_money(parse_money_text(m));
}

void put_opt(json& out, const char* key, const std::string& v) {
  if (!v.empty()) out[key] = v;
}

// core.inquiry.request -> INQUIRY-REQUEST (36 bytes).
std::string build_inquiry_request(const json& j) {
  RecordWriter w;
  w.alnum(S(j, "account_id"), 12);
  put_actor(w, j);
  return w.str();
}

// INQUIRY-REPLY (164 bytes) -> core.inquiry.response.
json parse_inquiry_reply(const std::string& rec) {
  RecordReader r(rec);
  json out;
  out["account_id"] = r.alnum(12);
  out["result"] = r.alnum(8);
  put_opt(out, "reason", r.alnum(40));
  put_opt(out, "customer_id", r.alnum(10));
  put_opt(out, "customer_name", r.alnum(40));
  put_opt(out, "branch", r.alnum(4));
  put_opt(out, "account_type", r.alnum(3));
  put_opt(out, "currency", r.alnum(3));
  put_opt(out, "status", r.alnum(8));
  put_money(out, "balance", r);
  put_opt(out, "opened_at", r.alnum(20));
  return out;
}

// core.statement.request -> STATEMENT-REQUEST (36 bytes).
std::string build_statement_request(const json& j) {
  return build_inquiry_request(j);
}

// STATEMENT-REPLY (1411 bytes: 81 header + 10 x 133 lines) -> core.statement.response.
json parse_statement_reply(const std::string& rec) {
  RecordReader r(rec);
  json out;
  out["account_id"] = r.alnum(12);
  out["result"] = r.alnum(8);
  put_opt(out, "reason", r.alnum(40));
  put_opt(out, "currency", r.alnum(3));
  put_money(out, "balance", r);
  std::string count = r.alnum(2);
  size_t n = 0;
  if (count.size() == 2 && isdigit(static_cast<unsigned char>(count[0])) &&
      isdigit(static_cast<unsigned char>(count[1])))
    n = static_cast<size_t>(std::stoi(count));
  if (n > 10) throw field_error("statement: more than 10 lines");
  json lines = json::array();
  for (size_t i = 0; i < n; ++i) {
    json line;
    line["posting_id"] = r.alnum(20);
    line["transfer_id"] = r.alnum(20);
    line["direction"] = r.alnum(1);
    line["amount"] = format_money(parse_money_text(r.alnum_raw(16)));
    line["posted_at"] = r.alnum(20);
    put_opt(line, "description", r.alnum(40));
    line["balance_after"] = format_money(parse_money_text(r.alnum_raw(16)));
    lines.push_back(line);
  }
  out["lines"] = lines;
  return out;
}

// core.cash.request -> CASH-REQUEST (83 bytes).
std::string build_cash_request(const json& j) {
  RecordWriter w;
  w.alnum(S(j, "transfer_id"), 20)
      .alnum(S(j, "account_id"), 12)
      .alnum(S(j, "action"), 8)
      .money16(parse_money(S(j, "amount")), 16)
      .alnum(S(j, "currency"), 3);
  put_actor(w, j);
  return w.str();
}

// CASH-REPLY (136 bytes) -> core.cash.response.
json parse_cash_reply(const std::string& rec) {
  RecordReader r(rec);
  json out;
  out["transfer_id"] = r.alnum(20);
  out["status"] = r.alnum(8);
  put_opt(out, "reason", r.alnum(40));
  put_opt(out, "account_posting", r.alnum(20));
  put_opt(out, "cash_posting", r.alnum(20));
  put_opt(out, "cash_account", r.alnum(12));
  put_money(out, "balance", r);
  return out;
}

// core.acct-maintenance.request -> MAINT-REQUEST (44 bytes).
std::string build_maint_request(const json& j) {
  RecordWriter w;
  w.alnum(S(j, "account_id"), 12).alnum(S(j, "action"), 8);
  put_actor(w, j);
  return w.str();
}

// MAINT-REPLY (68 bytes) -> core.acct-maintenance.response.
json parse_maint_reply(const std::string& rec) {
  RecordReader r(rec);
  json out;
  out["account_id"] = r.alnum(12);
  out["result"] = r.alnum(8);
  put_opt(out, "status", r.alnum(8));
  put_opt(out, "reason", r.alnum(40));
  return out;
}

void fail(httplib::Response& res, int code, const std::string& msg) {
  res.status = code;
  res.set_content(json({{"error", msg}}).dump(), "application/json");
}

// Run a COBOL binary with `record` on stdin, return the reply fit to `width`.
bool drive(const char* bin, const std::string& record, size_t width, std::string& reply,
           std::string& err) {
  static std::mutex one_at_a_time;
  std::lock_guard<std::mutex> lock(one_at_a_time);
  try {
    lg::proc::result pr = lg::proc::run({bin}, record + "\n");
    if (pr.status != 0) { err = std::string(bin) + " exited " + std::to_string(pr.status); return false; }
    reply = fit(pr.out, width);
    return true;
  } catch (const std::exception& e) {
    err = e.what();
    return false;
  }
}

}  // namespace

int main() {
  httplib::Server svr;

  svr.Get("/healthz", [](const httplib::Request&, httplib::Response& res) {
    res.set_content("ok", "text/plain");
  });

  svr.Post("/authenticate", [](const httplib::Request& req, httplib::Response& res) {
    try {
      std::string record = build_auth_request(json::parse(req.body));
      std::string reply, err;
      if (!drive("/app/staffauth", record, 55, reply, err)) return fail(res, 502, err);
      res.set_content(parse_auth_reply(reply).dump(), "application/json");
    } catch (const field_error& e) {
      fail(res, 400, e.what());
    } catch (const std::exception& e) {
      fail(res, 400, std::string("bad request: ") + e.what());
    }
  });

  svr.Post("/post-transfer", [](const httplib::Request& req, httplib::Response& res) {
    try {
      std::string record = build_transfer_request(json::parse(req.body));
      std::string reply, err;
      if (!drive("/app/postxfer", record, 159, reply, err)) return fail(res, 502, err);
      res.set_content(parse_transfer_reply(reply).dump(), "application/json");
    } catch (const field_error& e) {
      fail(res, 400, e.what());
    } catch (const std::exception& e) {
      fail(res, 400, std::string("bad request: ") + e.what());
    }
  });

  // The smaller core ops: one COBOL program each, request record in, reply record out.
  struct core_op {
    const char* path;
    const char* bin;
    size_t width;
    std::function<std::string(const json&)> build;
    std::function<json(const std::string&)> parse;
  };
  const core_op ops[] = {
      {"/inquiry", "/app/acctinq", 164, build_inquiry_request, parse_inquiry_reply},
      {"/statement", "/app/acctstmt", 1411, build_statement_request, parse_statement_reply},
      {"/cash", "/app/cashpost", 136, build_cash_request, parse_cash_reply},
      {"/maintenance", "/app/acctmnt", 68, build_maint_request, parse_maint_reply},
  };
  for (const core_op& op : ops) {
    svr.Post(op.path, [op](const httplib::Request& req, httplib::Response& res) {
      try {
        std::string record = op.build(json::parse(req.body));
        std::string reply, err;
        if (!drive(op.bin, record, op.width, reply, err)) return fail(res, 502, err);
        res.set_content(op.parse(reply).dump(), "application/json");
      } catch (const field_error& e) {
        fail(res, 400, e.what());
      } catch (const std::exception& e) {
        fail(res, 400, std::string("bad request: ") + e.what());
      }
    });
  }

  svr.listen("0.0.0.0", 8080);
  return 0;
}
