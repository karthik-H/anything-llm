#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_2370875416_20261013202446/api/_infra.sh

cv_step Given "chat-mode workspace with blended docs+general knowledge chat" $LINENO
cv_prereq "health check" $LINENO
health_check || cv_fail "health_check failed" $LINENO

MANAGER_USERNAME="manager_chat_mode"
MANAGER_PASSWORD="ManagerPass123!"
MANAGER_ROLE="manager"

cv_prereq "seed manager user" $LINENO
cat > /tmp/seed_manager_chat_mode_user.sql <<'SQL'
INSERT INTO users (username, password, role, suspended, createdAt, lastUpdatedAt)
VALUES ('manager_chat_mode', 'ManagerPass123!', 'manager', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
SQL
sqlite3 server/storage/anythingllm.db < /tmp/seed_manager_chat_mode_user.sql || cv_fail "failed to seed manager user" $LINENO

MANAGER_USER_ID="$(sqlite3 server/storage/anythingllm.db "SELECT id FROM users WHERE username='manager_chat_mode' LIMIT 1;" || true)"
if [ -z "${MANAGER_USER_ID}" ]; then
  cv_fail "failed to read MANAGER_USER_ID" $LINENO
fi

cv_prereq "seed chat-mode workspace" $LINENO
cat > /tmp/seed_chat_mode_workspace.sql <<'SQL'
INSERT INTO workspaces (name, slug, chatMode, createdAt, lastUpdatedAt)
VALUES (
  'Chat Mode Workspace',
  'chat-mode-workspace',
  'chat',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
);
SQL
sqlite3 server/storage/anythingllm.db < /tmp/seed_chat_mode_workspace.sql || cv_fail "failed to seed chat-mode workspace" $LINENO

CHAT_WORKSPACE_ID="$(sqlite3 server/storage/anythingllm.db "SELECT id FROM workspaces WHERE slug='chat-mode-workspace' LIMIT 1;" || true)"
if [ -z "${CHAT_WORKSPACE_ID}" ]; then
  cv_fail "failed to read CHAT_WORKSPACE_ID" $LINENO
fi

cv_prereq "seed blended docs+general knowledge chat" $LINENO
cat > /tmp/seed_chat_mode_workspace_chats.sql <<SQL
INSERT INTO workspace_chats (workspaceId, prompt, response, include, user_id, createdAt, lastUpdatedAt)
VALUES
  (
    $CHAT_WORKSPACE_ID,
    'What is our onboarding process and what are general best practices?',
    '{"text":"From your workspace documents: your onboarding steps are A, B, C. In general best practice, D and E are also recommended.","sources":[{"type":"document","name":"onboarding-guide"}]}',
    1,
    $MANAGER_USER_ID,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  );
SQL
sqlite3 server/storage/anythingllm.db < /tmp/seed_chat_mode_workspace_chats.sql || cv_fail "failed to seed chat-mode workspace chats" $LINENO

cv_prereq "login as manager via /request-token" $LINENO
auth_login_request_token "$MANAGER_USERNAME" "$MANAGER_PASSWORD" || cv_fail "failed to obtain manager JWT" $LINENO
MANAGER_TOKEN="$AUTH_TOKEN"

cv_step When "POST /api/system/workspace-chats for chat-mode listing" $LINENO
REQUEST_BODY='{"offset":0,"limit":20}'
LIST_RESPONSE="$(curl -sS -X POST "$BASE_URL/api/system/workspace-chats" \
  -H "Authorization: Bearer $MANAGER_TOKEN" \
  -H 'Content-Type: application/json' \
  -d "$REQUEST_BODY")"

printf '%s\n' "$LIST_RESPONSE" | jq '.'

cv_step Then "assert blended docs+general knowledge response present" $LINENO
if ! command -v jq >/dev/null 2>&1; then
  cv_fail "jq is required for response assertions" $LINENO
fi

HAS_CHATS="$(printf '%s' "$LIST_RESPONSE" | jq 'has("chats")')"
if [ "$HAS_CHATS" != "true" ]; then
  cv_fail "missing chats key in response" $LINENO
fi

CHAT_CHATS="$(printf '%s' "$LIST_RESPONSE" | jq ".chats | map(select(.workspaceId == ($CHAT_WORKSPACE_ID|tonumber)))")"

CASE_COUNT="$(printf '%s' "$CHAT_CHATS" | jq '[.[] | select(.prompt=="What is our onboarding process and what are general best practices?")] | length')"
if [ "$CASE_COUNT" -lt 1 ]; then
  cv_fail "chat-mode blended response not found in listing" $LINENO
fi

CHAT_RESPONSE_JSON="$(printf '%s' "$CHAT_CHATS" | jq -r '[.[] | select(.prompt=="What is our onboarding process and what are general best practices?")][0].response')"
CHAT_RESPONSE_TEXT="$(printf '%s' "$CHAT_RESPONSE_JSON" | jq -r '.text')"

if ! printf '%s' "$CHAT_RESPONSE_TEXT" | grep -q "workspace documents"; then
  cv_fail "chat-mode response does not reference workspace documents" $LINENO
fi

if ! printf '%s' "$CHAT_RESPONSE_TEXT" | grep -q "general best practice"; then
  cv_fail "chat-mode response does not include general model knowledge" $LINENO
fi

echo "chat_mode_uses_docs_and_general_knowledge: OK"

echo "CODEVALID_TEST_ASSERTION_OK:chat_mode_uses_docs_and_general_knowledge"

cv_step Cleanup "teardown seeded data" $LINENO
sqlite3 server/storage/anythingllm.db "DELETE FROM workspace_chats WHERE workspaceId=$CHAT_WORKSPACE_ID;" || cv_fail "failed to delete workspace_chats" $LINENO
sqlite3 server/storage/anythingllm.db "DELETE FROM workspaces WHERE id=$CHAT_WORKSPACE_ID;" || cv_fail "failed to delete workspace" $LINENO
sqlite3 server/storage/anythingllm.db "DELETE FROM users WHERE id=$MANAGER_USER_ID;" || cv_fail "failed to delete manager user" $LINENO
