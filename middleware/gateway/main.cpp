// Gateway: the public REST entry point and the transfer-flow orchestrator. It is non-vulnerable by
// construction -- it only routes, marshals, threads config, and mints the transfer_id correlation key.
// It runs no SQL and enforces no authorization (that lives in the modules: Pascal for the session,
// COBOL for branch scope / status / maker-checker).
//
// Public routes (called by the Pascal console):
//   GET  /healthz       -> "ok"
//   POST /authenticate  -> proxied to the COBOL core (staff.authenticate)
//   POST /transfer      -> the orchestration below (transfer.request -> transfer.response)
//   POST /cash          -> teller cash deposit/withdrawal (cash.request -> cash.response)
//   POST /inquiry       -> proxied to the COBOL core (account.inquiry)
//   POST /statement     -> proxied to the COBOL core (account.statement)
//   POST /maintenance   -> proxied to the COBOL core (account.maintenance)
//
// Transfer orchestration (happy path): mint transfer_id, call the COBOL core to validate + post the
// double entry; if it POSTED, fan out to Fortran (fee/interest), SAS (posting report) and ABAP (GL
// document), then aggregate everything into transfer.response. PENDING/REJECTED short-circuit.
// Cash runs the same way without the fee: the core posts against the branch cash account, then SAS
// reports it and ABAP books the GL document.
//
// The acting principal (actor) is supplied by the console -- which owns the session and resolved the
// token -- in the X-Staff-Id / X-Role / X-Branch headers. The gateway passes it straight through to
// the COBOL core, which does the actual authorization. `require_approval_over` comes from the
// environment (each profile sets it) and is threaded into the core call.
#include "httplib.h"
#include "json.hpp"

#include <cstdlib>
#include <ctime>
#include <mutex>
#include <stdexcept>
#include <string>

using json = nlohmann::json;

