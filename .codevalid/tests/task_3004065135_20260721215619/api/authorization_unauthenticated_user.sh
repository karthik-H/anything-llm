#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="authorization_unauthenticated_user"
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
  "name": "Unauthenticated Agent ${CASE_SUFFIX}",
  "config": {
    "blocks": []
  }
}
EOF

# Given
echo "STEP: Given — prepare unauthenticated save request"
echo "PREREQ: sending no authentication headers or session cookies"

# When
echo "STEP: When — submit save flow request without authentication"
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
echo "STEP: Then — verify unauthenticated access is denied"
[ "$status" = "401" ] || [ "$status" = "403" ] || { echo "ASSERTION_FAILED: expected HTTP 401 or 403 got ${status}"; exit 1; }

# Cleanup
echo "STEP: Cleanup — no cleanup required because unauthenticated request must not create data"

echo "CODEVALID_TEST_ASSERTION_OK:authorization_unauthenticated_user"
