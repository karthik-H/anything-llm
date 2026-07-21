#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="add_skill_duplicate_handling"
SKILL_NAME="file-operations-${CASE_SUFFIX}"
HEADERS1_FILE="/tmp/${TEST_ID}_first_headers_${CASE_SUFFIX}.txt"
BODY1_FILE="/tmp/${TEST_ID}_first_body_${CASE_SUFFIX}.txt"
HEADERS2_FILE="/tmp/${TEST_ID}_second_headers_${CASE_SUFFIX}.txt"
BODY2_FILE="/tmp/${TEST_ID}_second_body_${CASE_SUFFIX}.txt"
REQUEST_BODY_FILE="/tmp/${TEST_ID}_request_${CASE_SUFFIX}.json"

cleanup_files() {
  rm -f "$HEADERS1_FILE" "$BODY1_FILE" "$HEADERS2_FILE" "$BODY2_FILE" "$REQUEST_BODY_FILE"
}
trap cleanup_files EXIT

cat > "$REQUEST_BODY_FILE" <<EOF
{"skillName":"${SKILL_NAME}"}
EOF

echo "STEP: Given — authenticated caller context assumed and initial skill creation performed"
echo "PREREQ: this test assumes the environment provides a valid authenticated session accepted by the app"
echo "REQUEST_HEADERS: Content-Type: application/json"
echo "REQUEST_BODY:"
cat "$REQUEST_BODY_FILE"
code1=$(curl -sS -D "$HEADERS1_FILE" -o "$BODY1_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/agent-skills/whitelist/add" \
  -H 'Content-Type: application/json' \
  --data-binary @"$REQUEST_BODY_FILE")
echo "RESPONSE_HEADERS:"
cat "$HEADERS1_FILE"
echo "RESPONSE_BODY:"
cat "$BODY1_FILE"
echo "RESPONSE_STATUS: $code1"
[ "$code1" = "200" ] || { echo "ASSERTION_FAILED: expected prereq create HTTP 200 got ${code1}"; exit 1; }
grep -F '"success":true' "$BODY1_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected prereq create response body to contain \"success\":true"; exit 1; }

echo "STEP: When — POST /agent-skills/whitelist/add again with the same skill name"
echo "REQUEST_HEADERS: Content-Type: application/json"
echo "REQUEST_BODY:"
cat "$REQUEST_BODY_FILE"
code2=$(curl -sS -D "$HEADERS2_FILE" -o "$BODY2_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/agent-skills/whitelist/add" \
  -H 'Content-Type: application/json' \
  --data-binary @"$REQUEST_BODY_FILE")
echo "RESPONSE_HEADERS:"
cat "$HEADERS2_FILE"
echo "RESPONSE_BODY:"
cat "$BODY2_FILE"
echo "RESPONSE_STATUS: $code2"

echo "STEP: Then — duplicate add fails"
[ "$code2" = "400" ] || { echo "ASSERTION_FAILED: expected HTTP 400 got ${code2}"; exit 1; }
grep -F '"success":false' "$BODY2_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected response body to contain \"success\":false"; exit 1; }
grep -F 'error' "$BODY2_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected duplicate failure body to contain error"; exit 1; }

echo "STEP: Cleanup — no public cleanup endpoint available for whitelist entries"
echo "PREREQ: cleanup omitted because no public DELETE whitelist endpoint was provided in call graph"

echo "CODEVALID_TEST_ASSERTION_OK:add_skill_duplicate_handling"
