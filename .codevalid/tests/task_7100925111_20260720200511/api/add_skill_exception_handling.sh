#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
SKILL_NAME="valid-skill-${CASE_SUFFIX}"
TMP_DIR="$(mktemp -d)"
REQUEST_BODY_FILE="$TMP_DIR/request_body.json"
RESPONSE_HEADERS="$TMP_DIR/response_headers.txt"
RESPONSE_BODY="$TMP_DIR/response_body.txt"

cleanup_tmp() {
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

# Given
echo "STEP: Given — prepare request for exception-handling path"
echo "PREREQ: this scenario requires the runtime to be intentionally fault-injected so AgentSkillWhitelist.add throws an exception"
SESSION_COOKIE_HEADER="${SESSION_COOKIE_HEADER:-}"
if [ -z "$SESSION_COOKIE_HEADER" ]; then
  echo "ASSERTION_FAILED: set SESSION_COOKIE_HEADER with a valid session cookie header; authenticated context is required to reach the add path before the forced exception"
  exit 1
fi
if [ "${EXPECT_FORCED_EXCEPTION_MODE:-}" != "true" ]; then
  echo "ASSERTION_FAILED: set EXPECT_FORCED_EXCEPTION_MODE=true only when the environment has been intentionally prepared to make AgentSkillWhitelist.add throw; this repo exposes no public API or declared dependency seam to trigger that fault from the script itself"
  exit 1
fi
cat > "$REQUEST_BODY_FILE" <<EOF
{"skillName":"${SKILL_NAME}"}
EOF

# When
echo "STEP: When — POST /agent-skills/whitelist/add while backend exception mode is active"
echo "REQUEST_HEADERS: Content-Type: application/json"
echo "REQUEST_HEADERS: Accept: application/json"
echo "REQUEST_HEADERS: ${SESSION_COOKIE_HEADER}"
echo "REQUEST_BODY:"
cat "$REQUEST_BODY_FILE"
HTTP_CODE="$(curl -sS -D "$RESPONSE_HEADERS" -o "$RESPONSE_BODY" -w '%{http_code}' \
  -X POST "$BASE_URL/agent-skills/whitelist/add" \
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
echo "STEP: Then — assert the endpoint returns a 500 error payload"
[ "$HTTP_CODE" = "500" ] || { echo "ASSERTION_FAILED: expected HTTP 500 got ${HTTP_CODE}"; exit 1; }
grep -q '"success"[[:space:]]*:[[:space:]]*false' "$RESPONSE_BODY" || { echo "ASSERTION_FAILED: expected success false in response body"; exit 1; }
grep -q '"error"' "$RESPONSE_BODY" || { echo "ASSERTION_FAILED: expected error field in response body"; exit 1; }

# Cleanup
echo "STEP: Cleanup — no script-level cleanup available for internal exception injection mode"
echo "PREREQ: revert any external fault injection used to force the exception outside this script"

echo "CODEVALID_TEST_ASSERTION_OK:add_skill_exception_handling"
