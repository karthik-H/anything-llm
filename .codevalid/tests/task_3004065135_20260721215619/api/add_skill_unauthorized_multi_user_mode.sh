#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="add_skill_unauthorized_multi_user_mode"
SKILL_NAME="code-execution-${CASE_SUFFIX}"
HEADERS_FILE="/tmp/${TEST_ID}_headers_${CASE_SUFFIX}.txt"
BODY_FILE="/tmp/${TEST_ID}_body_${CASE_SUFFIX}.txt"
REQUEST_BODY_FILE="/tmp/${TEST_ID}_request_${CASE_SUFFIX}.json"

cleanup_files() {
  rm -f "$HEADERS_FILE" "$BODY_FILE" "$REQUEST_BODY_FILE"
}
trap cleanup_files EXIT

cat > "$REQUEST_BODY_FILE" <<EOF
{"skillName":"${SKILL_NAME}"}
EOF

echo "STEP: Given — unauthenticated multi-user mode context is required"
echo "PREREQ: this test must run in an environment where no valid user session exists and multi-user mode is enabled"

echo "STEP: When — POST /agent-skills/whitelist/add without authentication in multi-user mode"
echo "REQUEST_HEADERS: Content-Type: application/json"
echo "REQUEST_BODY:"
cat "$REQUEST_BODY_FILE"
code=$(curl -sS -D "$HEADERS_FILE" -o "$BODY_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/agent-skills/whitelist/add" \
  -H 'Content-Type: application/json' \
  --data-binary @"$REQUEST_BODY_FILE")
echo "RESPONSE_HEADERS:"
cat "$HEADERS_FILE"
echo "RESPONSE_BODY:"
cat "$BODY_FILE"
echo "RESPONSE_STATUS: $code"

echo "STEP: Then — unauthorized response is returned"
[ "$code" = "401" ] || { echo "ASSERTION_FAILED: expected HTTP 401 got ${code}"; exit 1; }
grep -F '"success":false' "$BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected response body to contain \"success\":false"; exit 1; }
grep -F 'Unauthorized' "$BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected response body to contain Unauthorized"; exit 1; }

echo "STEP: Cleanup — stateless authorization case"
echo "PREREQ: no cleanup required because unauthorized request should not create data"

echo "CODEVALID_TEST_ASSERTION_OK:add_skill_unauthorized_multi_user_mode"
