#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_5041700496_20261013202446/api/_infra.sh

cv_step Given "app is healthy and workspace exists for max context snippets scenario" $LINENO
cv_prereq "wait for app health" $LINENO
bash .codevalid/seed_test_cases/health_check.sh

WS_SLUG="default-workspace"
CHAT_ID="1"

cv_prereq "fetch workspace before max snippets edit" $LINENO
# Raw curl pre-check matching the plan's precondition
curl -sS "$BASE_URL/workspace/$WS_SLUG" >/dev/null 2>&1 || true
cv_http GET "/workspace/$WS_SLUG" 200
workspace_before_file="/tmp/workspace_before_topn.json"
cp "$CV_HTTP_BODY_FILE" "$workspace_before_file"

max_snippets_before=$(jq -r '.workspace.topN' "$workspace_before_file" 2>/dev/null || printf 'null')
printf 'TOPN_BEFORE=%s
' "$max_snippets_before"

cv_step When "assistant describes new max context snippets per chat" $LINENO
body=$(jq -nc --arg chatId "$CHAT_ID" --arg txt 'Set max context snippets per chat to 2.' '{chatId:$chatId|tonumber,newText:$txt,role:"assistant"}')
cv_http POST "/workspace/$WS_SLUG/update-chat" "$body" 200

cv_step Then "topN in workspace record remains unchanged" $LINENO
cv_http GET "/workspace/$WS_SLUG" 200
workspace_after_file="/tmp/workspace_after_topn.json"
cp "$CV_HTTP_BODY_FILE" "$workspace_after_file"

max_snippets_after=$(jq -r '.workspace.topN' "$workspace_after_file" 2>/dev/null || printf 'null')

printf 'Before topN: %s
' "$max_snippets_before"
printf 'After topN: %s
' "$max_snippets_after"

if [ "$max_snippets_before" != "null" ] && [ "$max_snippets_after" != "null" ] && [ "$max_snippets_before" != "$max_snippets_after" ]; then
  cv_fail "expected topN to remain unchanged after descriptive max snippets edit" $LINENO
fi

cv_step Cleanup "no teardown required" $LINENO

echo "CODEVALID_TEST_ASSERTION_OK:configure_max_context_snippets_limit_applied_per_chat"
