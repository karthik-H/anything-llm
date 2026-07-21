#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_AUTH_HEADER="${ADMIN_AUTH_HEADER:-Authorization: Bearer admin-token}"
ACCEPT_HEADER="Accept: application/json"
FLOW_NAME="Anonymous Access Guard Flow ${CASE_SUFFIX}"
FLOW_CONFIG='{"workspace_id":51,"capabilities":["execute_tasks"],"tools":["task-runner"],"blocks":[{"id":"block-anon","type":"capability","capability":"execute_tasks"}]}'

SAVE_HEADERS="/tmp/unauthenticated_user_denied_access_to_agent_flows_list_save_headers_${CASE_SUFFIX}.txt"
SAVE_BODY="/tmp/unauthenticated_user_denied_access_to_agent_flows_list_save_body_${CASE_SUFFIX}.txt"
LIST_HEADERS="/tmp/unauthenticated_user_denied_access_to_agent_flows_list_list_headers_${CASE_SUFFIX}.txt"
LIST_BODY="/tmp/unauthenticated_user_denied_access_to_agent_flows_list_list_body_${CASE_SUFFIX}.txt"
DELETE_HEADERS="/tmp/unauthenticated_user_denied_access_to_agent_flows_list_delete_headers_${CASE_SUFFIX}.txt"
DELETE_BODY="/tmp/unauthenticated_user_denied_access_to_agent_flows_list_delete_body_${CASE_SUFFIX}.txt"

cleanup_files() {
  rm -f "$SAVE_HEADERS" "$SAVE_BODY" "$LIST_HEADERS" "$LIST_BODY" "$DELETE_HEADERS" "$DELETE_BODY"
}
trap cleanup_files EXIT

FLOW_UUID=""

# Given — bring the system to the required state
printf 'STEP: Given — create an agent flow and omit authentication\n'
printf 'PREREQ: create a flow as admin so the endpoint has data to protect\n'
SAVE_REQUEST_BODY=$(printf '{"name":"%s","config":%s}' "$FLOW_NAME" "$FLOW_CONFIG")
printf 'REQUEST_HEADERS:\n%s\n%s\nContent-Type: application/json\n' "$ADMIN_AUTH_HEADER" "$ACCEPT_HEADER"
printf 'REQUEST_BODY:\n%s\n' "$SAVE_REQUEST_BODY"
SAVE_CODE=$(curl -sS -D "$SAVE_HEADERS" -o "$SAVE_BODY" -w '%{http_code}' \
  -X POST "$BASE_URL/api/agent-flows/save" \
  -H "$ADMIN_AUTH_HEADER" \
  -H "$ACCEPT_HEADER" \
  -H 'Content-Type: application/json' \
  --data "$SAVE_REQUEST_BODY")
printf 'RESPONSE_HEADERS:\n'
cat "$SAVE_HEADERS"
printf 'RESPONSE_BODY:\n'
cat "$SAVE_BODY"
printf '\nRESPONSE_STATUS: %s\n' "$SAVE_CODE"
[ "$SAVE_CODE" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 creating flow got ${SAVE_CODE}"; exit 1; }
FLOW_UUID=$(jq -r '.flow.uuid // empty' "$SAVE_BODY")
[ -n "$FLOW_UUID" ] || { echo "ASSERTION_FAILED: expected created flow uuid"; exit 1; }

# When — perform the action under test
printf 'STEP: When — unauthenticated request is sent to list agent flows\n'
printf 'REQUEST_HEADERS:\n%s\n' "$ACCEPT_HEADER"
printf 'REQUEST_BODY:\n<empty>\n'
LIST_CODE=$(curl -sS -D "$LIST_HEADERS" -o "$LIST_BODY" -w '%{http_code}' \
  -X GET "$BASE_URL/api/agent-flows/list" \
  -H "$ACCEPT_HEADER")
printf 'RESPONSE_HEADERS:\n'
cat "$LIST_HEADERS"
printf 'RESPONSE_BODY:\n'
cat "$LIST_BODY"
printf '\nRESPONSE_STATUS: %s\n' "$LIST_CODE"

# Then — HTTP/body assertions
printf 'STEP: Then — authentication is required\n'
[ "$LIST_CODE" = "401" ] || { echo "ASSERTION_FAILED: expected HTTP 401 got ${LIST_CODE}"; exit 1; }
grep -Eqi 'unauthorized|authentication|required|invalid' "$LIST_BODY" || { echo "ASSERTION_FAILED: expected authentication error message in response body"; exit 1; }

# Cleanup — undo Given side effects
printf 'STEP: Cleanup — delete created agent flow\n'
if [ -n "$FLOW_UUID" ]; then
  printf 'PREREQ: delete created flow %s\n' "$FLOW_UUID"
  DELETE_CODE=$(curl -sS -D "$DELETE_HEADERS" -o "$DELETE_BODY" -w '%{http_code}' \
    -X DELETE "$BASE_URL/api/agent-flows/$FLOW_UUID" \
    -H "$ADMIN_AUTH_HEADER" \
    -H "$ACCEPT_HEADER")
  printf 'RESPONSE_HEADERS:\n'
  cat "$DELETE_HEADERS"
  printf 'RESPONSE_BODY:\n'
  cat "$DELETE_BODY"
  printf '\nRESPONSE_STATUS: %s\n' "$DELETE_CODE"
  [ "$DELETE_CODE" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 deleting flow got ${DELETE_CODE}"; exit 1; }
fi

echo 'CODEVALID_TEST_ASSERTION_OK:unauthenticated_user_denied_access_to_agent_flows_list'
