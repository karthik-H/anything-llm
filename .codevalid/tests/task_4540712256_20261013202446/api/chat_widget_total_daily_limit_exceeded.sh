#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_4540712256_20261013202446/api/_infra.sh

cv_step Given "widget with max_chats_per_day enforced" $LINENO

CASE_DIR=".codevalid/wiremock/mappings/cases/chat_widget_total_daily_limit_exceeded"
mkdir -p "$CASE_DIR"

cv_prereq "stub LLM provider for daily limit case" $LINENO
cat > "$CASE_DIR/llm-chat-limit-daily.json" <<'JSON'
{
  "request": {
    "method": "POST",
    "urlPathPattern": "/v1/chat/completions",
    "bodyPatterns": [
      {
        "contains": "chat_widget_total_daily_limit_exceeded"
      }
    ]
  },
  "response": {
    "status": 200,
    "jsonBody": {
      "id": "cmpl-daily-limit-1",
      "object": "chat.completion",
      "choices": [
        {
          "index": 0,
          "message": {
            "role": "assistant",
            "content": "This answer should not be used when daily limit is exceeded."
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

WORKSPACE_NAME="Daily Limit Widget Workspace"
cv_prereq "create workspace for daily limit case" $LINENO
cv_http POST "/v1/workspace/new" "{\"name\":\"${WORKSPACE_NAME}\",\"chatMode\":\"chat\"}" 200 -H "Content-Type: application/json" -H "x-api-key: test-api-key"
printf '%s' "$CV_HTTP_BODY" > /tmp/chat_widget_daily_workspace.json

WORKSPACE_ID="$(jq -r '.workspace.id' /tmp/chat_widget_daily_workspace.json)"

cv_prereq "create embed with max_chats_per_day=3" $LINENO
# Use psql to insert embed_configs row instead of Node/Prisma
EMBED_UUID="embed-$(printf '%s' "$RANDOM$RANDOM$RANDOM")"
export WORKSPACE_ID
export EMBED_UUID
EMBED_ID="$(
  psql -At <<'SQL'
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
  :'EMBED_UUID',
  true,
  'chat',
  '["https://allowed.example.com"]',
  false,
  false,
  false,
  3,
  NULL,
  20,
  :'WORKSPACE_ID'
)
RETURNING id;
SQL
)"
# psql -At prints the id followed by newline; trim whitespace
EMBED_ID="$(printf '%s' "$EMBED_ID" | tr -d '[:space:]')"

SESSION_ID="daily-limit-session"

cv_prereq "seed embed_chats rows to reach daily limit" $LINENO
export EMBED_ID
export SESSION_ID
psql <<'SQL'
INSERT INTO embed_chats (
  prompt,
  embed_id,
  response,
  connection_information,
  session_id,
  include
) VALUES
  ('Seed prompt 0', :'EMBED_ID', '{"text":"Seed response","sources":[],"type":"chat"}', '{"origin":"https://allowed.example.com"}', :'SESSION_ID', true),
  ('Seed prompt 1', :'EMBED_ID', '{"text":"Seed response","sources":[],"type":"chat"}', '{"origin":"https://allowed.example.com"}', :'SESSION_ID', true),
  ('Seed prompt 2', :'EMBED_ID', '{"text":"Seed response","sources":[],"type":"chat"}', '{"origin":"https://allowed.example.com"}', :'SESSION_ID', true);
SQL

cv_step When "attempt chat over daily limit" $LINENO

REQUEST_JSON="$(jq -n \
  --arg sessionId "$SESSION_ID" \
  --arg message "chat_widget_total_daily_limit_exceeded: over daily limit attempt." \
  '{sessionId: $sessionId, message: $message}')"

HTTP_STATUS="$(command curl -sS -o /tmp/chat_widget_daily_stream.txt -w "%{http_code}" \
  -N -X POST "${BASE_URL}/embed/${EMBED_ID}/stream-chat" \
  -H "Content-Type: application/json" \
  -H "Origin: https://allowed.example.com" \
  --data "$REQUEST_JSON" || echo "curl_failed")"
echo "$HTTP_STATUS" > /tmp/chat_widget_daily_status.txt

cv_http POST "/embed/${EMBED_ID}/stream-chat" "$HTTP_STATUS" 000

cv_step Then "verify refusal when daily limit exceeded" $LINENO

STATUS="$(cat /tmp/chat_widget_daily_status.txt)"
if [ "$STATUS" = "curl_failed" ]; then
  cv_fail "curl failed for daily limit request" $LINENO
fi

if [ "$STATUS" = "200" ]; then
  if grep -q '"type":"textResponseChunk"' /tmp/chat_widget_daily_stream.txt; then
    cv_fail "expected no textResponseChunk for over daily limit" $LINENO
  fi
  if ! grep -q '"error"' /tmp/chat_widget_daily_stream.txt; then
    cv_fail "expected error flag in daily limit response" $LINENO
  fi
fi

cv_prereq "ensure daily count remains 3" $LINENO
# Use psql to assert embed_chats count
export EMBED_ID
COUNT="$(
  psql -At <<'SQL'
SELECT COUNT(*) FROM embed_chats WHERE embed_id = :'EMBED_ID';
SQL
)"
COUNT="$(printf '%s' "$COUNT" | tr -d '[:space:]')"
if [ "$COUNT" != "3" ]; then
  cv_fail "Expected 3 embed_chats rows (preseeded), found ${COUNT}" $LINENO
fi

cv_step Cleanup "cleanup daily limit workspace and embed" $LINENO

export WORKSPACE_ID
export EMBED_ID
psql <<'SQL'
DELETE FROM embed_chats WHERE embed_id = :'EMBED_ID';
DELETE FROM embed_configs WHERE id = :'EMBED_ID';
DELETE FROM workspaces WHERE id = :'WORKSPACE_ID';
SQL

rm -f /tmp/chat_widget_daily_workspace.json \
      /tmp/chat_widget_daily_embed.json \
      /tmp/chat_widget_daily_stream.txt \
      /tmp/chat_widget_daily_status.txt

echo "CODEVALID_TEST_ASSERTION_OK:chat_widget_total_daily_limit_exceeded"
