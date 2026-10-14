#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_4540712256_20261013202446/api/_infra.sh

cv_step Given "happy path widget with chat mode and limits within range" $LINENO

CASE_DIR=".codevalid/wiremock/mappings/cases/chat_widget_happy_path_chat_mode_within_limits"
mkdir -p "$CASE_DIR"

# Mocks
cv_prereq "stub LLM provider for happy path" $LINENO
cat > "$CASE_DIR/llm-chat-happy.json" <<'JSON'
{
  "request": {
    "method": "POST",
    "urlPathPattern": "/v1/chat/completions",
    "bodyPatterns": [
      {
        "contains": "chat_widget_happy_path_chat_mode_within_limits"
      }
    ]
  },
  "response": {
    "status": 200,
    "jsonBody": {
      "id": "cmpl-happy-1",
      "object": "chat.completion",
      "choices": [
        {
          "index": 0,
          "message": {
            "role": "assistant",
            "content": "This is a chat-mode answer grounded in workspace documents."
          },
          "finish_reason": "stop"
        }
      ],
      "usage": {
        "prompt_tokens": 10,
        "completion_tokens": 20,
        "total_tokens": 30
      }
    }
  }
}
JSON

cv_prereq "stub vector DB provider for happy path" $LINENO
cat > "$CASE_DIR/vector-search-happy.json" <<'JSON'
{
  "request": {
    "method": "POST",
    "urlPathPattern": "/vector/search",
    "bodyPatterns": [
      {
        "contains": "chat_widget_happy_path_chat_mode_within_limits"
      }
    ]
  },
  "response": {
    "status": 200,
    "jsonBody": {
      "contextTexts": [
        "Pinned and vectorized document content about AnythingLLM."
      ],
      "sources": [
        {
          "title": "anythingllm.txt",
          "chunk": "Pinned/vectorized content used for happy-path answer.",
          "published": "2024-01-01T00:00:00Z"
        }
      ],
      "message": null
    }
  }
}
JSON

cv_prereq "import WireMock mappings" $LINENO
wiremock_admin_import_mappings "$CASE_DIR"

# Preconditions: workspace creation and document seeding
WORKSPACE_NAME="Happy Path Widget Workspace"
cv_prereq "create workspace for happy path widget" $LINENO
WORKSPACE_BODY_JSON="$(jq -n \
  --arg name "$WORKSPACE_NAME" \
  --arg chatMode "chat" \
  --arg refusal "There is no relevant information in this workspace to answer your query." \
  '{name: $name, chatMode: $chatMode, queryRefusalResponse: $refusal}')"
cv_http POST "/v1/workspace/new" "$WORKSPACE_BODY_JSON" 200 -H "Content-Type: application/json" -H "x-api-key: test-api-key"
printf '%s' "$CV_HTTP_BODY" > /tmp/chat_widget_happy_workspace.json

WORKSPACE_ID="$(jq -r '.workspace.id' /tmp/chat_widget_happy_workspace.json)"
WORKSPACE_SLUG="$(jq -r '.workspace.slug' /tmp/chat_widget_happy_workspace.json)"

DOC_STORAGE_DIR="/work/server/storage/documents"
DOC_PATH_REL="custom-documents/happy-doc.json"
DOC_PATH="$DOC_STORAGE_DIR/$DOC_PATH_REL"

cv_prereq "seed document storage directory" $LINENO
mkdir -p "$DOC_STORAGE_DIR"
cat > "$DOC_PATH" <<'JSON'
{
  "title": "anythingllm.txt",
  "pageContent": "Pinned and vectorized document content about AnythingLLM.",
  "chunkSource": "file://anythingllm.txt",
  "token_count_estimate": 64
}
JSON

cv_prereq "update workspace embeddings" $LINENO
cv_http POST "/v1/workspace/${WORKSPACE_SLUG}/update-embeddings" "{\"adds\":[\"${DOC_PATH_REL}\"],\"deletes\":[]}" 200 -H "Content-Type: application/json" -H "x-api-key: test-api-key"
printf '%s' "$CV_HTTP_BODY" > /tmp/chat_widget_happy_update_embeddings.json

cv_prereq "pin document in workspace" $LINENO
cv_http POST "/v1/workspace/${WORKSPACE_SLUG}/update-pin" "{\"docPath\":\"${DOC_PATH_REL}\",\"pinStatus\":true}" 200 -H "Content-Type: application/json" -H "x-api-key: test-api-key"
printf '%s' "$CV_HTTP_BODY" > /tmp/chat_widget_happy_pin.json

