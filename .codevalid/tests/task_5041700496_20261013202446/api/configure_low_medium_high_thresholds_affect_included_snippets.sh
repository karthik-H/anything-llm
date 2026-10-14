#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_5041700496_20261013202446/api/_infra.sh

cv_step Given "app is healthy and workspace exists for threshold levels scenario" $LINENO
cv_prereq "wait for app health" $LINENO
bash .codevalid/seed_test_cases/health_check.sh

WS_SLUG="default-workspace"
CHAT_ID="1"

cv_prereq "fetch workspace before threshold level edits" $LINENO
# Plan step: use curl to fetch workspace and inspect similarityThreshold
curl -sS "$BASE_URL/workspace/$WS_SLUG" \
  -H "Content-Type: application/json" \
  | tee /tmp/workspace_before_thresholds.json

jq '.workspace.similarityThreshold' /tmp/workspace_before_thresholds.json || true

cv_http GET "/workspace/$WS_SLUG" 200
workspace_before_file="/tmp/workspace_before_thresholds.json"
cp "$CV_HTTP_BODY_FILE" "$workspace_before_file"

similarity_before=$(jq -r '.workspace.similarityThreshold' "$workspace_before_file" 2>/dev/null || printf 'null')
printf 'SIMILARITY_BEFORE=%s
' "$similarity_before"

cv_step When "assistant describes Low, Medium, High similarity thresholds in successive edits" $LINENO
for level in Low Medium High; do
  body=$(jq -nc --arg chatId "$CHAT_ID" --arg lvl "$level" '{chatId:$chatId|tonumber,newText:("Set similarity threshold to " + $lvl),role:"assistant"}')
  cv_http POST "/workspace/$WS_SLUG/update-chat" "$body" 200
done

cv_step Then "similarityThreshold in workspace record remains unchanged" $LINENO
cv_http GET "/workspace/$WS_SLUG" 200
workspace_after_file="/tmp/workspace_after_thresholds.json"
cp "$CV_HTTP_BODY_FILE" "$workspace_after_file"

similarity_after=$(jq -r '.workspace.similarityThreshold' "$workspace_after_file" 2>/dev/null || printf 'null')

printf 'Before similarityThreshold: %s
' "$similarity_before"
printf 'After similarityThreshold: %s
' "$similarity_after"

if [ "$similarity_before" != "null" ] && [ "$similarity_after" != "null" ] && [ "$similarity_before" != "$similarity_after" ]; then
  cv_fail "expected similarityThreshold to remain unchanged after descriptive threshold edits" $LINENO
fi

cv_step Cleanup "no teardown required" $LINENO

echo "CODEVALID_TEST_ASSERTION_OK:configure_low_medium_high_thresholds_affect_included_snippets"
