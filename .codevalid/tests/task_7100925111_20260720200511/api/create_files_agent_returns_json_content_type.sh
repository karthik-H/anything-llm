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
echo "STEP: Given — verify authenticated JSON-content-type precondition assumptions"
echo "PREREQ: this scenario requires a valid authenticated session accepted by validatedRequest middleware"
echo "PREREQ: this scenario also requires the create-files-agent plugin to be available and to return true in the running environment"

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
echo "STEP: Then — assert HTTP 200, JSON content type, and available true response"
[ "$HTTP_CODE" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 got ${HTTP_CODE}"; exit 1; }
grep -qi '^Content-Type: application/json' "$RESPONSE_HEADERS" || { echo "ASSERTION_FAILED: expected Content-Type application/json header"; exit 1; }
grep -F '"available":true' "$RESPONSE_BODY" >/dev/null 2>&1 || grep -F '"available": true' "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected available true in response body"; exit 1; }

# Cleanup
echo "STEP: Cleanup — no public cleanup available for capability discovery request"

echo "CODEVALID_TEST_ASSERTION_OK:create_files_agent_returns_json_content_type"
