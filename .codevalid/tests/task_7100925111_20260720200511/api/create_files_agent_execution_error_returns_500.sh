#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TMP_DIR="$(mktemp -d)"
RESPONSE_HEADERS="$TMP_DIR/response_headers.txt"
RESPONSE_BODY="$TMP_DIR/response_body.txt"

cleanup_tmp() {
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

# Given
echo "STEP: Given — verify authenticated isToolAvailable execution-error precondition assumptions"
echo "PREREQ: this scenario requires a valid authenticated session accepted by validatedRequest middleware"
echo "PREREQ: this scenario also requires the create-files-agent module to load successfully while isToolAvailable() throws an exception in the running environment"

# When
echo "STEP: When — GET /agent-skills/create-files-agent/is-available with authenticated request"
echo "REQUEST_HEADERS: Accept: application/json"
AUTH_HEADER_VALUE="${AUTH_HEADER_VALUE:-Bearer valid-session-token}"
echo "REQUEST_HEADERS: Authorization: ${AUTH_HEADER_VALUE}"
HTTP_CODE="$(curl -sS -D "$RESPONSE_HEADERS" -o "$RESPONSE_BODY" -w '%{http_code}' \
  -X GET "$BASE_URL/agent-skills/create-files-agent/is-available" \
  -H 'Accept: application/json' \
  -H "Authorization: ${AUTH_HEADER_VALUE}")"
echo "RESPONSE_STATUS: $HTTP_CODE"
echo "RESPONSE_HEADERS:"
cat "$RESPONSE_HEADERS"
echo "RESPONSE_BODY:"
cat "$RESPONSE_BODY"

# Then
echo "STEP: Then — assert HTTP 500 and JSON error body"
[ "$HTTP_CODE" = "500" ] || { echo "ASSERTION_FAILED: expected HTTP 500 got ${HTTP_CODE}"; exit 1; }
grep -qi '^Content-Type: application/json' "$RESPONSE_HEADERS" || { echo "ASSERTION_FAILED: expected application/json content type"; exit 1; }
grep -F '"available":false' "$RESPONSE_BODY" >/dev/null 2>&1 || grep -F '"available": false' "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected available false in response body"; exit 1; }
grep -F '"error":' "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected error field in response body"; exit 1; }

# Cleanup
echo "STEP: Cleanup — no public cleanup available for capability discovery request"

echo "CODEVALID_TEST_ASSERTION_OK:create_files_agent_execution_error_returns_500"
