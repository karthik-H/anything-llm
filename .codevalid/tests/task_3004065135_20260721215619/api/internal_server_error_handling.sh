#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="internal_server_error_handling"
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
  "name": "Error Triggering Agent ${CASE_SUFFIX}",
  "config": {
    "blocks": []
  }
}
EOF

# Given
echo "STEP: Given — prepare request for injected internal error scenario"
echo "PREREQ: this test expects the environment to honor X-Codevalid-Force-Error for fault injection if supported"

# When
echo "STEP: When — submit save flow request while requesting an injected internal error"
echo "REQUEST_HEADERS:"
printf 'Content-Type: application/json\nX-Codevalid-Force-Error: true\n' > "$REQ_HEADERS_FILE"
cat "$REQ_HEADERS_FILE"
echo "REQUEST_BODY:"
cat "$REQ_BODY_FILE"
status="$(curl -sS -D "$RESP_HEADERS_FILE" -o "$RESP_BODY_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/api/agent-flows/save" \
  -H 'Content-Type: application/json' \
  -H 'X-Codevalid-Force-Error: true' \
  --data @"$REQ_BODY_FILE")"
echo "RESPONSE_HEADERS:"
cat "$RESP_HEADERS_FILE"
echo "RESPONSE_BODY:"
cat "$RESP_BODY_FILE"
echo "RESPONSE_STATUS: $status"

# Then
echo "STEP: Then — verify unexpected exception is surfaced as HTTP 500"
[ "$status" = "500" ] || { echo "ASSERTION_FAILED: expected HTTP 500 got ${status}"; exit 1; }
grep -F '"success":false' "$RESP_BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected success false in 500 response body"; exit 1; }
grep -F '"error"' "$RESP_BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected error field in 500 response body"; exit 1; }

# Cleanup
echo "STEP: Cleanup — no cleanup required because failed request must not persist data"

echo "CODEVALID_TEST_ASSERTION_OK:internal_server_error_handling"
