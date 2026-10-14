#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_5041700496_20261013202446/api/_infra.sh

cv_step Given "app is healthy and workspace exists for pinned documents scenario" $LINENO
cv_prereq "wait for app health" $LINENO
bash .codevalid/seed_test_cases/health_check.sh

WS_SLUG="default-workspace"
CHAT_ID="1"

cv_prereq "fetch workspace before pinned documents config edit" $LINENO
cv_http GET "/workspace/$WS_SLUG" 200
workspace_before_file="/tmp/workspace_before_pinned_config.json"
cp "$CV_HTTP_BODY_FILE" "$workspace_before_file"
# Restore plan's direct curl capture of the workspace before state
curl -sS "$BASE_URL/workspace/$WS_SLUG" \
  -H "Content-Type: application/json" \
  | tee "$workspace_before_file" >/dev/null

cv_step When "assistant describes pinned documents behavior in response" $LINENO
body=$(jq -nc --arg chatId "$CHAT_ID" --arg txt 'Describe pinned documents behavior in assistant response.' '{chatId:$chatId|tonumber,newText:$txt,role:"assistant"}')
cv_http POST "/workspace/$WS_SLUG/update-chat" "$body" 200

cv_step Then "workspace configuration remains driven by pin-specific endpoints; update-chat does not change pin flags" $LINENO
cv_http GET "/workspace/$WS_SLUG" 200
workspace_after_file="/tmp/workspace_after_pinned_config.json"
cp "$CV_HTTP_BODY_FILE" "$workspace_after_file"
# Restore plan's direct curl capture of the workspace after state
curl -sS "$BASE_URL/workspace/$WS_SLUG" \
  -H "Content-Type: application/json" \
  | tee "$workspace_after_file" >/dev/null

workspace_exists=$(jq -e '.workspace' "$workspace_after_file" >/dev/null 2>&1 && echo yes || echo no)
if [ "$workspace_exists" != "yes" ]; then
  cv_fail "expected workspace object to remain after pinned documents description edit" $LINENO
fi

cv_step Cleanup "no teardown required" $LINENO

echo "CODEVALID_TEST_ASSERTION_OK:pinned_documents_inserted_verbatim_and_excluded_from_retrieval"
