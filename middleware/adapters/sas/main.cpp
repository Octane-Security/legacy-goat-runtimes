// SAS adapter: fronts the reporting shim over REST. Marshals report.posting.request JSON to the
// REPORT-REQUEST record, drives the Python shim (which runs the PROC SQL pass-through against
// Postgres), and assembles the REPORT-ROW lines into report.posting.response. Non-vulnerable.
#include "httplib.h"
#include "json.hpp"

#include "marshal.hpp"
#include "proc.hpp"

#include <string>

using json = nlohmann::json;
using namespace lg::marshal;

namespace {

std::string S(const json& j, const char* k) { return j.at(k).get<std::string>(); }

// report.posting.request -> REPORT-REQUEST (48 chars).
std::string build_request(const json& j) {
  RecordWriter w;
  w.alnum(S(j, "transfer_id"), 20).alnum(S(j, "report_type"), 8).alnum(S(j, "as_of"), 20);
  return w.str();
}

// One REPORT-ROW (92 chars) -> PostingLine.
json parse_row(const std::string& line) {
  RecordReader r(line);
  json row;
  row["posting_id"] = r.alnum(20);
  row["transfer_id"] = r.alnum(20);
  row["account_id"] = r.alnum(12);
  row["direction"] = r.alnum(1);
  row["amount"] = format_money(r.money16(16));
  row["currency"] = r.alnum(3);
  row["posted_at"] = r.alnum(20);
  return row;
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

  // Report export: forwards the caller's export label to the SAS job's %SYSEXEC path (shim export
  // mode). The adapter only marshals -- it runs no shell itself; the OS-command sink is in the SAS
  // module (LG-CMDI-001), armed by report_archive.
  svr.Post("/export", [](const httplib::Request& req, httplib::Response& res) {
    try {
      json j = json::parse(req.body);
      std::string label = S(j, "export_label");
      lg::proc::result pr = lg::proc::run({"python3", "/app/shim.py", "export"}, label + "\n");
      if (pr.status != 0) return fail(res, 502, "sas export exited " + std::to_string(pr.status));
      json out_json;
      out_json["output"] = pr.out;
      res.set_content(out_json.dump(), "application/json");
    } catch (const std::exception& e) {
      fail(res, 400, std::string("bad request: ") + e.what());
    }
  });

  svr.Post("/report", [](const httplib::Request& req, httplib::Response& res) {
    try {
      json j = json::parse(req.body);
      std::string record = build_request(j);
      lg::proc::result pr = lg::proc::run({"python3", "/app/shim.py"}, record + "\n");
      if (pr.status != 0) return fail(res, 502, "sas shim exited " + std::to_string(pr.status));
      json rows = json::array();
      std::string out = pr.out, line;
      size_t start = 0;
      while (start <= out.size()) {
        size_t nl = out.find('\n', start);
        line = out.substr(start, nl == std::string::npos ? std::string::npos : nl - start);
        while (!line.empty() && (line.back() == '\r')) line.pop_back();
        if (line.size() == 92) rows.push_back(parse_row(line));
        if (nl == std::string::npos) break;
        start = nl + 1;
      }
      json out_json;
      out_json["transfer_id"] = S(j, "transfer_id");
      out_json["report_type"] = S(j, "report_type");
      out_json["rows"] = rows;
      res.set_content(out_json.dump(), "application/json");
    } catch (const field_error& e) {
      fail(res, 400, e.what());
    } catch (const std::exception& e) {
      fail(res, 400, std::string("bad request: ") + e.what());
    }
  });

  svr.listen("0.0.0.0", 8080);
  return 0;
}
