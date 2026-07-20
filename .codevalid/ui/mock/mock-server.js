/**
 * Mock API server for AnythingLLM UI testing.
 * Intercepts all API calls so the frontend can render without a real backend.
 * Runs on port 3001 to match VITE_API_BASE=http://localhost:3001/api
 */

import http from "http";

const PORT = 3001;

/**
 * Mock responses keyed by method + path prefix.
 * All routes are under /api/
 */
const routes = {
  "GET /api/ping": () => ({ message: "pong" }),

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

  // System settings
  "GET /api/setup-complete": () => ({ isMultiUser: false }),
  "GET /api/system/vector-count": () => ({ remoteCount: 0 }),
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
  "GET /api/system/logo": () => null, // handled separately
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

  // Workspaces
  "GET /api/workspaces": () => ({ workspaces: [] }),
  "GET /api/workspace": () => ({ workspace: null }),

  // Onboarding
  "GET /api/system/multi-user-mode": () => ({ multiUserMode: false }),

  // Documents
  "GET /api/documents": () => ({ documents: [], folders: [] }),
};

function matchRoute(method, url) {
  const urlPath = url.split("?")[0];
  const key = `${method} ${urlPath}`;

  // Exact match
  if (routes[key]) return routes[key];

  // Prefix match for dynamic routes
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
  // CORS headers so browser-side requests succeed
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
    await readBody(req);
    const result = handler();
    if (result === null) {
      res.writeHead(204, { "Content-Type": "application/json" });
      res.end();
      return;
    }
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(result));
    return;
  }

  // Default: return a generic 200 with empty data so the UI doesn't crash
  console.log(`[mock-server] Unhandled: ${req.method} ${req.url}`);
  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify({}));
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`[mock-server] Listening on http://0.0.0.0:${PORT}`);
});
