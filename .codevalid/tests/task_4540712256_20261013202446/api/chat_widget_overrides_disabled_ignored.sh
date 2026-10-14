#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_4540712256_20261013202446/api/_infra.sh

cv_step Given "widget with overrides disabled" $LINENO

CASE_DIR=".codevalid/wiremock/mappings/cases/chat_widget_overrides_disabled_ignored"
mkdir -p "$CASE_DIR"

cv_prereq "stub LLM provider reflecting workspace defaults" $LINENO
cat > "$CASE_DIR/llm-chat-overrides-disabled.json" <<'JSON'
{
  "request": {
    "method": "POST",
    "urlPathPattern": "/v1/chat/completions",
    "bodyPatterns": [
      {
        "contains": "chat_widget_overrides_disabled_ignored"
      }
    ]
  },
  "response": {
    "status": 200,
    "jsonBody": {
      "id": "cmpl-overrides-disabled-1",
      "object": "chat.completion",
      "choices": [
        {
          "index": 0,
          "message": {
            "role": "assistant",
            "content": "Response using workspace defaults, not client overrides."
          },
          "finish_reason": "stop"
        }
      ]
    }
  }
}
JSON

cv_prereq "import WireMock mappings" $LINENO
wiremock_admin_import_mappings "$CASE_DIR"

WORKSPACE_NAME="Overrides Disabled Workspace"
cv_prereq "create workspace with explicit defaults" $LINENO
NEW_WS_BODY="$(jq -n \
  --arg name "$WORKSPACE_NAME" \
  --arg mode "chat" \
  --arg prompt "Default system prompt for overrides-disabled case." \
  --argjson temp 0.7 '
  {
    name: $name,
    chatMode: $mode,
    openAiTemp: $temp,
    openAiPrompt: $prompt
  }')"
cv_http POST "/v1/workspace/new" "$NEW_WS_BODY" 200 -H "Content-Type: application/json" -H "x-api-key: test-api-key"
printf '%s' "$CV_HTTP_BODY" > /tmp/chat_widget_overrides_workspace.json

WORKSPACE_ID="$(jq -r '.workspace.id' /tmp/chat_widget_overrides_workspace.json)"
WORKSPACE_SLUG="$(jq -r '.workspace.slug' /tmp/chat_widget_overrides_workspace.json)"

cv_prereq "set chatProvider and chatModel via update" $LINENO
UPDATE_WS_BODY='{"chatProvider":"openai","chatModel":"gpt-default-model"}'
cv_http POST "/v1/workspace/${WORKSPACE_SLUG}/update" "$UPDATE_WS_BODY" 200 -H "Content-Type: application/json" -H "x-api-key: test-api-key"
printf '%s' "$CV_HTTP_BODY" > /tmp/chat_widget_overrides_update_workspace.json

cv_prereq "create embed with overrides disabled via SQL" $LINENO
export WORKSPACE_ID
psql <<SQL
INSERT INTO embed_configs (
  uuid,
  enabled,
  chat_mode,
  allowlist_domains,
  allow_model_override,
  allow_temperature_override,
  allow_prompt_override,
  max_chats_per_day,
  max_chats_per_session,
  message_limit,
  workspace_id
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  TRUE,
  'chat',
  '["https://allowed.example.com"]',
  FALSE,
  FALSE,
  FALSE,
  NULL,
  NULL,
  20,
  ${WORKSPACE_ID}
)
RETURNING id;
SQL
EMBED_ID="$(psql -t -A <<SQL
SELECT id FROM embed_configs
WHERE workspace_id = ${WORKSPACE_ID}
ORDER BY id DESC
LIMIT 1;
SQL
)"
EMBED_ID="$(echo "$EMBED_ID" | tr -d '[:space:]')"

SESSION_ID="overrides-disabled-session"

cv_step When "attempt to send client overrides for prompt/model/temp" $LINENO

REQUEST_JSON="$(jq -n \
  --arg sessionId "$SESSION_ID" \
  --arg message "chat_widget_overrides_disabled_ignored: attempt to override model, prompt, and temperature." \
  --arg prompt "Client override system prompt that should be ignored." \
  --arg model "client-override-model" \
  --argjson temperature 0.1 '
  {
    sessionId: $sessionId,
    message: $message,
    prompt: $prompt,
    model: $model,
    temperature: $temperature
  }')"

curl -sS -f -N -X POST "http://app:6713/embed/${EMBED_ID}/stream-chat" \
  -H "Content-Type: application/json" \
  -H "Origin: https://allowed.example.com" \
  --data "$REQUEST_JSON" \
  > /tmp/chat_widget_overrides_stream.txt

cv_step Then "verify overrides are ignored and workspace config unchanged" $LINENO

if ! grep -q '"type":"textResponseChunk"' /tmp/chat_widget_overrides_stream.txt && \
   ! grep -q '"type":"finalizeResponseStream"' /tmp/chat_widget_overrides_stream.txt; then
  cv_fail "expected successful SSE chunks for overrides-disabled case" $LINENO
fi

cv_prereq "check workspace configuration" $LINENO
export WORKSPACE_ID
WS_VALUES="$(psql -t -A <<SQL
SELECT COALESCE(openAiTemp, 0), COALESCE(openAiPrompt, '')
FROM workspaces
WHERE id = ${WORKSPACE_ID};
SQL
)"
OPENAI_TEMP="$(echo "$WS_VALUES" | cut -d'|' -f1)"
OPENAI_PROMPT="$(echo "$WS_VALUES" | cut -d'|' -f2-)"

if [ "$OPENAI_TEMP" != "0.7" ]; then
  cv_fail "Expected workspace.openAiTemp to remain 0.7, found ${OPENAI_TEMP}" $LINENO
fi
if [ "$OPENAI_PROMPT" != "Default system prompt for overrides-disabled case." ]; then
  cv_fail "Workspace openAiPrompt was unexpectedly mutated by overrides." $LINENO
fi

cv_step Cleanup "cleanup overrides-disabled workspace and embed" $LINENO

export EMBED_ID
psql <<SQL
DELETE FROM embed_chats WHERE embed_id = ${EMBED_ID};
DELETE FROM embed_configs WHERE id = ${EMBED_ID};
DELETE FROM workspaces WHERE id = ${WORKSPACE_ID};
SQL

rm -f /tmp/chat_widget_overrides_workspace.json \
      /tmp/chat_widget_overrides_update_workspace.json \
      /tmp/chat_widget_overrides_embed.json \
      /tmp/chat_widget_overrides_stream.txt

echo "CODEVALID_TEST_ASSERTION_OK:chat_widget_overrides_disabled_ignored"
