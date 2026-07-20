#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TMP_DIR="$(mktemp -d)"

cleanup_tmp() {
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

# Given
echo "STEP: Given — prepare three concurrent POST /api/review requests"
echo "PREREQ: temporary workspace is $TMP_DIR"

run_request() {
  req_id="$1"
  headers_file="$TMP_DIR/${req_id}_headers.txt"
  body_file="$TMP_DIR/${req_id}_body.txt"
  code_file="$TMP_DIR/${req_id}_code.txt"
  echo "REQUEST_HEADERS(${req_id}): Content-Type: application/json"
  echo "REQUEST_BODY(${req_id}):"
  echo '{}'
  code="$(curl -sS -D "$headers_file" -o "$body_file" -w '%{http_code}' \
    -X POST "$BASE_URL/api/review" \
    -H 'Content-Type: application/json' \
    --data '{}')"
  printf '%s' "$code" > "$code_file"
}

# When
echo "STEP: When — send 3 concurrent POST requests to /api/review"
run_request "req1" &
pid1=$!
run_request "req2" &
pid2=$!
run_request "req3" &
pid3=$!
wait "$pid1"
wait "$pid2"
wait "$pid3"

for req_id in req1 req2 req3; do
  echo "RESPONSE_STATUS(${req_id}): $(cat "$TMP_DIR/${req_id}_code.txt")"
  echo "RESPONSE_HEADERS(${req_id}):"
  cat "$TMP_DIR/${req_id}_headers.txt"
  echo "RESPONSE_BODY(${req_id}):"
  cat "$TMP_DIR/${req_id}_body.txt"
done

# Then
echo "STEP: Then — assert all concurrent requests succeeded with review_triggered"
for req_id in req1 req2 req3; do
  code="$(cat "$TMP_DIR/${req_id}_code.txt")"
  [ "$code" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 for ${req_id} got ${code}"; exit 1; }
  body_compact="$(tr -d '[:space:]' < "$TMP_DIR/${req_id}_body.txt")"
  [ "$body_compact" = '{"status":"review_triggered"}' ] || { echo "ASSERTION_FAILED: expected review_triggered body for ${req_id} got ${body_compact}"; exit 1; }
done

# Cleanup
echo "STEP: Cleanup — no public cleanup available for detached concurrent review child processes"

echo "CODEVALID_TEST_ASSERTION_OK:review_endpoint_multiple_concurrent_requests"
