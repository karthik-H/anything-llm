import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import { setupAdminAgentSkillsPage, mockGoogleAgentSkillStatuses } from "../../helpers/mock-api.js";

test("google calendar skill status shows configured when valid deploymentId and apiKey are present", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "google_calendar_skill_configured_status_displayed",
    testTitle: "Google Calendar skill status shows 'Configured' when valid deploymentId and apiKey are present",
  });

  await recorder.step("Mock admin agents page dependencies with Google Calendar configured", async () => {
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
          config: {
            deploymentId: "calendar-deployment-456",
            apiKey: "********",
          },
        },
      },
    });
  });

  await recorder.step("Open the agent skills settings page", async () => {
    await page.goto("/settings/agents");
    await expect(page.getByText("Agent Skills")).toBeVisible();
  });

  await recorder.step("Open the Google Calendar skill panel", async () => {
    await page.getByText("Google Calendar", { exact: true }).click();
    await expect(page.getByText("Configuration", { exact: true })).toBeVisible();
  });

  await recorder.step("Verify configured Google Calendar status is shown", async () => {
    await expect(page.getByText("Configured", { exact: true })).toBeVisible();
    await expect(page.getByPlaceholder("AKfycb...")).toHaveValue("calendar-deployment-456");
    await expect(page.getByPlaceholder("Your API key...")).toHaveValue("********");
    await expect(page.getByText(/configuration required/i)).not.toBeVisible();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:google_calendar_skill_configured_status_displayed");
  await recorder.save(testInfo);
});
