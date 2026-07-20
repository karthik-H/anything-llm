import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import {
  setupAdminAgentSkillsPage,
  setupOutlookAgentScenario,
  openOutlookAgentPanel,
  getOutlookPanel,
} from "../../helpers/mock-api.js";

test("User successfully configures Outlook with valid credentials", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "outlook_config_successful_authorization",
    testTitle: "User successfully configures Outlook with valid credentials",
  });

  let popupPromise;
  let authRequestBody = null;

  await recorder.step("Mock successful Outlook authorization flow", async () => {
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
        status: 200,
        body: {
          success: true,
          url: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize?client_id=mock-client-id",
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

  await recorder.step("Fill valid common auth credentials", async () => {
    const panel = getOutlookPanel(page);
    await panel.locator("select").selectOption("common");
    await panel.locator('input[placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"]').first().fill("99999999-8888-7777-6666-555555555555");
    await panel.locator('input[placeholder="Your client secret..."]').fill("top-secret");
  });

  await recorder.step("Start Microsoft auth", async () => {
    await page.getByRole("button", { name: /authenticate with microsoft/i }).click();
  });

  await recorder.step("Assert popup/redirect and request payload", async () => {
    const popup = await popupPromise;
    await expect.poll(() => authRequestBody).not.toBeNull();
    expect(authRequestBody).toMatchObject({
      clientId: "99999999-8888-7777-6666-555555555555",
      clientSecret: "top-secret",
      tenantId: "",
      authType: "common",
    });
    await expect(popup).toHaveURL(/login\.microsoftonline\.com/);
    await popup.close();
    await expect(page.getByRole("button", { name: /authenticate with microsoft/i })).toBeEnabled();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:outlook_config_successful_authorization");
  await recorder.save(testInfo);
});
