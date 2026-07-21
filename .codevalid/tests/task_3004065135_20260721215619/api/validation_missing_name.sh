#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="validation_missing_name"
REQ_HEADERS_FILE="/tmp/${TEST_ID}_req_headers_${CASE_SUFFIX}.txt"
REQ_BODY_FILE="/tmp/${TEST_ID}_req_body_${CASE_SUFFIX}.json"
RESP_HEADERS_FILE="/tmp/${TEST_ID}_resp_headers_${CASE_SUFFIX}.txt"
RESP_BODY_FILE="/tmp/${TEST_ID}_resp_body_${CASE_SUFFIX}.json"

cleanup_files() {
  rm -f "$REQ_HEADERS_FILE" "$REQ_BODY_FILE" "$RESP_HEADERS_FILE" "$RESP_BODY_FILE"
}
trap cleanup_files EXIT

cat > "$REQ_BODY_FILE" <<EOF
{
  "config": {
    "blocks": [
      {"id": "block-1-${CASE_SUFFIX}", "type": "input"}
    ]
  }
}
EOF

# Given
echo "STEP: Given — prepare request missing required name"
echo "PREREQ: building a payload that omits the name field"

# When
echo "STEP: When — submit save flow request without name"
echo "REQUEST_HEADERS:"
printf 'Content-Type: application/json\n' > "$REQ_HEADERS_FILE"
cat "$REQ_HEADERS_FILE"
echo "REQUEST_BODY:"
cat "$REQ_BODY_FILE"
status="$(curl -sS -D "$RESP_HEADERS_FILE" -o "$RESP_BODY_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/api/agent-flows/save" \
  -H 'Content-Type: application/json' \
  --data @"$REQ_BODY_FILE")"
echo "RESPONSE_HEADERS:"
cat "$RESP_HEADERS_FILE"
echo "RESPONSE_BODY:"
cat "$RESP_BODY_FILE"
echo "RESPONSE_STATUS: $status"

# Then
echo "STEP: Then — verify validation rejects missing name"
[ "$status" = "400" ] || { echo "ASSERTION_FAILED: expected HTTP 400 got ${status}"; exit 1; }
grep -F '"success":false' "$RESP_BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected success false in response body"; exit 1; }
grep -F 'Name and config are required' "$RESP_BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected validation error message for missing name"; exit 1; }

# Cleanup
echo "STEP: Cleanup — no cleanup required for stateless validation request"

echo "CODEVALID_TEST_ASSERTION_OK:validation_missing_name"
