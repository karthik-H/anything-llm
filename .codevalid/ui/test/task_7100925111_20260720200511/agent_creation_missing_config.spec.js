import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import { setupAgentFlowBaseScenario } from "../../helpers/mock-api.js";

async function openAgentBuilder(page, recorder) {
  await recorder.step("Navigate to agent builder", async () => {
    await page.goto("/");
    await page.goto("/admin/agents");
  });
}

test("Agent creation fails when config is missing or empty", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "agent_creation_missing_config",
    testTitle: "Agent creation fails when config is missing or empty",
  });

  await setupAgentFlowBaseScenario(page);
  await openAgentBuilder(page, recorder);

  await recorder.step("Provide a non-empty name", async () => {
    await page.locator('[name="name"]').fill("Auto Responder");
    await expect(page.locator('[name="name"]')).toHaveValue("Auto Responder");
  });

  await recorder.step("Leave description empty to simulate incomplete configuration metadata", async () => {
    await page.locator('[name="description"]').fill("");
    await expect(page.locator('[name="description"]')).toHaveValue("");
  });

  await recorder.step("Attempt to save flow", async () => {
    await page.getByRole("button", { name: /save/i }).click();
  });

  await recorder.step("Assert required validation prevents submission", async () => {
    const descriptionField = page.locator('[name="description"]');
    await expect(descriptionField).toBeFocused();
    const validity = await descriptionField.evaluate((el) => el.checkValidity());
    expect(validity).toBe(false);
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:agent_creation_missing_config");
  await recorder.save(testInfo);
});
