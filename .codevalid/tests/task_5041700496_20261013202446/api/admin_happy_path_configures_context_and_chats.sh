#!/usr/bin/env bash
set -euo pipefail

# Case: admin_happy_path_configures_context_and_chats

source .codevalid/tests/task_5041700496_20261013202446/api/_infra.sh

BASE_URL="http://app:6713"
CASE_ID="admin_happy_path_configures_context_and_chats"

########################################
# Setup
########################################
cv_step Given "setup dependencies and DB connectivity" $LINENO

cv_prereq "toxiproxy:5432" $LINENO
cv_prereq "wiremock:8080" $LINENO
cv_prereq "app:6713" $LINENO

# Verify DB connectivity (DATABASE_URL must be configured for the app environment)
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "SELECT 1;" >/dev/null

########################################
# Mocks
########################################
cv_prereq "configure WireMock mappings for vectorDb and LLMConnector" $LINENO

CASE_DIR=".codevalid/wiremock/mappings/cases/${CASE_ID}"
mkdir -p "$CASE_DIR"

# Stub for vectorDb.performSimilaritySearch
cat > "${CASE_DIR}/vector-search.json" <<'JSON'
{
  "request": {
    "method": "POST",
    "urlPath": "/vectordb/similarity-search",
    "bodyPatterns": [
      {
        "contains": "admin_happy_path_configures_context_and_chats"
      }
    ]
  },
  "response": {
    "status": 200,
    "jsonBody": {
      "contextTexts": [
        "High-relevance snippet A for admin_happy_path_configures_context_and_chats.",
        "High-relevance snippet B for admin_happy_path_configures_context_and_chats."
      ],
      "sources": [
        {
          "id": "src-admin-case-1",
          "text": "High-relevance snippet A for admin_happy_path_configures_context_and_chats.",
          "score": 0.85,
          "title": "embedded-doc-a.txt",
          "published": "2024-01-01T00:00:00.000Z"
        },
        {
          "id": "src-admin-case-2",
          "text": "High-relevance snippet B for admin_happy_path_configures_context_and_chats.",
          "score": 0.90,
          "title": "embedded-doc-b.txt",
          "published": "2024-01-02T00:00:00.000Z"
        }
      ],
      "message": null
    }
  }
}
JSON

# Stub for LLMConnector.getChatCompletion
cat > "${CASE_DIR}/llm-connector.json" <<'JSON'
{
  "request": {
    "method": "POST",
    "urlPath": "/llm/chat-completions",
    "bodyPatterns": [
      {
        "contains": "admin_happy_path_configures_context_and_chats"
      }
    ]
  },
  "response": {
    "status": 200,
    "jsonBody": {
      "textResponse": "Stubbed admin chat response using high-relevance snippets A and B.",
      "metrics": {
        "prompt_tokens": 10,
        "completion_tokens": 20,
        "total_tokens": 30,
        "outputTps": 5,
        "duration": 6
      }
    }
  }
}
JSON

# CollectorApi is not called in this case (no document attachments), so no stub required.

wiremock_admin_import_mappings "$CASE_DIR"

########################################
# Preconditions
########################################
cv_prereq "seed API key, admin user, workspace, embeddings, and config" $LINENO

# 1. Seed API key via direct DB insert into api_keys.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO api_keys (secret)
VALUES ('seed-admin-case-api-key')
RETURNING id;
SQL

API_KEY="seed-admin-case-api-key"

# 2. Create an admin user via direct DB insert and ensure role is 'admin'.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO users (username, password, role)
VALUES ('admin_case_user', 'dummy-hash', 'admin')
RETURNING id;
SQL

ADMIN_USER_ID=$(psql "$DATABASE_URL" -At -c "SELECT id FROM users WHERE username = 'admin_case_user' LIMIT 1;")

# 3. Create a workspace via /v1/workspace/new with the API key.
NEW_WORKSPACE_BODY='{
    "name": "Admin Context Test Workspace",
    "similarityThreshold": 0.25,
    "topN": 4,
    "openAiHistory": 20,
    "chatMode": "chat"
  }'

