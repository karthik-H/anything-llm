import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import { mockAgentPluginConfigScenario } from "../../helpers/mock-api.js";

test("Config update succeeds with empty updates object", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "agent_plugin_config_empty_updates",
    testTitle: "Config update succeeds with empty updates object",
  });

  await recorder.step("Load application shell", async () => {
    await page.goto("/");
    await expect(page.locator("#root")).toBeAttached();
  });

  const hubId = "plugin-empty-updates";
  await recorder.step("Register empty updates success mock", async () => {
    await mockAgentPluginConfigScenario(page, {
      hubId,
      status: 200,
      role: "admin",
      responseBody: {
        success: true,
        hubId,
        active: true,
        tools: ["search"],
        data_access: "restricted",
      },
    });
  });

  await recorder.step("Invoke updatePluginConfig with empty object", async () => {
    await page.evaluate(async ({ hubId }) => {
      const mod = await import("/src/models/experimental/agentPlugins.js");
      window.__agentPluginEmptyUpdatesResult = await mod.default.updatePluginConfig(hubId, {});
    }, { hubId });
  });

  await recorder.step("Assert success with unchanged config", async () => {
    const result = await page.evaluate(() => window.__agentPluginEmptyUpdatesResult);
    const requestBody = await page.evaluate(() => window.__agentPluginLastConfigRequestBody);
    const response = await page.evaluate(() => window.__agentPluginLastConfigResponse);

    expect(result).toBe(true);
    expect(requestBody).toEqual({ updates: {} });
    expect(response.status).toBe(200);
    expect(response.body.tools).toEqual(["search"]);
    expect(response.body.data_access).toBe("restricted");
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:agent_plugin_config_empty_updates");
  await recorder.save(testInfo);
});
