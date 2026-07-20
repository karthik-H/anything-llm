import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import {
  setupAdminAgentSkillsPage,
  setupOutlookAgentScenario,
  openOutlookAgentPanel,
  getOutlookPanel,
} from "../../helpers/mock-api.js";

test("User attempts organization auth without Tenant ID", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "outlook_config_organization_auth_missing_tenant_id",
    testTitle: "User attempts organization auth without Tenant ID",
  });

  let popupOpened = false;
  let authRequestBody = null;

  await recorder.step("Mock organization validation failure", async () => {
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
        body: {
          success: false,
          error: "Tenant ID is required for organization-only authentication.",
        },
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

  await recorder.step("Switch to organization auth and enter credentials without tenant", async () => {
    const panel = getOutlookPanel(page);
    await panel.locator("select").selectOption("organization");
    const guidInputs = panel.locator('input[placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"]');
    await expect(guidInputs).toHaveCount(2);
    await guidInputs.nth(0).fill("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");
    await guidInputs.nth(1).fill("");
    await panel.locator('input[placeholder="Your client secret..."]').fill("org-secret");
  });

  await recorder.step("Submit organization auth", async () => {
    await page.getByRole("button", { name: /authenticate with microsoft/i }).click();
  });

  await recorder.step("Assert tenant validation request and no popup", async () => {
    const panel = getOutlookPanel(page);
    const guidInputs = panel.locator('input[placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"]');
    await expect.poll(() => authRequestBody).not.toBeNull();
    expect(authRequestBody.authType).toBe("organization");
    expect(authRequestBody.clientId).toBe("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");
    expect(authRequestBody.tenantId).toBe("");
    expect(authRequestBody.clientSecret).toBe("org-secret");
    expect(popupOpened).toBe(false);
    await expect(guidInputs.nth(1)).toHaveValue("");
    await expect(page.locator('input[placeholder="Your client secret..."]')).toHaveValue("org-secret");
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:outlook_config_organization_auth_missing_tenant_id");
  await recorder.save(testInfo);
});
