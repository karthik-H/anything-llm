import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import { mockAgentPluginConfigScenario } from "../../helpers/mock-api.js";

test("Non-admin user cannot update agent plugin config", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "agent_plugin_config_non_admin",
    testTitle: "Non-admin user cannot update agent plugin config",
  });

  await recorder.step("Load application shell", async () => {
    await page.goto("/");
    await expect(page.locator("#root")).toBeAttached();
  });

  const hubId = "plugin-forbidden-config";
  await recorder.step("Register forbidden config mock", async () => {
    await mockAgentPluginConfigScenario(page, {
      hubId,
      status: 403,
      role: "user",
      responseBody: {
        success: false,
        error: "Forbidden",
      },
    });
  });

  await recorder.step("Invoke updatePluginConfig as non-admin scenario", async () => {
    await page.evaluate(async ({ hubId }) => {
      const mod = await import("/src/models/experimental/agentPlugins.js");
      window.__agentPluginConfigForbiddenResult = await mod.default.updatePluginConfig(hubId, { tools: ["search"] });
    }, { hubId });
  });

  await recorder.step("Assert authorization failure", async () => {
    const result = await page.evaluate(() => window.__agentPluginConfigForbiddenResult);
    const response = await page.evaluate(() => window.__agentPluginLastConfigResponse);

    expect(result).toBe(false);
    expect(response.status).toBe(403);
    expect(response.body.error).toBe("Forbidden");
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:agent_plugin_config_non_admin");
  await recorder.save(testInfo);
});
