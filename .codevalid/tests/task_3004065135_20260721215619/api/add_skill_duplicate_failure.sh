#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="add_skill_duplicate_failure"
ITEM_ID="email_automation_${CASE_SUFFIX}"
GIVEN_HEADERS_FILE="/tmp/${TEST_ID}_given_headers_${CASE_SUFFIX}.txt"
GIVEN_BODY_FILE="/tmp/${TEST_ID}_given_body_${CASE_SUFFIX}.txt"
HEADERS_FILE="/tmp/${TEST_ID}_headers_${CASE_SUFFIX}.txt"
BODY_FILE="/tmp/${TEST_ID}_body_${CASE_SUFFIX}.txt"
REQUEST_BODY_FILE="/tmp/${TEST_ID}_request_${CASE_SUFFIX}.json"

cleanup_files() {
  rm -f "$GIVEN_HEADERS_FILE" "$GIVEN_BODY_FILE" "$HEADERS_FILE" "$BODY_FILE" "$REQUEST_BODY_FILE"
}
trap cleanup_files EXIT

cat > "$REQUEST_BODY_FILE" <<EOF
{"skillName":"${ITEM_ID}"}
EOF

# Given — bring the system to the required state
echo "STEP: Given — create an initial whitelist entry so the next add is a duplicate"
echo "PREREQ: creating prerequisite skillName ${ITEM_ID}"
echo "REQUEST_HEADERS: Content-Type: application/json"
echo "REQUEST_BODY:"
cat "$REQUEST_BODY_FILE"
given_code=$(curl -sS -D "$GIVEN_HEADERS_FILE" -o "$GIVEN_BODY_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/api/agent-skills/whitelist/add" \
  -H 'Content-Type: application/json' \
  --data-binary @"$REQUEST_BODY_FILE")
echo "RESPONSE_HEADERS:"
cat "$GIVEN_HEADERS_FILE"
echo "RESPONSE_BODY:"
cat "$GIVEN_BODY_FILE"
echo "RESPONSE_STATUS: $given_code"
[ "$given_code" = "200" ] || { echo "ASSERTION_FAILED: expected prerequisite HTTP 200 got ${given_code}"; exit 1; }
grep -F '"success":true' "$GIVEN_BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected prerequisite response body to contain success true"; exit 1; }

# When — perform the action under test
echo "STEP: When — POST add duplicate skillName"
echo "REQUEST_HEADERS: Content-Type: application/json"
echo "REQUEST_BODY:"
cat "$REQUEST_BODY_FILE"
code=$(curl -sS -D "$HEADERS_FILE" -o "$BODY_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/api/agent-skills/whitelist/add" \
  -H 'Content-Type: application/json' \
  --data-binary @"$REQUEST_BODY_FILE")
echo "RESPONSE_HEADERS:"
cat "$HEADERS_FILE"
echo "RESPONSE_BODY:"
cat "$BODY_FILE"
echo "RESPONSE_STATUS: $code"

# Then — HTTP/body assertions
echo "STEP: Then — duplicate add fails"
[ "$code" = "400" ] || { echo "ASSERTION_FAILED: expected HTTP 400 got ${code}"; exit 1; }
grep -F '"success":false' "$BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected response body to contain success false"; exit 1; }

# Cleanup — undo Given side effects
echo "STEP: Cleanup — no public delete endpoint exists for whitelist entries"
echo "PREREQ: cleanup omitted because available public API surface only exposes add and the test used unique skillName ${ITEM_ID}"

echo "CODEVALID_TEST_ASSERTION_OK:add_skill_duplicate_failure"
