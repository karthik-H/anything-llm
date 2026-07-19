// seed_test.js
// Seed test: verifies the AnythingLLM frontend is reachable and renders the
// expected page title inside the container.
//
// This file is intentionally free of mock data – all API mocking is handled
// by the mock server in .codevalid/ui/mock/mock-server.js.
//
// Import helpers from .codevalid/ui/helpers/ if you need ExecutionRecorder:
//   import { ExecutionRecorder } from "../helpers/execution-recorder.js";

import { test, expect } from "@playwright/test";

test("seed – app is reachable and renders the correct page title", async ({ page }) => {
  // Navigate to the root of the running Vite dev server (baseURL from playwright.config.js)
  await page.goto("/");

  // The <title> element in frontend/index.html is:
  //   "AnythingLLM | Your personal LLM trained on anything"
  await expect(page).toHaveTitle(/AnythingLLM/i);
});
