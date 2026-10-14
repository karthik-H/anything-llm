#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_4540712256_20261013202446/api/_infra.sh

cv_step Given "query-mode widget with document-scoped answers" $LINENO

CASE_DIR=".codevalid/wiremock/mappings/cases/query_mode_document_scoped_answers"
mkdir -p "$CASE_DIR"

cv_prereq "stub LLM for doc-related question" $LINENO
cat > "$CASE_DIR/llm-chat-query-doc.json" <<'JSON'
{
  "request": {
    "method": "POST",
    "urlPathPattern": "/v1/chat/completions",
    "bodyPatterns": [
      {
        "contains": "query_mode_document_scoped_answers: doc-related"
      }
    ]
  },
  "response": {
    "status": 200,
    "jsonBody": {
      "id": "cmpl-query-doc-1",
      "object": "chat.completion",
      "choices": [
        {
          "index": 0,
          "message": {
            "role": "assistant",
            "content": "Document-based answer referencing workspace content."
          },
          "finish_reason": "stop"
        }
      ]
    }
  }
}
JSON

cv_prereq "stub vector search for doc-related question" $LINENO
cat > "$CASE_DIR/vector-search-query-doc.json" <<'JSON'
{
  "request": {
    "method": "POST",
    "urlPathPattern": "/v1/workspace/:slug/vector-search",
    "bodyPatterns": [
      {
        "contains": "query_mode_document_scoped_answers: doc-related"
      }
    ]
  },
  "response": {
    "status": 200,
    "jsonBody": {
      "contextTexts": [
        "Workspace document content about the queried topic."
      ],
      "sources": [
        {
          "title": "query-doc.txt",
          "chunk": "Relevant snippet used to answer document-related question.",
          "published": "2024-01-01T00:00:00Z"
        }
      ],
      "message": null
    }
  }
}
JSON

cv_prereq "stub vector search for general question" $LINENO
cat > "$CASE_DIR/vector-search-query-general.json" <<'JSON'
{
  "request": {
    "method": "POST",
    "urlPathPattern": "/v1/workspace/:slug/vector-search",
    "bodyPatterns": [
      {
        "contains": "query_mode_document_scoped_answers: general"
      }
    ]
  },
  "response": {
    "status": 200,
    "jsonBody": {
      "contextTexts": [],
      "sources": [],
      "message": null
    }
  }
}
JSON

cv_prereq "import WireMock mappings" $LINENO
wiremock_admin_import_mappings "$CASE_DIR"

WORKSPACE_NAME="Query Mode Widget Workspace"
cv_prereq "create query-mode workspace" $LINENO
WORKSPACE_BODY="$(jq -n \
  --arg name "$WORKSPACE_NAME" \
  --arg chatMode "query" \
  --arg refusal "There is no relevant information in this workspace to answer your query." \
  '{name: $name, chatMode: $chatMode, queryRefusalResponse: $refusal}')"
cv_http POST "/v1/workspace/new" "$WORKSPACE_BODY" 200 -H "Content-Type: application/json" -H "x-api-key: test-api-key"
printf '%s' "$CV_HTTP_BODY" > /tmp/query_mode_workspace.json

WORKSPACE_ID="$(jq -r '.workspace.id' /tmp/query_mode_workspace.json)"
WORKSPACE_SLUG="$(jq -r '.workspace.slug' /tmp/query_mode_workspace.json)"

DOC_STORAGE_DIR="/work/server/storage/documents"
DOC_PATH_REL="custom-documents/query-doc.json"
DOC_PATH="$DOC_STORAGE_DIR/$DOC_PATH_REL"

cv_prereq "seed document and embeddings" $LINENO
mkdir -p "$DOC_STORAGE_DIR"
cat > "$DOC_PATH" <<'JSON'
{
  "title": "query-doc.txt",
  "pageContent": "Workspace document content about the queried topic.",
  "chunkSource": "file://query-doc.txt",
  "token_count_estimate": 64
}
JSON

EMBEDDINGS_BODY="$(jq -n \
  --arg docPathRel "$DOC_PATH_REL" \
  '{adds: [$docPathRel], deletes: []}')"
cv_http POST "/v1/workspace/${WORKSPACE_SLUG}/update-embeddings" "$EMBEDDINGS_BODY" 200 -H "Content-Type: application/json" -H "x-api-key: test-api-key"
printf '%s' "$CV_HTTP_BODY" > /tmp/query_mode_update_embeddings.json

cv_prereq "create query-mode embed config via SQL" $LINENO
# Generate a simple UUID-like value in bash if DB lacks uuid helpers
EMBED_UUID="$(printf 'cv-%s-%s' "$WORKSPACE_ID" "$RANDOM")"
psql <<SQL
INSERT INTO embed_configs (uuid, enabled, chat_mode, allowlist_domains, allow_model_override, allow_temperature_override, allow_prompt_override, max_chats_per_day, max_chats_per_session, message_limit, "workspaceId")
VALUES ('$EMBED_UUID', true, 'query', '["https://allowed.example.com"]', false, false, false, NULL, NULL, 20, $WORKSPACE_ID);
SQL

