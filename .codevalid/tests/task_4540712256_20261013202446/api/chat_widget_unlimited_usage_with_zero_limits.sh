#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_4540712256_20261013202446/api/_infra.sh

cv_step Given "widget with zero/NULL limits allowing unlimited usage" $LINENO

CASE_DIR=".codevalid/wiremock/mappings/cases/chat_widget_unlimited_usage_with_zero_limits"
mkdir -p "$CASE_DIR"

cv_prereq "stub LLM provider for unlimited usage" $LINENO
cat > "$CASE_DIR/llm-chat-unlimited.json" <<'JSON'
{
  "request": {
    "method": "POST",
    "urlPathPattern": "/v1/chat/completions",
    "bodyPatterns": [
      {
        "contains": "chat_widget_unlimited_usage_with_zero_limits"
      }
    ]
  },
  "response": {
    "status": 200,
    "jsonBody": {
      "id": "cmpl-unlimited-1",
      "object": "chat.completion",
      "choices": [
        {
          "index": 0,
          "message": {
            "role": "assistant",
            "content": "Unlimited chat response for widget."
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

WORKSPACE_NAME="Unlimited Widget Workspace"
cv_prereq "create workspace for unlimited usage" $LINENO
WORKSPACE_BODY="$(jq -n --arg name "$WORKSPACE_NAME" --arg chatMode "chat" '{name: $name, chatMode: $chatMode}')"
cv_http POST "/v1/workspace/new" "$WORKSPACE_BODY" 200 -H "Content-Type: application/json" -H "x-api-key: test-api-key"
printf '%s' "$CV_HTTP_BODY" > /tmp/chat_widget_unlimited_workspace.json

WORKSPACE_ID="$(jq -r '.workspace.id' /tmp/chat_widget_unlimited_workspace.json)"

cv_prereq "create embed with null limits via database" $LINENO
# Create embed_configs row directly using psql and return its id.
EMBED_ID="$(
  psql -X -q <<SQL | awk 'NR==1{print $1}'
INSERT INTO embed_configs (uuid, enabled, chat_mode, allowlist_domains, allow_model_override,
                           allow_temperature_override, allow_prompt_override, max_chats_per_day,
                           max_chats_per_session, message_limit, "workspaceId")
VALUES (
  gen_random_uuid(),
  true,
  'chat',
  '[\"https://allowed.example.com\",\"https://another.example.com\"]',
  false,
  false,
  false,
  NULL,
  NULL,
  20,
  ${WORKSPACE_ID}
)
RETURNING id;
SQL
)"

SESSION_ID_1="unlimited-session-1"
SESSION_ID_2="unlimited-session-2"

cv_step When "send multiple chats across sessions/origins" $LINENO

: > /tmp/chat_widget_unlimited_stream.txt

# Direct curl call restored from plan (diagnostic helper wraps curl in infra)
curl -sS -f -N -X POST "http://app:6713/embed/${EMBED_ID}/stream-chat" \
  -H "Content-Type: application/json" \
  -H "Origin: https://allowed.example.com" \
  --data "$(jq -n \
    --arg sessionId "$SESSION_ID_1" \
    --arg message "chat_widget_unlimited_usage_with_zero_limits: initial request for session 1." \
    '{sessionId: $sessionId, message: $message}')" \
  >> /tmp/chat_widget_unlimited_stream.txt

for i in $(seq 1 5); do
  BODY="$(jq -n --arg sessionId "$SESSION_ID_1" --arg message "chat_widget_unlimited_usage_with_zero_limits: request $i for session 1." '{sessionId: $sessionId, message: $message}')"
  cv_http POST "/embed/${EMBED_ID}/stream-chat" "$BODY" 200 -H "Content-Type: application/json" -H "Origin: https://allowed.example.com" -N
  printf '%s' "$CV_HTTP_BODY" >> /tmp/chat_widget_unlimited_stream.txt
done

for i in $(seq 1 5); do
  BODY="$(jq -n --arg sessionId "$SESSION_ID_2" --arg message "chat_widget_unlimited_usage_with_zero_limits: request $i for session 2." '{sessionId: $sessionId, message: $message}')"
  cv_http POST "/embed/${EMBED_ID}/stream-chat" "$BODY" 200 -H "Content-Type: application/json" -H "Origin: https://another.example.com" -N
  printf '%s' "$CV_HTTP_BODY" >> /tmp/chat_widget_unlimited_stream.txt
done

cv_step Then "verify multiple successful SSE responses and DB counts" $LINENO

if ! grep -q '"type":"textResponseChunk"' /tmp/chat_widget_unlimited_stream.txt && \
   ! grep -q '"type":"finalizeResponseStream"' /tmp/chat_widget_unlimited_stream.txt; then
  cv_fail "expected multiple SSE chunks for unlimited usage" $LINENO
fi

cv_prereq "verify embed_chats counts exceed typical limits using SQL" $LINENO
# Check that at least 5 chats per session exist for this embed.
COUNT_SESSION_1="$(
  psql -X -q <<SQL | awk 'NR==1{print $1}'
SELECT COUNT(*) FROM embed_chats
WHERE embed_id = ${EMBED_ID} AND session_id = '${SESSION_ID_1}';
SQL
)"
COUNT_SESSION_2="$(
  psql -X -q <<SQL | awk 'NR==1{print $1}'
SELECT COUNT(*) FROM embed_chats
WHERE embed_id = ${EMBED_ID} AND session_id = '${SESSION_ID_2}';
SQL
)"

if [ "${COUNT_SESSION_1:-0}" -lt 5 ] || [ "${COUNT_SESSION_2:-0}" -lt 5 ]; then
  cv_fail "Expected at least 5 chats per session: got count1=${COUNT_SESSION_1:-0}, count2=${COUNT_SESSION_2:-0}" $LINENO
fi

cv_step Cleanup "cleanup unlimited usage workspace and embed" $LINENO

# Delete embed chats and config, then workspace to keep DB clean
psql -X -q <<SQL
DELETE FROM embed_chats WHERE embed_id = ${EMBED_ID};
DELETE FROM embed_configs WHERE id = ${EMBED_ID};
DELETE FROM workspaces WHERE id = ${WORKSPACE_ID};
SQL

rm -f /tmp/chat_widget_unlimited_workspace.json \
      /tmp/chat_widget_unlimited_embed.json \
      /tmp/chat_widget_unlimited_stream.txt

echo "CODEVALID_TEST_ASSERTION_OK:chat_widget_unlimited_usage_with_zero_limits"
