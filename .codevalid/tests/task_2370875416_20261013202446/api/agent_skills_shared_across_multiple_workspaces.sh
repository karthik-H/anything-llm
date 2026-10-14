#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_2370875416_20261013202446/api/_infra.sh

cv_step Given "two agent-mode workspaces using shared risk-analyzer skill" $LINENO
cv_prereq "health check" $LINENO
health_check || cv_fail "health_check failed" $LINENO

ADMIN_USERNAME_MULTI="admin_multi_agent"
ADMIN_PASSWORD_MULTI="AdminMultiAgentPass123!"
ADMIN_ROLE_MULTI="admin"

cv_prereq "seed admin_multi_agent user" $LINENO
cat > /tmp/seed_admin_multi_agent_user.sql <<'SQL'
INSERT INTO users (username, password, role, suspended, createdAt, lastUpdatedAt)
VALUES ('admin_multi_agent', 'AdminMultiAgentPass123!', 'admin', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
SQL
sqlite3 server/storage/anythingllm.db < /tmp/seed_admin_multi_agent_user.sql || cv_fail "failed to seed admin_multi_agent user" $LINENO

ADMIN_MULTI_USER_ID="$(sqlite3 server/storage/anythingllm.db "SELECT id FROM users WHERE username='admin_multi_agent' LIMIT 1;" || true)"
if [ -z "${ADMIN_MULTI_USER_ID}" ]; then
  cv_fail "failed to read ADMIN_MULTI_USER_ID" $LINENO
fi

cv_prereq "seed Project A and Project B workspaces" $LINENO
cat > /tmp/seed_multi_agent_workspaces.sql <<'SQL'
INSERT INTO workspaces (name, slug, chatMode, createdAt, lastUpdatedAt)
VALUES
  ('Project A Workspace', 'project-a-workspace', 'automatic', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('Project B Workspace', 'project-b-workspace', 'automatic', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
SQL
sqlite3 server/storage/anythingllm.db < /tmp/seed_multi_agent_workspaces.sql || cv_fail "failed to seed multi-agent workspaces" $LINENO

PROJECT_A_ID="$(sqlite3 server/storage/anythingllm.db "SELECT id FROM workspaces WHERE slug='project-a-workspace' LIMIT 1;" || true)"
PROJECT_B_ID="$(sqlite3 server/storage/anythingllm.db "SELECT id FROM workspaces WHERE slug='project-b-workspace' LIMIT 1;" || true)"
if [ -z "${PROJECT_A_ID}" ] || [ -z "${PROJECT_B_ID}" ]; then
  cv_fail "failed to read PROJECT_A_ID or PROJECT_B_ID" $LINENO
fi

cv_prereq "seed risk-analyzer agent chats for both workspaces" $LINENO
cat > /tmp/seed_multi_agent_workspace_chats.sql <<SQL
INSERT INTO workspace_chats (workspaceId, prompt, response, include, user_id, createdAt, lastUpdatedAt)
VALUES
  (
    $PROJECT_A_ID,
    '@agent summarize project A risks using risk-analyzer',
    '{"text":"Used shared risk-analyzer agent skill to summarize risks for Project A based on its documents.","sources":[{"type":"skill","name":"risk-analyzer"}]}',
    1,
    $ADMIN_MULTI_USER_ID,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  ),
  (
    $PROJECT_A_ID,
    'exit',
    '{"text":"Agent session ended for Project A.","sources":[]}',
    1,
    $ADMIN_MULTI_USER_ID,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  ),
  (
    $PROJECT_B_ID,
    '@agent summarize project B risks using risk-analyzer',
    '{"text":"Used the same shared risk-analyzer agent skill but scoped to Project B''s documents.","sources":[{"type":"skill","name":"risk-analyzer"}]}',
    1,
    $ADMIN_MULTI_USER_ID,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  ),
  (
    $PROJECT_B_ID,
    'exit',
    '{"text":"Agent session ended for Project B.","sources":[]}',
    1,
    $ADMIN_MULTI_USER_ID,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  );
SQL
sqlite3 server/storage/anythingllm.db < /tmp/seed_multi_agent_workspace_chats.sql || cv_fail "failed to seed multi-agent workspace chats" $LINENO

cv_prereq "login as admin_multi_agent via /request-token" $LINENO
auth_login_request_token "$ADMIN_USERNAME_MULTI" "$ADMIN_PASSWORD_MULTI" || cv_fail "failed to obtain admin_multi_agent JWT" $LINENO
ADMIN_MULTI_TOKEN="$AUTH_TOKEN"

cv_step When "POST /api/system/workspace-chats for multi-agent listing" $LINENO
REQUEST_BODY='{"offset":0,"limit":50}'
LIST_RESPONSE="$(
  curl -sS -X POST "$BASE_URL/api/system/workspace-chats" \
    -H "Authorization: Bearer $ADMIN_MULTI_TOKEN" \
    -H 'Content-Type: application/json' \
    -d "$REQUEST_BODY"
)"
if command -v jq >/dev/null 2>&1; then
  printf '%s\n' "$LIST_RESPONSE" | jq '.'
else
  printf '%s\n' "$LIST_RESPONSE"
fi

cv_step Then "assert shared risk-analyzer skill across workspaces" $LINENO
if ! command -v jq >/dev/null 2>&1; then
  cv_fail "jq is required for response assertions" $LINENO
fi

PROJECT_A_CHATS="$(printf '%s' "$LIST_RESPONSE" | jq ".chats | map(select(.workspaceId == ($PROJECT_A_ID|tonumber)))")"
PROJECT_B_CHATS="$(printf '%s' "$LIST_RESPONSE" | jq ".chats | map(select(.workspaceId == ($PROJECT_B_ID|tonumber)))")"

A_AGENT_COUNT="$(printf '%s' "$PROJECT_A_CHATS" | jq '[.[] | select(.prompt | startswith("@agent"))] | length')"
A_EXIT_COUNT="$(printf '%s' "$PROJECT_A_CHATS" | jq '[.[] | select(.prompt=="exit")] | length')"
B_AGENT_COUNT="$(printf '%s' "$PROJECT_B_CHATS" | jq '[.[] | select(.prompt | startswith("@agent"))] | length')"
B_EXIT_COUNT="$(printf '%s' "$PROJECT_B_CHATS" | jq '[.[] | select(.prompt=="exit")] | length')"

if [ "$A_AGENT_COUNT" -lt 1 ] || [ "$A_EXIT_COUNT" -lt 1 ] || [ "$B_AGENT_COUNT" -lt 1 ] || [ "$B_EXIT_COUNT" -lt 1 ]; then
  cv_fail "expected @agent and exit chats for both Project A and B" $LINENO
fi

A_AGENT_RESP_JSON="$(printf '%s' "$PROJECT_A_CHATS" | jq -r '[.[] | select(.prompt | startswith("@agent"))][0].response')"
B_AGENT_RESP_JSON="$(printf '%s' "$PROJECT_B_CHATS" | jq -r '[.[] | select(.prompt | startswith("@agent"))][0].response')"
A_AGENT_RESP_TEXT="$(printf '%s' "$A_AGENT_RESP_JSON" | jq -r '.text')"
B_AGENT_RESP_TEXT="$(printf '%s' "$B_AGENT_RESP_JSON" | jq -r '.text')"
A_AGENT_SOURCE_SKILL="$(printf '%s' "$A_AGENT_RESP_JSON" | jq -r '.sources[0].name')"
B_AGENT_SOURCE_SKILL="$(printf '%s' "$B_AGENT_RESP_JSON" | jq -r '.sources[0].name')"

if [ "$A_AGENT_SOURCE_SKILL" != "risk-analyzer" ] || [ "$B_AGENT_SOURCE_SKILL" != "risk-analyzer" ]; then
  cv_fail "risk-analyzer skill not present in both workspace agent responses" $LINENO
fi

if ! printf '%s' "$A_AGENT_RESP_TEXT" | grep -q "Project A"; then
  cv_fail "Project A agent response not clearly scoped to Project A" $LINENO
fi

if ! printf '%s' "$B_AGENT_RESP_TEXT" | grep -q "Project B"; then
  cv_fail "Project B agent response not clearly scoped to Project B" $LINENO
fi

echo "agent_skills_shared_across_multiple_workspaces: OK"

echo "CODEVALID_TEST_ASSERTION_OK:agent_skills_shared_across_multiple_workspaces"

cv_step Cleanup "teardown seeded data" $LINENO
sqlite3 server/storage/anythingllm.db "DELETE FROM workspace_chats WHERE workspaceId IN ($PROJECT_A_ID,$PROJECT_B_ID);" || cv_fail "failed to delete workspace_chats" $LINENO
sqlite3 server/storage/anythingllm.db "DELETE FROM workspaces WHERE id IN ($PROJECT_A_ID,$PROJECT_B_ID);" || cv_fail "failed to delete workspaces" $LINENO
sqlite3 server/storage/anythingllm.db "DELETE FROM users WHERE id=$ADMIN_MULTI_USER_ID;" || cv_fail "failed to delete admin_multi_agent user" $LINENO
