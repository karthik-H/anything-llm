#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
SKILL_NAME="data-analysis-${CASE_SUFFIX}"
TMP_DIR="$(mktemp -d)"
REQUEST_BODY_FILE="$TMP_DIR/request_body.json"
RESPONSE_HEADERS="$TMP_DIR/response_headers.txt"
RESPONSE_BODY="$TMP_DIR/response_body.txt"

cleanup_tmp() {
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

# Given
echo "STEP: Given — prepare single-user mode request without authentication"
echo "PREREQ: this scenario requires the server to be configured in single-user mode"
if [ "${EXPECT_SINGLE_USER_MODE:-}" != "true" ]; then
  echo "ASSERTION_FAILED: set EXPECT_SINGLE_USER_MODE=true only when the environment is configured for single-user mode; otherwise this script may correctly return 401 in multi-user mode"
  exit 1
fi
cat > "$REQUEST_BODY_FILE" <<EOF
{"skillName":"${SKILL_NAME}"}
EOF

# When
echo "STEP: When — POST /agent-skills/whitelist/add without session cookie in single-user mode"
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
echo "STEP: Then — assert the request succeeds without authentication in single-user mode"
[ "$HTTP_CODE" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 got ${HTTP_CODE}"; exit 1; }
grep -q '"success"[[:space:]]*:[[:space:]]*true' "$RESPONSE_BODY" || { echo "ASSERTION_FAILED: expected success true in response body"; exit 1; }

# Cleanup
echo "STEP: Cleanup — no public cleanup API is exposed for whitelist entries"
echo "PREREQ: cleanup omitted because no delete endpoint for agent skill whitelist is present in the inspected public API call graph"

echo "CODEVALID_TEST_ASSERTION_OK:add_skill_single_user_mode"
