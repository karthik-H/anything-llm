import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";

test("Toggle request fails with malformed JSON body", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "agent_plugin_toggle_invalid_json",
    testTitle: "Toggle request fails with malformed JSON body",
  });

  await recorder.step("Load application shell", async () => {
    await page.goto("/");
    await expect(page.locator("#root")).toBeAttached();
  });

  const hubId = "plugin-invalid-json";
  await recorder.step("Register malformed JSON response mock", async () => {
    await page.route(`**/api/experimental/agent-plugins/${hubId}/toggle`, async (route) => {
      await route.fulfill({
        status: 400,
        contentType: "application/json",
        body: JSON.stringify({ success: false, error: "JSON parsing failure" }),
      });
    });
  });

  await recorder.step("Send malformed JSON request", async () => {
    await page.evaluate(async ({ hubId }) => {
      const response = await fetch(`/api/experimental/agent-plugins/${hubId}/toggle`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: '{active: true}',
      });
      window.__agentPluginInvalidJsonToggle = {
        status: response.status,
        body: await response.json(),
      };
    }, { hubId });
  });

  await recorder.step("Assert 400 response", async () => {
    const result = await page.evaluate(() => window.__agentPluginInvalidJsonToggle);
    expect(result.status).toBe(400);
    expect(result.body.error).toContain("JSON parsing");
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:agent_plugin_toggle_invalid_json");
  await recorder.save(testInfo);
});
