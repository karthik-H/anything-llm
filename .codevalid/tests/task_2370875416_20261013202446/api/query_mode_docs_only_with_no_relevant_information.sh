#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_2370875416_20261013202446/api/_infra.sh

cv_step Given "query-mode workspace with docs-only and no-relevant-information chats" $LINENO
cv_prereq "GET /health" $LINENO
cv_http GET "/health" "" 200

MANAGER_USERNAME_QM="manager_query_mode"
MANAGER_PASSWORD_QM="ManagerQMPass123!"
MANAGER_ROLE_QM="manager"

cv_prereq "seed manager user" $LINENO
cat > /tmp/seed_manager_query_mode_user.sql <<'SQL'
INSERT INTO users (username, password, role, suspended, createdAt, lastUpdatedAt)
VALUES ('manager_query_mode', 'ManagerQMPass123!', 'manager', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
SQL
sqlite3 server/storage/anythingllm.db < /tmp/seed_manager_query_mode_user.sql || cv_fail "failed to seed manager_query_mode user" $LINENO

MANAGER_QM_USER_ID="$(sqlite3 server/storage/anythingllm.db "SELECT id FROM users WHERE username='manager_query_mode' LIMIT 1;" || true)"
if [ -z "${MANAGER_QM_USER_ID}" ]; then
  cv_fail "failed to read MANAGER_QM_USER_ID" $LINENO
fi

QUERY_REFUSAL_MSG="No relevant information found in workspace documents."

cv_prereq "seed query-mode workspace with queryRefusalResponse" $LINENO
cat > /tmp/seed_query_mode_workspace.sql <<SQL
INSERT INTO workspaces (name, slug, chatMode, queryRefusalResponse, createdAt, lastUpdatedAt)
VALUES (
  'Query Mode Workspace',
  'query-mode-workspace',
  'query',
  '$QUERY_REFUSAL_MSG',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
);
SQL
sqlite3 server/storage/anythingllm.db < /tmp/seed_query_mode_workspace.sql || cv_fail "failed to seed query-mode workspace" $LINENO

QUERY_WORKSPACE_ID="$(sqlite3 server/storage/anythingllm.db "SELECT id FROM workspaces WHERE slug='query-mode-workspace' LIMIT 1;" || true)"
if [ -z "${QUERY_WORKSPACE_ID}" ]; then
  cv_fail "failed to read QUERY_WORKSPACE_ID" $LINENO
fi

cv_prereq "seed query-mode workspace chats (no-match and docs-only)" $LINENO
cat > /tmp/seed_query_mode_workspace_chats.sql <<SQL
INSERT INTO workspace_chats (workspaceId, prompt, response, include, user_id, createdAt, lastUpdatedAt)
VALUES
  (
    $QUERY_WORKSPACE_ID,
    'What is the GDP of a random country not covered by our docs?',
    '{"text":"No relevant information found in workspace documents.","sources":[]}',
    1,
    $MANAGER_QM_USER_ID,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  ),
  (
    $QUERY_WORKSPACE_ID,
    'Summarize our internal onboarding checklist.',
    '{"text":"Based solely on your workspace onboarding documents: step A, B, C.","sources":[{"type":"document","name":"onboarding-checklist"}]}',
    1,
    $MANAGER_QM_USER_ID,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  );
SQL
sqlite3 server/storage/anythingllm.db < /tmp/seed_query_mode_workspace_chats.sql || cv_fail "failed to seed query-mode workspace chats" $LINENO

cv_prereq "login as manager_query_mode via /request-token" $LINENO
auth_login_request_token "$MANAGER_USERNAME_QM" "$MANAGER_PASSWORD_QM" || cv_fail "failed to obtain manager_query_mode JWT" $LINENO
MANAGER_QM_TOKEN="$AUTH_TOKEN"

cv_step When "POST /api/system/workspace-chats for query-mode listing" $LINENO
LIST_RESPONSE="$(curl -sS -X POST "$BASE_URL/api/system/workspace-chats" \
  -H "Authorization: Bearer $MANAGER_QM_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"offset":0,"limit":20}')"

printf '%s\n' "$LIST_RESPONSE" | jq '.'

cv_step Then "assert docs-only and no-relevant-information behavior" $LINENO
if ! command -v jq >/dev/null 2>&1; then
  cv_fail "jq is required for response assertions" $LINENO
fi

QUERY_CHATS="$(printf '%s' "$LIST_RESPONSE" | jq ".chats | map(select(.workspaceId == ($QUERY_WORKSPACE_ID|tonumber)))")"

NO_MATCH_PROMPT="What is the GDP of a random country not covered by our docs?"
DOC_MATCH_PROMPT="Summarize our internal onboarding checklist."

NO_MATCH_TEXT="$(printf '%s' "$QUERY_CHATS" | jq -r "[.[] | select(.prompt==\"$NO_MATCH_PROMPT\")][0].response" | jq -r '.text')"
DOC_MATCH_TEXT="$(printf '%s' "$QUERY_CHATS" | jq -r "[.[] | select(.prompt==\"$DOC_MATCH_PROMPT\")][0].response" | jq -r '.text')"

if [ "$NO_MATCH_TEXT" != "$QUERY_REFUSAL_MSG" ]; then
  cv_fail "no-match response does not equal queryRefusalResponse" $LINENO
fi

if printf '%s' "$DOC_MATCH_TEXT" | grep -qi "general"; then
  cv_fail "docs-only answer appears to include general model knowledge" $LINENO
fi

if ! printf '%s' "$DOC_MATCH_TEXT" | grep -q "Based solely on your workspace onboarding documents"; then
  cv_fail "docs-only answer not clearly sourced solely from workspace documents" $LINENO
fi

echo "query_mode_docs_only_with_no_relevant_information: OK"

echo "CODEVALID_TEST_ASSERTION_OK:query_mode_docs_only_with_no_relevant_information"

cv_step Cleanup "teardown seeded data" $LINENO
sqlite3 server/storage/anythingllm.db "DELETE FROM workspace_chats WHERE workspaceId=$QUERY_WORKSPACE_ID;" || cv_fail "failed to delete workspace_chats" $LINENO
sqlite3 server/storage/anythingllm.db "DELETE FROM workspaces WHERE id=$QUERY_WORKSPACE_ID;" || cv_fail "failed to delete workspace" $LINENO
sqlite3 server/storage/anythingllm.db "DELETE FROM users WHERE id=$MANAGER_QM_USER_ID;" || cv_fail "failed to delete manager user" $LINENO
