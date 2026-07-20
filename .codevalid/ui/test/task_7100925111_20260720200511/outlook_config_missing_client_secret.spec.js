import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import {
  setupAdminAgentSkillsPage,
  setupOutlookAgentScenario,
  openOutlookAgentPanel,
} from "../../helpers/mock-api.js";

test("User attempts to save Outlook config without Client Secret", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "outlook_config_missing_client_secret",
    testTitle: "User attempts to save Outlook config without Client Secret",
  });

  let popupOpened = false;
  let authRequestBody = null;

  await recorder.step("Mock admin page and Outlook validation failure for missing secret", async () => {
    await setupAdminAgentSkillsPage(page, {
      defaultAgentSkills: ["gmail-agent", "google-calendar-agent", "outlook-agent"],
    });
    await setupOutlookAgentScenario(page, {
      initialStatus: {
        success: true,
        isConfigured: false,
        hasCredentials: false,
        isAuthenticated: false,
        tokenExpiry: null,
        config: { clientId: "", tenantId: "", clientSecret: "", authType: "common" },
      },
      authUrlResponse: {
        status: 400,
        body: { success: false, error: "Client ID and Client Secret are required." },
      },
      onAuthUrlRequest: async (body) => {
        authRequestBody = body;
      },
    });
    page.on("popup", () => {
      popupOpened = true;
    });
  });

  await recorder.step("Open Outlook panel", async () => {
    await page.goto("/");
    await openOutlookAgentPanel(page);
  });

  await recorder.step("Enter only Client ID", async () => {
    await page.locator('input[placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"]').first().fill("11111111-2222-3333-4444-555555555555");
    await expect(page.locator('input[placeholder="Your client secret..."]')).toHaveValue("");
  });

  await recorder.step("Submit config", async () => {
    await page.getByRole("button", { name: /authenticate with microsoft/i }).click();
  });

  await recorder.step("Assert no redirect and values preserved", async () => {
    await expect.poll(() => authRequestBody).not.toBeNull();
    expect(authRequestBody.clientId).toBe("11111111-2222-3333-4444-555555555555");
    expect(authRequestBody.clientSecret).toBe("");
    expect(popupOpened).toBe(false);
    await expect(page.locator('input[placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"]').first()).toHaveValue("11111111-2222-3333-4444-555555555555");
    await expect(page.locator('input[placeholder="Your client secret..."]')).toHaveValue("");
    await expect(page.getByRole("button", { name: /authenticate with microsoft/i })).toBeEnabled();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:outlook_config_missing_client_secret");
  await recorder.save(testInfo);
});
