#!/usr/bin/env bash
set -euo pipefail

# Source shared infra for this task
source .codevalid/tests/task_2370875416_20261013202446/api/_infra.sh

# Export API key as per plan
export API_KEY="test-api-key"

# Case: agent_mode_basic_workspace_scoped_session

# Given: workspace and session setup
cv_step Given "create automatic agent workspace and session" $LINENO

cv_prereq "create workspace via POST /v1/workspace/new" $LINENO
# Restore direct curl call as in the plan (against localhost:3001)
curl -sS -X POST "http://localhost:3001/v1/workspace/new" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -D "${TMPDIR:-/tmp}/cv_http_headers.$$" \
  -o "${TMPDIR:-/tmp}/cv_http_body.$$" \
  -w '%{http_code}' \
  -d '{
    "name": "Agent Basic Workspace",
    "similarityThreshold": 0.25,
    "openAiTemp": 0.7,
    "openAiHistory": 20,
    "topN": 4
  }' \
  || cv_fail "curl to create workspace failed" $LINENO
CV_HTTP_BODY_FILE="${TMPDIR:-/tmp}/cv_http_body.$$"
CV_HTTP_HEADERS_FILE="${TMPDIR:-/tmp}/cv_http_headers.$$"
CV_HTTP_BODY="$(cat "$CV_HTTP_BODY_FILE" 2>/dev/null || true)"
CV_HTTP_STATUS="$(tail -n1 "$CV_HTTP_HEADERS_FILE" 2>/dev/null || echo 000)"
cv_http POST "/v1/workspace/new" 200

# Save body to file for later jq extraction
printf '%s' "$CV_HTTP_BODY" > /tmp/ws_agent_basic_new.json

# Extract workspace slug
if ! command -v jq >/dev/null 2>&1; then
  cv_fail "jq is required but not installed" $LINENO
fi
AGENT_BASIC_SLUG="$(jq -r '.workspace.slug' /tmp/ws_agent_basic_new.json || true)"
if [ -z "$AGENT_BASIC_SLUG" ] || [ "$AGENT_BASIC_SLUG" = "null" ]; then
  cv_fail "failed to extract workspace.slug from /tmp/ws_agent_basic_new.json" $LINENO
fi
echo "Created workspace slug: ${AGENT_BASIC_SLUG}"

cv_prereq "ensure chatMode is automatic via POST /v1/workspace/:slug/update" $LINENO
curl_json \
  POST \
  "/v1/workspace/${AGENT_BASIC_SLUG}/update" \
  "{\"chatMode\":\"automatic\"}" \
  200 \
  -H "x-api-key: $API_KEY"

# Optional embedding call per plan
cv_prereq "call update-embeddings with empty adds/deletes" $LINENO
curl_json \
  POST \
  "/v1/workspace/${AGENT_BASIC_SLUG}/update-embeddings" \
  "{\"adds\":[],\"deletes\":[]}" \
  200 \
  -H "x-api-key: $API_KEY"

# Define session id
SESSION_ID_AGENT_BASIC="session-agent-basic"

# When: agent session interactions
cv_step When "interact with agent session in automatic mode" $LINENO

# 1) Start agent session with @agent message
curl_json \
  POST \
  "/v1/workspace/${AGENT_BASIC_SLUG}/chat" \
  "{\"message\":\"@agent Please summarize the policies in this workspace.\",\"mode\":\"automatic\",\"sessionId\":\"${SESSION_ID_AGENT_BASIC}\",\"attachments\":[],\"reset\":false}" \
  200 \
  -H "x-api-key: $API_KEY"
printf '%s' "$CV_HTTP_BODY" > /tmp/ws_agent_basic_agent_start.json

# 2) Continue conversation in same session
curl_json \
  POST \
  "/v1/workspace/${AGENT_BASIC_SLUG}/chat" \
  "{\"message\":\"Provide more detailed guidance on the same topic.\",\"mode\":\"automatic\",\"sessionId\":\"${SESSION_ID_AGENT_BASIC}\",\"attachments\":[],\"reset\":false}" \
  200 \
  -H "x-api-key: $API_KEY"
