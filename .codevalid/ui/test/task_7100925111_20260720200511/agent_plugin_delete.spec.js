import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import { mockAgentPluginDeleteScenario } from "../../helpers/mock-api.js";

test("Admin deletes an agent plugin from the system", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "agent_plugin_delete",
    testTitle: "Admin deletes an agent plugin from the system",
  });

  await recorder.step("Load application shell", async () => {
    await page.goto("/");
    await expect(page.locator("#root")).toBeAttached();
  });

  const hubId = "plugin-delete-1";
  await recorder.step("Register delete success mock", async () => {
    await mockAgentPluginDeleteScenario(page, {
      hubId,
      status: 200,
      role: "admin",
      responseBody: {
        success: true,
        deleted: true,
        hubId,
      },
    });
  });

  await recorder.step("Invoke deletePlugin", async () => {
    await page.evaluate(async ({ hubId }) => {
      const mod = await import("/src/models/experimental/agentPlugins.js");
      window.__agentPluginDeleteResult = await mod.default.deletePlugin(hubId);
    }, { hubId });
  });

  await recorder.step("Assert delete response", async () => {
    const result = await page.evaluate(() => window.__agentPluginDeleteResult);
    const response = await page.evaluate(() => window.__agentPluginLastDeleteResponse);

    expect(result).toBe(true);
    expect(response.status).toBe(200);
    expect(response.body.deleted).toBe(true);
    expect(response.body.hubId).toBe(hubId);
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:agent_plugin_delete");
  await recorder.save(testInfo);
});
