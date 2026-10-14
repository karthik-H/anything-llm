#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_2370875416_20261013202446/api/_infra.sh

cv_step Given "query-mode workspace that must refuse general knowledge answers" $LINENO
cv_prereq "health check" $LINENO
health_check || cv_fail "health_check failed" $LINENO

# Restore plan's direct health prereq curl
cv_prereq "GET $BASE_URL/health" $LINENO
curl -sS -f "$BASE_URL/health" >/dev/null || cv_fail "health endpoint not healthy" $LINENO

MANAGER_USERNAME_QREF="manager_query_refusal"
MANAGER_PASSWORD_QREF="ManagerQueryRefusalPass123!"
MANAGER_ROLE_QREF="manager"

cv_prereq "seed manager_query_refusal user" $LINENO
cat > /tmp/seed_manager_query_refusal_user.sql <<'SQL'
INSERT INTO users (username, password, role, suspended, createdAt, lastUpdatedAt)
VALUES ('manager_query_refusal', 'ManagerQueryRefusalPass123!', 'manager', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
SQL
sqlite3 server/storage/anythingllm.db < /tmp/seed_manager_query_refusal_user.sql || cv_fail "failed to seed manager_query_refusal user" $LINENO

MANAGER_QREF_USER_ID="$(sqlite3 server/storage/anythingllm.db "SELECT id FROM users WHERE username='manager_query_refusal' LIMIT 1;" || true)"
if [ -z "${MANAGER_QREF_USER_ID}" ]; then
  cv_fail "failed to read MANAGER_QREF_USER_ID" $LINENO
fi

QUERY_REFUSAL_MSG_STRICT="This workspace cannot answer your question from its documents."

cv_prereq "seed query-strict workspace" $LINENO
cat > /tmp/seed_query_strict_workspace.sql <<SQL
INSERT INTO workspaces (name, slug, chatMode, queryRefusalResponse, createdAt, lastUpdatedAt)
VALUES (
  'Query Strict Workspace',
  'query-strict-workspace',
  'query',
  '$QUERY_REFUSAL_MSG_STRICT',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
);
SQL
sqlite3 server/storage/anythingllm.db < /tmp/seed_query_strict_workspace.sql || cv_fail "failed to seed query-strict workspace" $LINENO

QUERY_STRICT_WORKSPACE_ID="$(sqlite3 server/storage/anythingllm.db "SELECT id FROM workspaces WHERE slug='query-strict-workspace' LIMIT 1;" || true)"
if [ -z "${QUERY_STRICT_WORKSPACE_ID}" ]; then
  cv_fail "failed to read QUERY_STRICT_WORKSPACE_ID" $LINENO
fi

cv_prereq "seed general-knowledge question chat that must be refused" $LINENO
cat > /tmp/seed_query_strict_workspace_chats.sql <<SQL
INSERT INTO workspace_chats (workspaceId, prompt, response, include, user_id, createdAt, lastUpdatedAt)
VALUES
  (
    $QUERY_STRICT_WORKSPACE_ID,
    'What is the capital of France?',
    '{"text":"This workspace cannot answer your question from its documents.","sources":[]}',
    1,
    $MANAGER_QREF_USER_ID,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  );
SQL
sqlite3 server/storage/anythingllm.db < /tmp/seed_query_strict_workspace_chats.sql || cv_fail "failed to seed query-strict workspace chats" $LINENO

cv_prereq "login as manager_query_refusal via /request-token" $LINENO
auth_login_request_token "$MANAGER_USERNAME_QREF" "$MANAGER_PASSWORD_QREF" || cv_fail "failed to obtain manager_query_refusal JWT" $LINENO
MANAGER_QREF_TOKEN="$AUTH_TOKEN"

cv_step When "POST /api/system/workspace-chats for query-strict listing" $LINENO
REQUEST_BODY='{"offset":0,"limit":20}'
cv_http POST "/api/system/workspace-chats" "$REQUEST_BODY" 200 -H "Authorization: Bearer $MANAGER_QREF_TOKEN" -H 'Content-Type: application/json'
LIST_RESPONSE="$CV_HTTP_BODY"

cv_step Then "assert query-mode refusal of general-knowledge question" $LINENO
if ! command -v jq >/dev/null 2>&1; then
  cv_fail "jq is required for response assertions" $LINENO
fi

QUERY_STRICT_CHATS="$(printf '%s' "$LIST_RESPONSE" | jq ".chats | map(select(.workspaceId == ($QUERY_STRICT_WORKSPACE_ID|tonumber)))")"

PROMPT_STRICT="What is the capital of France?"
STRICT_TEXT="$(printf '%s' "$QUERY_STRICT_CHATS" | jq -r "[.[] | select(.prompt==\"$PROMPT_STRICT\")][0].response" | jq -r '.text')"

if [ "$STRICT_TEXT" != "$QUERY_REFUSAL_MSG_STRICT" ]; then
  cv_fail "query-strict workspace did not return configured queryRefusalResponse" $LINENO
fi

if printf '%s' "$STRICT_TEXT" | grep -qi "Paris"; then
  cv_fail "query-strict workspace appears to have answered from general knowledge" $LINENO
fi

echo "query_mode_rejects_general_knowledge_answer: OK"

echo "CODEVALID_TEST_ASSERTION_OK:query_mode_rejects_general_knowledge_answer"

cv_step Cleanup "teardown seeded data" $LINENO
sqlite3 server/storage/anythingllm.db "DELETE FROM workspace_chats WHERE workspaceId=$QUERY_STRICT_WORKSPACE_ID;" || cv_fail "failed to delete workspace_chats" $LINENO
sqlite3 server/storage/anythingllm.db "DELETE FROM workspaces WHERE id=$QUERY_STRICT_WORKSPACE_ID;" || cv_fail "failed to delete workspace" $LINENO
sqlite3 server/storage/anythingllm.db "DELETE FROM users WHERE id=$MANAGER_QREF_USER_ID;" || cv_fail "failed to delete manager_query_refusal user" $LINENO
