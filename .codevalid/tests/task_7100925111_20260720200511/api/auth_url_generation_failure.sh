#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
CLIENT_ID="valid-client-123-${CASE_SUFFIX}"
CLIENT_SECRET="valid-secret-123-${CASE_SUFFIX}"
TMP_DIR="$(mktemp -d)"
REQUEST_BODY_FILE="$TMP_DIR/request_body.json"
RESPONSE_HEADERS="$TMP_DIR/response_headers.txt"
RESPONSE_BODY="$TMP_DIR/response_body.txt"

cleanup_tmp() {
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

# Given
echo "STEP: Given — prepare valid request and require repo-specific seam that forces auth URL generation failure"
echo "PREREQ: this admin endpoint requires single-user-mode auth/session state"
SESSION_COOKIE_HEADER="${SESSION_COOKIE_HEADER:-}"
if [ -z "$SESSION_COOKIE_HEADER" ]; then
  echo "ASSERTION_FAILED: set SESSION_COOKIE_HEADER with a valid session cookie header, e.g. 'Cookie: session=...'"
  exit 1
fi
OUTLOOK_AUTH_URL_FAILURE_HEADER="${OUTLOOK_AUTH_URL_FAILURE_HEADER:-}"
if [ -z "$OUTLOOK_AUTH_URL_FAILURE_HEADER" ]; then
  echo "ASSERTION_FAILED: set OUTLOOK_AUTH_URL_FAILURE_HEADER to a repo-specific header that makes getAuthUrl return { success: false, error: ... } for this test"
  exit 1
fi
cat > "$REQUEST_BODY_FILE" <<EOF
{"clientId":"${CLIENT_ID}","clientSecret":"${CLIENT_SECRET}","authType":"common"}
EOF

echo "PREREQ: request body prepared for downstream getAuthUrl failure path"
echo "REQUEST_HEADERS: Content-Type: application/json"
echo "REQUEST_HEADERS: Accept: application/json"
echo "REQUEST_HEADERS: ${SESSION_COOKIE_HEADER}"
echo "REQUEST_HEADERS: ${OUTLOOK_AUTH_URL_FAILURE_HEADER}"
echo "REQUEST_BODY:"
cat "$REQUEST_BODY_FILE"

# When
echo "STEP: When — POST /admin/agent-skills/outlook/auth-url while forcing auth URL generation failure"
HTTP_CODE="$(curl -sS -D "$RESPONSE_HEADERS" -o "$RESPONSE_BODY" -w '%{http_code}' \
  -X POST "$BASE_URL/admin/agent-skills/outlook/auth-url" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H "$SESSION_COOKIE_HEADER" \
  -H "$OUTLOOK_AUTH_URL_FAILURE_HEADER" \
  --data @"$REQUEST_BODY_FILE")"
echo "RESPONSE_STATUS: $HTTP_CODE"
echo "RESPONSE_HEADERS:"
cat "$RESPONSE_HEADERS"
echo "RESPONSE_BODY:"
cat "$RESPONSE_BODY"

# Then
echo "STEP: Then — assert endpoint surfaces auth URL generation failure"
[ "$HTTP_CODE" = "400" ] || { echo "ASSERTION_FAILED: expected HTTP 400 got ${HTTP_CODE}"; exit 1; }
grep -q '"success"[[:space:]]*:[[:space:]]*false' "$RESPONSE_BODY" || { echo "ASSERTION_FAILED: expected success false in response body"; exit 1; }
EXPECTED_ERROR_SUBSTRING="${EXPECTED_ERROR_SUBSTRING:-error}"
grep -F "$EXPECTED_ERROR_SUBSTRING" "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected failure response body to contain substring ${EXPECTED_ERROR_SUBSTRING}"; exit 1; }

# Cleanup
echo "STEP: Cleanup — no public cleanup API is exposed for persisted Outlook config"
echo "PREREQ: cleanup is intentionally omitted because the inspected public API surface here exposes auth-url generation but no config reset/delete endpoint"

echo "CODEVALID_TEST_ASSERTION_OK:auth_url_generation_failure"
