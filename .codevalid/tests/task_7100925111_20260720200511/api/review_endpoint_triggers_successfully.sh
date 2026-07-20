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
echo "STEP: Given — prepare a fire-and-forget review trigger request"
echo "PREREQ: relying on a running server for POST /api/review"
echo "PREREQ: internal detached child-process behavior is not exposed by any discovered public API"

# When
echo "STEP: When — POST /api/review with no request body"
echo "REQUEST_HEADERS: Content-Type: application/json"
echo "REQUEST_BODY:"
echo "{}"
HTTP_CODE="$(curl -sS -D "$RESPONSE_HEADERS" -o "$RESPONSE_BODY" -w '%{http_code}' \
  -X POST "$BASE_URL/api/review" \
  -H 'Content-Type: application/json' \
  --data '{}')"
echo "RESPONSE_STATUS: $HTTP_CODE"
echo "RESPONSE_HEADERS:"
cat "$RESPONSE_HEADERS"
echo "RESPONSE_BODY:"
cat "$RESPONSE_BODY"

# Then
echo "STEP: Then — assert immediate review trigger success response is returned"
[ "$HTTP_CODE" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 got ${HTTP_CODE}"; exit 1; }
grep -F '"status":"review_triggered"' "$RESPONSE_BODY" >/dev/null 2>&1 \
  || grep -F '"status": "review_triggered"' "$RESPONSE_BODY" >/dev/null 2>&1 \
  || { echo "ASSERTION_FAILED: expected status review_triggered in response body"; exit 1; }
echo "ASSERTION_NOTE: detached spawn arguments are internal implementation details not verifiable via discovered public API"

# Cleanup
echo "STEP: Cleanup — no public cleanup available for detached review child process"

echo "CODEVALID_TEST_ASSERTION_OK:review_endpoint_triggers_successfully"
