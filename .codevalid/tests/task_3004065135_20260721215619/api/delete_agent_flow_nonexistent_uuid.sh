#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
FLOW_UUID="nonexistent-uuid-${CASE_SUFFIX}"
AUTH_HEADER="${AUTH_HEADER:-Authorization: Bearer admin-token-${CASE_SUFFIX}}"

WHEN_RESPONSE_HEADERS="/tmp/delete_agent_flow_nonexistent_uuid_when_headers_${CASE_SUFFIX}.txt"
WHEN_RESPONSE_BODY="/tmp/delete_agent_flow_nonexistent_uuid_when_body_${CASE_SUFFIX}.txt"

cleanup_files() {
  rm -f "$WHEN_RESPONSE_HEADERS" "$WHEN_RESPONSE_BODY"
}
trap cleanup_files EXIT

# Given
echo "STEP: Given — prepare admin request for non-existent agent flow uuid"
echo "PREREQ: using unique non-existent uuid ${FLOW_UUID} with admin authorization header"

# When
echo "STEP: When — send DELETE request for non-existent agent flow"
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
echo "STEP: Then — assert endpoint returns one of the documented outcomes"
if [ "$when_code" != "200" ] && [ "$when_code" != "500" ]; then
  echo "ASSERTION_FAILED: expected HTTP 200 or 500 got ${when_code}"
  exit 1
fi
if [ "$when_code" = "200" ]; then
  grep -q '"success"[[:space:]]*:[[:space:]]*true' "$WHEN_RESPONSE_BODY" || { echo 'ASSERTION_FAILED: expected 200 response body to contain success true'; exit 1; }
fi
if [ "$when_code" = "500" ]; then
  grep -q '"success"[[:space:]]*:[[:space:]]*false' "$WHEN_RESPONSE_BODY" || { echo 'ASSERTION_FAILED: expected 500 response body to contain success false'; exit 1; }
  grep -q 'Failed to delete flow' "$WHEN_RESPONSE_BODY" || { echo 'ASSERTION_FAILED: expected 500 response body to mention Failed to delete flow'; exit 1; }
fi

# Cleanup
echo "STEP: Cleanup — no cleanup required for non-existent resource test"

echo 'CODEVALID_TEST_ASSERTION_OK:delete_agent_flow_nonexistent_uuid'
