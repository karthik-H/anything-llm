// mock-routes.js
// Central registry of all HTTP route handlers used by the mock server.
//
// Every handler receives (req, res, url) where `url` is a WHATWG URL object.
// Add one entry per route: `"METHOD /path": handlerFn`
//
// Keep mock DATA here and import it from mock-data.js.
// Test files must NOT contain mock data directly.

import {
  MOCK_HEALTH,
  MOCK_AUTH_USER,
  MOCK_WORKSPACES,
} from "./mock-data.js";

/**
 * Helper – send a JSON response.
 */
function json(res, statusCode, body) {
  const payload = JSON.stringify(body);
  res.writeHead(statusCode, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(payload),
    "Access-Control-Allow-Origin": "*",
  });
  res.end(payload);
}

/**
 * Returns the route map consumed by mock-server.js.
 * Each key is `"METHOD /path"`.
 */
export function getRoutes() {
  return {
    // ── Health ────────────────────────────────────────────────────────────
    "GET /api/health": (_req, res) => {
      json(res, 200, MOCK_HEALTH);
    },

    // ── Auth ──────────────────────────────────────────────────────────────
    "GET /api/v1/auth": (_req, res) => {
      json(res, 200, MOCK_AUTH_USER);
    },

    // ── Workspaces ────────────────────────────────────────────────────────
    "GET /api/v1/workspaces": (_req, res) => {
      json(res, 200, MOCK_WORKSPACES);
    },

    // ── CORS pre-flight (broad catch-all for OPTIONS) ─────────────────────
    "OPTIONS /": (_req, res) => {
      res.writeHead(204, {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type,Authorization",
      });
      res.end();
    },
  };
}