cv_http POST "/v1/workspace/new" "$NEW_WORKSPACE_BODY" 200 -H "Authorization: Bearer ${API_KEY}" -H "Content-Type: application/json"

NEW_WORKSPACE_RESP="$CV_HTTP_BODY"
WORKSPACE_SLUG=$(echo "$NEW_WORKSPACE_RESP" | jq -r '.workspace.slug')
[ -n "$WORKSPACE_SLUG" ] || cv_fail "workspace slug not returned from /v1/workspace/new" $LINENO

# 4. Associate the admin user with the workspace in workspace_users.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL
INSERT INTO workspace_users (user_id, workspace_id)
SELECT ${ADMIN_USER_ID}, id FROM workspaces WHERE slug = '${WORKSPACE_SLUG}';
SQL

# 5. Embed at least one document into the workspace via /v1/workspace/:slug/update-embeddings.
EMBED_BODY=$(cat <<EOF
{
  "adds": ["custom-documents/${CASE_ID}-doc-a.json"],
  "deletes": []
}
EOF
)

cv_http POST "/v1/workspace/${WORKSPACE_SLUG}/update-embeddings" "$EMBED_BODY" 200 -H "Authorization: Bearer ${API_KEY}" -H "Content-Type: application/json"

# 6. Configure workspace similarityThreshold and topN via /v1/workspace/:slug/update.
UPDATE_BODY=$(cat <<EOF
{
  "similarityThreshold": 0.5,
  "topN": 2
}
EOF
)

cv_http POST "/v1/workspace/${WORKSPACE_SLUG}/update" "$UPDATE_BODY" 200 -H "Authorization: Bearer ${API_KEY}" -H "Content-Type: application/json"

UPDATE_RESP="$CV_HTTP_BODY"

echo "$UPDATE_RESP" | jq -e '.workspace.similarityThreshold == 0.5' >/dev/null || cv_fail "workspace.similarityThreshold not updated to 0.5" $LINENO
echo "$UPDATE_RESP" | jq -e '.workspace.topN == 2' >/dev/null || cv_fail "workspace.topN not updated to 2" $LINENO

########################################
# When
########################################
cv_step When "admin chats in workspace and triggers context search + LLM" $LINENO

SESSION_ID="${CASE_ID}-session"
CHAT_BODY=$(cat <<EOF
{
  "message": "admin_happy_path_configures_context_and_chats: describe embedded docs.",
  "mode": "chat",
  "sessionId": "${SESSION_ID}",
  "attachments": [],
  "reset": false
}
EOF
)

CHAT_RESP=$(curl -sS -X POST "http://app:6713/v1/workspace/${WORKSPACE_SLUG}/chat" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "${CHAT_BODY}")

echo "$CHAT_RESP"

########################################
# Then
########################################
cv_step Then "assert chat response shape, sources, metrics, and persistence" $LINENO

# 1. Basic shape and success fields.
RESP_TYPE=$(echo "$CHAT_RESP" | jq -r '.type')
RESP_CLOSE=$(echo "$CHAT_RESP" | jq -r '.close')
RESP_ERROR=$(echo "$CHAT_RESP" | jq -r '.error')
RESP_TEXT=$(echo "$CHAT_RESP" | jq -r '.textResponse')
RESP_CHAT_ID=$(echo "$CHAT_RESP" | jq -r '.chatId')

[ "$RESP_TYPE" = "textResponse" ] || cv_fail "expected type=textResponse got ${RESP_TYPE}" $LINENO
[ "$RESP_CLOSE" = "true" ] || cv_fail "expected close=true got ${RESP_CLOSE}" $LINENO
[ "$RESP_ERROR" = "null" ] || cv_fail "expected error=null got ${RESP_ERROR}" $LINENO
[ "$RESP_TEXT" = "Stubbed admin chat response using high-relevance snippets A and B." ] || cv_fail "unexpected textResponse: ${RESP_TEXT}" $LINENO
[ "$RESP_CHAT_ID" != "null" ] || cv_fail "expected non-null chatId" $LINENO

