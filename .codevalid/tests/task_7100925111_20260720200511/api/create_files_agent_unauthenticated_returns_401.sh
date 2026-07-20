#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TMP_DIR="$(mktemp -d)"
RESPONSE_HEADERS="$TMP_DIR/response_headers.txt"
RESPONSE_BODY="$TMP_DIR/response_body.txt"

cleanup_tmp() {
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

# Given
echo "STEP: Given — verify unauthenticated request precondition"
echo "PREREQ: this scenario requires no valid authenticated session so validatedRequest rejects the request before handler execution"

# When
echo "STEP: When — GET /agent-skills/create-files-agent/is-available without authentication"
echo "REQUEST_HEADERS: Accept: application/json"
HTTP_CODE="$(curl -sS -D "$RESPONSE_HEADERS" -o "$RESPONSE_BODY" -w '%{http_code}' \
  -X GET "$BASE_URL/agent-skills/create-files-agent/is-available" \
  -H 'Accept: application/json')"
echo "RESPONSE_STATUS: $HTTP_CODE"
echo "RESPONSE_HEADERS:"
cat "$RESPONSE_HEADERS"
echo "RESPONSE_BODY:"
cat "$RESPONSE_BODY"

# Then
echo "STEP: Then — assert request is rejected by authentication middleware"
if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
  :
else
  echo "ASSERTION_FAILED: expected HTTP 401 or 403 got ${HTTP_CODE}"
  exit 1
fi

# Cleanup
echo "STEP: Cleanup — no public cleanup available for rejected unauthenticated request"

echo "CODEVALID_TEST_ASSERTION_OK:create_files_agent_unauthenticated_returns_401"
