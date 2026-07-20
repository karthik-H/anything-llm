import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import { setupAdminAgentSkillsPage, mockGoogleAgentSkillStatuses } from "../../helpers/mock-api.js";

test("User can navigate from unconfigured status to Gmail configuration panel by selecting the skill", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "user_can_navigate_to_configure_action",
    testTitle: "User can navigate from unconfigured status to configuration panel via 'Configure' button",
  });

  await recorder.step("Mock admin agents page with Gmail unconfigured", async () => {
    await setupAdminAgentSkillsPage(page);
    await mockGoogleAgentSkillStatuses(page, {
      gmail: {
        status: 200,
        body: {
          success: true,
          isConfigured: false,
          config: { deploymentId: "", apiKey: "" },
        },
      },
      calendar: {
        status: 200,
        body: {
          success: true,
          isConfigured: true,
          config: { deploymentId: "calendar-deployment-456", apiKey: "********" },
        },
      },
    });
  });

  await recorder.step("Open the admin agents settings page", async () => {
    await page.goto("/settings/agents");
    await expect(page.getByText("App Integrations")).toBeVisible();
  });

  await recorder.step("Navigate into the Gmail configuration panel", async () => {
    await page.getByText("Gmail", { exact: true }).click();
    await expect(page.getByText("Configuration", { exact: true })).toBeVisible();
  });

  await recorder.step("Verify deploymentId and apiKey fields are presented and start empty", async () => {
    await expect(page.getByPlaceholder("AKfycb...")).toHaveValue("");
    await expect(page.getByPlaceholder("Your API key...")).toHaveValue("");
    await expect(page.getByText(/configuration required/i)).toBeVisible();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:user_can_navigate_to_configure_action");
  await recorder.save(testInfo);
});
