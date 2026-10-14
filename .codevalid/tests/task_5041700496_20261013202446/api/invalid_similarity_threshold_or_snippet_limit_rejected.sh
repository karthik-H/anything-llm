#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_5041700496_20261013202446/api/_infra.sh

cv_step Given "app is healthy and workspace exists for invalid config scenario" $LINENO
cv_prereq "wait for app health" $LINENO
bash .codevalid/seed_test_cases/health_check.sh

WS_SLUG="default-workspace"
CHAT_ID="1"

cv_prereq "fetch workspace before invalid configuration edit" $LINENO
cv_http GET "/workspace/$WS_SLUG" 200
workspace_before_file="/tmp/workspace_before_invalid_config.json"
cp "$CV_HTTP_BODY_FILE" "$workspace_before_file"

similarity_before=$(jq -r '.workspace.similarityThreshold' "$workspace_before_file" 2>/dev/null || printf 'null')
max_snippets_before=$(jq -r '.workspace.topN' "$workspace_before_file" 2>/dev/null || printf 'null')
printf 'SIMILARITY_BEFORE=%s
' "$similarity_before"
printf 'TOPN_BEFORE=%s
' "$max_snippets_before"

cv_step When "assistant encodes invalid similarity threshold and snippet limit in plain text" $LINENO
body=$(jq -nc --arg chatId "$CHAT_ID" --arg txt 'Set similarity threshold to "not-a-number" and max snippets to -1.' '{chatId:$chatId|tonumber,newText:$txt,role:"assistant"}')
cv_http POST "/workspace/$WS_SLUG/update-chat" "$body" 200

cv_step Then "endpoint returns 200 but workspace similarityThreshold/topN remain unchanged" $LINENO
cv_http GET "/workspace/$WS_SLUG" 200
workspace_after_file="/tmp/workspace_after_invalid_config.json"
cp "$CV_HTTP_BODY_FILE" "$workspace_after_file"

# Restore original plan step that used curl directly for comparison output
curl -sS "$BASE_URL/workspace/$WS_SLUG" \
  -H "Content-Type: application/json" \
  | tee /tmp/workspace_after_invalid_config_plan.json

echo "Before similarityThreshold/topN:"
jq '.workspace.similarityThreshold, .workspace.topN' "$workspace_before_file" || true
echo "After similarityThreshold/topN:"
jq '.workspace.similarityThreshold, .workspace.topN' /tmp/workspace_after_invalid_config_plan.json || true

similarity_after=$(jq -r '.workspace.similarityThreshold' "$workspace_after_file" 2>/dev/null || printf 'null')
max_snippets_after=$(jq -r '.workspace.topN' "$workspace_after_file" 2>/dev/null || printf 'null')

printf 'Before similarityThreshold/topN: %s / %s
' "$similarity_before" "$max_snippets_before"
printf 'After similarityThreshold/topN: %s / %s
' "$similarity_after" "$max_snippets_after"

if [ "$similarity_before" != "null" ] && [ "$similarity_after" != "null" ] && [ "$similarity_before" != "$similarity_after" ]; then
  cv_fail "expected similarityThreshold to remain unchanged after invalid config description" $LINENO
fi
if [ "$max_snippets_before" != "null" ] && [ "$max_snippets_after" != "null" ] && [ "$max_snippets_before" != "$max_snippets_after" ]; then
  cv_fail "expected topN to remain unchanged after invalid config description" $LINENO
fi

cv_step Cleanup "no teardown required" $LINENO

echo "CODEVALID_TEST_ASSERTION_OK:invalid_similarity_threshold_or_snippet_limit_rejected"
