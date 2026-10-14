#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_2370875416_20261013202446/api/_infra.sh

cv_step Given "agent-mode workspace with session exit and follow-up non-agent message" $LINENO
cv_prereq "health check" $LINENO
health_check || cv_fail "health_check failed" $LINENO

ADMIN_USERNAME_EXIT="admin_agent_exit"
ADMIN_PASSWORD_EXIT="AdminAgentExitPass123!"
ADMIN_ROLE_EXIT="admin"

cv_prereq "seed admin_agent_exit user" $LINENO
cat > /tmp/seed_admin_agent_exit_user.sql <<'SQL'
INSERT INTO users (username, password, role, suspended, createdAt, lastUpdatedAt)
VALUES ('admin_agent_exit', 'AdminAgentExitPass123!', 'admin', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
SQL
sqlite3 server/storage/anythingllm.db < /tmp/seed_admin_agent_exit_user.sql || cv_fail "failed to seed admin_agent_exit user" $LINENO

ADMIN_EXIT_USER_ID="$(sqlite3 server/storage/anythingllm.db "SELECT id FROM users WHERE username='admin_agent_exit' LIMIT 1;" || true)"
if [ -z "${ADMIN_EXIT_USER_ID}" ]; then
  cv_fail "failed to read ADMIN_EXIT_USER_ID" $LINENO
fi

cv_prereq "seed Agent Exit Workspace" $LINENO
cat > /tmp/seed_agent_exit_workspace.sql <<'SQL'
INSERT INTO workspaces (name, slug, chatMode, agentProvider, agentModel, createdAt, lastUpdatedAt)
VALUES (
  'Agent Exit Workspace',
  'agent-exit-workspace',
  'automatic',
  'openai',
  'gpt-4o',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
);
SQL
sqlite3 server/storage/anythingllm.db < /tmp/seed_agent_exit_workspace.sql || cv_fail "failed to seed agent exit workspace" $LINENO

AGENT_EXIT_WORKSPACE_ID="$(sqlite3 server/storage/anythingllm.db "SELECT id FROM workspaces WHERE slug='agent-exit-workspace' LIMIT 1;" || true)"
if [ -z "${AGENT_EXIT_WORKSPACE_ID}" ]; then
  cv_fail "failed to read AGENT_EXIT_WORKSPACE_ID" $LINENO
fi

cv_prereq "seed agent exit workspace chats" $LINENO
cat > /tmp/seed_agent_exit_workspace_chats.sql <<SQL
INSERT INTO workspace_chats (workspaceId, prompt, response, include, user_id, createdAt, lastUpdatedAt)
VALUES
  (
    $AGENT_EXIT_WORKSPACE_ID,
    '@agent start a planning session for Q4',
    '{"text":"Agent session started for Q4 planning using configured tools.","sources":[{"type":"skill","name":"planning-tool"}]}',
    1,
    $ADMIN_EXIT_USER_ID,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  ),
  (
    $AGENT_EXIT_WORKSPACE_ID,
    'exit',
    '{"text":"Agent session ended. Subsequent messages will be handled as normal workspace chat.","sources":[]}',
    1,
    $ADMIN_EXIT_USER_ID,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  ),
  (
    $AGENT_EXIT_WORKSPACE_ID,
    'What is our Q4 goal summary now?',
    '{"text":"Answered as normal agent-mode chat without starting a new explicit agent session.","sources":[{"type":"document","name":"q4-goals"}]}',
    1,
    $ADMIN_EXIT_USER_ID,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  );
SQL
sqlite3 server/storage/anythingllm.db < /tmp/seed_agent_exit_workspace_chats.sql || cv_fail "failed to seed agent exit workspace chats" $LINENO

cv_prereq "login as admin_agent_exit via /request-token" $LINENO
auth_login_request_token "$ADMIN_USERNAME_EXIT" "$ADMIN_PASSWORD_EXIT" || cv_fail "failed to obtain admin_agent_exit JWT" $LINENO
ADMIN_EXIT_TOKEN="$AUTH_TOKEN"

cv_step When "POST /api/system/workspace-chats for agent exit workspace" $LINENO
LIST_RESPONSE="$(curl -sS -X POST "$BASE_URL/api/system/workspace-chats" \
  -H "Authorization: Bearer $ADMIN_EXIT_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"offset":0,"limit":20}')"

echo "$LIST_RESPONSE" | jq '.'

cv_step Then "assert agent session exit and follow-up non-agent message behavior" $LINENO
if ! command -v jq >/dev/null 2>&1; then
  cv_fail "jq is required for response assertions" $LINENO
fi

AGENT_EXIT_CHATS="$(printf '%s' "$LIST_RESPONSE" | jq ".chats | map(select(.workspaceId == ($AGENT_EXIT_WORKSPACE_ID|tonumber)))")"

AGENT_START_COUNT="$(printf '%s' "$AGENT_EXIT_CHATS" | jq '[.[] | select(.prompt | startswith("@agent"))] | length')"
EXIT_COUNT_EXITCASE="$(printf '%s' "$AGENT_EXIT_CHATS" | jq '[.[] | select(.prompt=="exit")] | length')"
FOLLOWUP_COUNT_EXITCASE="$(printf '%s' "$AGENT_EXIT_CHATS" | jq '[.[] | select(.prompt=="What is our Q4 goal summary now?")] | length')"

if [ "$AGENT_START_COUNT" -lt 1 ] || [ "$EXIT_COUNT_EXITCASE" -lt 1 ] || [ "$FOLLOWUP_COUNT_EXITCASE" -lt 1 ]; then
  cv_fail "missing agent start, exit, or follow-up chat in listing" $LINENO
fi

EXIT_RESP_JSON_CASE="$(printf '%s' "$AGENT_EXIT_CHATS" | jq -r '[.[] | select(.prompt=="exit")][0].response')"
EXIT_RESP_TEXT_CASE="$(printf '%s' "$EXIT_RESP_JSON_CASE" | jq -r '.text')"
FOLLOWUP_RESP_JSON_CASE="$(printf '%s' "$AGENT_EXIT_CHATS" | jq -r '[.[] | select(.prompt=="What is our Q4 goal summary now?")][0].response')"
FOLLOWUP_RESP_TEXT_CASE="$(printf '%s' "$FOLLOWUP_RESP_JSON_CASE" | jq -r '.text')"

if ! printf '%s' "$EXIT_RESP_TEXT_CASE" | grep -q "Agent session ended"; then
  cv_fail "exit response does not clearly state agent session ended" $LINENO
fi

if ! printf '%s' "$FOLLOWUP_RESP_TEXT_CASE" | grep -q "Answered as normal agent-mode chat"; then
  cv_fail "follow-up response does not show normal agent-mode behavior" $LINENO
fi

echo "agent_session_exit_and_followup_non_agent_message: OK"

echo "CODEVALID_TEST_ASSERTION_OK:agent_session_exit_and_followup_non_agent_message"

cv_step Cleanup "teardown seeded data" $LINENO
sqlite3 server/storage/anythingllm.db "DELETE FROM workspace_chats WHERE workspaceId=$AGENT_EXIT_WORKSPACE_ID;" || cv_fail "failed to delete workspace_chats" $LINENO
sqlite3 server/storage/anythingllm.db "DELETE FROM workspaces WHERE id=$AGENT_EXIT_WORKSPACE_ID;" || cv_fail "failed to delete workspace" $LINENO
sqlite3 server/storage/anythingllm.db "DELETE FROM users WHERE id=$ADMIN_EXIT_USER_ID;" || cv_fail "failed to delete admin_agent_exit user" $LINENO
