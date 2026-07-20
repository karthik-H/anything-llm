/**
 * Seed test for AnythingLLM UI.
 *
 * Verifies that:
 *  1. The Vite dev server is reachable on port 5174.
 *  2. The page title contains "AnythingLLM".
 *  3. The root #root element is present in the DOM.
 *
 * This test intentionally contains no mock data — all API mocking is
 * handled by .codevalid/ui/mock/mock-server.js which runs on port 3001.
 */

import { test, expect } from "@playwright/test";

test("app is reachable and renders the AnythingLLM page", async ({ page }) => {
  await page.goto("/");

  // The page title must contain "AnythingLLM"
  await expect(page).toHaveTitle(/AnythingLLM/i);

  // The React root element must be present
  const root = page.locator("#root");
  await expect(root).toBeAttached();
});
