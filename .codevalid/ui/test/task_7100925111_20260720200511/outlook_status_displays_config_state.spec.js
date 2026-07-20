import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import {
  setupAdminAgentSkillsPage,
  setupOutlookAgentScenario,
  openOutlookAgentPanel,
  getOutlookPanel,
} from "../../helpers/mock-api.js";

test("UI correctly displays configuration and authentication status", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "outlook_status_displays_config_state",
    testTitle: "UI correctly displays configuration and authentication status",
  });

  await recorder.step("Mock stored authenticated Outlook status", async () => {
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
          clientId: "stored-client-id",
          tenantId: "stored-tenant-id",
          clientSecret: "********",
          authType: "organization",
        },
      },
    });
  });

  await recorder.step("Open Outlook panel", async () => {
    await page.goto("/");
    await openOutlookAgentPanel(page);
  });

  await recorder.step("Assert stored config and configured state are shown", async () => {
    const panel = getOutlookPanel(page);
    const guidInputs = panel.locator('input[placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"]');
    await expect(panel.locator("select")).toHaveValue("organization");
    await expect(guidInputs).toHaveCount(2);
    await expect(guidInputs.nth(0)).toHaveValue("stored-client-id");
    await expect(guidInputs.nth(1)).toHaveValue("stored-tenant-id");
    await expect(panel.locator('input[placeholder="Your client secret..."]')).toHaveValue("********");
    await expect(panel.getByText(/configured/i)).toBeVisible();
    await expect(panel.getByText(/authenticated/i)).toBeVisible();
    await expect(page.getByRole("button", { name: /revoke access/i })).toBeVisible();
    await expect(page.getByRole("button", { name: /authenticate with microsoft/i })).toHaveCount(0);
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:outlook_status_displays_config_state");
  await recorder.save(testInfo);
});
