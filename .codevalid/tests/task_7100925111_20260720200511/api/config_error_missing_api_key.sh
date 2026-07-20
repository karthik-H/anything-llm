#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
TMP_DIR="$(mktemp -d)"
REQUEST_BODY_FILE="$TMP_DIR/request_body.json"
RESPONSE_HEADERS="$TMP_DIR/response_headers.txt"
RESPONSE_BODY="$TMP_DIR/response_body.txt"

cleanup_tmp() {
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

# Given
echo "STEP: Given — require app runtime with OPENAI_API_KEY and OPENAI_BASE_URL both unset"
echo "PREREQ: this scenario depends on process configuration and must be run against an app instance started without OpenAI credentials or base URL"
cat > "$REQUEST_BODY_FILE" <<'EOF'
{"prompt":"Test prompt"}
EOF

# When
echo "STEP: When — POST /api/v1/prompt with a valid prompt while config is missing"
echo "REQUEST_HEADERS: Content-Type: application/json"
echo "REQUEST_BODY:"
cat "$REQUEST_BODY_FILE"
HTTP_CODE="$(curl -sS -D "$RESPONSE_HEADERS" -o "$RESPONSE_BODY" -w '%{http_code}' \
  -X POST "$BASE_URL/api/v1/prompt" \
  -H 'Content-Type: application/json' \
  --data @"$REQUEST_BODY_FILE")"
echo "RESPONSE_STATUS: $HTTP_CODE"
echo "RESPONSE_HEADERS:"
cat "$RESPONSE_HEADERS"
echo "RESPONSE_BODY:"
cat "$RESPONSE_BODY"

# Then
echo "STEP: Then — assert HTTP 500 and configuration guidance"
[ "$HTTP_CODE" = "500" ] || { echo "ASSERTION_FAILED: expected HTTP 500 got ${HTTP_CODE}"; exit 1; }
grep -F 'OPENAI_API_KEY not configured' "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected OPENAI_API_KEY not configured message in response body"; exit 1; }
grep -F 'POST /api/v1/config with api_key' "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected api_key setup guidance in response body"; exit 1; }

# Cleanup
echo "STEP: Cleanup — no cleanup required"

echo "CODEVALID_TEST_ASSERTION_OK:config_error_missing_api_key"
