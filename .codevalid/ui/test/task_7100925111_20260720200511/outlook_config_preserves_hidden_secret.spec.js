import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import {
  setupAdminAgentSkillsPage,
  setupOutlookAgentScenario,
  openOutlookAgentPanel,
  getOutlookPanel,
} from "../../helpers/mock-api.js";

test("Client Secret is masked and preserved as asterisks after successful save", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "outlook_config_preserves_hidden_secret",
    testTitle: "Client Secret is masked and preserved as asterisks after successful save",
  });

  let authRequestBody = null;
  let popupPromise;

  await recorder.step("Mock successful save followed by stored masked secret status", async () => {
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
          clientId: "masked-client",
          tenantId: "",
          clientSecret: "********",
          authType: "common",
        },
      },
      authUrlResponse: {
        status: 200,
        body: {
          success: true,
          url: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize?client_id=masked-client",
        },
      },
      onAuthUrlRequest: async (body) => {
        authRequestBody = body;
      },
    });
  });

  await recorder.step("Open Outlook panel and verify masked stored secret", async () => {
    popupPromise = page.waitForEvent("popup");
    await page.goto("/");
    await openOutlookAgentPanel(page);
    const panel = getOutlookPanel(page);
    await expect(panel.locator('input[placeholder="Your client secret..."]')).toHaveValue("********");
    await expect(panel.locator('input[placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"]').first()).toHaveValue("masked-client");
  });

  await recorder.step("Submit again with masked secret unchanged", async () => {
    await page.getByRole("button", { name: /revoke access/i }).click();
    await page.reload();
    await openOutlookAgentPanel(page);
    const panel = getOutlookPanel(page);
    await panel.locator('input[placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"]').first().fill("masked-client");
    await panel.locator('input[placeholder="Your client secret..."]').fill("********");
    await page.getByRole("button", { name: /authenticate with microsoft/i }).click();
    const popup = await popupPromise;
    await expect(popup).toHaveURL(/login\.microsoftonline\.com/);
    await popup.close();
  });

  await recorder.step("Assert secret stays masked in request/UI", async () => {
    expect(authRequestBody.clientSecret).toBe("********");
    await page.reload();
    await openOutlookAgentPanel(page);
    await expect(getOutlookPanel(page).locator('input[placeholder="Your client secret..."]')).toHaveValue("********");
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:outlook_config_preserves_hidden_secret");
  await recorder.save(testInfo);
});
