#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TMP_DIR="$(mktemp -d)"
REQUEST_BODY_ONE="$TMP_DIR/request_body_one.json"
REQUEST_BODY_TWO="$TMP_DIR/request_body_two.json"
RESPONSE_ONE_HEADERS="$TMP_DIR/response_one_headers.txt"
RESPONSE_ONE_BODY="$TMP_DIR/response_one_body.txt"
RESPONSE_TWO_HEADERS="$TMP_DIR/response_two_headers.txt"
RESPONSE_TWO_BODY="$TMP_DIR/response_two_body.txt"

cleanup_tmp() {
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

cat > "$REQUEST_BODY_ONE" <<EOF
{"agent_id":"agent-${CASE_SUFFIX}","conversation_id":"conv-${CASE_SUFFIX}","notes":"first payload"}
EOF
cat > "$REQUEST_BODY_TWO" <<EOF
{"foo":"bar-${CASE_SUFFIX}","nested":{"value":"${CASE_SUFFIX}"},"items":[1,2,3]}
EOF

# Given
echo "STEP: Given — prepare two distinct request payloads that should be ignored"
echo "PREREQ: first payload file created at $REQUEST_BODY_ONE"
echo "PREREQ: second payload file created at $REQUEST_BODY_TWO"

# When
echo "STEP: When — POST /api/review twice with different request bodies"
echo "REQUEST_HEADERS: Content-Type: application/json"
echo "REQUEST_BODY:"
cat "$REQUEST_BODY_ONE"
HTTP_CODE_ONE="$(curl -sS -D "$RESPONSE_ONE_HEADERS" -o "$RESPONSE_ONE_BODY" -w '%{http_code}' \
  -X POST "$BASE_URL/api/review" \
  -H 'Content-Type: application/json' \
  --data @"$REQUEST_BODY_ONE")"
echo "RESPONSE_STATUS: $HTTP_CODE_ONE"
echo "RESPONSE_HEADERS:"
cat "$RESPONSE_ONE_HEADERS"
echo "RESPONSE_BODY:"
cat "$RESPONSE_ONE_BODY"

echo "REQUEST_HEADERS: Content-Type: application/json"
echo "REQUEST_BODY:"
cat "$REQUEST_BODY_TWO"
HTTP_CODE_TWO="$(curl -sS -D "$RESPONSE_TWO_HEADERS" -o "$RESPONSE_TWO_BODY" -w '%{http_code}' \
  -X POST "$BASE_URL/api/review" \
  -H 'Content-Type: application/json' \
  --data @"$REQUEST_BODY_TWO")"
echo "RESPONSE_STATUS: $HTTP_CODE_TWO"
echo "RESPONSE_HEADERS:"
cat "$RESPONSE_TWO_HEADERS"
echo "RESPONSE_BODY:"
cat "$RESPONSE_TWO_BODY"

# Then
echo "STEP: Then — assert both responses are identical successful review triggers"
[ "$HTTP_CODE_ONE" = "200" ] || { echo "ASSERTION_FAILED: expected first HTTP 200 got ${HTTP_CODE_ONE}"; exit 1; }
[ "$HTTP_CODE_TWO" = "200" ] || { echo "ASSERTION_FAILED: expected second HTTP 200 got ${HTTP_CODE_TWO}"; exit 1; }
BODY_ONE_COMPACT="$(tr -d '[:space:]' < "$RESPONSE_ONE_BODY")"
BODY_TWO_COMPACT="$(tr -d '[:space:]' < "$RESPONSE_TWO_BODY")"
[ "$BODY_ONE_COMPACT" = '{"status":"review_triggered"}' ] || { echo "ASSERTION_FAILED: expected first response to be review_triggered got ${BODY_ONE_COMPACT}"; exit 1; }
[ "$BODY_TWO_COMPACT" = '{"status":"review_triggered"}' ] || { echo "ASSERTION_FAILED: expected second response to be review_triggered got ${BODY_TWO_COMPACT}"; exit 1; }
[ "$BODY_ONE_COMPACT" = "$BODY_TWO_COMPACT" ] || { echo "ASSERTION_FAILED: expected identical responses but got ${BODY_ONE_COMPACT} vs ${BODY_TWO_COMPACT}"; exit 1; }

# Cleanup
echo "STEP: Cleanup — no cleanup required for request-body ignore behavior"

echo "CODEVALID_TEST_ASSERTION_OK:review_endpoint_ignores_request_body"
