import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import {
  setupAdminAgentSkillsPage,
  setupOutlookAgentScenario,
  openOutlookAgentPanel,
  getOutlookPanel,
} from "../../helpers/mock-api.js";

test("UI updates authentication status to unauthenticated after revoke", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "outlook_status_unauthenticated_after_revoke",
    testTitle: "UI updates authentication status to unauthenticated after revoke",
  });

  await recorder.step("Mock authenticated status followed by revoked status", async () => {
    await setupAdminAgentSkillsPage(page, {
      defaultAgentSkills: ["gmail-agent", "google-calendar-agent", "outlook-agent"],
    });
    await setupOutlookAgentScenario(page, {
      initialStatus: {
        success: true,
        isConfigured: true,
        hasCredentials: true,
        isAuthenticated: true,
        tokenExpiry: 1893456000000,
        config: {
          clientId: "configured-client",
          tenantId: "",
          clientSecret: "********",
          authType: "common",
        },
      },
      statusAfterRevoke: {
        success: true,
        isConfigured: false,
        hasCredentials: false,
        isAuthenticated: false,
        tokenExpiry: null,
        config: {
          clientId: "",
          tenantId: "",
          clientSecret: "",
          authType: "common",
        },
      },
      revokeResponse: {
        status: 200,
        body: { success: true },
      },
    });
  });

  await recorder.step("Open Outlook panel", async () => {
    await page.goto("/");
    await openOutlookAgentPanel(page);
  });

  await recorder.step("Verify authenticated state", async () => {
    await expect(page.getByRole("button", { name: /revoke access/i })).toBeVisible();
    await expect(getOutlookPanel(page).getByText(/authenticated/i)).toBeVisible();
  });

  await recorder.step("Revoke and refresh status", async () => {
    await page.getByRole("button", { name: /revoke access/i }).click();
    await page.reload();
    await openOutlookAgentPanel(page);
  });

  await recorder.step("Assert unauthenticated state after revoke", async () => {
    const panel = getOutlookPanel(page);
    await expect(page.getByRole("button", { name: /authenticate with microsoft/i })).toBeVisible();
    await expect(page.getByRole("button", { name: /revoke access/i })).toHaveCount(0);
    await expect(panel.locator('input[placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"]').first()).toHaveValue("");
    await expect(panel.locator('input[placeholder="Your client secret..."]')).toHaveValue("");
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:outlook_status_unauthenticated_after_revoke");
  await recorder.save(testInfo);
});
