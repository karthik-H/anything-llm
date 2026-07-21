#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="add_skill_null_skillname_validation"
HEADERS_FILE="/tmp/${TEST_ID}_headers_${CASE_SUFFIX}.txt"
BODY_FILE="/tmp/${TEST_ID}_body_${CASE_SUFFIX}.txt"
REQUEST_BODY_FILE="/tmp/${TEST_ID}_request_${CASE_SUFFIX}.json"

cleanup_files() {
  rm -f "$HEADERS_FILE" "$BODY_FILE" "$REQUEST_BODY_FILE"
}
trap cleanup_files EXIT

cat > "$REQUEST_BODY_FILE" <<EOF
{"skillName":null}
EOF

echo "STEP: Given — caller context assumed and null skillName request prepared"
echo "PREREQ: this test assumes the environment provides a valid authenticated session if the app requires one"

echo "STEP: When — POST /agent-skills/whitelist/add with skillName null"
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

echo "STEP: Then — validation error is returned for null skillName"
[ "$code" = "400" ] || { echo "ASSERTION_FAILED: expected HTTP 400 got ${code}"; exit 1; }
grep -F '"success":false' "$BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected response body to contain \"success\":false"; exit 1; }
grep -F 'Missing skillName' "$BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected response body to contain Missing skillName"; exit 1; }

echo "STEP: Cleanup — stateless validation case"
echo "PREREQ: no cleanup required because request should not create data"

echo "CODEVALID_TEST_ASSERTION_OK:add_skill_null_skillname_validation"
