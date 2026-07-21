#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_AUTH_HEADER="${ADMIN_AUTH_HEADER:-Authorization: Bearer admin-token}"
ACCEPT_HEADER="Accept: application/json"
FLOW_NAME_ONE="Data Processing Agent ${CASE_SUFFIX}"
FLOW_NAME_TWO="Workflow Automation Agent ${CASE_SUFFIX}"
FLOW_CONFIG_ONE='{"workspace_id":51,"capabilities":["browse_data","execute_tasks"],"tools":["browser","task-runner"],"blocks":[{"id":"block-a","type":"capability","capability":"browse_data"}]}'
FLOW_CONFIG_TWO='{"workspace_id":51,"capabilities":["workflow_runner","task_scheduler"],"tools":["workflow-engine","scheduler"],"blocks":[{"id":"block-b","type":"capability","capability":"workflow_runner"}]}'

SAVE1_HEADERS="/tmp/admin_user_retrieves_agent_flows_list_successfully_save1_headers_${CASE_SUFFIX}.txt"
SAVE1_BODY="/tmp/admin_user_retrieves_agent_flows_list_successfully_save1_body_${CASE_SUFFIX}.txt"
SAVE2_HEADERS="/tmp/admin_user_retrieves_agent_flows_list_successfully_save2_headers_${CASE_SUFFIX}.txt"
SAVE2_BODY="/tmp/admin_user_retrieves_agent_flows_list_successfully_save2_body_${CASE_SUFFIX}.txt"
LIST_HEADERS="/tmp/admin_user_retrieves_agent_flows_list_successfully_list_headers_${CASE_SUFFIX}.txt"
LIST_BODY="/tmp/admin_user_retrieves_agent_flows_list_successfully_list_body_${CASE_SUFFIX}.txt"
DELETE1_HEADERS="/tmp/admin_user_retrieves_agent_flows_list_successfully_delete1_headers_${CASE_SUFFIX}.txt"
DELETE1_BODY="/tmp/admin_user_retrieves_agent_flows_list_successfully_delete1_body_${CASE_SUFFIX}.txt"
DELETE2_HEADERS="/tmp/admin_user_retrieves_agent_flows_list_successfully_delete2_headers_${CASE_SUFFIX}.txt"
DELETE2_BODY="/tmp/admin_user_retrieves_agent_flows_list_successfully_delete2_body_${CASE_SUFFIX}.txt"

cleanup_files() {
  rm -f "$SAVE1_HEADERS" "$SAVE1_BODY" "$SAVE2_HEADERS" "$SAVE2_BODY" "$LIST_HEADERS" "$LIST_BODY" "$DELETE1_HEADERS" "$DELETE1_BODY" "$DELETE2_HEADERS" "$DELETE2_BODY"
}
trap cleanup_files EXIT

FLOW_UUID_ONE=""
FLOW_UUID_TWO=""

# Given — bring the system to the required state
printf 'STEP: Given — create two agent flows as admin for workspace 51\n'
printf 'PREREQ: create first agent flow for list retrieval\n'
SAVE1_REQUEST_BODY=$(printf '{"name":"%s","config":%s}' "$FLOW_NAME_ONE" "$FLOW_CONFIG_ONE")
printf 'REQUEST_HEADERS:\n%s\n%s\nContent-Type: application/json\n' "$ADMIN_AUTH_HEADER" "$ACCEPT_HEADER"
printf 'REQUEST_BODY:\n%s\n' "$SAVE1_REQUEST_BODY"
SAVE1_CODE=$(curl -sS -D "$SAVE1_HEADERS" -o "$SAVE1_BODY" -w '%{http_code}' \
  -X POST "$BASE_URL/api/agent-flows/save" \
  -H "$ADMIN_AUTH_HEADER" \
  -H "$ACCEPT_HEADER" \
  -H 'Content-Type: application/json' \
  --data "$SAVE1_REQUEST_BODY")
