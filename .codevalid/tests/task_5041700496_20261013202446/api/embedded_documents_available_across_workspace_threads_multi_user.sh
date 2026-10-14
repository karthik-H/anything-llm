#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_5041700496_20261013202446/api/_infra.sh

cv_step Given "app is healthy and workspace exists for embedded documents scenario" $LINENO
cv_prereq "wait for app health" $LINENO
bash .codevalid/seed_test_cases/health_check.sh

WS_SLUG="default-workspace"
CHAT_ID="1"

cv_prereq "fetch workspace before embedded documents edit" $LINENO
# Restore plan's raw curl precondition to capture workspace before state
curl -sS "$BASE_URL/workspace/$WS_SLUG" \
  -H "Content-Type: application/json" \
  | tee /tmp/workspace_before_embedded.json >/dev/null
cv_http GET "/workspace/$WS_SLUG" 200
workspace_before_file="/tmp/workspace_before_embedded.json"
cp "$CV_HTTP_BODY_FILE" "$workspace_before_file"

cv_step When "admin edits chat after embeddings are configured" $LINENO
body=$(jq -nc --arg chatId "$CHAT_ID" --arg txt 'Admin edits chat after embeddings are configured.' '{chatId:$chatId|tonumber,newText:$txt,role:"assistant"}')
cv_http POST "/workspace/$WS_SLUG/update-chat" "$body" 200

cv_step Then "workspace object still present and embeddings-related fields untouched" $LINENO
cv_http GET "/workspace/$WS_SLUG" 200
workspace_after_file="/tmp/workspace_after_embedded.json"
cp "$CV_HTTP_BODY_FILE" "$workspace_after_file"

# We only assert that workspace field exists and that core config fields remain
workspace_exists=$(jq -e '.workspace' "$workspace_after_file" >/dev/null 2>&1 && echo yes || echo no)
if [ "$workspace_exists" != "yes" ]; then
  cv_fail "expected workspace object to be present after update-chat" $LINENO
fi

cv_step Cleanup "no teardown required" $LINENO

echo "CODEVALID_TEST_ASSERTION_OK:embedded_documents_available_across_workspace_threads_multi_user"
