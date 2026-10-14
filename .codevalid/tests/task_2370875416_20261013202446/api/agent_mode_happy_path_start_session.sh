#!/usr/bin/env bash
set -euo pipefail

cv_step Given "setup infra and seed workspace/user/chat" $LINENO
source .codevalid/tests/task_2370875416_20261013202446/api/_infra.sh

cv_prereq "ensure app is healthy" $LINENO
health_check

# 1. Seed a workspace row and capture its slug and id.
workspace_slug="test-workspace-update-chat"
workspace_name="Test Workspace Update Chat"

cv_prereq "insert workspace row" $LINENO
sqlite3 "server/storage/anythingllm.db" <<'SQL'
INSERT INTO workspaces (name, slug, createdAt, lastUpdatedAt)
VALUES ('Test Workspace Update Chat', 'test-workspace-update-chat', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
SQL

# 2. Seed a user row.
cv_prereq "insert user row" $LINENO
sqlite3 "server/storage/anythingllm.db" <<'SQL'
INSERT INTO users (username, password, role, suspended, createdAt, lastUpdatedAt, web_push_subscription_config)
VALUES ('testuser_update_chat', 'hashed-password', 'default', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, '{}');
SQL

# 3. Lookup workspaceId and userId for later inserts.
workspace_id="$(sqlite3 "server/storage/anythingllm.db" "SELECT id FROM workspaces WHERE slug = 'test-workspace-update-chat' LIMIT 1;")"
user_id="$(sqlite3 "server/storage/anythingllm.db" "SELECT id FROM users WHERE username = 'testuser_update_chat' LIMIT 1;")"

if [ -z "${workspace_id:-}" ]; then
  cv_fail "workspace_id lookup returned empty" $LINENO
fi
if [ -z "${user_id:-}" ]; then
  cv_fail "user_id lookup returned empty" $LINENO
fi

# 4. Seed a workspace_chats row with a JSON response containing text and sources.
initial_response='{"text":"Original assistant reply","sources":[{"title":"Doc 1"}]}'

cv_prereq "insert workspace_chats row" $LINENO
sqlite3 "server/storage/anythingllm.db" <<SQL
INSERT INTO workspace_chats (workspaceId, prompt, response, include, user_id, thread_id, createdAt, lastUpdatedAt)
VALUES (${workspace_id}, 'Original user prompt', '${initial_response}', 1, ${user_id}, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
SQL

# 5. Capture the chatId of the inserted workspace_chats row.
chat_id="$(sqlite3 "server/storage/anythingllm.db" "SELECT id FROM workspace_chats WHERE workspaceId = ${workspace_id} AND user_id = ${user_id} AND thread_id IS NULL ORDER BY id DESC LIMIT 1;")"

if [ -z "${chat_id:-}" ]; then
  cv_fail "chat_id lookup returned empty" $LINENO
fi

cv_step When "POST update-chat to update assistant response text" $LINENO
updated_text="Updated assistant reply"

# Build JSON body safely
request_body=$(printf '{"chatId":%s,"newText":"%s"}' "$chat_id" "$updated_text")

# Restore plan's explicit curl call to capture status code, while still using cv_http as required.
status_code="$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  "$BASE_URL/api/workspace/${workspace_slug}/update-chat" \
  -H "Content-Type: application/json" \
  -d "$request_body")"

# Use cv_http to perform the POST and assert on status later.
cv_http POST "/api/workspace/${workspace_slug}/update-chat" "$request_body" 200

cv_step Then "verify HTTP 200 and DB response text/sources" $LINENO

# cv_http already asserted 200 because we passed 200 as expected status.
# Still keep a sanity check on CV_HTTP_STATUS for clarity.
if [ "${CV_HTTP_STATUS:-}" != "200" ]; then
  cv_fail "expected HTTP 200 got ${CV_HTTP_STATUS:-}" $LINENO
fi

# Fetch the updated workspace_chats.response from the database.
response_json="$(sqlite3 "server/storage/anythingllm.db" "SELECT response FROM workspace_chats WHERE id = ${chat_id} LIMIT 1;")"

if [ -z "${response_json:-}" ]; then
  cv_fail "response_json from DB is empty" $LINENO
fi

# Verify that the response JSON contains the updated text and preserves the sources array.
if command -v jq >/dev/null 2>&1; then
  text_field="$(printf '%s' "$response_json" | jq -r '.text')"
  sources_title="$(printf '%s' "$response_json" | jq -r '.sources[0].title')"
  if [ "$text_field" != "$updated_text" ]; then
    cv_fail "expected response.text to be '$updated_text' got '$text_field'" $LINENO
  fi
  if [ "$sources_title" != "Doc 1" ]; then
    cv_fail "expected sources[0].title to remain 'Doc 1' got '$sources_title'" $LINENO
  fi
else
  # Fallback: basic substring checks.
  case "$response_json" in
    *"Updated assistant reply"* ) ;;
    *)
      cv_fail "updated text not found in response JSON: $response_json" $LINENO
      ;;
  esac
  case "$response_json" in
    *"Doc 1"* ) ;;
    *)
      cv_fail "original sources title 'Doc 1' not preserved in response JSON: $response_json" $LINENO
      ;;
  esac
fi

cv_step Cleanup "delete seeded workspace_chats/users/workspaces rows" $LINENO
sqlite3 "server/storage/anythingllm.db" <<SQL
DELETE FROM workspace_chats WHERE id = ${chat_id};
DELETE FROM users WHERE id = ${user_id};
DELETE FROM workspaces WHERE id = ${workspace_id};
SQL

echo "CODEVALID_TEST_ASSERTION_OK:agent_mode_happy_path_start_session"
