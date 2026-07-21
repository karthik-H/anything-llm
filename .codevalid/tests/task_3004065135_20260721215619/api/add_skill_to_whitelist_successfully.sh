#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="add_skill_to_whitelist_successfully"
ITEM_ID="web_browsing_${CASE_SUFFIX}"
HEADERS_FILE="/tmp/${TEST_ID}_headers_${CASE_SUFFIX}.txt"
BODY_FILE="/tmp/${TEST_ID}_body_${CASE_SUFFIX}.txt"
REQUEST_BODY_FILE="/tmp/${TEST_ID}_request_${CASE_SUFFIX}.json"

cleanup_files() {
  rm -f "$HEADERS_FILE" "$BODY_FILE" "$REQUEST_BODY_FILE"
}
trap cleanup_files EXIT

cat > "$REQUEST_BODY_FILE" <<EOF
{"skillName":"${ITEM_ID}"}
EOF

# Given — bring the system to the required state
echo "STEP: Given — prepare a unique skillName for a self-contained whitelist add request"
echo "PREREQ: using unique skillName ${ITEM_ID} so the test does not depend on pre-existing rows"
echo "PREREQ: this test assumes the environment provides a valid authenticated session or single-user access"

# When — perform the action under test
echo "STEP: When — POST add skill to whitelist"
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
echo "STEP: Then — success response is returned"
[ "$code" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 got ${code}"; exit 1; }
grep -F '"success":true' "$BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected response body to contain success true"; exit 1; }

# Cleanup — undo Given side effects
echo "STEP: Cleanup — no public delete endpoint exists for whitelist entries"
echo "PREREQ: cleanup omitted because available public API surface only exposes add and the test used unique skillName ${ITEM_ID}"

echo "CODEVALID_TEST_ASSERTION_OK:add_skill_to_whitelist_successfully"
