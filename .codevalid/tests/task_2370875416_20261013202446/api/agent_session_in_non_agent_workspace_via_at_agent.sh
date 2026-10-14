#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_2370875416_20261013202446/api/_infra.sh

cv_step Given "non-Agent workspace with @agent session and follow-up chats" $LINENO
cv_prereq "health check" $LINENO
health_check || cv_fail "health_check failed" $LINENO

ADMIN_USERNAME_NONAGENT="admin_non_agent_workspace"
ADMIN_PASSWORD_NONAGENT="AdminNonAgentPass123!"
ADMIN_ROLE_NONAGENT="admin"

cv_prereq "seed admin_non_agent_workspace user" $LINENO
cat > /tmp/seed_admin_non_agent_user.sql <<'SQL'
INSERT INTO users (username, password, role, suspended, createdAt, lastUpdatedAt)
VALUES ('admin_non_agent_workspace', 'AdminNonAgentPass123!', 'admin', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
SQL
sqlite3 server/storage/anythingllm.db < /tmp/seed_admin_non_agent_user.sql || cv_fail "failed to seed admin_non_agent_workspace user" $LINENO

ADMIN_NONAGENT_USER_ID="$(sqlite3 server/storage/anythingllm.db "SELECT id FROM users WHERE username='admin_non_agent_workspace' LIMIT 1;" || true)"
if [ -z "${ADMIN_NONAGENT_USER_ID}" ]; then
  cv_fail "failed to read ADMIN_NONAGENT_USER_ID" $LINENO
fi

cv_prereq "seed non-Agent workspace" $LINENO
cat > /tmp/seed_non_agent_workspace.sql <<'SQL'
INSERT INTO workspaces (name, slug, chatMode, createdAt, lastUpdatedAt)
VALUES (
  'Non-Agent Workspace',
  'non-agent-workspace',
  'chat',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
);
SQL
sqlite3 server/storage/anythingllm.db < /tmp/seed_non_agent_workspace.sql || cv_fail "failed to seed non-Agent workspace" $LINENO

NON_AGENT_WORKSPACE_ID="$(sqlite3 server/storage/anythingllm.db "SELECT id FROM workspaces WHERE slug='non-agent-workspace' LIMIT 1;" || true)"
if [ -z "${NON_AGENT_WORKSPACE_ID}" ]; then
  cv_fail "failed to read NON_AGENT_WORKSPACE_ID" $LINENO
fi

cv_prereq "seed non-Agent workspace chats sequence" $LINENO
cat > /tmp/seed_non_agent_workspace_chats.sql <<SQL
INSERT INTO workspace_chats (workspaceId, prompt, response, include, user_id, createdAt, lastUpdatedAt)
VALUES
  (
    $NON_AGENT_WORKSPACE_ID,
    'Normal chat question in non-Agent workspace.',
    '{"text":"Here is an answer using the workspace documents and chat behavior.","sources":[{"type":"document","name":"workspace-doc"}]}',
    1,
    $ADMIN_NONAGENT_USER_ID,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  ),
  (
    $NON_AGENT_WORKSPACE_ID,
    '@agent fetch external metrics and combine with workspace data',
    '{"text":"Agent session started via @agent. Used shared agent skills to fetch metrics and combined them with this workspace''s documents.","sources":[{"type":"skill","name":"metrics-fetch"}]}',
    1,
    $ADMIN_NONAGENT_USER_ID,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  ),
  (
    $NON_AGENT_WORKSPACE_ID,
    'exit',
    '{"text":"Agent session ended for this non-Agent workspace. Subsequent messages will use its original chat behavior.","sources":[]}',
    1,
    $ADMIN_NONAGENT_USER_ID,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  ),
  (
    $NON_AGENT_WORKSPACE_ID,
    'Follow-up question after agent session ended.',
    '{"text":"Answered using the workspace''s Chat mode without agent tools.","sources":[{"type":"document","name":"workspace-doc"}]}',
    1,
    $ADMIN_NONAGENT_USER_ID,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  );
SQL
sqlite3 server/storage/anythingllm.db < /tmp/seed_non_agent_workspace_chats.sql || cv_fail "failed to seed non-Agent workspace chats" $LINENO

cv_prereq "login as admin_non_agent_workspace via /request-token" $LINENO
auth_login_request_token "$ADMIN_USERNAME_NONAGENT" "$ADMIN_PASSWORD_NONAGENT" || cv_fail "failed to obtain admin_non_agent_workspace JWT" $LINENO
ADMIN_NONAGENT_TOKEN="$AUTH_TOKEN"

cv_step When "POST /api/system/workspace-chats for non-Agent workspace listing" $LINENO
LIST_RESPONSE="$(curl -sS -X POST "$BASE_URL/api/system/workspace-chats" \
  -H "Authorization: Bearer $ADMIN_NONAGENT_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"offset":0,"limit":20}')"

