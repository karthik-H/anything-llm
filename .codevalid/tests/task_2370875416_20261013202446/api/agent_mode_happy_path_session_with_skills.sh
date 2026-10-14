#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_2370875416_20261013202446/api/_infra.sh

cv_step Given "agent-mode workspace with @agent session and exit chats seeded" $LINENO
cv_prereq "health check" $LINENO
health_check || cv_fail "health_check failed" $LINENO

# 2. Seed an admin user and an Agent-behaving workspace plus representative workspace_chats rows.
ADMIN_USERNAME="admin_agent_mode"
ADMIN_PASSWORD="AdminPass123!"
ADMIN_ROLE="admin"

cv_prereq "seed admin user" $LINENO
cat > /tmp/seed_admin_user_agent_mode.sql <<'SQL'
INSERT INTO users (username, password, role, suspended, createdAt, lastUpdatedAt)
VALUES ('admin_agent_mode', 'AdminPass123!', 'admin', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
SQL
sqlite3 server/storage/anythingllm.db < /tmp/seed_admin_user_agent_mode.sql || cv_fail "failed to seed admin user" $LINENO

ADMIN_USER_ID="$(sqlite3 server/storage/anythingllm.db "SELECT id FROM users WHERE username='admin_agent_mode' LIMIT 1;" || true)"
if [ -z "${ADMIN_USER_ID}" ]; then
  cv_fail "failed to read ADMIN_USER_ID" $LINENO
fi

cv_prereq "seed agent-mode workspace" $LINENO
cat > /tmp/seed_agent_workspace.sql <<'SQL'
INSERT INTO workspaces (name, slug, chatMode, agentProvider, agentModel, createdAt, lastUpdatedAt)
VALUES (
  'Agent Mode Workspace',
  'agent-mode-workspace',
  'automatic',
  'openai',
  'gpt-4o',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
);
SQL
sqlite3 server/storage/anythingllm.db < /tmp/seed_agent_workspace.sql || cv_fail "failed to seed agent workspace" $LINENO

AGENT_WORKSPACE_ID="$(sqlite3 server/storage/anythingllm.db "SELECT id FROM workspaces WHERE slug='agent-mode-workspace' LIMIT 1;" || true)"
if [ -z "${AGENT_WORKSPACE_ID}" ]; then
  cv_fail "failed to read AGENT_WORKSPACE_ID" $LINENO
fi

cv_prereq "seed agent workspace chats" $LINENO
cat > /tmp/seed_agent_workspace_chats.sql <<SQL
INSERT INTO workspace_chats (workspaceId, prompt, response, include, user_id, createdAt, lastUpdatedAt)
VALUES
  (
    $AGENT_WORKSPACE_ID,
    'Tell me about our project timeline.',
    '{"text":"Here is your project timeline based on workspace context and agent defaults.","sources":[]}',
    1,
    $ADMIN_USER_ID,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  ),
  (
    $AGENT_WORKSPACE_ID,
    '@agent summarize open tasks and use the task-tracker skill',
    '{"text":"I used the task-tracker skill and other configured tools to summarize open tasks scoped to this workspace.","sources":[{"type":"skill","name":"task-tracker"}]}',
    1,
    $ADMIN_USER_ID,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  ),
  (
    $AGENT_WORKSPACE_ID,
    'exit',
    '{"text":"Agent session ended. I will now answer as normal agent-mode chat within this workspace.","sources":[]}',
    1,
    $ADMIN_USER_ID,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  );
SQL
sqlite3 server/storage/anythingllm.db < /tmp/seed_agent_workspace_chats.sql || cv_fail "failed to seed agent workspace chats" $LINENO

cv_prereq "login as admin via /request-token" $LINENO
auth_login_request_token "$ADMIN_USERNAME" "$ADMIN_PASSWORD" || cv_fail "failed to obtain admin JWT" $LINENO
ADMIN_TOKEN="$AUTH_TOKEN"

cv_step When "POST /api/system/workspace-chats for agent-mode listing" $LINENO
LIST_RESPONSE="$(curl -sS -X POST "$BASE_URL/api/system/workspace-chats" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"offset":0,"limit":20}')"

cv_step Then "assert agent-mode chats and responses present" $LINENO
if ! command -v jq >/dev/null 2>&1; then
  cv_fail "jq is required for response assertions" $LINENO
fi

HAS_CHATS="$(printf '%s' "$LIST_RESPONSE" | jq 'has("chats")')"
HAS_TOTAL_CHATS="$(printf '%s' "$LIST_RESPONSE" | jq 'has("totalChats")')"
HAS_HASPAGES="$(printf '%s' "$LIST_RESPONSE" | jq 'has("hasPages")')"

if [ "$HAS_CHATS" != "true" ] || [ "$HAS_TOTAL_CHATS" != "true" ] || [ "$HAS_HASPAGES" != "true" ]; then
  cv_fail "response missing chats/totalChats/hasPages keys" $LINENO
fi

AGENT_CHATS="$(printf '%s' "$LIST_RESPONSE" | jq ".chats | map(select(.workspaceId == ($AGENT_WORKSPACE_ID|tonumber)))")"

NORMAL_COUNT="$(printf '%s' "$AGENT_CHATS" | jq '[.[] | select(.prompt=="Tell me about our project timeline.") ] | length')"
AGENT_SESSION_COUNT="$(printf '%s' "$AGENT_CHATS" | jq '[.[] | select(.prompt | startswith("@agent")) ] | length')"
EXIT_COUNT="$(printf '%s' "$AGENT_CHATS" | jq '[.[] | select(.prompt=="exit") ] | length')"

if [ "$NORMAL_COUNT" -lt 1 ] || [ "$AGENT_SESSION_COUNT" -lt 1 ] || [ "$EXIT_COUNT" -lt 1 ]; then
  cv_fail "expected normal, @agent, and exit chats for agent workspace" $LINENO
fi

AGENT_SESSION_RESPONSE_JSON="$(printf '%s' "$AGENT_CHATS" | jq -r '[.[] | select(.prompt | startswith("@agent"))][0].response')"
AGENT_SESSION_RESPONSE_TEXT="$(printf '%s' "$AGENT_SESSION_RESPONSE_JSON" | jq -r '.text')"
AGENT_SESSION_SOURCES_TYPE="$(printf '%s' "$AGENT_SESSION_RESPONSE_JSON" | jq -r '.sources[0].type')"

if ! printf '%s' "$AGENT_SESSION_RESPONSE_TEXT" | grep -q "task-tracker"; then
  cv_fail "@agent response text does not mention task-tracker" $LINENO
fi

if [ "$AGENT_SESSION_SOURCES_TYPE" != "skill" ]; then
  cv_fail "@agent response sources[0].type is not skill" $LINENO
fi

EXIT_RESPONSE_JSON="$(printf '%s' "$AGENT_CHATS" | jq -r '[.[] | select(.prompt=="exit")][0].response')"
EXIT_RESPONSE_TEXT="$(printf '%s' "$EXIT_RESPONSE_JSON" | jq -r '.text')"

if ! printf '%s' "$EXIT_RESPONSE_TEXT" | grep -q "Agent session ended"; then
  cv_fail "exit response text does not indicate agent session termination" $LINENO
fi

echo "agent_mode_happy_path_session_with_skills: OK"

echo "CODEVALID_TEST_ASSERTION_OK:agent_mode_happy_path_session_with_skills"

cv_step Cleanup "teardown seeded data" $LINENO
sqlite3 server/storage/anythingllm.db "DELETE FROM workspace_chats WHERE workspaceId=$AGENT_WORKSPACE_ID;" || cv_fail "failed to delete workspace_chats" $LINENO
sqlite3 server/storage/anythingllm.db "DELETE FROM workspaces WHERE id=$AGENT_WORKSPACE_ID;" || cv_fail "failed to delete workspace" $LINENO
sqlite3 server/storage/anythingllm.db "DELETE FROM users WHERE id=$ADMIN_USER_ID;" || cv_fail "failed to delete admin user" $LINENO
