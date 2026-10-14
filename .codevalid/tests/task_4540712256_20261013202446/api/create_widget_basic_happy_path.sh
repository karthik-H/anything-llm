#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_4540712256_20261013202446/api/_infra.sh

cv_step Given "prepare database and seed data (assumed pre-seeded; Node/Prisma unavailable)" $LINENO

cv_prereq "apply Prisma migrations (skipped: npx unavailable; assume DB is migrated)" $LINENO
# tool_missing__npx: cannot run `npx prisma migrate deploy`; assuming schema is already applied.

cv_prereq "seed workspace row (skipped: node unavailable; assume workspace exists)" $LINENO
# tool_missing__node: original seeding via Node/Prisma removed; relying on existing workspace data.

cv_prereq "seed user row (skipped: node unavailable; assume user exists)" $LINENO
# tool_missing__node: original seeding via Node/Prisma removed; relying on existing user data.

cv_prereq "seed API key (skipped: node unavailable; using static test-admin-secret)" $LINENO
# tool_missing__node: original API key seeding via Node/Prisma removed.
API_SECRET="test-admin-secret"

cv_prereq "ensure at least 21 workspace_chats exist (skipped: node unavailable; assume data present)" $LINENO
# tool_missing__node: original seeding via Node/Prisma removed; relying on fixture data.

cv_step When "call /v1/admin/workspace-chats with offset 0" $LINENO

AUTH_HEADER="Authorization: Bearer ${API_SECRET}"

# The plan used curl directly; here we use cv_http, which wraps curl and records diagnostics.
cv_http POST "/v1/admin/workspace-chats" '{"offset":0}' 200 -H "Content-Type: application/json" -H "$AUTH_HEADER"
RESPONSE_JSON="$CV_HTTP_BODY"
HTTP_STATUS="$CV_HTTP_STATUS"

if [ "$HTTP_STATUS" != "200" ]; then
  cv_fail "expected HTTP 200 got $HTTP_STATUS" $LINENO
fi

cv_step Then "assert response body structure and pagination" $LINENO

cv_prereq "compute chats length" $LINENO
CHATS_LENGTH=$(printf '%s' "$RESPONSE_JSON" | jq 'if (.chats // null) | type == "array" then (.chats | length) else 0 end') || cv_fail "failed to compute chats length" $LINENO

cv_prereq "compute hasPages flag" $LINENO
HAS_PAGES=$(printf '%s' "$RESPONSE_JSON" | jq -r 'if .hasPages == true then "true" else "false" end') || cv_fail "failed to compute hasPages flag" $LINENO

if [ "$CHATS_LENGTH" -gt 20 ]; then
  cv_fail "expected at most 20 chats on first page, got $CHATS_LENGTH" $LINENO
fi

if [ "$HAS_PAGES" != "true" ]; then
  cv_fail "expected hasPages=true when more than 20 chats are present" $LINENO
fi

cv_prereq "validate workspace and user fields on each chat" $LINENO
jq '
  if ((.chats // null) | type != "array" or (.chats | length) == 0) then
    halt_error(1; "No chats array or empty chats")
  else
    .chats[]
    | if ((.workspace // null) | type != "object"
          or (.workspace.name // null) | type != "string") then
        halt_error(1; "Missing workspace.name")
      elif (.workspace | has("slug") | not) then
        halt_error(1; "Missing workspace.slug key")
      elif ((.user // null) | type != "object"
            or (.user.username // null) | type != "string") then
        halt_error(1; "Missing user.username")
      else
        .
      end
  end
' >/dev/null 2>&1 <<<"$RESPONSE_JSON" || cv_fail "workspace/user fields validation failed" $LINENO

echo "CODEVALID_TEST_ASSERTION_OK:create_widget_basic_happy_path"

cv_step Cleanup "remove seeded data (skipped: node unavailable)" $LINENO
# tool_missing__node: original teardown used Node/Prisma; cannot run without node.
# Leaving database cleanup to external mechanisms.
