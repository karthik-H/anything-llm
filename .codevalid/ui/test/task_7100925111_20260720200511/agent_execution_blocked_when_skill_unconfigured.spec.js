import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import { setupAdminAgentSkillsPage, mockGoogleAgentSkillStatuses } from "../../helpers/mock-api.js";

test("agent execution fails gracefully when a required skill is unconfigured", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "agent_execution_blocked_when_skill_unconfigured",
    testTitle: "Agent execution fails gracefully when a required skill is unconfigured",
  });

  await recorder.step("Mock admin agents page with Gmail unconfigured", async () => {
    await setupAdminAgentSkillsPage(page);
    await mockGoogleAgentSkillStatuses(page, {
      gmail: {
        status: 200,
        body: { success: true, isConfigured: false, config: { deploymentId: "", apiKey: "" } },
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

  await recorder.step("Open the admin agent skills page", async () => {
    await page.goto("/settings/agents");
    await expect(page.getByText("Agent Skills")).toBeVisible();
  });

  await recorder.step("Verify current UI has no Run Agent action on this screen", async () => {
    await expect(page.getByRole("button", { name: /run agent/i })).toHaveCount(0);
    await page.getByText("Gmail", { exact: true }).click();
    await expect(page.getByText(/configuration required/i)).toBeVisible();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:agent_execution_blocked_when_skill_unconfigured");
  await recorder.save(testInfo);
});
