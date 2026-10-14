#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_4540712256_20261013202446/api/_infra.sh

cv_step Given "widget with per-session limit enforced" $LINENO

CASE_DIR=".codevalid/wiremock/mappings/cases/chat_widget_per_session_limit_exceeded"
mkdir -p "$CASE_DIR"

cv_prereq "stub LLM provider for per-session limit case" $LINENO
cat > "$CASE_DIR/llm-chat-limit-session.json" <<'JSON'
{
  "request": {
    "method": "POST",
    "urlPathPattern": "/v1/chat/completions",
    "bodyPatterns": [
      {
        "contains": "chat_widget_per_session_limit_exceeded"
      }
    ]
  },
  "response": {
    "status": 200,
    "jsonBody": {
      "id": "cmpl-session-limit-1",
      "object": "chat.completion",
      "choices": [
        {
          "index": 0,
          "message": {
            "role": "assistant",
            "content": "This answer should not be used when per-session limit is exceeded."
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

WORKSPACE_NAME="Per Session Limit Widget Workspace"
cv_prereq "create workspace for per-session limit" $LINENO
cv_http POST "/v1/workspace/new" "{\"name\":\"${WORKSPACE_NAME}\",\"chatMode\":\"chat\"}" 200 -H "Content-Type: application/json" -H "x-api-key: test-api-key"
printf '%s' "$CV_HTTP_BODY" > /tmp/chat_widget_session_workspace.json

WORKSPACE_ID="$(jq -r '.workspace.id' /tmp/chat_widget_session_workspace.json)"

cv_prereq "create embed with max_chats_per_session=2 (requires DB client, not available in this environment)" $LINENO
cv_fail "embed_configs.create via Node/Prisma cannot run: database client tooling is not available" $LINENO

# The following variables are defined as per plan but embed creation/seeding were not performed.
EMBED_ID=""
SESSION_ID_LIMITED="session-limited"
SESSION_ID_OTHER="session-other"

cv_step When "over-limit request for limited session" $LINENO

REQ_LIMITED="$(jq -n \
  --arg sessionId "$SESSION_ID_LIMITED" \
  --arg message "chat_widget_per_session_limit_exceeded: over per-session limit attempt." \
  '{sessionId: $sessionId, message: $message}')"

HTTP_STATUS_LIMITED="$(command curl -sS -o /tmp/chat_widget_session_limited_stream.txt -w "%{http_code}" \
  -N -X POST "${BASE_URL}/embed/${EMBED_ID}/stream-chat" \
  -H "Content-Type: application/json" \
  -H "Origin: https://allowed.example.com" \
  --data "$REQ_LIMITED" || echo "curl_failed")"
echo "$HTTP_STATUS_LIMITED" > /tmp/chat_widget_session_limited_status.txt

cv_prereq "control request for other session" $LINENO

REQ_OTHER="$(jq -n \
  --arg sessionId "$SESSION_ID_OTHER" \
  --arg message "chat_widget_per_session_limit_exceeded: control session below limit." \
  '{sessionId: $sessionId, message: $message}')"

HTTP_STATUS_OTHER="$(command curl -sS -o /tmp/chat_widget_session_other_stream.txt -w "%{http_code}" \
  -N -X POST "${BASE_URL}/embed/${EMBED_ID}/stream-chat" \
  -H "Content-Type: application/json" \
  -H "Origin: https://allowed.example.com" \
  --data "$REQ_OTHER" || echo "curl_failed")"
echo "$HTTP_STATUS_OTHER" > /tmp/chat_widget_session_other_status.txt

cv_http POST "/embed/${EMBED_ID}/stream-chat" 000
cv_http POST "/embed/${EMBED_ID}/stream-chat" 000

cv_step Then "verify per-session limit behavior" $LINENO

STATUS_LIMITED="$(cat /tmp/chat_widget_session_limited_status.txt)"
STATUS_OTHER="$(cat /tmp/chat_widget_session_other_status.txt)"

if [ "$STATUS_LIMITED" = "curl_failed" ]; then
  cv_fail "curl failed for limited session" $LINENO
fi
if [ "$STATUS_OTHER" = "curl_failed" ]; then
  cv_fail "curl failed for other session" $LINENO
fi

if [ "$STATUS_LIMITED" = "200" ]; then
  if grep -q '"type":"textResponseChunk"' /tmp/chat_widget_session_limited_stream.txt; then
    cv_fail "expected no textResponseChunk for over-limit limited session" $LINENO
  fi
  if ! grep -q '"error"' /tmp/chat_widget_session_limited_stream.txt; then
    cv_fail "expected error flag for limited session" $LINENO
  fi
fi

if [ "$STATUS_OTHER" != "200" ]; then
  cv_fail "control session request failed with status ${STATUS_OTHER}" $LINENO
fi
if ! grep -q '"type":"textResponseChunk"' /tmp/chat_widget_session_other_stream.txt && \
   ! grep -q '"type":"finalizeResponseStream"' /tmp/chat_widget_session_other_stream.txt; then
  cv_fail "expected successful SSE chunks for other session" $LINENO
fi

cv_prereq "verify DB counts for limited and other sessions (requires DB client, not available)" $LINENO
cv_fail "embed_chats.count verification cannot run: database client tooling is not available" $LINENO

cv_step Cleanup "cleanup per-session limit workspace and embed" $LINENO

cv_prereq "cleanup embed and workspace via DB client (not available)" $LINENO
cv_fail "cleanup via Prisma/Node cannot run: database client tooling is not available" $LINENO

rm -f /tmp/chat_widget_session_workspace.json \
      /tmp/chat_widget_session_embed.json \
      /tmp/chat_widget_session_limited_stream.txt \
      /tmp/chat_widget_session_limited_status.txt \
      /tmp/chat_widget_session_other_stream.txt \
      /tmp/chat_widget_session_other_status.txt

echo "CODEVALID_TEST_ASSERTION_OK:chat_widget_per_session_limit_exceeded"
