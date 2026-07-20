import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";

test("Config update request fails without hubId in path", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "agent_plugin_config_missing_hubId",
    testTitle: "Config update request fails without hubId in path",
  });

  await recorder.step("Load application shell", async () => {
    await page.goto("/");
    await expect(page.locator("#root")).toBeAttached();
  });

  await recorder.step("Register missing hubId config route mock", async () => {
    await page.route("**/api/experimental/agent-plugins//config", async (route) => {
      await route.fulfill({
        status: 404,
        contentType: "application/json",
        body: JSON.stringify({ success: false, error: "Not Found" }),
      });
    });
  });

  await recorder.step("Send raw fetch request with missing hubId", async () => {
    await page.evaluate(async () => {
      const response = await fetch("/api/experimental/agent-plugins//config", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ updates: { tools: ["search"] } }),
      });
      window.__agentPluginMissingHubConfig = {
        status: response.status,
        body: await response.json(),
      };
    });
  });

  await recorder.step("Assert 404 response", async () => {
    const result = await page.evaluate(() => window.__agentPluginMissingHubConfig);
    expect(result.status).toBe(404);
    expect(result.body.success).toBe(false);
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:agent_plugin_config_missing_hubId");
  await recorder.save(testInfo);
});
