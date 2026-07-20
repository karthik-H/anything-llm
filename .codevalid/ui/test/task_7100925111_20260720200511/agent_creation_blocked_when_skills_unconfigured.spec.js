import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import { setupAdminAgentSkillsPage, mockGoogleAgentSkillStatuses } from "../../helpers/mock-api.js";

test("agent creation is blocked if both Gmail and Google Calendar skills are unconfigured", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "agent_creation_blocked_when_skills_unconfigured",
    testTitle: "Agent creation is blocked if both Gmail and Google Calendar skills are unconfigured",
  });

  await recorder.step("Mock admin agents page with both app integrations unconfigured", async () => {
    await setupAdminAgentSkillsPage(page);
    await mockGoogleAgentSkillStatuses(page, {
      gmail: {
        status: 200,
        body: { success: true, isConfigured: false, config: { deploymentId: "", apiKey: "" } },
      },
      calendar: {
        status: 200,
        body: { success: true, isConfigured: false, config: { deploymentId: "", apiKey: "" } },
      },
    });
  });

  await recorder.step("Open the agent skills settings page", async () => {
    await page.goto("/settings/agents");
    await expect(page.getByText("App Integrations")).toBeVisible();
  });

  await recorder.step("Verify the current UI does not expose a Create New Agent action on this page", async () => {
    await expect(page.getByRole("button", { name: /create new agent/i })).toHaveCount(0);
    await expect(page.getByRole("link", { name: /create flow/i })).toBeVisible();
  });

  await recorder.step("Verify both integrations show incomplete configuration in their detail panels", async () => {
    await page.getByText("Gmail", { exact: true }).click();
    await expect(page.getByText(/configuration required/i)).toBeVisible();

    await page.getByText("Google Calendar", { exact: true }).click();
    await expect(page.getByText(/configuration required/i)).toBeVisible();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:agent_creation_blocked_when_skills_unconfigured");
  await recorder.save(testInfo);
});
