import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import { mockAgentPluginToggleScenario } from "../../helpers/mock-api.js";

test("Admin toggles agent plugin to inactive state", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "agent_plugin_toggle_inactive",
    testTitle: "Admin toggles agent plugin to inactive state",
  });

  await recorder.step("Load application shell", async () => {
    await page.goto("/");
    await expect(page.locator("#root")).toBeAttached();
  });

  const hubId = "plugin-123";
  await recorder.step("Register toggle inactive mock", async () => {
    await mockAgentPluginToggleScenario(page, {
      hubId,
      status: 200,
      role: "admin",
      responseBody: {
        success: true,
        hubId,
        active: false,
        tools: ["search"],
        data_access: "restricted",
      },
    });
  });

  await recorder.step("Invoke toggleFeature with active false", async () => {
    await page.evaluate(async ({ hubId }) => {
      const mod = await import("/src/models/experimental/agentPlugins.js");
      window.__agentPluginToggleResult = await mod.default.toggleFeature(hubId, false);
    }, { hubId });
  });

  await recorder.step("Assert request and result", async () => {
    const result = await page.evaluate(() => window.__agentPluginToggleResult);
    const requestBody = await page.evaluate(() => window.__agentPluginLastToggleRequestBody);
    const response = await page.evaluate(() => window.__agentPluginLastToggleResponse);

    expect(result).toBe(true);
    expect(requestBody).toEqual({ active: false });
    expect(response.status).toBe(200);
    expect(response.body.active).toBe(false);
    expect(response.body.hubId).toBe(hubId);
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:agent_plugin_toggle_inactive");
  await recorder.save(testInfo);
});
