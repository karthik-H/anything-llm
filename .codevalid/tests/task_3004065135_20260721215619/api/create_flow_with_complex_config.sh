#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="create_flow_with_complex_config"
REQ_HEADERS_FILE="/tmp/${TEST_ID}_req_headers_${CASE_SUFFIX}.txt"
REQ_BODY_FILE="/tmp/${TEST_ID}_req_body_${CASE_SUFFIX}.json"
RESP_HEADERS_FILE="/tmp/${TEST_ID}_resp_headers_${CASE_SUFFIX}.txt"
RESP_BODY_FILE="/tmp/${TEST_ID}_resp_body_${CASE_SUFFIX}.json"
DELETE_RESP_HEADERS_FILE="/tmp/${TEST_ID}_delete_resp_headers_${CASE_SUFFIX}.txt"
DELETE_RESP_BODY_FILE="/tmp/${TEST_ID}_delete_resp_body_${CASE_SUFFIX}.json"
CREATED_UUID=""

cleanup_files() {
  rm -f "$REQ_HEADERS_FILE" "$REQ_BODY_FILE" "$RESP_HEADERS_FILE" "$RESP_BODY_FILE" \
    "$DELETE_RESP_HEADERS_FILE" "$DELETE_RESP_BODY_FILE"
}
trap cleanup_files EXIT

cat > "$REQ_BODY_FILE" <<EOF
{
  "name": "Complex Automation Agent ${CASE_SUFFIX}",
  "config": {
    "blocks": [
      {"id": "block-input-1-${CASE_SUFFIX}", "type": "input", "config": {"label": "User Request"}},
      {"id": "block-llm-1-${CASE_SUFFIX}", "type": "llm", "config": {"model": "gpt-4", "temperature": 0.7}},
      {"id": "block-tool-1-${CASE_SUFFIX}", "type": "tool", "config": {"toolName": "web_search", "enabled": true}},
      {"id": "block-output-1-${CASE_SUFFIX}", "type": "output", "config": {"format": "json"}}
    ],
    "capabilities": ["web_browsing", "file_access", "api_calls"],
    "tools": [
      {"name": "calendar", "enabled": true},
      {"name": "email", "enabled": true}
    ]
  },
  "uuid": null
}
EOF

# Given
echo "STEP: Given — prepare a complex nested agent flow configuration"
echo "PREREQ: using unique block ids and flow name so the test is isolated"

# When
echo "STEP: When — create a flow with blocks, capabilities, and tools"
echo "REQUEST_HEADERS:"
printf 'Content-Type: application/json\n' > "$REQ_HEADERS_FILE"
cat "$REQ_HEADERS_FILE"
echo "REQUEST_BODY:"
cat "$REQ_BODY_FILE"
status="$(curl -sS -D "$RESP_HEADERS_FILE" -o "$RESP_BODY_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/api/agent-flows/save" \
  -H 'Content-Type: application/json' \
  --data @"$REQ_BODY_FILE")"
echo "RESPONSE_HEADERS:"
cat "$RESP_HEADERS_FILE"
echo "RESPONSE_BODY:"
cat "$RESP_BODY_FILE"
echo "RESPONSE_STATUS: $status"

# Then
echo "STEP: Then — verify complex config save succeeds"
[ "$status" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 got ${status}"; exit 1; }
grep -F '"success":true' "$RESP_BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected success true in response body"; exit 1; }
grep -F "Complex Automation Agent ${CASE_SUFFIX}" "$RESP_BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected created flow name in response body"; exit 1; }
grep -F 'web_browsing' "$RESP_BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected capabilities in response body"; exit 1; }
grep -F 'calendar' "$RESP_BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected tools in response body"; exit 1; }
CREATED_UUID="$(grep -o '"uuid":"[^"]*"' "$RESP_BODY_FILE" | head -n 1 | sed 's/"uuid":"//; s/"$//')"
[ -n "$CREATED_UUID" ] || { echo "ASSERTION_FAILED: expected created flow uuid in response body"; exit 1; }

# Cleanup
echo "STEP: Cleanup — delete the created complex flow"
delete_status="$(curl -sS -D "$DELETE_RESP_HEADERS_FILE" -o "$DELETE_RESP_BODY_FILE" -w '%{http_code}' \
  -X DELETE "$BASE_URL/api/agent-flows/$CREATED_UUID")"
echo "RESPONSE_HEADERS:"
cat "$DELETE_RESP_HEADERS_FILE"
echo "RESPONSE_BODY:"
cat "$DELETE_RESP_BODY_FILE"
echo "RESPONSE_STATUS: $delete_status"
[ "$delete_status" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 during cleanup delete got ${delete_status}"; exit 1; }

echo "CODEVALID_TEST_ASSERTION_OK:create_flow_with_complex_config"
