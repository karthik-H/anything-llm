#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="add_skill_to_whitelist_success"
SKILL_NAME="web-browsing-${CASE_SUFFIX}"
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

echo "STEP: Given — authenticated caller context assumed and unique skill prepared"
echo "PREREQ: this test assumes the environment provides a valid authenticated session accepted by the app"
echo "PREREQ: using unique skillName ${SKILL_NAME} to avoid collisions"

echo "STEP: When — POST /agent-skills/whitelist/add with a valid skill name"
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

echo "STEP: Then — response indicates whitelist add succeeded"
[ "$code" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 got ${code}"; exit 1; }
grep -F '"success":true' "$BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected response body to contain \"success\":true"; exit 1; }

echo "STEP: Cleanup — no public cleanup endpoint available for whitelist entries"
echo "PREREQ: cleanup omitted because no public DELETE whitelist endpoint was provided in call graph"

echo "CODEVALID_TEST_ASSERTION_OK:add_skill_to_whitelist_success"
