#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
FLOW_UUID="flow-non-admin-${CASE_SUFFIX}"
AUTH_HEADER="${AUTH_HEADER:-Authorization: Bearer member-token-${CASE_SUFFIX}}"

WHEN_RESPONSE_HEADERS="/tmp/delete_agent_flow_unauthorized_non_admin_when_headers_${CASE_SUFFIX}.txt"
WHEN_RESPONSE_BODY="/tmp/delete_agent_flow_unauthorized_non_admin_when_body_${CASE_SUFFIX}.txt"

cleanup_files() {
  rm -f "$WHEN_RESPONSE_HEADERS" "$WHEN_RESPONSE_BODY"
}
trap cleanup_files EXIT

# Given
echo "STEP: Given — prepare non-admin delete request context"
echo "PREREQ: using non-admin authorization header and target flow uuid ${FLOW_UUID}"

# When
echo "STEP: When — send DELETE request for agent flow as non-admin user"
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
echo "STEP: Then — assert request is rejected for missing admin role"
if [ "$when_code" != "401" ] && [ "$when_code" != "403" ]; then
  echo "ASSERTION_FAILED: expected HTTP 401 or 403 got ${when_code}"
  exit 1
fi

# Cleanup
echo "STEP: Cleanup — no additional cleanup required for authorization-only request"

echo 'CODEVALID_TEST_ASSERTION_OK:delete_agent_flow_unauthorized_non_admin'