printf 'RESPONSE_HEADERS:\n'
cat "$SAVE1_HEADERS"
printf 'RESPONSE_BODY:\n'
cat "$SAVE1_BODY"
printf '\nRESPONSE_STATUS: %s\n' "$SAVE1_CODE"
[ "$SAVE1_CODE" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 creating first flow got ${SAVE1_CODE}"; exit 1; }
FLOW_UUID_ONE=$(jq -r '.flow.uuid // empty' "$SAVE1_BODY")
[ -n "$FLOW_UUID_ONE" ] || { echo "ASSERTION_FAILED: expected first flow uuid in response"; exit 1; }

printf 'PREREQ: create second agent flow for list retrieval\n'
SAVE2_REQUEST_BODY=$(printf '{"name":"%s","config":%s}' "$FLOW_NAME_TWO" "$FLOW_CONFIG_TWO")
printf 'REQUEST_HEADERS:\n%s\n%s\nContent-Type: application/json\n' "$ADMIN_AUTH_HEADER" "$ACCEPT_HEADER"
printf 'REQUEST_BODY:\n%s\n' "$SAVE2_REQUEST_BODY"
SAVE2_CODE=$(curl -sS -D "$SAVE2_HEADERS" -o "$SAVE2_BODY" -w '%{http_code}' \
  -X POST "$BASE_URL/api/agent-flows/save" \
  -H "$ADMIN_AUTH_HEADER" \
  -H "$ACCEPT_HEADER" \
  -H 'Content-Type: application/json' \
  --data "$SAVE2_REQUEST_BODY")
printf 'RESPONSE_HEADERS:\n'
cat "$SAVE2_HEADERS"
printf 'RESPONSE_BODY:\n'
cat "$SAVE2_BODY"
printf '\nRESPONSE_STATUS: %s\n' "$SAVE2_CODE"
[ "$SAVE2_CODE" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 creating second flow got ${SAVE2_CODE}"; exit 1; }
FLOW_UUID_TWO=$(jq -r '.flow.uuid // empty' "$SAVE2_BODY")
[ -n "$FLOW_UUID_TWO" ] || { echo "ASSERTION_FAILED: expected second flow uuid in response"; exit 1; }

# When — perform the action under test
printf 'STEP: When — list agent flows as admin\n'
printf 'REQUEST_HEADERS:\n%s\n%s\n' "$ADMIN_AUTH_HEADER" "$ACCEPT_HEADER"
printf 'REQUEST_BODY:\n<empty>\n'
LIST_CODE=$(curl -sS -D "$LIST_HEADERS" -o "$LIST_BODY" -w '%{http_code}' \
  -X GET "$BASE_URL/api/agent-flows/list" \
  -H "$ADMIN_AUTH_HEADER" \
  -H "$ACCEPT_HEADER")
printf 'RESPONSE_HEADERS:\n'
cat "$LIST_HEADERS"
printf 'RESPONSE_BODY:\n'
cat "$LIST_BODY"
printf '\nRESPONSE_STATUS: %s\n' "$LIST_CODE"

# Then — HTTP/body assertions
printf 'STEP: Then — response includes both created flows\n'
[ "$LIST_CODE" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 got ${LIST_CODE}"; exit 1; }
jq -e '.success == true' "$LIST_BODY" >/dev/null || { echo "ASSERTION_FAILED: expected success true"; exit 1; }
jq -e '.flows | type == "array"' "$LIST_BODY" >/dev/null || { echo "ASSERTION_FAILED: expected flows array"; exit 1; }
jq -e --arg n "$FLOW_NAME_ONE" '.flows[] | select(.name == $n)' "$LIST_BODY" >/dev/null || { echo "ASSERTION_FAILED: expected first created flow in list"; exit 1; }
jq -e --arg n "$FLOW_NAME_TWO" '.flows[] | select(.name == $n)' "$LIST_BODY" >/dev/null || { echo "ASSERTION_FAILED: expected second created flow in list"; exit 1; }
grep -F 'browse_data' "$LIST_BODY" >/dev/null || { echo "ASSERTION_FAILED: expected browse_data capability in response"; exit 1; }
grep -F 'workflow_runner' "$LIST_BODY" >/dev/null || { echo "ASSERTION_FAILED: expected workflow_runner capability in response"; exit 1; }
grep -F '51' "$LIST_BODY" >/dev/null || { echo "ASSERTION_FAILED: expected workspace_id 51 in response"; exit 1; }

# Cleanup — undo Given side effects
printf 'STEP: Cleanup — delete created agent flows\n'
if [ -n "$FLOW_UUID_ONE" ]; then
  printf 'PREREQ: delete first created flow %s\n' "$FLOW_UUID_ONE"
  DELETE1_CODE=$(curl -sS -D "$DELETE1_HEADERS" -o "$DELETE1_BODY" -w '%{http_code}' \
    -X DELETE "$BASE_URL/api/agent-flows/$FLOW_UUID_ONE" \
    -H "$ADMIN_AUTH_HEADER" \
    -H "$ACCEPT_HEADER")
  printf 'RESPONSE_HEADERS:\n'
  cat "$DELETE1_HEADERS"
  printf 'RESPONSE_BODY:\n'
  cat "$DELETE1_BODY"
  printf '\nRESPONSE_STATUS: %s\n' "$DELETE1_CODE"
  [ "$DELETE1_CODE" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 deleting first flow got ${DELETE1_CODE}"; exit 1; }
fi
if [ -n "$FLOW_UUID_TWO" ]; then
  printf 'PREREQ: delete second created flow %s\n' "$FLOW_UUID_TWO"
  DELETE2_CODE=$(curl -sS -D "$DELETE2_HEADERS" -o "$DELETE2_BODY" -w '%{http_code}' \
    -X DELETE "$BASE_URL/api/agent-flows/$FLOW_UUID_TWO" \
    -H "$ADMIN_AUTH_HEADER" \
    -H "$ACCEPT_HEADER")
  printf 'RESPONSE_HEADERS:\n'
  cat "$DELETE2_HEADERS"
  printf 'RESPONSE_BODY:\n'
  cat "$DELETE2_BODY"
  printf '\nRESPONSE_STATUS: %s\n' "$DELETE2_CODE"
  [ "$DELETE2_CODE" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 deleting second flow got ${DELETE2_CODE}"; exit 1; }
fi

echo 'CODEVALID_TEST_ASSERTION_OK:admin_user_retrieves_agent_flows_list_successfully'
