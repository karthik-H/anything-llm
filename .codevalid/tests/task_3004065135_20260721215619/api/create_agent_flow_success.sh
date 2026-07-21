#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="create_agent_flow_success"
REQ_HEADERS_FILE="/tmp/${TEST_ID}_req_headers_${CASE_SUFFIX}.txt"
REQ_BODY_FILE="/tmp/${TEST_ID}_req_body_${CASE_SUFFIX}.json"
RESP_HEADERS_FILE="/tmp/${TEST_ID}_resp_headers_${CASE_SUFFIX}.txt"
RESP_BODY_FILE="/tmp/${TEST_ID}_resp_body_${CASE_SUFFIX}.json"
LIST_HEADERS_FILE="/tmp/${TEST_ID}_list_headers_${CASE_SUFFIX}.txt"
LIST_BODY_FILE="/tmp/${TEST_ID}_list_body_${CASE_SUFFIX}.json"
DELETE_HEADERS_FILE="/tmp/${TEST_ID}_delete_headers_${CASE_SUFFIX}.txt"
DELETE_BODY_FILE="/tmp/${TEST_ID}_delete_body_${CASE_SUFFIX}.json"
CREATED_UUID=""

cleanup_files() {
  rm -f "$REQ_HEADERS_FILE" "$REQ_BODY_FILE" "$RESP_HEADERS_FILE" "$RESP_BODY_FILE" \
    "$LIST_HEADERS_FILE" "$LIST_BODY_FILE" "$DELETE_HEADERS_FILE" "$DELETE_BODY_FILE"
}
trap cleanup_files EXIT

cat > "$REQ_BODY_FILE" <<EOF
{
  "name": "Customer Support Agent ${CASE_SUFFIX}",
  "config": {
    "blocks": [
      {"id": "block-1-${CASE_SUFFIX}", "type": "input", "config": {}},
      {"id": "block-2-${CASE_SUFFIX}", "type": "llm", "config": {"model": "gpt-4"}}
    ]
  },
  "uuid": null
}
EOF

# Given
echo "STEP: Given — prepare a unique valid agent flow payload"
echo "PREREQ: using unique flow name and block ids so the test is self-contained"

# When
echo "STEP: When — create a new agent flow via POST /api/agent-flows/save"
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
echo "STEP: Then — verify the flow is created successfully"
[ "$status" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 got ${status}"; exit 1; }
grep -F '"success":true' "$RESP_BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected success true in response body"; exit 1; }
grep -F '"flow"' "$RESP_BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected flow object in response body"; exit 1; }
grep -F "Customer Support Agent ${CASE_SUFFIX}" "$RESP_BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected created flow name in response body"; exit 1; }
CREATED_UUID="$(grep -o '"uuid":"[^"]*"' "$RESP_BODY_FILE" | head -n 1 | sed 's/"uuid":"//; s/"$//')"
[ -n "$CREATED_UUID" ] || { echo "ASSERTION_FAILED: expected created flow uuid in response body"; exit 1; }

# Cleanup
echo "STEP: Cleanup — delete the created agent flow"
delete_status="$(curl -sS -D "$DELETE_HEADERS_FILE" -o "$DELETE_BODY_FILE" -w '%{http_code}' \
  -X DELETE "$BASE_URL/api/agent-flows/$CREATED_UUID")"
echo "RESPONSE_HEADERS:"
cat "$DELETE_HEADERS_FILE"
echo "RESPONSE_BODY:"
cat "$DELETE_BODY_FILE"
echo "RESPONSE_STATUS: $delete_status"
[ "$delete_status" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 during cleanup delete got ${delete_status}"; exit 1; }

echo "CODEVALID_TEST_ASSERTION_OK:create_agent_flow_success"
