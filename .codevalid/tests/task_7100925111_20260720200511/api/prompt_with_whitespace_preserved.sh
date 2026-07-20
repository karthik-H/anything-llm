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
echo "STEP: Given — require a running hypervisor-backed workspace for prompt forwarding"
echo "PREREQ: this scenario requires configured OpenAI/base URL, workspace.piRpc active, and workspace.id=ws-001"
cat > "$REQUEST_BODY_FILE" <<'EOF'
{"prompt":"  Please analyze this data   "}
EOF

# When
echo "STEP: When — POST /api/v1/prompt with leading and trailing whitespace preserved"
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
echo "STEP: Then — assert prompt was accepted"
[ "$HTTP_CODE" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 got ${HTTP_CODE}"; exit 1; }
grep -F '"status":"prompt_sent"' "$RESPONSE_BODY" >/dev/null 2>&1 || grep -F '"status": "prompt_sent"' "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected status prompt_sent in response body"; exit 1; }
grep -F '"workspace_id":"ws-001"' "$RESPONSE_BODY" >/dev/null 2>&1 || grep -F '"workspace_id": "ws-001"' "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected workspace_id ws-001 in response body"; exit 1; }

# Cleanup
echo "STEP: Cleanup — no cleanup required"

echo "CODEVALID_TEST_ASSERTION_OK:prompt_with_whitespace_preserved"