cv_prereq "create embed configuration in database" $LINENO
# Use the database client (psql) instead of Node/Prisma to create the embed configuration row.
# We generate a UUID using the database's functions where available; fall back to a random string.
EMBED_UUID="embed-$(date +%s)-$RANDOM"
EMBED_ID=$(
  psql -At <<SQL
INSERT INTO embed_configs
  (uuid, enabled, chat_mode, allowlist_domains, allow_model_override,
   allow_temperature_override, allow_prompt_override, max_chats_per_day,
   max_chats_per_session, message_limit, workspace_id)
VALUES
  ('$EMBED_UUID', TRUE, 'chat', '[\"https://allowed.example.com\"]',
   TRUE, TRUE, TRUE, 100, 20, 20, ${WORKSPACE_ID})
RETURNING id;
SQL
)
# Ensure EMBED_ID is a plain number
EMBED_ID="$(printf '%s' "$EMBED_ID" | tr -d '[:space:]')"

SESSION_ID="happy-session-1"

cv_step When "stream chat from widget within limits" $LINENO

REQUEST_BODY_JSON="$(jq -n \
  --arg sessionId "$SESSION_ID" \
  --arg message "chat_widget_happy_path_chat_mode_within_limits: Tell me about AnythingLLM." \
  --arg prompt "Override system prompt for happy-path widget." \
  --arg model "override-model-happy" \
  --argjson temperature 0.3 '{
    sessionId: $sessionId,
    message: $message,
    prompt: $prompt,
    model: $model,
    temperature: $temperature,
    username: "widget-user-happy"
  }')"

# Perform streaming POST with curl as in the plan, capture body to file
HTTP_STATUS=$(curl -sS -o /tmp/chat_widget_happy_stream.txt -w "%{http_code}" \
  -N -X POST "${BASE_URL}/embed/${EMBED_ID}/stream-chat" \
  -H "Content-Type: application/json" \
  -H "Origin: https://allowed.example.com" \
  --data "$REQUEST_BODY_JSON" || echo "curl_failed")

# Emit cv_http marker for the streaming request
cv_http POST "/embed/${EMBED_ID}/stream-chat" 200

if [ "$HTTP_STATUS" != "200" ]; then
  cv_fail "expected HTTP 200 from POST /embed/${EMBED_ID}/stream-chat got $HTTP_STATUS" $LINENO
fi

cv_step Then "verify streaming response and DB records" $LINENO

# Verify that the stream contains at least one textResponseChunk and closes cleanly
if ! grep -q '"type":"textResponseChunk"' /tmp/chat_widget_happy_stream.txt; then
  cv_fail "expected at least one textResponseChunk in stream" $LINENO
fi
if ! grep -q '"close":true' /tmp/chat_widget_happy_stream.txt; then
  cv_fail "expected close:true in stream" $LINENO
fi
if ! grep -q '"error":false' /tmp/chat_widget_happy_stream.txt; then
  cv_fail "expected error:false in stream" $LINENO
fi

# Confirm that an EmbedChats row was created for this embed and session and reflects stubbed LLM content
EMBED_CHAT_CHECK=$(
  psql -At <<SQL
SELECT response
FROM embed_chats
WHERE embed_id = ${EMBED_ID}
  AND session_id = '${SESSION_ID}'
ORDER BY id ASC;
SQL
)

if [ -z "$EMBED_CHAT_CHECK" ]; then
  cv_fail "No embed_chats rows found for happy-path case" $LINENO
fi

# Take the last response JSON and inspect its text field
LAST_RESPONSE_JSON="$(printf '%s\n' "$EMBED_CHAT_CHECK" | tail -n 1)"
RESP_TEXT="$(printf '%s' "$LAST_RESPONSE_JSON" | jq -r '.text // empty' 2>/dev/null || true)"

if [ -z "$RESP_TEXT" ]; then
  cv_fail "embed_chats.response text field missing for happy-path case" $LINENO
fi

if ! printf '%s' "$RESP_TEXT" | grep -q "workspace documents" && \
   ! printf '%s' "$RESP_TEXT" | grep -q "AnythingLLM"; then
  cv_fail "Response text does not reflect stubbed LLM content" $LINENO
fi

cv_step Cleanup "remove happy path workspace and embeds" $LINENO

# Teardown via database client: delete embed chats, embed config, workspace chats/documents and workspace
psql <<SQL
DELETE FROM embed_chats WHERE embed_id = ${EMBED_ID};
DELETE FROM embed_configs WHERE id = ${EMBED_ID};
DELETE FROM workspace_chats WHERE workspaceId = ${WORKSPACE_ID};
DELETE FROM workspace_documents WHERE workspaceId = ${WORKSPACE_ID};
DELETE FROM workspaces WHERE id = ${WORKSPACE_ID};
SQL

rm -f /tmp/chat_widget_happy_workspace.json \
      /tmp/chat_widget_happy_update_embeddings.json \
      /tmp/chat_widget_happy_pin.json \
      /tmp/chat_widget_happy_embed.json \
      /tmp/chat_widget_happy_stream.txt

echo "CODEVALID_TEST_ASSERTION_OK:chat_widget_happy_path_chat_mode_within_limits"
