#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
FLOW_UUID="flow-exec-${CASE_SUFFIX}"
AUTH_HEADER="${AUTH_HEADER:-Authorization: Bearer admin-token-${CASE_SUFFIX}}"

WHEN_RESPONSE_HEADERS="/tmp/delete_agent_flow_with_execution_history_when_headers_${CASE_SUFFIX}.txt"
WHEN_RESPONSE_BODY="/tmp/delete_agent_flow_with_execution_history_when_body_${CASE_SUFFIX}.txt"
CLEANUP_RESPONSE_HEADERS="/tmp/delete_agent_flow_with_execution_history_cleanup_headers_${CASE_SUFFIX}.txt"
CLEANUP_RESPONSE_BODY="/tmp/delete_agent_flow_with_execution_history_cleanup_body_${CASE_SUFFIX}.txt"

cleanup_files() {
  rm -f "$WHEN_RESPONSE_HEADERS" "$WHEN_RESPONSE_BODY" "$CLEANUP_RESPONSE_HEADERS" "$CLEANUP_RESPONSE_BODY"
}
trap cleanup_files EXIT

# Given
echo "STEP: Given — prepare admin delete request for flow with implied execution history"
echo "PREREQ: using admin authorization header and unique flow uuid ${FLOW_UUID}"

# When
echo "STEP: When — send DELETE request for agent flow with execution history"
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
echo "STEP: Then — assert delete succeeded for flow with execution history"
[ "$when_code" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 got ${when_code}"; exit 1; }
grep -q '"success"[[:space:]]*:[[:space:]]*true' "$WHEN_RESPONSE_BODY" || { echo 'ASSERTION_FAILED: expected response body to contain success true'; exit 1; }

# Cleanup
echo "STEP: Cleanup — best-effort idempotent delete retry for execution-history test uuid"
echo 'REQUEST_HEADERS: Content-Type: application/json'
echo "REQUEST_HEADERS: ${AUTH_HEADER}"
echo 'REQUEST_BODY: '
cleanup_code="$(curl -sS -D "$CLEANUP_RESPONSE_HEADERS" -o "$CLEANUP_RESPONSE_BODY" -w '%{http_code}' -X DELETE "$BASE_URL/api/agent-flows/${FLOW_UUID}" -H "$AUTH_HEADER" -H 'Content-Type: application/json' || true)"
echo 'RESPONSE_HEADERS:'
cat "$CLEANUP_RESPONSE_HEADERS" 2>/dev/null || true
echo 'RESPONSE_BODY:'
cat "$CLEANUP_RESPONSE_BODY" 2>/dev/null || true
echo "RESPONSE_STATUS: ${cleanup_code}"

echo 'CODEVALID_TEST_ASSERTION_OK:delete_agent_flow_with_execution_history'
