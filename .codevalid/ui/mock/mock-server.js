// mock-server.js
// Lightweight HTTP mock server for AnythingLLM UI tests.
//
// Usage in tests (after importing):
//   import { startMockServer, stopMockServer } from "../../mock/mock-server.js";
//
//   test.beforeAll(async () => { await startMockServer(); });
//   test.afterAll(async  () => { await stopMockServer();  });
//
// All route handlers (mock data) live in mock-routes.js.
// This file only wires up the server lifecycle; tests must NOT contain data.

import http from "http";
import { getRoutes } from "./mock-routes.js";

const DEFAULT_PORT = process.env.MOCK_SERVER_PORT
  ? parseInt(process.env.MOCK_SERVER_PORT, 10)
  : 4001;

let server = null;

/**
 * Start the mock server on `port` (default: 4001).
 * Returns a Promise that resolves once the server is listening.
 */
export function startMockServer(port = DEFAULT_PORT) {
  if (server) {
    return Promise.resolve(server);
  }

  const routes = getRoutes();

  server = http.createServer((req, res) => {
    const url = new URL(req.url, `http://localhost:${port}`);
    const key = `${req.method} ${url.pathname}`;

    const handler = routes[key];
    if (handler) {
      handler(req, res, url);
    } else {
      // Default: 404 with JSON body
      res.writeHead(404, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Not found", path: url.pathname }));
    }
  });

  return new Promise((resolve, reject) => {
    server.listen(port, "0.0.0.0", () => {
      console.log(`[mock-server] Listening on http://localhost:${port}`);
      resolve(server);
    });
    server.on("error", reject);
  });
}

/**
 * Gracefully shut down the mock server.
 */
export function stopMockServer() {
  if (!server) {
    return Promise.resolve();
  }

  return new Promise((resolve, reject) => {
    server.close((err) => {
      server = null;
      if (err) {
        reject(err);
      } else {
        console.log("[mock-server] Stopped.");
        resolve();
      }
    });
  });
}
