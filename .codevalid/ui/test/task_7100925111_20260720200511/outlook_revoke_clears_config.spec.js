import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import {
  setupAdminAgentSkillsPage,
  setupOutlookAgentScenario,
  openOutlookAgentPanel,
  getOutlookPanel,
} from "../../helpers/mock-api.js";

test("Revoke operation permanently deletes configuration from backend", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "outlook_revoke_clears_config",
    testTitle: "Revoke operation permanently deletes configuration from backend",
  });

  await recorder.step("Mock configured status then cleared status after revoke", async () => {
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
          clientId: "persisted-client",
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

  await recorder.step("Open Outlook panel and revoke", async () => {
    await page.goto("/");
    await openOutlookAgentPanel(page);
    await page.getByRole("button", { name: /revoke access/i }).click();
  });

  await recorder.step("Refresh page to confirm persisted cleared backend state", async () => {
    await page.reload();
    await openOutlookAgentPanel(page);
  });

  await recorder.step("Assert cleared config requires re-entry", async () => {
    const panel = getOutlookPanel(page);
    await expect(page.getByRole("button", { name: /authenticate with microsoft/i })).toBeVisible();
    await expect(page.getByRole("button", { name: /revoke access/i })).toHaveCount(0);
    await expect(panel.locator('input[placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"]').first()).toHaveValue("");
    await expect(panel.locator('input[placeholder="Your client secret..."]')).toHaveValue("");
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:outlook_revoke_clears_config");
  await recorder.save(testInfo);
});
