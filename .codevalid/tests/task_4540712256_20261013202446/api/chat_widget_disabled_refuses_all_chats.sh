#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_4540712256_20261013202446/api/_infra.sh

cv_step Given "disabled widget that must refuse all chats" $LINENO

CASE_DIR=".codevalid/wiremock/mappings/cases/chat_widget_disabled_refuses_all_chats"
mkdir -p "$CASE_DIR"

cv_prereq "stub LLM provider (should not be used)" $LINENO
cat > "$CASE_DIR/llm-chat-disabled.json" <<'JSON'
{
  "request": {
    "method": "POST",
    "urlPathPattern": "/v1/chat/completions",
    "bodyPatterns": [
      {
        "contains": "chat_widget_disabled_refuses_all_chats"
      }
    ]
  },
  "response": {
    "status": 200,
    "jsonBody": {
      "id": "cmpl-disabled-1",
      "object": "chat.completion",
      "choices": [
        {
          "index": 0,
          "message": {
            "role": "assistant",
            "content": "This answer should never be used because widget is disabled."
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

WORKSPACE_NAME="Disabled Widget Workspace"
cv_prereq "create workspace for disabled widget" $LINENO
cv_http POST "/v1/workspace/new" "{\"name\":\"${WORKSPACE_NAME}\",\"chatMode\":\"chat\"}" 200 -H "Content-Type: application/json" -H "x-api-key: test-api-key"
printf '%s' "$CV_HTTP_BODY" > /tmp/chat_widget_disabled_workspace.json

WORKSPACE_ID="$(jq -r '.workspace.id' /tmp/chat_widget_disabled_workspace.json)"
export WORKSPACE_ID

cv_prereq "create disabled embed config" $LINENO
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
  md5(random()::text),
  false,
  'chat',
  '["https://allowed.example.com"]',
  false,
  false,
  false,
  NULL,
  NULL,
  20,
  ${WORKSPACE_ID}
);
SQL

EMBED_ID="$(psql -Atqc "SELECT id FROM embed_configs WHERE workspace_id = ${WORKSPACE_ID} ORDER BY id DESC LIMIT 1;")"
export EMBED_ID
SESSION_ID="disabled-session"
export SESSION_ID

cv_step When "attempt chat on disabled widget" $LINENO

REQUEST_JSON="$(jq -n \
  --arg sessionId "$SESSION_ID" \
  --arg message "chat_widget_disabled_refuses_all_chats: attempt to chat on disabled widget." \
  '{sessionId: $sessionId, message: $message}')"

HTTP_STATUS="$(command curl -sS -o /tmp/chat_widget_disabled_stream.txt -w "%{http_code}" \
  -N -X POST "${BASE_URL}/embed/${EMBED_ID}/stream-chat" \
  -H "Content-Type: application/json" \
  -H "Origin: https://allowed.example.com" \
  --data "$REQUEST_JSON" || echo "curl_failed")"
echo "$HTTP_STATUS" > /tmp/chat_widget_disabled_status.txt

cv_http POST "/embed/${EMBED_ID}/stream-chat" "$HTTP_STATUS" 000

cv_step Then "verify disabled widget refuses and records no chats" $LINENO

STATUS="$(cat /tmp/chat_widget_disabled_status.txt)"
if [ "$STATUS" = "curl_failed" ]; then
  cv_fail "curl failed for disabled widget request" $LINENO
fi

if [ "$STATUS" = "200" ]; then
  if grep -q '"type":"textResponseChunk"' /tmp/chat_widget_disabled_stream.txt; then
    cv_fail "expected no textResponseChunk for disabled widget" $LINENO
  fi
  if ! grep -q '"error"' /tmp/chat_widget_disabled_stream.txt; then
    cv_fail "expected error flag for disabled widget" $LINENO
  fi
fi

cv_prereq "ensure no embed_chats rows created" $LINENO
CHAT_COUNT="$(psql -Atqc "SELECT COUNT(*) FROM embed_chats WHERE embed_id = ${EMBED_ID} AND session_id = '${SESSION_ID}';")"
if [ "${CHAT_COUNT}" != "0" ]; then
  cv_fail "Embed chats were created for disabled widget case" $LINENO
fi

cv_step Cleanup "cleanup disabled widget workspace and embed" $LINENO

psql <<SQL
DELETE FROM embed_chats WHERE embed_id = ${EMBED_ID};
DELETE FROM embed_configs WHERE id = ${EMBED_ID};
DELETE FROM workspaces WHERE id = ${WORKSPACE_ID};
SQL

rm -f /tmp/chat_widget_disabled_workspace.json \
      /tmp/chat_widget_disabled_embed.json \
      /tmp/chat_widget_disabled_stream.txt \
      /tmp/chat_widget_disabled_status.txt

echo "CODEVALID_TEST_ASSERTION_OK:chat_widget_disabled_refuses_all_chats"
