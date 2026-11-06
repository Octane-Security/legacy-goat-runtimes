// ABAP runtime ICF shim. ABAP speaks HTTP natively, so there is NO C++ adapter: this
// Node server bridges HTTP <-> the transpiled IF_HTTP_EXTENSION~HANDLE_REQUEST handler.
//
// Loads ./bundle-core.mjs (sets globalThis.abap, registers all classes), then for each
// request builds a plain-JS ICF `server` object shaped exactly like the calls the
// transpiled handler makes -- request->get_cdata(), response->set_cdata/set_status/
// set_header_field -- invokes the handler, and returns its captured response.
import { createServer } from "node:http";

await import("./bundle-core.mjs");

const PORT = Number(process.env.PORT) || 8080;

// The route -> ABAP handler class map. One handler today (GL posting); add rows as the
// benchmark grows. Each class must implement IF_HTTP_EXTENSION.
const ROUTES = { "/gl": "ZCL_GL_POST" };

// open-abap wraps scalars in typed objects with .get(); unwrap defensively.
const g = (v) => (v && typeof v.get === "function" ? v.get() : v);

async function invokeHandler(className, requestBody) {
  let responseBody = "";
  let statusCode = 200;
  let contentType = "application/json";

  // Per-request ICF headers. The profile's config flags are threaded in here (compose passes
  // them as env) and surface to the handler exactly like a real ICF request header would.
  const headers = { "x-preformatted-refs": (process.env.PREFORMATTED_REFS || "off").toLowerCase() };
  const request = {
    if_http_entity$get_cdata: async () => requestBody,
    if_http_entity$get_header_field: async (p) => headers[String(g(p.name)).toLowerCase()] || "",
  };
  const response = {
    if_http_entity$set_header_field: async (p) => {
      if (String(g(p.name)).toLowerCase() === "content-type") contentType = g(p.value);
    },
    if_http_response$set_status: async (p) => { statusCode = Number(g(p.code)) || statusCode; },
    if_http_entity$set_cdata: async (p) => { responseBody = g(p.data); },
  };
  const server = {
    if_http_server$request: { get: () => request },
    if_http_server$response: { get: () => response },
  };

  const cls = globalThis.abap.Classes[className];
  if (!cls) throw new Error(`ABAP class ${className} not registered`);
  const inst = new cls();
  if (typeof inst.constructor_ === "function") await inst.constructor_();
  await inst.if_http_extension$handle_request({ server });
  return { statusCode, contentType, responseBody };
}

const readBody = (req) => new Promise((resolve, reject) => {
  let b = "";
  req.on("data", (c) => { b += c; });
  req.on("end", () => resolve(b));
  req.on("error", reject);
});

createServer(async (req, res) => {
  try {
    if (req.method === "GET" && req.url === "/healthz") {
      res.writeHead(200, { "content-type": "text/plain" });
      res.end("ok");
      return;
    }
    const cls = req.method === "POST" ? ROUTES[req.url] : undefined;
    if (cls) {
      const body = await readBody(req);
      const { statusCode, contentType, responseBody } = await invokeHandler(cls, body);
      res.writeHead(statusCode, { "content-type": contentType || "application/json" });
      res.end(responseBody);
      return;
    }
    res.writeHead(404, { "content-type": "text/plain" });
    res.end("not found");
  } catch (e) {
    // A handler crash must not take the service down; report 500 and keep serving.
    res.writeHead(500, { "content-type": "text/plain" });
    res.end("abap shim error: " + (e && e.message ? e.message : String(e)));
  }
}).listen(PORT, () => console.log(`[abap] ICF shim listening on :${PORT} (POST ${Object.keys(ROUTES).join(", ")})`));
