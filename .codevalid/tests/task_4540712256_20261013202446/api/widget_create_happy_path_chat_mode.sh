#!/usr/bin/env bash
set -euo pipefail

# Setup
source .codevalid/tests/task_4540712256_20261013202446/api/_infra.sh

cv_step Given "healthy app and seeded workspace chat" $LINENO

# Plan precondition: Ensure app is healthy via curl
curl -s -o /dev/null -w '%{http_code}\n' "$HEALTH_URL"

cv_prereq "wait for health check to return 200" $LINENO
cv_http GET "$HEALTH_URL/health" 200

# Prepare SQLite DB path used by Prisma
DB_PATH="server/storage/anythingllm.db"
cv_prereq "ensure SQLite DB directory exists" $LINENO
mkdir -p "$(dirname "$DB_PATH")"

# Seed user, workspace, and workspace_chats row
cv_prereq "seed users, workspaces, workspace_users, workspace_chats" $LINENO
sqlite3 "$DB_PATH" <<'SQL'
PRAGMA foreign_keys = ON;

-- Clean any existing rows to avoid FK collisions.
DELETE FROM workspace_chats;
DELETE FROM workspace_users;
DELETE FROM workspaces;
DELETE FROM users;

-- Insert a user; role defaults to "default" per schema but we set explicitly.
INSERT INTO users (id, username, password, role)
VALUES (1, 'adminuser', 'hashed-password-placeholder', 'admin');

-- Insert a workspace with a known slug.
INSERT INTO workspaces (id, name, slug)
VALUES (1, 'Widget Workspace', 'widget-ws');

-- Link user to workspace (workspace_users).
INSERT INTO workspace_users (id, user_id, workspace_id, createdAt, lastUpdatedAt)
VALUES (1, 1, 1, datetime('now'), datetime('now'));

-- Insert a workspace_chats row owned by this user with a JSON response containing text.
INSERT INTO workspace_chats (
  id,
  workspaceId,
  prompt,
  response,
  include,
  user_id,
  thread_id,
  api_session_id,
  createdAt,
  lastUpdatedAt
) VALUES (
  1,
  1,
  'Original user prompt',
  '{"text":"Original assistant reply","type":"chart","sources":[]}',
  1,
  1,
  NULL,
  NULL,
  datetime('now'),
  datetime('now')
);
SQL

cv_step When "update assistant chat response via POST" $LINENO

update_body='{"chatId":1,"newText":"Updated assistant reply from widget","role":"assistant"}'
cv_http POST "/workspace/widget-ws/update-chat" "$update_body" 200

cv_step Then "chat response text updated in DB" $LINENO

# 1. Assert HTTP 200 status from the endpoint (cv_http already enforced 200, but we double-check).
if [ "${CV_HTTP_STATUS:-}" != "200" ]; then
  cv_fail "expected HTTP 200 from POST /workspace/widget-ws/update-chat got ${CV_HTTP_STATUS:-}" $LINENO
fi

# 2. Verify in DB that workspace_chats.response JSON text field was updated to the new value.
UPDATED_RESPONSE="$(sqlite3 "$DB_PATH" "SELECT response FROM workspace_chats WHERE id = 1;")"
if ! printf '%s' "$UPDATED_RESPONSE" | grep -q '"text":"Updated assistant reply from widget"'; then
  cv_fail "expected workspace_chats.response.text to be updated, got: $UPDATED_RESPONSE" $LINENO
fi

cv_step Cleanup "remove seeded rows from SQLite DB" $LINENO
sqlite3 "$DB_PATH" <<'SQL'
DELETE FROM workspace_chats;
DELETE FROM workspace_users;
DELETE FROM workspaces;
DELETE FROM users;
SQL

echo "CODEVALID_TEST_ASSERTION_OK:widget_create_happy_path_chat_mode"
