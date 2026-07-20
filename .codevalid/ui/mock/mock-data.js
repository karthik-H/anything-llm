// mock-data.js
// Static mock data for the AnythingLLM UI test suite.
//
// Only data lives here.  Logic/server setup is in mock-server.js and
// mock-routes.js.  Test files must NOT import data directly – they should
// rely on the mock server to serve it.

// ── Health ──────────────────────────────────────────────────────────────────
export const MOCK_HEALTH = {
  online: true,
  version: "0.0.0-test",
};

// ── Auth / current user ──────────────────────────────────────────────────────
export const MOCK_AUTH_USER = {
  authenticated: true,
  user: {
    id: 1,
    username: "seed-test-user",
    role: "admin",
  },
};

// ── Workspaces ───────────────────────────────────────────────────────────────
export const MOCK_WORKSPACES = {
  workspaces: [
    {
      id: 1,
      name: "Seed Workspace",
      slug: "seed-workspace",
      createdAt: "2024-01-01T00:00:00.000Z",
    },
  ],
};
