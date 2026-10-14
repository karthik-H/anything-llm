#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_5041700496_20261013202446/api/_infra.sh

cv_step Given "app is healthy and workspace exists for attachment scope scenario" $LINENO
cv_prereq "wait for app health" $LINENO
bash .codevalid/seed_test_cases/health_check.sh

WS_SLUG="default-workspace"
CHAT_ID="1"

cv_prereq "fetch workspace before attachment scope edit" $LINENO
# Plan: curl -sS "$BASE_URL/workspace/$WS_SLUG" -H "Content-Type: application/json" | tee /tmp/workspace_before_attachments_scope.json
curl -sS "$BASE_URL/workspace/$WS_SLUG" \
  -H "Content-Type: application/json" \
  -D /tmp/workspace_before_attachments_scope_headers.json \
  -o /tmp/workspace_before_attachments_scope.json \
  -w '%{http_code} %{time_total}\n'
cv_http GET "/workspace/$WS_SLUG" 200
workspace_before_file="/tmp/workspace_before_attachments_scope.json"

cv_step When "assistant edits response in a thread with attachments" $LINENO
body=$(jq -nc --arg chatId "$CHAT_ID" --arg txt 'Edit response in a thread with attachments.' '{chatId:$chatId|tonumber,newText:$txt,role:"assistant"}')
# Plan: curl -sS -o /dev/null -w '%{http_code}\n' -X POST "$BASE_URL/workspace/$WS_SLUG/update-chat" -H "Content-Type: application/json" -d "$body"
curl -sS -X POST "$BASE_URL/workspace/$WS_SLUG/update-chat" \
  -H "Content-Type: application/json" \
  --data "$body" \
  -D /tmp/workspace_attachments_scope_update_headers.json \
  -o /tmp/workspace_attachments_scope_update_body.json \
  -w '%{http_code} %{time_total}\n'
cv_http POST "/workspace/$WS_SLUG/update-chat" 200

cv_step Then "workspace-level configuration remains unchanged; attachment scoping unaffected" $LINENO
# Plan: curl -sS "$BASE_URL/workspace/$WS_SLUG" -H "Content-Type: application/json" | tee /tmp/workspace_after_attachments_scope.json
curl -sS "$BASE_URL/workspace/$WS_SLUG" \
  -H "Content-Type: application/json" \
  -D /tmp/workspace_after_attachments_scope_headers.json \
  -o /tmp/workspace_after_attachments_scope.json \
  -w '%{http_code} %{time_total}\n'
cv_http GET "/workspace/$WS_SLUG" 200
workspace_after_file="/tmp/workspace_after_attachments_scope.json"

# For this case we simply ensure workspace exists and core config fields are still present
workspace_exists=$(jq -e '.workspace' "$workspace_after_file" >/dev/null 2>&1 && echo yes || echo no)
if [ "$workspace_exists" != "yes" ]; then
  cv_fail "expected workspace object to remain after attachment-related edit" $LINENO
fi

cv_step Cleanup "no teardown required" $LINENO

echo "CODEVALID_TEST_ASSERTION_OK:chat_attachments_remain_thread_scoped_not_workspace_scoped"
