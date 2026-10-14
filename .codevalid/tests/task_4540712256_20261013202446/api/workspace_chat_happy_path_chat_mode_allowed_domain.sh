#!/usr/bin/env bash
set -euo pipefail

# Setup
source .codevalid/tests/task_4540712256_20261013202446/api/_infra.sh

# Case: workspace_chat_happy_path_chat_mode_allowed_domain

cv_step Given "multi-user admin and workspace chats seeded" $LINENO

DB_PATH="server/storage/anythingllm.db"

cv_prereq "apply Prisma migrations if needed" $LINENO
npx prisma migrate deploy --schema server/prisma/schema.prisma

cv_prereq "ensure SQLite DB file exists" $LINENO
sqlite3 "$DB_PATH" "SELECT 1;" >/dev/null 2>&1 || cv_fail "SQLite DB $DB_PATH is not accessible" $LINENO

cv_prereq "enable multi_user_mode in system_settings" $LINENO
sqlite3 "$DB_PATH" <<'SQL'
INSERT INTO system_settings (label, value, createdAt, lastUpdatedAt)
VALUES ('multi_user_mode', 'true', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT(label) DO UPDATE SET value='true', lastUpdatedAt=CURRENT_TIMESTAMP;
SQL

cv_prereq "seed admin user with bcrypt-hashed password \"adminpass\"" $LINENO
node <<'NODE'
const bcrypt = require('bcryptjs');
const fs = require('fs');
const path = require('path');
const { Database } = require('sqlite3');

const dbPath = path.resolve('server/storage/anythingllm.db');
const db = new Database(dbPath);

const username = 'admin_user';
const password = 'adminpass';
const role = 'admin';

bcrypt.hash(password, 10, (err, hash) => {
  if (err) { console.error(err); process.exit(1); }
  db.run(
    `INSERT INTO users (username, password, role, suspended, createdAt, lastUpdatedAt)
     VALUES (?, ?, ?, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
     ON CONFLICT(username) DO UPDATE SET password=excluded.password, role=excluded.role, lastUpdatedAt=CURRENT_TIMESTAMP;`,
    [username, hash, role],
    function (e) {
      if (e) { console.error(e); process.exit(1); }
      db.close(() => process.exit(0));
    }
  );
});
NODE

cv_prereq "seed test workspace" $LINENO
sqlite3 "$DB_PATH" <<'SQL'
INSERT INTO workspaces (name, slug, createdAt, openAiHistory, lastUpdatedAt, similarityThreshold, vectorSearchMode)
VALUES ('Test Workspace', 'test-workspace', CURRENT_TIMESTAMP, 20, CURRENT_TIMESTAMP, 0.25, 'default')
ON CONFLICT(slug) DO NOTHING;
SQL

WORKSPACE_ID="$(sqlite3 "$DB_PATH" "SELECT id FROM workspaces WHERE slug = 'test-workspace' LIMIT 1;")"
if [ -z "$WORKSPACE_ID" ]; then
  cv_fail "Failed to get WORKSPACE_ID" $LINENO
fi

cv_prereq "seed workspace_chats for workspace" $LINENO
sqlite3 "$DB_PATH" <<SQL
INSERT INTO workspace_chats (workspaceId, prompt, response, include, user_id, thread_id, api_session_id, createdAt, lastUpdatedAt)
VALUES
  ($WORKSPACE_ID, 'Hello 1', '{"text":"Response 1"}', 1, NULL, NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ($WORKSPACE_ID, 'Hello 2', '{"text":"Response 2"}', 1, NULL, NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
SQL

cv_step When "admin obtains JWT via /request-token and calls /system/update-env" $LINENO

BASE_URL="${BASE_URL:-http://app:6713}"

# Obtain JWT via /request-token (multi-user branch).
LOGIN_RESPONSE="$(curl -s -X POST "$BASE_URL/request-token" \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin_user","password":"adminpass"}')"
cv_http POST "$BASE_URL/request-token" 200

TOKEN="$(printf '%s' "$LOGIN_RESPONSE" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{const j=JSON.parse(d);console.log(j.token||'');}catch{console.log('');}})")"
if [ -z "$TOKEN" ]; then
  cv_fail "Failed to obtain JWT token from /request-token" $LINENO
fi

# Call POST /system/update-env with default offset/limit using the admin JWT.
BODY_FILE="$(mktemp)"
HTTP_STATUS="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$BASE_URL/system/update-env" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"offset":0,"limit":20}')"
cv_http POST "$BASE_URL/system/update-env" "$HTTP_STATUS"

HTTP_BODY="$(cat "$BODY_FILE")"
rm -f "$BODY_FILE"

cv_step Then "response has chats array and pagination fields" $LINENO

if [ "$HTTP_STATUS" != "200" ]; then
  cv_fail "Expected HTTP 200, got $HTTP_STATUS: $(printf '%s' "$HTTP_BODY" | head -c 300)" $LINENO
fi

node <<'NODE'
let body = '';
process.stdin.on('data', c => body += c).on('end', () => {
  try {
    const json = JSON.parse(body);
    if (!Object.prototype.hasOwnProperty.call(json, 'chats')) {
      console.error('Missing "chats" field in response'); process.exit(1);
    }
    if (!Array.isArray(json.chats)) {
      console.error('"chats" is not an array'); process.exit(1);
    }
    if (!Object.prototype.hasOwnProperty.call(json, 'hasPages')) {
      console.error('Missing "hasPages" field in response'); process.exit(1);
    }
    if (typeof json.hasPages !== 'boolean') {
      console.error('"hasPages" is not a boolean'); process.exit(1);
    }
    if (!Object.prototype.hasOwnProperty.call(json, 'totalChats')) {
      console.error('Missing "totalChats" field in response'); process.exit(1);
    }
    if (typeof json.totalChats !== 'number') {
      console.error('"totalChats" is not a number'); process.exit(1);
    }
    if (json.totalChats < json.chats.length) {
      console.error('totalChats is less than number of returned chats'); process.exit(1);
    }
    process.exit(0);
  } catch (e) {
    console.error('Failed to parse JSON response:', e.message);
    process.exit(1);
  }
});
NODE <<<"$HTTP_BODY"

cv_step Cleanup "remove seeded workspace chats, workspace, and admin user" $LINENO
sqlite3 "$DB_PATH" <<SQL
DELETE FROM workspace_chats WHERE workspaceId = $WORKSPACE_ID;
DELETE FROM workspaces WHERE id = $WORKSPACE_ID;
DELETE FROM users WHERE username = 'admin_user';
SQL

echo "CODEVALID_TEST_ASSERTION_OK:workspace_chat_happy_path_chat_mode_allowed_domain"
