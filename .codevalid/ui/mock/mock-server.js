/**
 * Mock API server for AnythingLLM UI testing.
 * Intercepts all API calls so the frontend can render without a real backend.
 * Runs on port 3001 to match VITE_API_BASE=http://localhost:3001/api
 */

import http from "http";
import { MOCK_AGENT_SKILL_STATUS_DEFAULTS } from "./mock-data.js";

const PORT = 3001;

/**
 * Mock responses keyed by method + path prefix.
 * All routes are under /api/
 */
const routes = {
  "GET /api/ping": () => ({ message: "pong", online: true }),

  // Auth / user system
  "GET /api/auth": () => ({
    authenticated: true,
    user: null,
  }),
  "POST /api/request-token": () => ({
    valid: true,
    user: {
      id: 1,
      username: "testuser",
      role: "admin",
      suspended: 0,
      createdAt: new Date().toISOString(),
    },
    token: "mock-jwt-token",
  }),
  "GET /api/system/check-token": () => ({ success: true }),
  "GET /api/system/refresh-user": () => ({
    success: true,
    user: { id: 1, username: "testuser", role: "admin" },
    message: null,
  }),

  // System settings
  "GET /api/setup-complete": () => ({ results: { MultiUserMode: false } }),
  "GET /api/system/local-files": () => ({ localFiles: [] }),
  "GET /api/system/check-token": () => ({ success: true }),
  "GET /api/system/env-dump": () => ({
    SystemSettings: {
      multi_user_mode: false,
      telemetry_id: "mock-telemetry",
      jwt_secret: "mock-secret",
      authToken: null,
      footer_data: "[]",
      support_email: null,
      customization: null,
      AgentGlobalSettings: {},
    },
  }),
  "GET /api/system/logo": () => null,
  "GET /api/system/appearance": () => ({
    headerImagePath: null,
    loginPageCustomization: {},
    supportEmail: null,
    customAppName: null,
    footerData: [],
    noViewScrolling: false,
    chatFontSize: "normal",
    dynamicIconSetting: "none",
    customCSS: null,
  }),
  "GET /api/system/user": () => ({
    user: {
      id: 1,
      username: "testuser",
      role: "admin",
      suspended: 0,
    },
  }),
  "GET /api/system/pfp": () => null,
  "GET /api/system/multi-user-mode": () => ({ multiUserMode: false }),

  // Admin preferences used by settings pages
  "POST /api/admin/system-preferences-by-fields": async (_req, body) => {
    const fields = Array.isArray(body?.fields) ? body.fields : [];
    const settings = {};
    if (fields.includes("disabled_agent_skills")) settings.disabled_agent_skills = [];
    if (fields.includes("default_agent_skills")) settings.default_agent_skills = ["gmail", "google-calendar"];
    if (fields.includes("imported_agent_skills")) settings.imported_agent_skills = [];
    if (fields.includes("active_agent_flows")) settings.active_agent_flows = [];
    if (fields.includes("disabled_gmail_skills")) settings.disabled_gmail_skills = [];
    if (fields.includes("disabled_google_calendar_skills")) settings.disabled_google_calendar_skills = [];
    return { success: true, settings };
  },

  // Workspaces
  "GET /api/workspaces": () => ({ workspaces: [] }),
  "GET /api/workspace": () => ({ workspace: null }),

  // Onboarding
  "GET /api/system/multi-user-mode": () => ({ multiUserMode: false }),

  // Documents
  "GET /api/documents": () => ({ documents: [], folders: [] }),

  // Agent skills
  "GET /api/agent-skills/filesystem-agent/is-available": () => ({ available: false }),
  "GET /api/agent-skills/create-files-agent/is-available": () => ({ available: false }),
  "GET /api/admin/agent-skills/gmail/status": () => MOCK_AGENT_SKILL_STATUS_DEFAULTS.gmail,
  "GET /api/admin/agent-skills/google-calendar/status": () => MOCK_AGENT_SKILL_STATUS_DEFAULTS.calendar,

  // Agent flows
  "GET /api/agent-flows/list": () => ({ success: true, flows: [] }),

  // MCP servers
  "GET /api/mcp-servers": () => ({ servers: [] }),
};

function matchRoute(method, url) {
  const urlPath = url.split("?")[0];
  const key = `${method} ${urlPath}`;

  if (routes[key]) return routes[key];

  for (const routeKey of Object.keys(routes)) {
    const [rMethod, rPath] = routeKey.split(" ");
    if (rMethod === method && urlPath.startsWith(rPath)) {
      return routes[routeKey];
    }
  }

  return null;
}

function readBody(req) {
  return new Promise((resolve) => {
    let body = "";
    req.on("data", (chunk) => (body += chunk));
    req.on("end", () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch {
        resolve({});
      }
    });
  });
}

const server = http.createServer(async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,PATCH,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With");

  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }

  const handler = matchRoute(req.method, req.url);

  if (handler) {
    const requestBody = await readBody(req);
    const result = await handler(req, requestBody);
    if (result === null) {
      res.writeHead(204, { "Content-Type": "application/json" });
      res.end();
      return;
    }
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(result));
    return;
  }

  console.log(`[mock-server] Unhandled: ${req.method} ${req.url}`);
  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify({}));
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`[mock-server] Listening on http://0.0.0.0:${PORT}`);
});
