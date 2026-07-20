#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CLIENT_ID="masked-client"
MASKED_SECRET="********"
TMP_DIR="$(mktemp -d)"
REQUEST_BODY_FILE="$TMP_DIR/request_body.json"
RESPONSE_HEADERS="$TMP_DIR/response_headers.txt"
RESPONSE_BODY="$TMP_DIR/response_body.txt"

cleanup_tmp() {
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

# Given
echo "STEP: Given — prepare request with masked clientSecret"
echo "PREREQ: this admin endpoint requires single-user-mode auth/session state"
echo "PREREQ: this scenario assumes an existing Outlook config already contains the real secret"
SESSION_COOKIE_HEADER="${SESSION_COOKIE_HEADER:-}"
if [ -z "$SESSION_COOKIE_HEADER" ]; then
  echo "ASSERTION_FAILED: set SESSION_COOKIE_HEADER with a valid session cookie header, e.g. 'Cookie: session=...'"
  exit 1
fi
cat > "$REQUEST_BODY_FILE" <<EOF
{"clientId":"${CLIENT_ID}","clientSecret":"${MASKED_SECRET}","authType":"common"}
EOF

echo "PREREQ: request body prepared with asterisk-masked clientSecret"
echo "REQUEST_HEADERS: Content-Type: application/json"
echo "REQUEST_HEADERS: Accept: application/json"
echo "REQUEST_HEADERS: ${SESSION_COOKIE_HEADER}"
echo "REQUEST_BODY:"
cat "$REQUEST_BODY_FILE"

# When
echo "STEP: When — POST /admin/agent-skills/outlook/auth-url with masked secret"
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
echo "STEP: Then — assert masked secret request succeeds without exposing the secret"
[ "$HTTP_CODE" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 got ${HTTP_CODE}"; exit 1; }
grep -q '"success"[[:space:]]*:[[:space:]]*true' "$RESPONSE_BODY" || { echo "ASSERTION_FAILED: expected success true in response body"; exit 1; }
grep -F "$MASKED_SECRET" "$RESPONSE_BODY" >/dev/null 2>&1 && { echo "ASSERTION_FAILED: response body should not echo masked clientSecret"; exit 1; }
echo "PREREQ: persisted-secret preservation is an internal side effect not directly verifiable via inspected public API; success response confirms masked input was accepted"

# Cleanup
echo "STEP: Cleanup — no public cleanup API is exposed for persisted Outlook config"
echo "PREREQ: cleanup is intentionally omitted because the inspected public API surface here exposes auth-url generation but no config reset/delete endpoint"

echo "CODEVALID_TEST_ASSERTION_OK:client_secret_masking_asterisks"
