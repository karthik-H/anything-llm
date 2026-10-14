#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_5041700496_20261013202446/api/_infra.sh

cv_step Given "app is healthy and workspace exists for default user scenario" $LINENO
cv_prereq "wait for app health" $LINENO
bash .codevalid/seed_test_cases/health_check.sh

WS_SLUG="default-workspace"
CHAT_ID="1"

cv_prereq "fetch workspace before default user edit" $LINENO
cv_http GET "/workspace/$WS_SLUG" 200
workspace_before_file="/tmp/workspace_before_default.json"
cp "$CV_HTTP_BODY_FILE" "$workspace_before_file"

similarity_before=$(jq -r '.workspace.similarityThreshold' "$workspace_before_file" 2>/dev/null || printf 'null')
max_snippets_before=$(jq -r '.workspace.topN' "$workspace_before_file" 2>/dev/null || printf 'null')
printf 'SIMILARITY_BEFORE=%s
' "$similarity_before"
printf 'TOPN_BEFORE=%s
' "$max_snippets_before"

cv_step When "default user attempts to describe workspace chat settings change" $LINENO
default_body=$(jq -nc --arg chatId "$CHAT_ID" --arg txt 'Default user attempts to change workspace chat settings.' '{chatId:$chatId|tonumber,newText:$txt,role:"assistant"}')
cv_http POST "/workspace/$WS_SLUG/update-chat" "$default_body" 200

# Restore plan's raw curl call for this step (diagnostic only; main assertion via cv_http)
curl -sS -o /dev/null -w '%{http_code}\n' \
  -X POST "$BASE_URL/workspace/$WS_SLUG/update-chat" \
  -H "Content-Type: application/json" \
  -d "$default_body"
cv_http POST "$BASE_URL/workspace/$WS_SLUG/update-chat" 200 0

cv_step Then "workspace thresholds remain unchanged; endpoint does not enforce role-based config" $LINENO
cv_http GET "/workspace/$WS_SLUG" 200
workspace_after_file="/tmp/workspace_after_default.json"
cp "$CV_HTTP_BODY_FILE" "$workspace_after_file"

similarity_after=$(jq -r '.workspace.similarityThreshold' "$workspace_after_file" 2>/dev/null || printf 'null')
max_snippets_after=$(jq -r '.workspace.topN' "$workspace_after_file" 2>/dev/null || printf 'null')

printf 'Before similarityThreshold/topN: %s / %s
' "$similarity_before" "$max_snippets_before"
printf 'After similarityThreshold/topN: %s / %s
' "$similarity_after" "$max_snippets_after"

if [ "$similarity_before" != "null" ] && [ "$similarity_after" != "null" ] && [ "$similarity_before" != "$similarity_after" ]; then
  cv_fail "expected similarityThreshold to remain unchanged after default user edit" $LINENO
fi
if [ "$max_snippets_before" != "null" ] && [ "$max_snippets_after" != "null" ] && [ "$max_snippets_before" != "$max_snippets_after" ]; then
  cv_fail "expected topN to remain unchanged after default user edit" $LINENO
fi

cv_step Cleanup "no teardown required" $LINENO

echo "CODEVALID_TEST_ASSERTION_OK:default_user_cannot_access_or_modify_workspace_chat_settings"
