import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import { setupAgentFlowBaseScenario } from "../../helpers/mock-api.js";

async function openAgentBuilder(page, recorder) {
  await recorder.step("Navigate to agent builder", async () => {
    await page.goto("/");
    await page.goto("/admin/agents");
  });
}

test("Agent creation fails when name is missing from configuration", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "agent_creation_missing_name",
    testTitle: "Agent creation fails when name is missing from configuration",
  });

  await setupAgentFlowBaseScenario(page);
  await openAgentBuilder(page, recorder);

  await recorder.step("Leave name empty", async () => {
    await page.locator('[name="name"]').fill("");
    await expect(page.locator('[name="name"]')).toHaveValue("");
  });

  await recorder.step("Provide description", async () => {
    await page
      .locator('[name="description"]')
      .fill("A valid description that satisfies minimum length.");
  });

  await recorder.step("Attempt to save flow", async () => {
    await page.getByRole("button", { name: /save/i }).click();
  });

  await recorder.step("Assert HTML required validation prevents submission", async () => {
    const nameField = page.locator('[name="name"]');
    await expect(nameField).toBeFocused();
    const validity = await nameField.evaluate((el) => el.checkValidity());
    expect(validity).toBe(false);
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:agent_creation_missing_name");
  await recorder.save(testInfo);
});