namespace {

std::string env_or(const char* name, const std::string& dflt) {
  const char* v = std::getenv(name);
  return (v && *v) ? std::string(v) : dflt;
}

// Service base URLs (scheme://host:port). Compose sets these; defaults match the compose service names.
const std::string COBOL_URL   = env_or("COBOL_URL",   "http://cobol:8080");
const std::string FORTRAN_URL = env_or("FORTRAN_URL", "http://fortran:8080");
const std::string SAS_URL     = env_or("SAS_URL",     "http://sas:8080");
const std::string ABAP_URL    = env_or("ABAP_URL",    "http://abap:8080");

// Config knobs threaded into module calls (config.schema.json), read from the environment.
const std::string REQUIRE_APPROVAL_OVER = env_or("REQUIRE_APPROVAL_OVER", "10000.00");
const std::string DEFAULT_RATE_CODE     = env_or("RATE_CODE", "STD");

// A downstream call failed; carries an HTTP status to surface to the caller.
struct upstream_error {
  int status;
  std::string message;
};

// YYYY-MM-DDThh:mm:ssZ, UTC, second precision (contracts Timestamp).
std::string now_iso8601() {
  std::time_t t = std::time(nullptr);
  std::tm tm{};
  gmtime_r(&t, &tm);
  char buf[32];
  std::strftime(buf, sizeof buf, "%Y-%m-%dT%H:%M:%SZ", &tm);
  return buf;
}

// transfer_id: "T" + YYYYMMDDHHMMSS + 4-digit in-process sequence (19 chars, so a posting id with
// its D/C suffix fits 20; ^[A-Z0-9]$). Unique unless 10000 are minted within one second.
std::string mint_transfer_id() {
  static std::mutex m;
  static int seq = 0;
  std::lock_guard<std::mutex> lock(m);
  int n = seq++ % 10000;
  std::time_t t = std::time(nullptr);
  std::tm tm{};
  gmtime_r(&t, &tm);
  char buf[32];
  std::strftime(buf, sizeof buf, "T%Y%m%d%H%M%S", &tm);
  char out[24];
  std::snprintf(out, sizeof out, "%s%04d", buf, n);
  return out;
}

// POST `body` to `base`+`path`, expecting a JSON 200. Throws upstream_error otherwise.
json post_json(const std::string& base, const std::string& path, const json& body) {
  httplib::Client cli(base.c_str());
  cli.set_connection_timeout(5, 0);
  cli.set_read_timeout(30, 0);
  auto res = cli.Post(path.c_str(), body.dump(), "application/json");
  if (!res) throw upstream_error{502, base + path + ": unreachable"};
  if (res->status != 200) throw upstream_error{502, base + path + ": HTTP " + std::to_string(res->status)};
  try {
    return json::parse(res->body);
  } catch (const std::exception& e) {
    throw upstream_error{502, base + path + ": bad JSON reply"};
  }
}

// A call made after the core has posted. The posting stands whatever happens here, so a failure
// becomes a note in the reply rather than an error the caller could take for a failed posting.
bool post_after_posting(const std::string& base, const std::string& path, const json& body, json& reply) {
  try {
    reply = post_json(base, path, body);
    return true;
  } catch (const upstream_error&) {
    return false;
  }
}

// Records the first downstream failure as the reply's reason.
void note(json& out, const char* reason) {
  if (!out.contains("reason")) out["reason"] = reason;
}

std::string S(const json& j, const char* k) { return j.at(k).get<std::string>(); }
std::string opt(const json& j, const char* k) {
  auto it = j.find(k);
  return (it != j.end() && it->is_string()) ? it->get<std::string>() : std::string();
}

// Build the two GL lines (debit from-account, credit to-account) for the balanced GL document.
json gl_lines(const std::string& from, const std::string& to, const std::string& amount) {
  return json::array({
      json{{"account_id", from}, {"direction", "D"}, {"amount", amount}},
      json{{"account_id", to},   {"direction", "C"}, {"amount", amount}},
  });
}

void send_json(httplib::Response& res, int status, const json& body) {
  res.status = status;
  res.set_content(body.dump(), "application/json");
}

// The transfer orchestration. `req` is a validated transfer.request; actor comes from headers.
json orchestrate_transfer(const json& req, const json& actor) {
  const std::string from     = S(req, "from_account");
  const std::string to       = S(req, "to_account");
  const std::string amount   = S(req, "amount");
  const std::string currency = S(req, "currency");
  const std::string reqby    = S(req, "requested_by");

  const std::string transfer_id  = mint_transfer_id();
  const std::string requested_at = now_iso8601();

  // 1) COBOL core: validate (status/branch/currency/funds) + post the double entry.
  json core_req = {
      {"transfer_id", transfer_id},
      {"from_account", from},
      {"to_account", to},
      {"amount", amount},
      {"currency", currency},
      {"requested_by", reqby},
      {"requested_at", requested_at},
      {"actor", actor},
      {"require_approval_over", REQUIRE_APPROVAL_OVER},
  };
  json core = post_json(COBOL_URL, "/post-transfer", core_req);
  const std::string status = S(core, "status");

  json out = {{"transfer_id", transfer_id}, {"status", status}};
  if (!opt(core, "reason").empty()) out["reason"] = opt(core, "reason");

  // PENDING (needs supervisor approval) and REJECTED short-circuit: no downstream posting.
  if (status != "POSTED") return out;

  if (!opt(core, "from_balance").empty()) out["from_balance"] = core.at("from_balance");
  if (!opt(core, "to_balance").empty())   out["to_balance"]   = core.at("to_balance");
  const std::string account_type = opt(core, "account_type");

  // 2) Fortran: fee / interest / net for the posted amount.
  json fee_req = {
      {"transfer_id", transfer_id},
      {"amount", amount},
      {"currency", currency},
      {"account_type", account_type.empty() ? "CHK" : account_type},
      {"term_days", 0},
      {"rate_code", DEFAULT_RATE_CODE},
  };
  json fee;
  if (post_after_posting(FORTRAN_URL, "/compute-fee", fee_req, fee) && fee.contains("fee")) {
    out["fee"]        = fee.at("fee");
    out["interest"]   = fee.at("interest");
    out["net_amount"] = fee.at("net_amount");
  } else {
    note(out, "FEE NOT COMPUTED");
  }

  // 3) SAS: posting report for this transfer.
  json rpt_req = {
      {"transfer_id", transfer_id},
      {"report_type", "POSTING"},
      {"as_of", now_iso8601()},
  };
  json rpt;
  if (post_after_posting(SAS_URL, "/report", rpt_req, rpt) && rpt.contains("rows"))
    out["report"] = rpt.at("rows");
  else
    note(out, "POSTING REPORT UNAVAILABLE");

  // 4) ABAP: post the GL document (balanced two-line entry), reference = transfer_id.
  json gl_req = {
      {"reference", transfer_id},
      {"currency", currency},
      {"posting_date", now_iso8601()},
      {"lines", gl_lines(from, to, amount)},
  };
  json gl;
  if (post_after_posting(ABAP_URL, "/gl", gl_req, gl) && !opt(gl, "gl_doc_id").empty())
    out["gl_doc_id"] = gl.at("gl_doc_id");
  else
    note(out, "GL DOCUMENT NOT POSTED");

  return out;
}

// Teller cash: the core posts the deposit or withdrawal; a POSTED one gets its report and GL document.
json orchestrate_cash(const json& req, const json& actor) {
  const std::string account  = S(req, "account_id");
  const std::string action   = S(req, "action");
  const std::string amount   = S(req, "amount");
  const std::string currency = S(req, "currency");
  if (action != "DEPOSIT" && action != "WITHDRAW")
    throw std::invalid_argument("action must be DEPOSIT or WITHDRAW");

  const std::string transfer_id = mint_transfer_id();

  json core_req = {
      {"transfer_id", transfer_id},
      {"account_id", account},
      {"action", action},
      {"amount", amount},
      {"currency", currency},
      {"actor", actor},
  };
  json core = post_json(COBOL_URL, "/cash", core_req);
  const std::string status = S(core, "status");

  json out = {{"transfer_id", transfer_id}, {"status", status}, {"account_id", account}};
  if (!opt(core, "reason").empty()) out["reason"] = opt(core, "reason");
  if (status != "POSTED") return out;

  const std::string cash_account = S(core, "cash_account");
  out["cash_account"] = cash_account;
  if (!opt(core, "balance").empty()) out["balance"] = core.at("balance");

  json rpt_req = {
      {"transfer_id", transfer_id},
      {"report_type", "POSTING"},
      {"as_of", now_iso8601()},
  };
  json rpt;
  if (post_after_posting(SAS_URL, "/report", rpt_req, rpt) && rpt.contains("rows"))
    out["report"] = rpt.at("rows");
  else
    note(out, "POSTING REPORT UNAVAILABLE");

  // A deposit debits the branch cash account; a withdrawal credits it.
  const bool deposit = action == "DEPOSIT";
  json gl_req = {
      {"reference", transfer_id},
      {"currency", currency},
      {"posting_date", now_iso8601()},
      {"lines", deposit ? gl_lines(cash_account, account, amount)
                        : gl_lines(account, cash_account, amount)},
  };
  json gl;
  if (post_after_posting(ABAP_URL, "/gl", gl_req, gl) && !opt(gl, "gl_doc_id").empty())
    out["gl_doc_id"] = gl.at("gl_doc_id");
  else
    note(out, "GL DOCUMENT NOT POSTED");

  return out;
}

// The acting principal from the console's headers; false (after answering 401) when one is missing.
bool read_actor(const httplib::Request& req, httplib::Response& res, json& actor) {
  if (!req.has_header("X-Staff-Id") || !req.has_header("X-Role") || !req.has_header("X-Branch")) {
    send_json(res, 401, json{{"error", "missing actor (X-Staff-Id/X-Role/X-Branch)"}});
    return false;
  }
  actor = {
      {"staff_id", req.get_header_value("X-Staff-Id")},
      {"role", req.get_header_value("X-Role")},
      {"branch", req.get_header_value("X-Branch")},
  };
  return true;
}

// A console account op the core answers directly: account_id (+ action) and the actor, passed through.
json account_op(const char* path, const json& req, const json& actor, bool with_action) {
  json core_req = {{"account_id", S(req, "account_id")}, {"actor", actor}};
  if (with_action) core_req["action"] = S(req, "action");
  return post_json(COBOL_URL, path, core_req);
}

}  // namespace

