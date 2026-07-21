#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_AUTH_HEADER="${ADMIN_AUTH_HEADER:-Authorization: Bearer admin-token}"
ACCEPT_HEADER="Accept: application/json"
LIST_HEADERS="/tmp/empty_agent_flows_list_returned_successfully_list_headers_${CASE_SUFFIX}.txt"
LIST_BODY="/tmp/empty_agent_flows_list_returned_successfully_list_body_${CASE_SUFFIX}.txt"

cleanup_files() {
  rm -f "$LIST_HEADERS" "$LIST_BODY"
}
trap cleanup_files EXIT

# Given — bring the system to the required state
printf 'STEP: Given — ensure request is made as admin expecting no flows in this isolated environment\n'
printf 'PREREQ: no per-test flows are created before listing\n'

# When — perform the action under test
printf 'STEP: When — admin requests the agent flows list\n'
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
printf 'STEP: Then — a successful empty list is returned\n'
[ "$LIST_CODE" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 got ${LIST_CODE}"; exit 1; }
jq -e '.success == true' "$LIST_BODY" >/dev/null || { echo "ASSERTION_FAILED: expected success true"; exit 1; }
jq -e '.flows == []' "$LIST_BODY" >/dev/null || { echo "ASSERTION_FAILED: expected flows to equal an empty array"; exit 1; }

# Cleanup — undo Given side effects
printf 'STEP: Cleanup — no cleanup required because Given was stateless\n'

echo 'CODEVALID_TEST_ASSERTION_OK:empty_agent_flows_list_returned_successfully'