EMBED_ID="$(psql -t -A <<SQL
SELECT id FROM embed_configs WHERE uuid = '$EMBED_UUID';
SQL
)"
EMBED_ID="$(printf '%s' "$EMBED_ID" | tr -d '[:space:]')"

SESSION_ID="query-mode-session"

cv_step When "ask document-related and general questions" $LINENO

# Use plain curl as in the plan, then record with cv_http marker
REQ_DOC="$(jq -n \
  --arg sessionId "$SESSION_ID" \
  --arg message "query_mode_document_scoped_answers: doc-related question about the stored topic." \
  '{sessionId: $sessionId, message: $message}')"
curl -sS -f -N -X POST "${BASE_URL}/embed/${EMBED_ID}/stream-chat" \
  -H "Content-Type: application/json" \
  -H "Origin: https://allowed.example.com" \
  --data "$REQ_DOC" \
  > /tmp/query_mode_doc_stream.txt
cv_http POST "/embed/${EMBED_ID}/stream-chat" 200

REQ_GEN="$(jq -n \
  --arg sessionId "$SESSION_ID" \
  --arg message "query_mode_document_scoped_answers: general question unrelated to documents." \
  '{sessionId: $sessionId, message: $message}')"
curl -sS -f -N -X POST "${BASE_URL}/embed/${EMBED_ID}/stream-chat" \
  -H "Content-Type: application/json" \
  -H "Origin: https://allowed.example.com" \
  --data "$REQ_GEN" \
  > /tmp/query_mode_general_stream.txt
cv_http POST "/embed/${EMBED_ID}/stream-chat" 200

cv_step Then "verify document-scoped answer and refusal" $LINENO

if ! grep -q '"type":"textResponseChunk"' /tmp/query_mode_doc_stream.txt && \
   ! grep -q '"type":"finalizeResponseStream"' /tmp/query_mode_doc_stream.txt; then
  cv_fail "expected SSE chunks for doc-related query" $LINENO
fi
if ! grep -q "Document-based answer referencing workspace content." /tmp/query_mode_doc_stream.txt; then
  cv_fail "expected document-based answer content in doc stream" $LINENO
fi

if ! grep -q "There is no relevant information in this workspace to answer your query." /tmp/query_mode_general_stream.txt; then
  cv_fail "expected queryRefusalResponse in general stream" $LINENO
fi

cv_prereq "verify embed_chats rows for both questions via SQL" $LINENO
CHAT_ROWS="$(psql -t -A <<SQL
SELECT response FROM embed_chats
WHERE embed_id = $EMBED_ID AND session_id = '$SESSION_ID'
ORDER BY id ASC;
SQL
)"
CHAT_COUNT="$(printf '%s\n' "$CHAT_ROWS" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
if [ "$CHAT_COUNT" -lt 2 ]; then
  cv_fail "Expected at least 2 embed_chats rows, found ${CHAT_COUNT}" $LINENO
fi

FIRST_RESP_TEXT="$(printf '%s\n' "$CHAT_ROWS" | sed -n '1p' | jq -r '.text' 2>/dev/null || true)"
SECOND_RESP_TEXT="$(printf '%s\n' "$CHAT_ROWS" | sed -n '2p' | jq -r '.text' 2>/dev/null || true)"

if [ -z "$FIRST_RESP_TEXT" ] || ! printf '%s' "$FIRST_RESP_TEXT" | grep -q "Document-based answer"; then
  cv_fail "First query-mode response is not document-based as expected." $LINENO
fi
if [ -z "$SECOND_RESP_TEXT" ] || ! printf '%s' "$SECOND_RESP_TEXT" | grep -q "There is no relevant information"; then
  cv_fail "Second query-mode response does not use queryRefusalResponse." $LINENO
fi

cv_step Cleanup "cleanup query-mode workspace, embed, and documents" $LINENO

psql <<SQL
DELETE FROM embed_chats WHERE embed_id = $EMBED_ID;
DELETE FROM embed_configs WHERE id = $EMBED_ID;
DELETE FROM workspace_documents WHERE "workspaceId" = $WORKSPACE_ID;
DELETE FROM workspaces WHERE id = $WORKSPACE_ID;
SQL

rm -f /tmp/query_mode_workspace.json \
      /tmp/query_mode_update_embeddings.json \
      /tmp/query_mode_embed.json \
      /tmp/query_mode_doc_stream.txt \
      /tmp/query_mode_general_stream.txt

echo "CODEVALID_TEST_ASSERTION_OK:query_mode_document_scoped_answers"