int main() {
  httplib::Server svr;

  svr.Get("/healthz", [](const httplib::Request&, httplib::Response& res) {
    res.set_content("ok", "text/plain");
  });

  // Login step 1: verify the credential against the COBOL core. The console mints the token.
  svr.Post("/authenticate", [](const httplib::Request& req, httplib::Response& res) {
    try {
      json body = json::parse(req.body);
      json reply = post_json(COBOL_URL, "/authenticate", body);
      send_json(res, 200, reply);
    } catch (const upstream_error& e) {
      send_json(res, e.status, json{{"error", e.message}});
    } catch (const std::exception& e) {
      send_json(res, 400, json{{"error", std::string("bad request: ") + e.what()}});
    }
  });

  // Every console op carries the actor the console resolved from its session, as headers.
  using op_fn = json (*)(const json&, const json&);
  const struct {
    const char* path;
    op_fn run;
  } ops[] = {
      {"/transfer", orchestrate_transfer},
      {"/cash", orchestrate_cash},
      {"/inquiry", [](const json& b, const json& a) { return account_op("/inquiry", b, a, false); }},
      {"/statement", [](const json& b, const json& a) { return account_op("/statement", b, a, false); }},
      {"/maintenance", [](const json& b, const json& a) { return account_op("/maintenance", b, a, true); }},
  };
  for (const auto& op : ops) {
    op_fn run = op.run;
    svr.Post(op.path, [run](const httplib::Request& req, httplib::Response& res) {
      try {
        json body = json::parse(req.body);
        json actor;
        if (!read_actor(req, res, actor)) return;
        send_json(res, 200, run(body, actor));
      } catch (const upstream_error& e) {
        send_json(res, e.status, json{{"error", e.message}});
      } catch (const std::exception& e) {
        send_json(res, 400, json{{"error", std::string("bad request: ") + e.what()}});
      }
    });
  }

  svr.listen("0.0.0.0", 8080);
  return 0;
}
