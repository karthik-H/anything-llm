import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import { mockAgentPluginToggleScenario } from "../../helpers/mock-api.js";

test("Toggle fails when hubId does not exist", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "agent_plugin_toggle_nonexistent_hubid",
    testTitle: "Toggle fails when hubId does not exist",
  });

  await recorder.step("Load application shell", async () => {
    await page.goto("/");
    await expect(page.locator("#root")).toBeAttached();
  });

  const hubId = "999999";
  await recorder.step("Register nonexistent hub toggle mock", async () => {
    await mockAgentPluginToggleScenario(page, {
      hubId,
      status: 404,
      role: "admin",
      responseBody: {
        success: false,
        error: "Plugin not found",
      },
    });
  });

  await recorder.step("Invoke toggleFeature for nonexistent hub", async () => {
    await page.evaluate(async ({ hubId }) => {
      const mod = await import("/src/models/experimental/agentPlugins.js");
      window.__agentPluginToggleMissingResult = await mod.default.toggleFeature(hubId, true);
    }, { hubId });
  });

  await recorder.step("Assert 404 response", async () => {
    const result = await page.evaluate(() => window.__agentPluginToggleMissingResult);
    const response = await page.evaluate(() => window.__agentPluginLastToggleResponse);

    expect(result).toBe(false);
    expect(response.status).toBe(404);
    expect(response.body.error).toBe("Plugin not found");
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:agent_plugin_toggle_nonexistent_hubid");
  await recorder.save(testInfo);
});
