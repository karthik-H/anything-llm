#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
SKILL_NAME="file-reader-${CASE_SUFFIX}"
TMP_DIR="$(mktemp -d)"
REQUEST_BODY_FILE="$TMP_DIR/request_body.json"
RESPONSE_HEADERS="$TMP_DIR/response_headers.txt"
RESPONSE_BODY="$TMP_DIR/response_body.txt"

cleanup_tmp() {
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

# Given
echo "STEP: Given — prepare unauthenticated request in multi-user mode"
echo "PREREQ: this assertion requires the server to be running in multi-user mode"
cat > "$REQUEST_BODY_FILE" <<EOF
{"skillName":"${SKILL_NAME}"}
EOF

# When
echo "STEP: When — POST /agent-skills/whitelist/add without session cookie"
echo "REQUEST_HEADERS: Content-Type: application/json"
echo "REQUEST_HEADERS: Accept: application/json"
echo "REQUEST_BODY:"
cat "$REQUEST_BODY_FILE"
HTTP_CODE="$(curl -sS -D "$RESPONSE_HEADERS" -o "$RESPONSE_BODY" -w '%{http_code}' \
  -X POST "$BASE_URL/agent-skills/whitelist/add" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  --data @"$REQUEST_BODY_FILE")"
echo "RESPONSE_STATUS: $HTTP_CODE"
echo "RESPONSE_HEADERS:"
cat "$RESPONSE_HEADERS"
echo "RESPONSE_BODY:"
cat "$RESPONSE_BODY"

# Then
echo "STEP: Then — assert the request is rejected as unauthorized in multi-user mode"
[ "$HTTP_CODE" = "401" ] || { echo "ASSERTION_FAILED: expected HTTP 401 got ${HTTP_CODE}"; exit 1; }
grep -q '"success"[[:space:]]*:[[:space:]]*false' "$RESPONSE_BODY" || { echo "ASSERTION_FAILED: expected success false in response body"; exit 1; }
grep -q 'Unauthorized' "$RESPONSE_BODY" || { echo "ASSERTION_FAILED: expected Unauthorized error message"; exit 1; }

# Cleanup
echo "STEP: Cleanup — no cleanup required because unauthorized request is rejected before persistence"

echo "CODEVALID_TEST_ASSERTION_OK:add_skill_unauthorized_multi_user_mode"
