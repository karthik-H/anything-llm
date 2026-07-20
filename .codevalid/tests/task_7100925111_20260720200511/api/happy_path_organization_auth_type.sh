#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
CLIENT_ID="org-client-456-${CASE_SUFFIX}"
CLIENT_SECRET="org-secret-xyz-${CASE_SUFFIX}"
TENANT_ID="tenant-789-org-${CASE_SUFFIX}"
TMP_DIR="$(mktemp -d)"
REQUEST_BODY_FILE="$TMP_DIR/request_body.json"
RESPONSE_HEADERS="$TMP_DIR/response_headers.txt"
RESPONSE_BODY="$TMP_DIR/response_body.txt"

cleanup_tmp() {
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

# Given
echo "STEP: Given — prepare valid organization auth request"
echo "PREREQ: this admin endpoint requires single-user-mode auth/session state"
SESSION_COOKIE_HEADER="${SESSION_COOKIE_HEADER:-}"
if [ -z "$SESSION_COOKIE_HEADER" ]; then
  echo "ASSERTION_FAILED: set SESSION_COOKIE_HEADER with a valid session cookie header, e.g. 'Cookie: session=...'"
  exit 1
fi
cat > "$REQUEST_BODY_FILE" <<EOF
{"clientId":"${CLIENT_ID}","clientSecret":"${CLIENT_SECRET}","authType":"organization","tenantId":"${TENANT_ID}"}
EOF

echo "PREREQ: request body prepared for organization auth type"
echo "REQUEST_HEADERS: Content-Type: application/json"
echo "REQUEST_HEADERS: Accept: application/json"
echo "REQUEST_HEADERS: ${SESSION_COOKIE_HEADER}"
echo "REQUEST_BODY:"
cat "$REQUEST_BODY_FILE"

# When
echo "STEP: When — POST /admin/agent-skills/outlook/auth-url with valid organization configuration"
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
echo "STEP: Then — assert successful organization auth URL generation"
[ "$HTTP_CODE" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 got ${HTTP_CODE}"; exit 1; }
grep -q '"success"[[:space:]]*:[[:space:]]*true' "$RESPONSE_BODY" || { echo "ASSERTION_FAILED: expected success true in response body"; exit 1; }
grep -E 'https?://' "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected response body to contain an auth URL"; exit 1; }
grep -F "$TENANT_ID" "$RESPONSE_BODY" >/dev/null 2>&1 || {
  EXPECTED_ORG_AUTH_HINT="${EXPECTED_ORG_AUTH_HINT:-organization}"
  grep -F "$EXPECTED_ORG_AUTH_HINT" "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected organization-specific authority hint in response body"; exit 1; }
}

# Cleanup
echo "STEP: Cleanup — no public cleanup API is exposed for persisted Outlook config"
echo "PREREQ: cleanup is intentionally omitted because the inspected public API surface here exposes auth-url generation but no config reset/delete endpoint"

echo "CODEVALID_TEST_ASSERTION_OK:happy_path_organization_auth_type"
