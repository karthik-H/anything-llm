import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import { mockAgentPluginConfigScenario } from "../../helpers/mock-api.js";

test("Config update request fails with non-object updates", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "agent_plugin_config_invalid_updates",
    testTitle: "Config update request fails with non-object updates",
  });

  await recorder.step("Load application shell", async () => {
    await page.goto("/");
    await expect(page.locator("#root")).toBeAttached();
  });

  const hubId = "plugin-invalid-updates";
  await recorder.step("Register validation failure mock", async () => {
    await mockAgentPluginConfigScenario(page, {
      hubId,
      status: 400,
      role: "admin",
      expectedUpdatesType: "object",
      responseBody: {
        success: false,
        error: "Validation error on updates field type.",
      },
    });
  });

  await recorder.step("Invoke updatePluginConfig with invalid string updates", async () => {
    await page.evaluate(async ({ hubId }) => {
      const mod = await import("/src/models/experimental/agentPlugins.js");
      window.__agentPluginInvalidUpdatesResult = await mod.default.updatePluginConfig(hubId, "invalid-string");
    }, { hubId });
  });

  await recorder.step("Assert boolean failure and 400 response", async () => {
    const result = await page.evaluate(() => window.__agentPluginInvalidUpdatesResult);
    const requestBody = await page.evaluate(() => window.__agentPluginLastConfigRequestBody);
    const response = await page.evaluate(() => window.__agentPluginLastConfigResponse);

    expect(result).toBe(false);
    expect(requestBody).toEqual({ updates: "invalid-string" });
    expect(response.status).toBe(400);
    expect(response.body.error).toContain("Validation error");
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:agent_plugin_config_invalid_updates");
  await recorder.save(testInfo);
});