printf '%s' "$CV_HTTP_BODY" > /tmp/ws_agent_basic_agent_continue.json

# 3) Send exit message
curl_json \
  POST \
  "/v1/workspace/${AGENT_BASIC_SLUG}/chat" \
  "{\"message\":\"exit\",\"mode\":\"automatic\",\"sessionId\":\"${SESSION_ID_AGENT_BASIC}\",\"attachments\":[],\"reset\":false}" \
  200 \
  -H "x-api-key: $API_KEY"
printf '%s' "$CV_HTTP_BODY" > /tmp/ws_agent_basic_agent_exit.json

# 4) Post-exit message in same session
curl_json \
  POST \
  "/v1/workspace/${AGENT_BASIC_SLUG}/chat" \
  "{\"message\":\"Now answer as a normal workspace chat without using tools.\",\"mode\":\"automatic\",\"sessionId\":\"${SESSION_ID_AGENT_BASIC}\",\"attachments\":[],\"reset\":false}" \
  200 \
  -H "x-api-key: $API_KEY"
printf '%s' "$CV_HTTP_BODY" > /tmp/ws_agent_basic_post_exit.json

# Then: verify responses and session-scoped history
cv_step Then "assert agent session behavior and workspace-scoped history" $LINENO

# 1) Assertions for @agent invocation
jq '.' /tmp/ws_agent_basic_agent_start.json
AGENT_START_TYPE="$(jq -r '.type' /tmp/ws_agent_basic_agent_start.json || true)"
AGENT_START_TEXT="$(jq -r '.textResponse' /tmp/ws_agent_basic_agent_start.json || true)"
AGENT_START_THOUGHTS_COUNT="$(jq -r '.thoughts | length' /tmp/ws_agent_basic_agent_start.json || echo 0)"
AGENT_START_OUTPUTS_COUNT="$(jq -r '.outputs | length' /tmp/ws_agent_basic_agent_start.json || echo 0)"
AGENT_START_SOURCES_COUNT="$(jq -r '.sources | length' /tmp/ws_agent_basic_agent_start.json || echo 0)"

[ "$AGENT_START_TYPE" = "textResponse" ] || cv_fail "expected AGENT_START_TYPE=textResponse got $AGENT_START_TYPE" $LINENO
[ -n "$AGENT_START_TEXT" ] || cv_fail "expected non-empty AGENT_START_TEXT" $LINENO
# counts must be numeric and >= 0
case "$AGENT_START_THOUGHTS_COUNT" in ''|*[!0-9]*) cv_fail "invalid thoughts count: $AGENT_START_THOUGHTS_COUNT" $LINENO ;; esac
case "$AGENT_START_OUTPUTS_COUNT" in ''|*[!0-9]*) cv_fail "invalid outputs count: $AGENT_START_OUTPUTS_COUNT" $LINENO ;; esac
case "$AGENT_START_SOURCES_COUNT" in ''|*[!0-9]*) cv_fail "invalid sources count: $AGENT_START_SOURCES_COUNT" $LINENO ;; esac
[ "$AGENT_START_THOUGHTS_COUNT" -ge 0 ] || cv_fail "thoughts count negative: $AGENT_START_THOUGHTS_COUNT" $LINENO
[ "$AGENT_START_OUTPUTS_COUNT" -ge 0 ] || cv_fail "outputs count negative: $AGENT_START_OUTPUTS_COUNT" $LINENO
[ "$AGENT_START_SOURCES_COUNT" -ge 0 ] || cv_fail "sources count negative: $AGENT_START_SOURCES_COUNT" $LINENO

# 2) Assertions for follow-up message
jq '.' /tmp/ws_agent_basic_agent_continue.json
AGENT_CONTINUE_TYPE="$(jq -r '.type' /tmp/ws_agent_basic_agent_continue.json || true)"
AGENT_CONTINUE_TEXT="$(jq -r '.textResponse' /tmp/ws_agent_basic_agent_continue.json || true)"

