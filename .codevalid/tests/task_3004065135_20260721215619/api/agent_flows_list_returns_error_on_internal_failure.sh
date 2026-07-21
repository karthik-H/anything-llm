#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_AUTH_HEADER="${ADMIN_AUTH_HEADER:-Authorization: Bearer admin-token}"
ACCEPT_HEADER="Accept: application/json"
TOXIPROXY_BASE="${TOXIPROXY_BASE:-http://toxiproxy:8474}"
DATABASE_URL="${DATABASE_URL:-postgresql://postgres:postgres@toxiproxy:5432/app}"
LIST_HEADERS="/tmp/agent_flows_list_returns_error_on_internal_failure_list_headers_${CASE_SUFFIX}.txt"
LIST_BODY="/tmp/agent_flows_list_returns_error_on_internal_failure_list_body_${CASE_SUFFIX}.txt"
TOXIC_HEADERS="/tmp/agent_flows_list_returns_error_on_internal_failure_toxic_headers_${CASE_SUFFIX}.txt"
TOXIC_BODY="/tmp/agent_flows_list_returns_error_on_internal_failure_toxic_body_${CASE_SUFFIX}.txt"
REMOVE_HEADERS="/tmp/agent_flows_list_returns_error_on_internal_failure_remove_headers_${CASE_SUFFIX}.txt"
REMOVE_BODY="/tmp/agent_flows_list_returns_error_on_internal_failure_remove_body_${CASE_SUFFIX}.txt"
TOXIC_NAME="agent-flows-list-db-timeout-${CASE_SUFFIX}"

cleanup_files() {
  rm -f "$LIST_HEADERS" "$LIST_BODY" "$TOXIC_HEADERS" "$TOXIC_BODY" "$REMOVE_HEADERS" "$REMOVE_BODY"
}
trap cleanup_files EXIT

# Given — bring the system to the required state
printf 'STEP: Given — inject a database timeout through toxiproxy\n'
printf 'PREREQ: register a timeout toxic on postgres proxy\n'
TOXIC_REQUEST_BODY=$(printf '{"name":"%s","type":"timeout","stream":"downstream","attributes":{"timeout":1500}}' "$TOXIC_NAME")
printf 'REQUEST_HEADERS:\nContent-Type: application/json\nAccept: application/json\n'
printf 'REQUEST_BODY:\n%s\n' "$TOXIC_REQUEST_BODY"
TOXIC_CODE=$(curl -sS -D "$TOXIC_HEADERS" -o "$TOXIC_BODY" -w '%{http_code}' \
  -X POST "$TOXIPROXY_BASE/proxies/postgres/toxics" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  --data "$TOXIC_REQUEST_BODY")
printf 'RESPONSE_HEADERS:\n'
cat "$TOXIC_HEADERS"
printf 'RESPONSE_BODY:\n'
cat "$TOXIC_BODY"
printf '\nRESPONSE_STATUS: %s\n' "$TOXIC_CODE"
[ "$TOXIC_CODE" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 creating toxiproxy toxic got ${TOXIC_CODE}"; exit 1; }

# When — perform the action under test
printf 'STEP: When — admin requests agent flows while database proxy is timing out\n'
printf 'REQUEST_HEADERS:\n%s\n%s\n' "$ADMIN_AUTH_HEADER" "$ACCEPT_HEADER"
printf 'REQUEST_BODY:\n<empty>\n'
LIST_CODE=$(curl -sS -D "$LIST_HEADERS" -o "$LIST_BODY" -w '%{http_code}' \
  -X GET "$BASE_URL/api/agent-flows/list" \
  -H "$ADMIN_AUTH_HEADER" \
  -H "$ACCEPT_HEADER")
printf 'RESPONSE_HEADERS:\n'
cat "$LIST_HEADERS"
printf 'RESPONSE_BODY:\n'
cat "$LIST_BODY"
printf '\nRESPONSE_STATUS: %s\n' "$LIST_CODE"

# Then — HTTP/body assertions
printf 'STEP: Then — endpoint returns an internal error response\n'
[ "$LIST_CODE" = "500" ] || { echo "ASSERTION_FAILED: expected HTTP 500 got ${LIST_CODE}"; exit 1; }
jq -e '.success == false' "$LIST_BODY" >/dev/null || { echo "ASSERTION_FAILED: expected success false"; exit 1; }
grep -Eqi 'error|failed|database|timeout' "$LIST_BODY" || { echo "ASSERTION_FAILED: expected internal failure message in response body"; exit 1; }

# Cleanup — undo Given side effects
printf 'STEP: Cleanup — remove injected toxiproxy toxic\n'
printf 'PREREQ: delete toxiproxy toxic %s\n' "$TOXIC_NAME"
REMOVE_CODE=$(curl -sS -D "$REMOVE_HEADERS" -o "$REMOVE_BODY" -w '%{http_code}' \
  -X DELETE "$TOXIPROXY_BASE/proxies/postgres/toxics/$TOXIC_NAME")
printf 'RESPONSE_HEADERS:\n'
cat "$REMOVE_HEADERS"
printf 'RESPONSE_BODY:\n'
cat "$REMOVE_BODY"
printf '\nRESPONSE_STATUS: %s\n' "$REMOVE_CODE"
case "$REMOVE_CODE" in
  200|204|404) ;;
  *) echo "ASSERTION_FAILED: expected HTTP 200, 204, or 404 removing toxic got ${REMOVE_CODE}"; exit 1 ;;
esac

echo 'CODEVALID_TEST_ASSERTION_OK:agent_flows_list_returns_error_on_internal_failure'