printf '%s\n' "$LIST_RESPONSE" | jq '.'

cv_step Then "assert non-Agent workspace @agent session and follow-up semantics" $LINENO
if ! command -v jq >/dev/null 2>&1; then
  cv_fail "jq is required for response assertions" $LINENO
fi

NON_AGENT_CHATS="$(printf '%s' "$LIST_RESPONSE" | jq ".chats | map(select(.workspaceId == ($NON_AGENT_WORKSPACE_ID|tonumber)))")"

NORMAL_COUNT_NONAGENT="$(printf '%s' "$NON_AGENT_CHATS" | jq '[.[] | select(.prompt=="Normal chat question in non-Agent workspace.") ] | length')"
AGENT_COUNT_NONAGENT="$(printf '%s' "$NON_AGENT_CHATS" | jq '[.[] | select(.prompt | startswith("@agent")) ] | length')"
EXIT_COUNT_NONAGENT="$(printf '%s' "$NON_AGENT_CHATS" | jq '[.[] | select(.prompt=="exit") ] | length')"
FOLLOWUP_COUNT_NONAGENT="$(printf '%s' "$NON_AGENT_CHATS" | jq '[.[] | select(.prompt=="Follow-up question after agent session ended.") ] | length')"

if [ "$NORMAL_COUNT_NONAGENT" -lt 1 ] || [ "$AGENT_COUNT_NONAGENT" -lt 1 ] || [ "$EXIT_COUNT_NONAGENT" -lt 1 ] || [ "$FOLLOWUP_COUNT_NONAGENT" -lt 1 ]; then
  cv_fail "expected normal, @agent, exit, and follow-up chats for non-Agent workspace" $LINENO
fi

AGENT_RESP_JSON_NONAGENT="$(printf '%s' "$NON_AGENT_CHATS" | jq -r '[.[] | select(.prompt | startswith("@agent"))][0].response')"
AGENT_RESP_TEXT_NONAGENT="$(printf '%s' "$AGENT_RESP_JSON_NONAGENT" | jq -r '.text')"
AGENT_RESP_SOURCE_TYPE_NONAGENT="$(printf '%s' "$AGENT_RESP_JSON_NONAGENT" | jq -r '.sources[0].type')"

if ! printf '%s' "$AGENT_RESP_TEXT_NONAGENT" | grep -q "Agent session started via @agent"; then
  cv_fail "@agent response does not indicate agent session start" $LINENO
fi

if [ "$AGENT_RESP_SOURCE_TYPE_NONAGENT" != "skill" ]; then
  cv_fail "@agent response sources[0].type is not skill" $LINENO
fi

EXIT_RESP_JSON_NONAGENT="$(printf '%s' "$NON_AGENT_CHATS" | jq -r '[.[] | select(.prompt=="exit")][0].response')"
EXIT_RESP_TEXT_NONAGENT="$(printf '%s' "$EXIT_RESP_JSON_NONAGENT" | jq -r '.text')"
if ! printf '%s' "$EXIT_RESP_TEXT_NONAGENT" | grep -q "Agent session ended"; then
  cv_fail "exit response does not mark session end" $LINENO
fi

FOLLOWUP_RESP_JSON_NONAGENT="$(printf '%s' "$NON_AGENT_CHATS" | jq -r '[.[] | select(.prompt=="Follow-up question after agent session ended.")][0].response')"
FOLLOWUP_RESP_TEXT_NONAGENT="$(printf '%s' "$FOLLOWUP_RESP_JSON_NONAGENT" | jq -r '.text')"
if ! printf '%s' "$FOLLOWUP_RESP_TEXT_NONAGENT" | grep -q "Chat mode without agent tools"; then
  cv_fail "follow-up response does not reflect Chat mode without agent tools" $LINENO
fi

echo "agent_session_in_non_agent_workspace_via_at_agent: OK"

echo "CODEVALID_TEST_ASSERTION_OK:agent_session_in_non_agent_workspace_via_at_agent"

cv_step Cleanup "teardown seeded data" $LINENO
sqlite3 server/storage/anythingllm.db "DELETE FROM workspace_chats WHERE workspaceId=$NON_AGENT_WORKSPACE_ID;" || cv_fail "failed to delete workspace_chats" $LINENO
sqlite3 server/storage/anythingllm.db "DELETE FROM workspaces WHERE id=$NON_AGENT_WORKSPACE_ID;" || cv_fail "failed to delete workspace" $LINENO
sqlite3 server/storage/anythingllm.db "DELETE FROM users WHERE id=$ADMIN_NONAGENT_USER_ID;" || cv_fail "failed to delete admin user" $LINENO
