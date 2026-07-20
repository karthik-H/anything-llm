import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import { setupAdminAgentSkillsPage, mockGoogleAgentSkillStatuses } from "../../helpers/mock-api.js";

test("gmail skill status shows configured when valid deploymentId and apiKey are present", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "gmail_skill_configured_status_displayed",
    testTitle: "Gmail skill status shows 'Configured' when valid deploymentId and apiKey are present",
  });

  await recorder.step("Mock admin agents page dependencies with Gmail configured", async () => {
    await setupAdminAgentSkillsPage(page);
    await mockGoogleAgentSkillStatuses(page, {
      gmail: {
        status: 200,
        body: {
          success: true,
          isConfigured: true,
          config: {
            deploymentId: "gmail-deployment-123",
            apiKey: "********",
          },
        },
      },
      calendar: {
        status: 200,
        body: {
          success: true,
          isConfigured: false,
          config: { deploymentId: "", apiKey: "" },
        },
      },
    });
  });

  await recorder.step("Open the agent skills settings page", async () => {
    await page.goto("/settings/agents");
    await expect(page.getByText("Agent Skills")).toBeVisible();
  });

  await recorder.step("Open the Gmail skill panel", async () => {
    await page.getByText("Gmail", { exact: true }).click();
    await expect(page.getByText("Configuration", { exact: true })).toBeVisible();
  });

  await recorder.step("Verify configured Gmail status is shown", async () => {
    await expect(page.getByText("Configured", { exact: true })).toBeVisible();
    await expect(page.getByPlaceholder("AKfycb...")).toHaveValue("gmail-deployment-123");
    await expect(page.getByPlaceholder("Your API key...")).toHaveValue("********");
    await expect(page.getByText(/configuration required/i)).not.toBeVisible();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:gmail_skill_configured_status_displayed");
  await recorder.save(testInfo);
});
