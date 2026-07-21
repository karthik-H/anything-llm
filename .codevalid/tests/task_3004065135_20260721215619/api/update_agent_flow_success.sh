#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="update_agent_flow_success"
CREATE_REQ_HEADERS_FILE="/tmp/${TEST_ID}_create_req_headers_${CASE_SUFFIX}.txt"
CREATE_REQ_BODY_FILE="/tmp/${TEST_ID}_create_req_body_${CASE_SUFFIX}.json"
CREATE_RESP_HEADERS_FILE="/tmp/${TEST_ID}_create_resp_headers_${CASE_SUFFIX}.txt"
CREATE_RESP_BODY_FILE="/tmp/${TEST_ID}_create_resp_body_${CASE_SUFFIX}.json"
UPDATE_REQ_HEADERS_FILE="/tmp/${TEST_ID}_update_req_headers_${CASE_SUFFIX}.txt"
UPDATE_REQ_BODY_FILE="/tmp/${TEST_ID}_update_req_body_${CASE_SUFFIX}.json"
UPDATE_RESP_HEADERS_FILE="/tmp/${TEST_ID}_update_resp_headers_${CASE_SUFFIX}.txt"
UPDATE_RESP_BODY_FILE="/tmp/${TEST_ID}_update_resp_body_${CASE_SUFFIX}.json"
DELETE_RESP_HEADERS_FILE="/tmp/${TEST_ID}_delete_resp_headers_${CASE_SUFFIX}.txt"
DELETE_RESP_BODY_FILE="/tmp/${TEST_ID}_delete_resp_body_${CASE_SUFFIX}.json"
CREATED_UUID=""

cleanup_files() {
  rm -f "$CREATE_REQ_HEADERS_FILE" "$CREATE_REQ_BODY_FILE" "$CREATE_RESP_HEADERS_FILE" "$CREATE_RESP_BODY_FILE" \
    "$UPDATE_REQ_HEADERS_FILE" "$UPDATE_REQ_BODY_FILE" "$UPDATE_RESP_HEADERS_FILE" "$UPDATE_RESP_BODY_FILE" \
    "$DELETE_RESP_HEADERS_FILE" "$DELETE_RESP_BODY_FILE"
}
trap cleanup_files EXIT

cat > "$CREATE_REQ_BODY_FILE" <<EOF
{
  "name": "Old Agent Name ${CASE_SUFFIX}",
  "config": {
    "blocks": [
      {"id": "seed-block-${CASE_SUFFIX}", "type": "input", "config": {"label": "Original"}}
    ]
  },
  "uuid": null
}
EOF

# Given
echo "STEP: Given — create an existing flow to update"
echo "PREREQ: creating a baseline flow through the public save API"
echo "REQUEST_HEADERS:"
printf 'Content-Type: application/json\n' > "$CREATE_REQ_HEADERS_FILE"
cat "$CREATE_REQ_HEADERS_FILE"
echo "REQUEST_BODY:"
cat "$CREATE_REQ_BODY_FILE"
create_status="$(curl -sS -D "$CREATE_RESP_HEADERS_FILE" -o "$CREATE_RESP_BODY_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/api/agent-flows/save" \
  -H 'Content-Type: application/json' \
  --data @"$CREATE_REQ_BODY_FILE")"
echo "RESPONSE_HEADERS:"
cat "$CREATE_RESP_HEADERS_FILE"
echo "RESPONSE_BODY:"
cat "$CREATE_RESP_BODY_FILE"
echo "RESPONSE_STATUS: $create_status"
[ "$create_status" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 when creating baseline flow got ${create_status}"; exit 1; }
CREATED_UUID="$(grep -o '"uuid":"[^"]*"' "$CREATE_RESP_BODY_FILE" | head -n 1 | sed 's/"uuid":"//; s/"$//')"
[ -n "$CREATED_UUID" ] || { echo "ASSERTION_FAILED: expected created uuid from baseline flow"; exit 1; }

cat > "$UPDATE_REQ_BODY_FILE" <<EOF
{
  "name": "Updated Support Agent ${CASE_SUFFIX}",
  "config": {
    "blocks": [
      {"id": "block-1-${CASE_SUFFIX}", "type": "input", "config": {"label": "User Query"}}
    ]
  },
  "uuid": "${CREATED_UUID}"
}
EOF

# When
echo "STEP: When — update the existing agent flow by uuid"
echo "REQUEST_HEADERS:"
printf 'Content-Type: application/json\n' > "$UPDATE_REQ_HEADERS_FILE"
cat "$UPDATE_REQ_HEADERS_FILE"
echo "REQUEST_BODY:"
cat "$UPDATE_REQ_BODY_FILE"
update_status="$(curl -sS -D "$UPDATE_RESP_HEADERS_FILE" -o "$UPDATE_RESP_BODY_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/api/agent-flows/save" \
  -H 'Content-Type: application/json' \
  --data @"$UPDATE_REQ_BODY_FILE")"
echo "RESPONSE_HEADERS:"
cat "$UPDATE_RESP_HEADERS_FILE"
echo "RESPONSE_BODY:"
cat "$UPDATE_RESP_BODY_FILE"
echo "RESPONSE_STATUS: $update_status"

# Then
echo "STEP: Then — verify the flow update succeeds"
[ "$update_status" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 got ${update_status}"; exit 1; }
grep -F '"success":true' "$UPDATE_RESP_BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected success true in update response"; exit 1; }
grep -F "$CREATED_UUID" "$UPDATE_RESP_BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected same uuid in update response"; exit 1; }
grep -F "Updated Support Agent ${CASE_SUFFIX}" "$UPDATE_RESP_BODY_FILE" >/dev/null || { echo "ASSERTION_FAILED: expected updated flow name in response body"; exit 1; }

# Cleanup
echo "STEP: Cleanup — delete the updated flow"
delete_status="$(curl -sS -D "$DELETE_RESP_HEADERS_FILE" -o "$DELETE_RESP_BODY_FILE" -w '%{http_code}' \
  -X DELETE "$BASE_URL/api/agent-flows/$CREATED_UUID")"
echo "RESPONSE_HEADERS:"
cat "$DELETE_RESP_HEADERS_FILE"
echo "RESPONSE_BODY:"
cat "$DELETE_RESP_BODY_FILE"
echo "RESPONSE_STATUS: $delete_status"
[ "$delete_status" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 during cleanup delete got ${delete_status}"; exit 1; }

echo "CODEVALID_TEST_ASSERTION_OK:update_agent_flow_success"
