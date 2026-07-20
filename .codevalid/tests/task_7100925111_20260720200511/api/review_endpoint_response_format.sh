#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
TMP_DIR="$(mktemp -d)"
RESPONSE_HEADERS="$TMP_DIR/response_headers.txt"
RESPONSE_BODY="$TMP_DIR/response_body.txt"

cleanup_tmp() {
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

# Given
echo "STEP: Given — prepare a request expecting the canonical JSON response format"
echo "PREREQ: server is running and reachable at ${BASE_URL}"

# When
echo "STEP: When — POST /api/review with Content-Type application/json"
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
echo "STEP: Then — assert JSON response contains only the status field with review_triggered"
[ "$HTTP_CODE" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 got ${HTTP_CODE}"; exit 1; }
BODY_COMPACT="$(tr -d '[:space:]' < "$RESPONSE_BODY")"
[ "$BODY_COMPACT" = '{"status":"review_triggered"}' ] || { echo "ASSERTION_FAILED: expected exact body {\"status\":\"review_triggered\"} got ${BODY_COMPACT}"; exit 1; }

# Cleanup
echo "STEP: Cleanup — no cleanup required for stateless response-format assertion"

echo "CODEVALID_TEST_ASSERTION_OK:review_endpoint_response_format"
