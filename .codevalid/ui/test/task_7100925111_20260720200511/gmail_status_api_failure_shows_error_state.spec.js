import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import { setupAdminAgentSkillsPage, mockGoogleAgentSkillStatuses } from "../../helpers/mock-api.js";

test("UI displays fallback unconfigured state when Gmail status API returns 500", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "gmail_status_api_failure_shows_error_state",
    testTitle: "UI displays error state when Gmail status API returns 500",
  });

  await recorder.step("Mock admin agents page with Gmail status API failure", async () => {
    await setupAdminAgentSkillsPage(page);
    await mockGoogleAgentSkillStatuses(page, {
      gmail: {
        status: 500,
        body: { success: false, error: "Server error" },
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

  await recorder.step("Open Gmail skill panel after page load", async () => {
    await page.goto("/settings/agents");
    await page.getByText("Gmail", { exact: true }).click();
    await expect(page.getByText("Configuration", { exact: true })).toBeVisible();
  });

  await recorder.step("Verify the implemented UI falls back to incomplete configuration messaging", async () => {
    await expect(page.getByText("Configured", { exact: true })).not.toBeVisible();
    await expect(page.getByPlaceholder("AKfycb...")).toHaveValue("");
    await expect(page.getByPlaceholder("Your API key...")).toHaveValue("");
    await expect(page.getByText(/configuration required/i)).toBeVisible();
    await expect(page.getByRole("button", { name: /retry/i })).toHaveCount(0);
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:gmail_status_api_failure_shows_error_state");
  await recorder.save(testInfo);
});
