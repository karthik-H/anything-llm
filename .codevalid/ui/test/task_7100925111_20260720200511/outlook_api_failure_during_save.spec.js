import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import {
  setupAdminAgentSkillsPage,
  setupOutlookAgentScenario,
  openOutlookAgentPanel,
  getOutlookPanel,
} from "../../helpers/mock-api.js";

test("UI handles backend 500 error during auth-url request", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "outlook_api_failure_during_save",
    testTitle: "UI handles backend 500 error during auth-url request",
  });

  let popupOpened = false;

  await recorder.step("Mock backend failure during Outlook save", async () => {
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
        status: 500,
        body: { success: false, error: "Unexpected Outlook auth failure" },
      },
    });
    page.on("popup", () => {
      popupOpened = true;
    });
  });

  await recorder.step("Open panel and enter valid values", async () => {
    await page.goto("/");
    await openOutlookAgentPanel(page);
    const panel = getOutlookPanel(page);
    await panel.locator('input[placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"]').first().fill("client-500");
    await panel.locator('input[placeholder="Your client secret..."]').fill("secret-500");
  });

  await recorder.step("Submit and wait for failure response", async () => {
    const button = page.getByRole("button", { name: /authenticate with microsoft/i });
    await button.click();
    await expect(button).toBeEnabled();
  });

  await recorder.step("Assert user input preserved and no popup opened", async () => {
    const panel = getOutlookPanel(page);
    expect(popupOpened).toBe(false);
    await expect(panel.locator('input[placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"]').first()).toHaveValue("client-500");
    await expect(panel.locator('input[placeholder="Your client secret..."]')).toHaveValue("secret-500");
    await expect(page.getByRole("button", { name: /authenticate with microsoft/i })).toBeEnabled();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:outlook_api_failure_during_save");
  await recorder.save(testInfo);
});
