#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="add_skill_internal_error"
SKILL_NAME="api-calls-${CASE_SUFFIX}"
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

echo "STEP: Given — internal failure must be induced externally before request"
echo "PREREQ: this test requires the environment to force AgentSkillWhitelist.add or its database dependency to fail before invocation"

echo "STEP: When — POST /agent-skills/whitelist/add while internal dependency is failing"
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

echo "STEP: Then — internal server error is returned"
[ "$code" = "500" ] || { echo "ASSERTION_FAILED: expected HTTP 500 got ${code}"; exit 1; }
grep -F '"success":false' "$BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected response body to contain \"success\":false"; exit 1; }
grep -F 'error' "$BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected response body to contain error"; exit 1; }

echo "STEP: Cleanup — best effort only because prerequisite failure should prevent persistence"
echo "PREREQ: no cleanup required because failing request should not create data"

echo "CODEVALID_TEST_ASSERTION_OK:add_skill_internal_error"
