#!/usr/bin/env bash
set -euo pipefail

# Setup
source .codevalid/tests/task_2370875416_20261013202446/api/_infra.sh
: "${APP_BASE_URL:?APP_BASE_URL must be set}"

cv_step Given "seed user, workspace, thread, api key" $LINENO

cv_prereq "insert user" $LINENO
USER_ID=$(psql -t -A <<'SQL'
INSERT INTO users (username, role)
VALUES ('agent_default_user', 'admin')
RETURNING id;
SQL
)
USER_ID=$(echo "$USER_ID" | tr -d '[:space:]')
[ -n "$USER_ID" ] || cv_fail "USER_ID not returned from users insert" $LINENO

cv_prereq "insert workspace with automatic chatMode" $LINENO
WORKSPACE_ID=$(psql -t -A <<'SQL'
INSERT INTO workspaces (
  name,
  slug,
  openAiPrompt,
  openAiTemp,
  openAiHistory,
  similarityThreshold,
  chatProvider,
  chatModel,
  topN,
  chatMode,
  agentProvider,
  agentModel,
  queryRefusalResponse,
  vectorSearchMode,
  router_id
)
VALUES (
  'Agent Default Workspace',
  'agent-workspace',
  'System prompt',
  0.7,
  20,
  0.25,
  'openai',
  'gpt-4o',
  4,
  'automatic',
  NULL,
  NULL,
  'There is no relevant information in this workspace to answer your query.',
  'default',
  NULL
)
RETURNING id;
SQL
)
WORKSPACE_ID=$(echo "$WORKSPACE_ID" | tr -d '[:space:]')
[ -n "$WORKSPACE_ID" ] || cv_fail "WORKSPACE_ID not returned from workspaces insert" $LINENO

cv_prereq "insert workspace thread" $LINENO
THREAD_ID=$(psql -t -A <<SQL
INSERT INTO workspace_threads (name, slug, user_id, workspace_id)
VALUES ('Agent Thread', 'agent-thread', $USER_ID, $WORKSPACE_ID)
RETURNING id;
SQL
)
THREAD_ID=$(echo "$THREAD_ID" | tr -d '[:space:]')
[ -n "$THREAD_ID" ] || cv_fail "THREAD_ID not returned from workspace_threads insert" $LINENO

cv_prereq "insert api key" $LINENO
API_KEY_SECRET=$(psql -t -A <<'SQL'
INSERT INTO apiKeys (label, secret)
VALUES ('agent_default_key', gen_random_uuid()::text)
RETURNING secret;
SQL
)
API_KEY_SECRET=$(echo "$API_KEY_SECRET" | tr -d '[:space:]')
[ -n "$API_KEY_SECRET" ] || cv_fail "API_KEY_SECRET not returned from apiKeys insert" $LINENO

cleanup() {
  cv_step Cleanup "delete seeded data" $LINENO || true
  psql -v ON_ERROR_STOP=1 <<SQL || true
DELETE FROM workspace_chats WHERE workspaceId = $WORKSPACE_ID;
DELETE FROM workspace_threads WHERE id = $THREAD_ID;
DELETE FROM workspaces WHERE id = $WORKSPACE_ID;
DELETE FROM apiKeys WHERE secret = '$API_KEY_SECRET';
DELETE FROM users WHERE id = $USER_ID;
SQL
}
trap cleanup EXIT

cv_step When "invoke agent then exit on same thread" $LINENO

cv_prereq "POST @agent message" $LINENO
REQ_BODY1=$(cat <<JSON
{
  "message": "@agent agent_mode_default_workspace_session_lifecycle: describe agent behavior",
  "mode": "automatic",
  "userId": $USER_ID,
  "attachments": [],
  "reset": false
}
JSON
)
FIRST_RESP_FILE="/tmp/agent_mode_default_workspace_session_lifecycle_1.json"
curl -sS -X POST "$APP_BASE_URL/v1/workspace/agent-workspace/thread/agent-thread/chat" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY_SECRET" \
  -d "$REQ_BODY1" | tee "$FIRST_RESP_FILE" >/dev/null
cv_http POST "$APP_BASE_URL/v1/workspace/agent-workspace/thread/agent-thread/chat" 200

cv_prereq "POST exit message" $LINENO
REQ_BODY2=$(cat <<JSON
{
  "message": "exit",
  "mode": "automatic",
  "userId": $USER_ID,
  "attachments": [],
  "reset": false
}
JSON
)
SECOND_RESP_FILE="/tmp/agent_mode_default_workspace_session_lifecycle_2.json"
curl -sS -X POST "$APP_BASE_URL/v1/workspace/agent-workspace/thread/agent-thread/chat" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY_SECRET" \
  -d "$REQ_BODY2" | tee "$SECOND_RESP_FILE" >/dev/null
cv_http POST "$APP_BASE_URL/v1/workspace/agent-workspace/thread/agent-thread/chat" 200

cv_step Then "assert agent response and clean session end" $LINENO

# Assert the first response is a textResponse from the agent, scoped to this workspace/thread.
TYPE=$(jq -r '.type' "$FIRST_RESP_FILE")
[ "$TYPE" = "textResponse" ] || cv_fail "expected .type=\"textResponse\" got $TYPE" $LINENO

HAS_TEXT=$(jq '.textResponse != null' "$FIRST_RESP_FILE")
[ "$HAS_TEXT" = "true" ] || cv_fail "expected .textResponse != null in first response" $LINENO

SOURCES_TYPE=$(jq -r '.sources | type' "$FIRST_RESP_FILE")
[ "$SOURCES_TYPE" = "array" ] || cv_fail "expected .sources to be array got $SOURCES_TYPE" $LINENO

CLOSE_VAL=$(jq '.close' "$FIRST_RESP_FILE")
[ "$CLOSE_VAL" = "true" ] || cv_fail "expected .close = true got $CLOSE_VAL" $LINENO

ERROR1=$(jq '.error' "$FIRST_RESP_FILE")
[ "$ERROR1" = "null" ] || cv_fail "expected .error = null in first response got $ERROR1" $LINENO

# Assert the second response corresponds to clean session end (no abort error).
ERROR2=$(jq '.error' "$SECOND_RESP_FILE")
[ "$ERROR2" = "null" ] || cv_fail "expected .error = null in second response got $ERROR2" $LINENO

# Confirm both chats are stored for the same workspace/thread.
THREAD_IDS=$(psql -t -A <<SQL
SELECT thread_id FROM workspace_chats
WHERE workspaceId = $WORKSPACE_ID
ORDER BY id;
SQL
)
# Normalize whitespace
THREAD_IDS_CLEAN=$(echo "$THREAD_IDS" | tr -s '[:space:]' '
' | sed '/^$/d')
if ! echo "$THREAD_IDS_CLEAN" | grep -Fx "$THREAD_ID" >/dev/null 2>&1; then
  cv_fail "workspace_chats does not contain expected THREAD_ID=$THREAD_ID; got: $THREAD_IDS_CLEAN" $LINENO
fi

CODEVALID_TEST_ASSERTION_OK:agent_mode_default_workspace_session_lifecycle
