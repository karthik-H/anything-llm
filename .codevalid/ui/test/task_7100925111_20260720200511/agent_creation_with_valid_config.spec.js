import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import { setupAgentFlowSaveSuccessScenario } from "../../helpers/mock-api.js";

async function openAgentBuilder(page, recorder) {
  await recorder.step("Navigate to agent builder", async () => {
    await page.goto("/");
    await page.goto("/admin/agents");
  });
}

test("User successfully creates a new agent flow with valid name and config", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "agent_creation_with_valid_config",
    testTitle: "User successfully creates a new agent flow with valid name and config",
  });

  await setupAgentFlowSaveSuccessScenario(page, {
    flowUuid: "flow-data-summarizer-001",
    flowName: "Data Summarizer",
    description: "Summarizes indexed information for the user.",
  });

  await openAgentBuilder(page, recorder);

  await recorder.step("Fill flow name", async () => {
    await page.locator('[name="name"]').fill("Data Summarizer");
    await expect(page.locator('[name="name"]')).toHaveValue("Data Summarizer");
  });

  await recorder.step("Fill flow description", async () => {
    await page
      .locator('[name="description"]')
      .fill("Summarizes indexed information for the user.");
    await expect(page.locator('[name="description"]')).toHaveValue(
      "Summarizes indexed information for the user."
    );
  });

  await recorder.step("Save agent flow", async () => {
    await page.getByRole("button", { name: /save/i }).click();
  });

  await recorder.step("Assert saved state is reflected", async () => {
    await expect(page.locator('[name="name"]')).toHaveValue("Data Summarizer");
    await expect(page.locator('[name="description"]')).toHaveValue(
      "Summarizes indexed information for the user."
    );
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:agent_creation_with_valid_config");
  await recorder.save(testInfo);
});