# 2. Ensure exactly two sources (matching topN=2) from vectorDb are returned and no extras.
SOURCES_COUNT=$(echo "$CHAT_RESP" | jq '.sources | length')
[ "$SOURCES_COUNT" -eq 2 ] || cv_fail "expected 2 sources got ${SOURCES_COUNT}" $LINENO

SRC0_ID=$(echo "$CHAT_RESP" | jq -r '.sources[0].id')
SRC1_ID=$(echo "$CHAT_RESP" | jq -r '.sources[1].id')

[ "$SRC0_ID" = "src-admin-case-1" ] || cv_fail "unexpected sources[0].id: ${SRC0_ID}" $LINENO
[ "$SRC1_ID" = "src-admin-case-2" ] || cv_fail "unexpected sources[1].id: ${SRC1_ID}" $LINENO

# 3. Ensure metrics match the LLMConnector stub.
PROMPT_TOKENS=$(echo "$CHAT_RESP" | jq '.metrics.prompt_tokens')
COMPLETION_TOKENS=$(echo "$CHAT_RESP" | jq '.metrics.completion_tokens')
TOTAL_TOKENS=$(echo "$CHAT_RESP" | jq '.metrics.total_tokens')

[ "$PROMPT_TOKENS" -eq 10 ] || cv_fail "unexpected prompt_tokens: ${PROMPT_TOKENS}" $LINENO
[ "$COMPLETION_TOKENS" -eq 20 ] || cv_fail "unexpected completion_tokens: ${COMPLETION_TOKENS}" $LINENO
[ "$TOTAL_TOKENS" -eq 30 ] || cv_fail "unexpected total_tokens: ${TOTAL_TOKENS}" $LINENO

# 4. Verify the chat row was persisted in workspace_chats with the same api_session_id and response.text.
ROW_EXISTS=$(psql "$DATABASE_URL" -At <<SQL
SELECT count(*) FROM workspace_chats
WHERE workspaceId = (SELECT id FROM workspaces WHERE slug = '${WORKSPACE_SLUG}')
  AND api_session_id = '${SESSION_ID}'
  AND id = ${RESP_CHAT_ID}
  AND response::json->>'text' = 'Stubbed admin chat response using high-relevance snippets A and B.';
SQL
)

[ "$ROW_EXISTS" -eq 1 ] || cv_fail "expected 1 persisted chat row, got ${ROW_EXISTS}" $LINENO

# If we reached here, all assertions passed.
echo "CODEVALID_TEST_ASSERTION_OK:admin_happy_path_configures_context_and_chats"

########################################
# Teardown
########################################
cv_step Cleanup "remove seeded data for this case" $LINENO

# Delete workspace_chats for this workspace and session.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL
DELETE FROM workspace_chats
WHERE workspaceId = (SELECT id FROM workspaces WHERE slug = '${WORKSPACE_SLUG}')
  AND api_session_id = '${SESSION_ID}';
SQL

# Delete document_vectors and workspace_documents for this workspace.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL
DELETE FROM document_vectors
WHERE docId IN (
  SELECT docId FROM workspace_documents
  WHERE workspaceId = (SELECT id FROM workspaces WHERE slug = '${WORKSPACE_SLUG}')
);

DELETE FROM workspace_documents
WHERE workspaceId = (SELECT id FROM workspaces WHERE slug = '${WORKSPACE_SLUG}');
SQL

# Remove workspace_user relation and workspace.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL
DELETE FROM workspace_users
WHERE workspace_id = (SELECT id FROM workspaces WHERE slug = '${WORKSPACE_SLUG}' );

DELETE FROM workspaces
WHERE slug = '${WORKSPACE_SLUG}';
SQL

# Delete admin user.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL
DELETE FROM users WHERE username = 'admin_case_user';
SQL

# Delete API key.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL
DELETE FROM api_keys WHERE secret = '${API_KEY}';
SQL
