#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="authorization_non_admin_user"
REQ_HEADERS_FILE="/tmp/${TEST_ID}_req_headers_${CASE_SUFFIX}.txt"
REQ_BODY_FILE="/tmp/${TEST_ID}_req_body_${CASE_SUFFIX}.json"
RESP_HEADERS_FILE="/tmp/${TEST_ID}_resp_headers_${CASE_SUFFIX}.txt"
RESP_BODY_FILE="/tmp/${TEST_ID}_resp_body_${CASE_SUFFIX}.json"
AUTH_HEADER_VALUE="${CURL_AUTH_HEADER:-X-Test-Role: member}"
AUTH_HEADER_NAME="${AUTH_HEADER_VALUE%%:*}"
AUTH_HEADER_BODY="${AUTH_HEADER_VALUE#*: }"

cleanup_files() {
  rm -f "$REQ_HEADERS_FILE" "$REQ_BODY_FILE" "$RESP_HEADERS_FILE" "$RESP_BODY_FILE"
}
trap cleanup_files EXIT

cat > "$REQ_BODY_FILE" <<EOF
{
  "name": "Unauthorized Agent ${CASE_SUFFIX}",
  "config": {
    "blocks": []
  }
}
EOF

# Given
echo "STEP: Given — prepare non-admin save request"
echo "PREREQ: using a member-role header override via CURL_AUTH_HEADER or the default X-Test-Role: member"
[ -n "$AUTH_HEADER_NAME" ] || { echo "ASSERTION_FAILED: expected non-empty authorization header name"; exit 1; }
[ -n "$AUTH_HEADER_BODY" ] || { echo "ASSERTION_FAILED: expected non-empty authorization header value"; exit 1; }

# When
echo "STEP: When — submit save flow request as non-admin user"
echo "REQUEST_HEADERS:"
printf 'Content-Type: application/json\n%s: %s\n' "$AUTH_HEADER_NAME" "$AUTH_HEADER_BODY" > "$REQ_HEADERS_FILE"
cat "$REQ_HEADERS_FILE"
echo "REQUEST_BODY:"
cat "$REQ_BODY_FILE"
status="$(curl -sS -D "$RESP_HEADERS_FILE" -o "$RESP_BODY_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/api/agent-flows/save" \
  -H 'Content-Type: application/json' \
  -H "${AUTH_HEADER_NAME}: ${AUTH_HEADER_BODY}" \
  --data @"$REQ_BODY_FILE")"
echo "RESPONSE_HEADERS:"
cat "$RESP_HEADERS_FILE"
echo "RESPONSE_BODY:"
cat "$RESP_BODY_FILE"
echo "RESPONSE_STATUS: $status"

# Then
echo "STEP: Then — verify non-admin access is denied"
[ "$status" = "401" ] || [ "$status" = "403" ] || { echo "ASSERTION_FAILED: expected HTTP 401 or 403 got ${status}"; exit 1; }

# Cleanup
echo "STEP: Cleanup — no cleanup required because unauthorized request must not create data"

echo "CODEVALID_TEST_ASSERTION_OK:authorization_non_admin_user"
