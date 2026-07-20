import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import {
  setupAdminAgentSkillsPage,
  setupOutlookAgentScenario,
  openOutlookAgentPanel,
  getOutlookPanel,
} from "../../helpers/mock-api.js";

test("Changing authentication type clears existing access tokens", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "outlook_auth_type_change_clears_tokens",
    testTitle: "Changing authentication type clears existing access tokens",
  });

  let authRequestBody = null;
  let popupPromise;

  await recorder.step("Mock authenticated common auth then unauthenticated organization status", async () => {
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
          clientId: "switch-client",
          tenantId: "",
          clientSecret: "********",
          authType: "common",
        },
      },
      authUrlResponse: {
        status: 200,
        body: {
          success: true,
          url: "https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize?client_id=switch-client",
        },
      },
      statusAfterAuth: {
        success: true,
        isConfigured: false,
        hasCredentials: true,
        isAuthenticated: false,
        tokenExpiry: null,
        config: {
          clientId: "switch-client",
          tenantId: "tenant-123",
          clientSecret: "********",
          authType: "organization",
        },
      },
      onAuthUrlRequest: async (body) => {
        authRequestBody = body;
      },
    });
  });

  await recorder.step("Open Outlook panel", async () => {
    popupPromise = page.waitForEvent("popup");
    await page.goto("/");
    await openOutlookAgentPanel(page);
  });

  await recorder.step("Switch auth type and save", async () => {
    const panel = getOutlookPanel(page);
    await panel.locator("select").selectOption("organization");
    const guidInputs = panel.locator('input[placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"]');
    await expect(guidInputs).toHaveCount(2);
    await guidInputs.nth(1).fill("tenant-123");
    await page.getByRole("button", { name: /authenticate with microsoft/i }).click();
    const popup = await popupPromise;
    await expect(popup).toHaveURL(/login\.microsoftonline\.com/);
    await popup.close();
  });

  await recorder.step("Reload and assert re-authentication required", async () => {
    expect(authRequestBody.authType).toBe("organization");
    expect(authRequestBody.tenantId).toBe("tenant-123");
    await page.reload();
    await openOutlookAgentPanel(page);
    const panel = getOutlookPanel(page);
    const guidInputs = panel.locator('input[placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"]');
    await expect(panel.locator("select")).toHaveValue("organization");
    await expect(guidInputs.nth(0)).toHaveValue("switch-client");
    await expect(guidInputs.nth(1)).toHaveValue("tenant-123");
    await expect(panel.locator('input[placeholder="Your client secret..."]')).toHaveValue("********");
    await expect(page.getByRole("button", { name: /authenticate with microsoft/i })).toBeVisible();
    await expect(page.getByRole("button", { name: /revoke access/i })).toHaveCount(0);
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:outlook_auth_type_change_clears_tokens");
  await recorder.save(testInfo);
});
