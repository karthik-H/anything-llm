#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
TMP_DIR="$(mktemp -d)"
REQUEST_BODY_FILE="$TMP_DIR/request_body.json"
RESPONSE_HEADERS_ONE="$TMP_DIR/response_headers_one.txt"
RESPONSE_BODY_ONE="$TMP_DIR/response_body_one.txt"
RESPONSE_HEADERS_TWO="$TMP_DIR/response_headers_two.txt"
RESPONSE_BODY_TWO="$TMP_DIR/response_body_two.txt"

cleanup_tmp() {
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

# Given
echo "STEP: Given — prepare duplicate whitelist add request"
echo "PREREQ: this scenario assumes the backend returns a business-level failure when the same skill is added twice for the same authenticated user"
SESSION_COOKIE_HEADER="${SESSION_COOKIE_HEADER:-}"
if [ -z "$SESSION_COOKIE_HEADER" ]; then
  echo "ASSERTION_FAILED: set SESSION_COOKIE_HEADER with a valid session cookie header for a user whose duplicate add behavior you want to verify"
  exit 1
fi
DUPLICATE_SKILL_NAME="${DUPLICATE_SKILL_NAME:-duplicate-skill}"
cat > "$REQUEST_BODY_FILE" <<EOF
{"skillName":"${DUPLICATE_SKILL_NAME}"}
EOF

echo "PREREQ: issuing first request to establish the duplicate condition"
echo "REQUEST_HEADERS: Content-Type: application/json"
echo "REQUEST_HEADERS: Accept: application/json"
echo "REQUEST_HEADERS: ${SESSION_COOKIE_HEADER}"
echo "REQUEST_BODY:"
cat "$REQUEST_BODY_FILE"
FIRST_HTTP_CODE="$(curl -sS -D "$RESPONSE_HEADERS_ONE" -o "$RESPONSE_BODY_ONE" -w '%{http_code}' \
  -X POST "$BASE_URL/agent-skills/whitelist/add" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H "$SESSION_COOKIE_HEADER" \
  --data @"$REQUEST_BODY_FILE")"
echo "RESPONSE_STATUS: $FIRST_HTTP_CODE"
echo "RESPONSE_HEADERS:"
cat "$RESPONSE_HEADERS_ONE"
echo "RESPONSE_BODY:"
cat "$RESPONSE_BODY_ONE"
if [ "$FIRST_HTTP_CODE" = "200" ] || [ "$FIRST_HTTP_CODE" = "400" ]; then
  :
else
  echo "ASSERTION_FAILED: expected first setup request to return 200 or 400 got ${FIRST_HTTP_CODE}"
  exit 1
fi

# When
echo "STEP: When — POST /agent-skills/whitelist/add again with the same skillName"
echo "REQUEST_HEADERS: Content-Type: application/json"
echo "REQUEST_HEADERS: Accept: application/json"
echo "REQUEST_HEADERS: ${SESSION_COOKIE_HEADER}"
echo "REQUEST_BODY:"
cat "$REQUEST_BODY_FILE"
HTTP_CODE="$(curl -sS -D "$RESPONSE_HEADERS_TWO" -o "$RESPONSE_BODY_TWO" -w '%{http_code}' \
  -X POST "$BASE_URL/agent-skills/whitelist/add" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H "$SESSION_COOKIE_HEADER" \
  --data @"$REQUEST_BODY_FILE")"
echo "RESPONSE_STATUS: $HTTP_CODE"
echo "RESPONSE_HEADERS:"
cat "$RESPONSE_HEADERS_TWO"
echo "RESPONSE_BODY:"
cat "$RESPONSE_BODY_TWO"

# Then
echo "STEP: Then — assert the duplicate add returns a business failure response"
[ "$HTTP_CODE" = "400" ] || { echo "ASSERTION_FAILED: expected HTTP 400 got ${HTTP_CODE}"; exit 1; }
grep -q '"success"[[:space:]]*:[[:space:]]*false' "$RESPONSE_BODY_TWO" || { echo "ASSERTION_FAILED: expected success false in duplicate-add response body"; exit 1; }

# Cleanup
echo "STEP: Cleanup — no public cleanup API is exposed for whitelist entries"
echo "PREREQ: cleanup omitted because only add behavior is exposed in the inspected public API surface"

echo "CODEVALID_TEST_ASSERTION_OK:add_skill_operation_failure"
