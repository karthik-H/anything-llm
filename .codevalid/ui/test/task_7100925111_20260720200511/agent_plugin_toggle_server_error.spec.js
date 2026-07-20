import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import { mockAgentPluginToggleScenario } from "../../helpers/mock-api.js";

test("Toggle request fails with 500 on server exception", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "agent_plugin_toggle_server_error",
    testTitle: "Toggle request fails with 500 on server exception",
  });

  await recorder.step("Load application shell", async () => {
    await page.goto("/");
    await expect(page.locator("#root")).toBeAttached();
  });

  const hubId = "plugin-toggle-500";
  await recorder.step("Register toggle server error mock", async () => {
    await mockAgentPluginToggleScenario(page, {
      hubId,
      status: 500,
      role: "admin",
      responseBody: {
        success: false,
        error: "Internal Server Error",
      },
    });
  });

  await recorder.step("Invoke toggleFeature during server error", async () => {
    await page.evaluate(async ({ hubId }) => {
      const mod = await import("/src/models/experimental/agentPlugins.js");
      window.__agentPluginToggleServerErrorResult = await mod.default.toggleFeature(hubId, true);
    }, { hubId });
  });

  await recorder.step("Assert boolean failure and 500 response", async () => {
    const result = await page.evaluate(() => window.__agentPluginToggleServerErrorResult);
    const response = await page.evaluate(() => window.__agentPluginLastToggleResponse);

    expect(result).toBe(false);
    expect(response.status).toBe(500);
    expect(response.body.error).toBe("Internal Server Error");
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:agent_plugin_toggle_server_error");
  await recorder.save(testInfo);
});
