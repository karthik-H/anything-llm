import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import { mockAgentPluginConfigScenario } from "../../helpers/mock-api.js";

test("Admin updates agent plugin configuration with new tool permissions", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "agent_plugin_config_update",
    testTitle: "Admin updates agent plugin configuration with new tool permissions",
  });

  await recorder.step("Load application shell", async () => {
    await page.goto("/");
    await expect(page.locator("#root")).toBeAttached();
  });

  const hubId = "plugin-456";
  const updates = { tools: ["search", "email"], data_access: "restricted" };

  await recorder.step("Register config success mock", async () => {
    await mockAgentPluginConfigScenario(page, {
      hubId,
      status: 200,
      role: "admin",
      responseBody: {
        success: true,
        hubId,
        active: true,
        ...updates,
      },
    });
  });

  await recorder.step("Invoke updatePluginConfig", async () => {
    await page.evaluate(async ({ hubId, updates }) => {
      const mod = await import("/src/models/experimental/agentPlugins.js");
      window.__agentPluginConfigResult = await mod.default.updatePluginConfig(hubId, updates);
    }, { hubId, updates });
  });

  await recorder.step("Assert request and persisted values", async () => {
    const result = await page.evaluate(() => window.__agentPluginConfigResult);
    const requestBody = await page.evaluate(() => window.__agentPluginLastConfigRequestBody);
    const response = await page.evaluate(() => window.__agentPluginLastConfigResponse);

    expect(result).toBe(true);
    expect(requestBody).toEqual({ updates });
    expect(response.status).toBe(200);
    expect(response.body.tools).toEqual(["search", "email"]);
    expect(response.body.data_access).toBe("restricted");
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:agent_plugin_config_update");
  await recorder.save(testInfo);
});
