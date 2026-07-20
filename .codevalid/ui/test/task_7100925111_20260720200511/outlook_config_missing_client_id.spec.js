import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import {
  setupAdminAgentSkillsPage,
  setupOutlookAgentScenario,
  openOutlookAgentPanel,
} from "../../helpers/mock-api.js";

test("User attempts to save Outlook config without Client ID", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "outlook_config_missing_client_id",
    testTitle: "User attempts to save Outlook config without Client ID",
  });

  let popupOpened = false;
  let authRequestBody = null;

  await recorder.step("Mock admin agent page and Outlook validation failure", async () => {
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

  await recorder.step("Open Admin Agents page", async () => {
    await page.goto("/");
    await openOutlookAgentPanel(page);
  });

  await recorder.step("Enter only Client Secret", async () => {
    await page.locator('input[placeholder="Your client secret..."]').fill("super-secret-value");
    await expect(page.locator('input[placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"]').first()).toHaveValue("");
  });

  await recorder.step("Click Authenticate with Microsoft", async () => {
    const button = page.getByRole("button", { name: /authenticate with microsoft/i });
    await expect(button).toBeEnabled();
    await button.click();
  });

  await recorder.step("Assert failed validation behavior", async () => {
    await expect.poll(() => authRequestBody).not.toBeNull();
    expect(authRequestBody.clientId).toBe("");
    expect(authRequestBody.clientSecret).toBe("super-secret-value");
    expect(authRequestBody.authType).toBe("common");
    expect(popupOpened).toBe(false);
    await expect(page.locator('input[placeholder="Your client secret..."]')).toHaveValue("super-secret-value");
    await expect(page.locator('input[placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"]').first()).toHaveValue("");
    await expect(page.getByRole("button", { name: /authenticate with microsoft/i })).toBeEnabled();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:outlook_config_missing_client_id");
  await recorder.save(testInfo);
});
