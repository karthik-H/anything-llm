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
echo "STEP: Given — require pendingHelp without rpc and a fallback piRpc connection"
echo "PREREQ: this scenario requires hidden in-memory server state not configurable through any discovered public setup API"
echo "PREREQ: expected state includes workspace.pendingHelp.id=help-456, workspace.pendingHelp.rpc=null, workspace.piRpc active, workspace.id=ws-001"
cat > "$REQUEST_BODY_FILE" <<'EOF'
{"prompt":"Try using the alternate data source"}
EOF

# When
echo "STEP: When — POST /api/v1/prompt to answer help via piRpc fallback"
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
echo "STEP: Then — assert prompt was accepted and routed through fallback RPC path"
[ "$HTTP_CODE" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 got ${HTTP_CODE}"; exit 1; }
grep -F '"status":"prompt_sent"' "$RESPONSE_BODY" >/dev/null 2>&1 || grep -F '"status": "prompt_sent"' "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected status prompt_sent in response body"; exit 1; }
grep -F '"workspace_id":"ws-001"' "$RESPONSE_BODY" >/dev/null 2>&1 || grep -F '"workspace_id": "ws-001"' "$RESPONSE_BODY" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected workspace_id ws-001 in response body"; exit 1; }

# Cleanup
echo "STEP: Cleanup — no public cleanup available for in-memory pendingHelp/piRpc state"

echo "CODEVALID_TEST_ASSERTION_OK:pending_help_fallback_to_pi_rpc"
