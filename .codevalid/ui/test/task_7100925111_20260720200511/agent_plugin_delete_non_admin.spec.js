import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import { mockAgentPluginDeleteScenario } from "../../helpers/mock-api.js";

test("Non-admin user cannot delete agent plugin", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "agent_plugin_delete_non_admin",
    testTitle: "Non-admin user cannot delete agent plugin",
  });

  await recorder.step("Load application shell", async () => {
    await page.goto("/");
    await expect(page.locator("#root")).toBeAttached();
  });

  const hubId = "plugin-forbidden-delete";
  await recorder.step("Register forbidden delete mock", async () => {
    await mockAgentPluginDeleteScenario(page, {
      hubId,
      status: 403,
      role: "user",
      responseBody: {
        success: false,
        error: "Forbidden",
      },
    });
  });

  await recorder.step("Invoke deletePlugin as non-admin scenario", async () => {
    await page.evaluate(async ({ hubId }) => {
      const mod = await import("/src/models/experimental/agentPlugins.js");
      window.__agentPluginDeleteForbiddenResult = await mod.default.deletePlugin(hubId);
    }, { hubId });
  });

  await recorder.step("Assert authorization failure", async () => {
    const result = await page.evaluate(() => window.__agentPluginDeleteForbiddenResult);
    const response = await page.evaluate(() => window.__agentPluginLastDeleteResponse);

    expect(result).toBe(false);
    expect(response.status).toBe(403);
    expect(response.body.error).toBe("Forbidden");
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:agent_plugin_delete_non_admin");
  await recorder.save(testInfo);
});