[ "$AGENT_CONTINUE_TYPE" = "textResponse" ] || cv_fail "expected AGENT_CONTINUE_TYPE=textResponse got $AGENT_CONTINUE_TYPE" $LINENO
[ -n "$AGENT_CONTINUE_TEXT" ] || cv_fail "expected non-empty AGENT_CONTINUE_TEXT" $LINENO

# 3) Assertions for exit message
jq '.' /tmp/ws_agent_basic_agent_exit.json
AGENT_EXIT_TYPE="$(jq -r '.type' /tmp/ws_agent_basic_agent_exit.json || true)"
AGENT_EXIT_TEXT="$(jq -r '.textResponse' /tmp/ws_agent_basic_agent_exit.json || true)"
AGENT_EXIT_ERROR="$(jq -r '.error' /tmp/ws_agent_basic_agent_exit.json || true)"

[ "$AGENT_EXIT_TYPE" = "textResponse" ] || cv_fail "expected AGENT_EXIT_TYPE=textResponse got $AGENT_EXIT_TYPE" $LINENO
[ -n "$AGENT_EXIT_TEXT" ] || cv_fail "expected non-empty AGENT_EXIT_TEXT" $LINENO
[ "$AGENT_EXIT_ERROR" = "null" ] || cv_fail "expected AGENT_EXIT_ERROR=null got $AGENT_EXIT_ERROR" $LINENO

# 4) Assertions for post-exit message
jq '.' /tmp/ws_agent_basic_post_exit.json
POST_EXIT_TYPE="$(jq -r '.type' /tmp/ws_agent_basic_post_exit.json || true)"
POST_EXIT_TEXT="$(jq -r '.textResponse' /tmp/ws_agent_basic_post_exit.json || true)"
POST_EXIT_THOUGHTS_COUNT="$(jq -r '.thoughts | length' /tmp/ws_agent_basic_post_exit.json || echo 0)"

[ "$POST_EXIT_TYPE" = "textResponse" ] || cv_fail "expected POST_EXIT_TYPE=textResponse got $POST_EXIT_TYPE" $LINENO
[ -n "$POST_EXIT_TEXT" ] || cv_fail "expected non-empty POST_EXIT_TEXT" $LINENO
case "$POST_EXIT_THOUGHTS_COUNT" in ''|*[!0-9]*) cv_fail "invalid post-exit thoughts count: $POST_EXIT_THOUGHTS_COUNT" $LINENO ;; esac
[ "$POST_EXIT_THOUGHTS_COUNT" -eq 0 ] || cv_fail "expected POST_EXIT_THOUGHTS_COUNT=0 got $POST_EXIT_THOUGHTS_COUNT" $LINENO

# 5) Assert workspace-scoped session isolation via GET /v1/workspace/:slug/chats
cv_prereq "fetch chats by apiSessionId via GET /v1/workspace/:slug/chats" $LINENO
cv_http \
  GET \
  "/v1/workspace/${AGENT_BASIC_SLUG}/chats?apiSessionId=${SESSION_ID_AGENT_BASIC}&limit=20&orderBy=asc" \
  200 \
  -H "x-api-key: $API_KEY"
printf '%s' "$CV_HTTP_BODY" > /tmp/ws_agent_basic_chats_session.json

SESSION_HISTORY_COUNT="$(jq -r '.history | length' /tmp/ws_agent_basic_chats_session.json || echo 0)"
case "$SESSION_HISTORY_COUNT" in ''|*[!0-9]*) cv_fail "invalid SESSION_HISTORY_COUNT: $SESSION_HISTORY_COUNT" $LINENO ;; esac
[ "$SESSION_HISTORY_COUNT" -ge 1 ] || cv_fail "expected at least 1 history item, got $SESSION_HISTORY_COUNT" $LINENO

# Cleanup: delete workspace
cv_step Cleanup "delete test workspace" $LINENO
cv_http \
  DELETE \
  "/v1/workspace/${AGENT_BASIC_SLUG}" \
  200 \
  -H "x-api-key: $API_KEY" || true

# Success marker required by runner
echo "CODEVALID_TEST_ASSERTION_OK:agent_mode_basic_workspace_scoped_session"
