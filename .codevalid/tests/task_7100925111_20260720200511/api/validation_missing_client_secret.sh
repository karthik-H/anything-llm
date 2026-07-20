#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
CLIENT_ID="client-no-secret-${CASE_SUFFIX}"
TMP_DIR="$(mktemp -d)"
REQUEST_BODY_FILE="$TMP_DIR/request_body.json"
RESPONSE_HEADERS="$TMP_DIR/response_headers.txt"
RESPONSE_BODY="$TMP_DIR/response_body.txt"

cleanup_tmp() {
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

# Given
echo "STEP: Given — prepare request missing clientSecret"
echo "PREREQ: this admin endpoint requires single-user-mode auth/session state"
SESSION_COOKIE_HEADER="${SESSION_COOKIE_HEADER:-}"
if [ -z "$SESSION_COOKIE_HEADER" ]; then
  echo "ASSERTION_FAILED: set SESSION_COOKIE_HEADER with a valid session cookie header, e.g. 'Cookie: session=...'"
  exit 1
fi
cat > "$REQUEST_BODY_FILE" <<EOF
{"clientId":"${CLIENT_ID}","authType":"common"}
EOF

echo "PREREQ: invalid request body prepared without clientSecret"
echo "REQUEST_HEADERS: Content-Type: application/json"
echo "REQUEST_HEADERS: Accept: application/json"
echo "REQUEST_HEADERS: ${SESSION_COOKIE_HEADER}"
echo "REQUEST_BODY:"
cat "$REQUEST_BODY_FILE"

# When
echo "STEP: When — POST /admin/agent-skills/outlook/auth-url without clientSecret"
HTTP_CODE="$(curl -sS -D "$RESPONSE_HEADERS" -o "$RESPONSE_BODY" -w '%{http_code}' \
  -X POST "$BASE_URL/admin/agent-skills/outlook/auth-url" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H "$SESSION_COOKIE_HEADER" \
  --data @"$REQUEST_BODY_FILE")"
echo "RESPONSE_STATUS: $HTTP_CODE"
echo "RESPONSE_HEADERS:"
cat "$RESPONSE_HEADERS"
echo "RESPONSE_BODY:"
cat "$RESPONSE_BODY"

# Then
echo "STEP: Then — assert validation error for missing clientSecret"
[ "$HTTP_CODE" = "400" ] || { echo "ASSERTION_FAILED: expected HTTP 400 got ${HTTP_CODE}"; exit 1; }
grep -q '"success"[[:space:]]*:[[:space:]]*false' "$RESPONSE_BODY" || { echo "ASSERTION_FAILED: expected success false in response body"; exit 1; }
grep -F 'Client ID and Client Secret are required.' "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected missing client credentials validation error"; exit 1; }

# Cleanup
echo "STEP: Cleanup — no cleanup required for rejected validation request"

echo "CODEVALID_TEST_ASSERTION_OK:validation_missing_client_secret"
