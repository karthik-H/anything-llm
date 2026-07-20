import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import { setupAdminAgentSkillsPage, mockGoogleAgentSkillStatuses } from "../../helpers/mock-api.js";

test("UI correctly shows mixed configuration status when one skill is configured and the other is not", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "mixed_skills_status_both_conf_and_unconf_displayed",
    testTitle: "UI correctly shows mixed configuration status when one skill is configured and the other is not",
  });

  await recorder.step("Mock admin agents page with Gmail configured and Google Calendar unconfigured", async () => {
    await setupAdminAgentSkillsPage(page);
    await mockGoogleAgentSkillStatuses(page, {
      gmail: {
        status: 200,
        body: {
          success: true,
          isConfigured: true,
          config: { deploymentId: "gmail-deployment-123", apiKey: "********" },
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
    await expect(page.getByText("App Integrations")).toBeVisible();
  });

  await recorder.step("Verify Gmail is configured", async () => {
    await page.getByText("Gmail", { exact: true }).click();
    await expect(page.getByText("Configured", { exact: true })).toBeVisible();
    await expect(page.getByPlaceholder("AKfycb...")).toHaveValue("gmail-deployment-123");
  });

  await recorder.step("Verify Google Calendar is unconfigured", async () => {
    await page.getByText("Google Calendar", { exact: true }).click();
    await expect(page.getByText("Configured", { exact: true })).not.toBeVisible();
    await expect(page.getByText(/configuration required/i)).toBeVisible();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:mixed_skills_status_both_conf_and_unconf_displayed");
  await recorder.save(testInfo);
});
