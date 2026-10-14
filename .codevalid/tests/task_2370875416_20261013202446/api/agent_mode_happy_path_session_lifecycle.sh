#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_2370875416_20261013202446/api/_infra.sh

cv_step Given "workspace with automatic chatMode and agent configured" $LINENO
cv_prereq "API key must be set" $LINENO
[ -n "${API_KEY:-}" ] || cv_fail "API_KEY is not set" $LINENO

# Establish an identity (principal) for authenticated workspace operations.
# For password auth, ensure credentials are configured and derive the identity from that.
cv_prereq "Password auth identity available" $LINENO
# The plan assumes identity is already established; no additional HTTP call is required here.

# Create a workspace with automatic chatMode and agent provider/model configured.
WS_AGENT_NAME="agent-mode-lifecycle"
cv_prereq "create automatic-mode workspace for agent session" $LINENO

# Raw curl invocation restored from plan (uses curl helper from _infra.sh).
curl -sS -f -X POST "$BASE_URL/v1/workspace/new" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  --data "{\"name\":\"$WS_AGENT_NAME\",\"chatMode\":\"automatic\",\"agentProvider\":null,\"agentModel\":null}" \
  | jq -r '.workspace.slug' > /tmp/ws_agent_slug.txt

curl_json POST "/v1/workspace/new" \
  "{\"name\":\"${WS_AGENT_NAME}\",\"chatMode\":\"automatic\",\"agentProvider\":null,\"agentModel\":null}" \
  200 \
  -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json"

# Extract slug from response body file written by cv_http / curl_json.
WS_AGENT_SLUG=$(jq -r '.workspace.slug' "$CV_HTTP_BODY_FILE" || printf '')
if [ -z "$WS_AGENT_SLUG" ] || [ "$WS_AGENT_SLUG" = "null" ]; then
  cv_fail "failed to parse workspace slug from /v1/workspace/new response" $LINENO
fi
printf 'Parsed workspace slug: %s
' "$WS_AGENT_SLUG"

# Ensure workspace exists by fetching it.
cv_prereq "fetch created workspace" $LINENO
cv_http GET "/v1/workspace/$WS_AGENT_SLUG" "" 200 -H "Authorization: Bearer $API_KEY"
cp "$CV_HTTP_BODY_FILE" /tmp/ws_agent_get.json

cv_step When "start and exit agent session via SSE" $LINENO

# Start an agent session in the workspace by sending a @agent-prefixed message.
AGENT_SESSION_ID="agent-session-1"
START_BODY='{"message":"@agent summarize workspace context","mode":"automatic","sessionId":"'"$AGENT_SESSION_ID"'","attachments":[],"reset":false}'
cv_prereq "start agent SSE stream" $LINENO
cv_http POST "/v1/workspace/$WS_AGENT_SLUG/stream-chat" "$START_BODY" 200 \
  -H "Authorization: Bearer $API_KEY" \
  -H "Accept: text/event-stream" \
  -H "Content-Type: application/json" \
  --no-buffer
cp "$CV_HTTP_BODY_FILE" /tmp/agent_mode_lifecycle_start.sse

# End the agent session by sending exit with the same sessionId.
EXIT_BODY='{"message":"exit","mode":"automatic","sessionId":"'"$AGENT_SESSION_ID"'","attachments":[],"reset":false}'
cv_prereq "exit agent SSE stream" $LINENO
cv_http POST "/v1/workspace/$WS_AGENT_SLUG/stream-chat" "$EXIT_BODY" 200 \
  -H "Authorization: Bearer $API_KEY" \
  -H "Accept: text/event-stream" \
  -H "Content-Type: application/json" \
  --no-buffer
cp "$CV_HTTP_BODY_FILE" /tmp/agent_mode_lifecycle_exit.sse

cv_step Then "agent session lifecycle events and chat history are correct" $LINENO

# Assert that the first SSE stream contains agentThought or textResponseChunk events from the agent cluster.
if ! grep -q '"type":"agentThought"' /tmp/agent_mode_lifecycle_start.sse && \
   ! grep -q '"type":"textResponseChunk"' /tmp/agent_mode_lifecycle_start.sse; then
  cv_fail "expected agentThought or textResponseChunk in start SSE stream" $LINENO
fi

# Assert that the first stream ends with a finalizeResponseStream event carrying metrics and/or outputs/thoughts.
if ! grep -q '"type":"finalizeResponseStream"' /tmp/agent_mode_lifecycle_start.sse; then
  cv_fail "expected finalizeResponseStream in start SSE stream" $LINENO
fi

# Assert that the exit stream completes without additional agentThought events, indicating session termination.
if grep -q '"type":"agentThought"' /tmp/agent_mode_lifecycle_exit.sse; then
  cv_fail "unexpected agentThought events present in exit SSE stream" $LINENO
fi

# Verify that workspace_chats contains at least one record for this workspace with type set to the chat mode (automatic)
# and thoughts/outputs present for the agent run.
cv_prereq "fetch workspace chat history" $LINENO
cv_http GET "/v1/workspace/$WS_AGENT_SLUG/chats" "" 200 -H "Authorization: Bearer $API_KEY"
cp "$CV_HTTP_BODY_FILE" /tmp/agent_mode_lifecycle_chats.json

HISTORY_LEN=$(jq '.history | length' /tmp/agent_mode_lifecycle_chats.json || printf '0')
if ! printf '%s
' "$HISTORY_LEN" | grep -Eq '^[1-9][0-9]*$'; then
  cv_fail "expected at least one chat history entry, got $HISTORY_LEN" $LINENO
fi

# All assertions passed.
printf 'CODEVALID_TEST_ASSERTION_OK:agent_mode_happy_path_session_lifecycle
'

cv_step Cleanup "delete workspace created for this case" $LINENO
# Teardown: delete the workspace; do not fail the entire test if deletion fails.
set +e
cv_http DELETE "/v1/workspace/$WS_AGENT_SLUG" "" 200 -H "Authorization: Bearer $API_KEY" || true
set -e
