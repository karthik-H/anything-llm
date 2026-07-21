#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
FLOW_UUID="flow-fail123"
AUTH_HEADER="${AUTH_HEADER:-Authorization: Bearer admin-token-${CASE_SUFFIX}}"

WHEN_RESPONSE_HEADERS="/tmp/delete_agent_flow_database_failure_when_headers_${CASE_SUFFIX}.txt"
WHEN_RESPONSE_BODY="/tmp/delete_agent_flow_database_failure_when_body_${CASE_SUFFIX}.txt"

cleanup_files() {
  rm -f "$WHEN_RESPONSE_HEADERS" "$WHEN_RESPONSE_BODY"
}
trap cleanup_files EXIT

# Given
echo "STEP: Given — prepare admin request targeting failure sentinel uuid"
echo "PREREQ: using admin authorization header and failure uuid ${FLOW_UUID}"

# When
echo "STEP: When — send DELETE request expected to trigger deleteFlow failure path"
echo 'REQUEST_HEADERS: Content-Type: application/json'
echo "REQUEST_HEADERS: ${AUTH_HEADER}"
echo 'REQUEST_BODY: '
when_code="$(curl -sS -D "$WHEN_RESPONSE_HEADERS" -o "$WHEN_RESPONSE_BODY" -w '%{http_code}' -X DELETE "$BASE_URL/api/agent-flows/${FLOW_UUID}" -H "$AUTH_HEADER" -H 'Content-Type: application/json')"
echo 'RESPONSE_HEADERS:'
cat "$WHEN_RESPONSE_HEADERS"
echo 'RESPONSE_BODY:'
cat "$WHEN_RESPONSE_BODY"
echo "RESPONSE_STATUS: ${when_code}"

# Then
echo "STEP: Then — assert graceful 500 error contract for delete failure"
[ "$when_code" = "500" ] || { echo "ASSERTION_FAILED: expected HTTP 500 got ${when_code}"; exit 1; }
grep -q '"success"[[:space:]]*:[[:space:]]*false' "$WHEN_RESPONSE_BODY" || { echo 'ASSERTION_FAILED: expected response body to contain success false'; exit 1; }
grep -q 'Failed to delete flow' "$WHEN_RESPONSE_BODY" || { echo 'ASSERTION_FAILED: expected response body to mention Failed to delete flow'; exit 1; }

# Cleanup
echo "STEP: Cleanup — no cleanup required beyond temporary files for failure-path request"

echo 'CODEVALID_TEST_ASSERTION_OK:delete_agent_flow_database_failure'
