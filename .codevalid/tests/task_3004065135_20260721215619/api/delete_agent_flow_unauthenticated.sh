#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
FLOW_UUID="flow-unauth-${CASE_SUFFIX}"

WHEN_RESPONSE_HEADERS="/tmp/delete_agent_flow_unauthenticated_when_headers_${CASE_SUFFIX}.txt"
WHEN_RESPONSE_BODY="/tmp/delete_agent_flow_unauthenticated_when_body_${CASE_SUFFIX}.txt"

cleanup_files() {
  rm -f "$WHEN_RESPONSE_HEADERS" "$WHEN_RESPONSE_BODY"
}
trap cleanup_files EXIT

# Given
echo "STEP: Given — prepare unauthenticated delete request context"
echo "PREREQ: no Authorization header will be sent for flow uuid ${FLOW_UUID}"

# When
echo "STEP: When — send DELETE request for agent flow without authentication"
echo 'REQUEST_HEADERS: Content-Type: application/json'
echo 'REQUEST_BODY: '
when_code="$(curl -sS -D "$WHEN_RESPONSE_HEADERS" -o "$WHEN_RESPONSE_BODY" -w '%{http_code}' -X DELETE "$BASE_URL/api/agent-flows/${FLOW_UUID}" -H 'Content-Type: application/json')"
echo 'RESPONSE_HEADERS:'
cat "$WHEN_RESPONSE_HEADERS"
echo 'RESPONSE_BODY:'
cat "$WHEN_RESPONSE_BODY"
echo "RESPONSE_STATUS: ${when_code}"

# Then
echo "STEP: Then — assert unauthenticated request is rejected"
[ "$when_code" = "401" ] || { echo "ASSERTION_FAILED: expected HTTP 401 got ${when_code}"; exit 1; }

# Cleanup
echo "STEP: Cleanup — no cleanup required for unauthenticated negative test"

echo 'CODEVALID_TEST_ASSERTION_OK:delete_agent_flow_unauthenticated'
