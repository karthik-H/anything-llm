import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../helpers/execution-recorder.js";
import { mockAgentPluginDeleteScenario } from "../../helpers/mock-api.js";

test("Delete fails with 500 on server exception", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "agent_plugin_delete_server_error",
    testTitle: "Delete fails with 500 on server exception",
  });

  await recorder.step("Load application shell", async () => {
    await page.goto("/");
    await expect(page.locator("#root")).toBeAttached();
  });

  const hubId = "plugin-delete-500";
  await recorder.step("Register delete server error mock", async () => {
    await mockAgentPluginDeleteScenario(page, {
      hubId,
      status: 500,
      role: "admin",
      responseBody: {
        success: false,
        error: "Internal Server Error",
      },
    });
  });

  await recorder.step("Invoke deletePlugin during server error", async () => {
    await page.evaluate(async ({ hubId }) => {
      const mod = await import("/src/models/experimental/agentPlugins.js");
      window.__agentPluginDeleteServerErrorResult = await mod.default.deletePlugin(hubId);
    }, { hubId });
  });

  await recorder.step("Assert boolean failure and 500 response", async () => {
    const result = await page.evaluate(() => window.__agentPluginDeleteServerErrorResult);
    const response = await page.evaluate(() => window.__agentPluginLastDeleteResponse);

    expect(result).toBe(false);
    expect(response.status).toBe(500);
    expect(response.body.error).toBe("Internal Server Error");
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:agent_plugin_delete_server_error");
  await recorder.save(testInfo);
});
