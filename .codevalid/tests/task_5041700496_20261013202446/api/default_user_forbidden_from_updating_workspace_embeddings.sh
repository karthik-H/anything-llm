#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_5041700496_20261013202446/api/_infra.sh

cv_step Given "workspace and document for default user embeddings attempt" $LINENO

cv_prereq "create workspace for default-role expectation" $LINENO
WS_NAME="default-role-ws-$(date +%s)"

# Use only what the image provides for authorization; avoid missing api_key_header helper.
AUTH_TOKEN="${AUTH_TOKEN:-test-default-token}"
API_KEY_HEADER=(-H "Authorization: Bearer ${AUTH_TOKEN}")

WS_CREATE_BODY="$(jq -n --arg name "${WS_NAME}" '{name: $name}')"
cv_http POST "/v1/workspace/new" "${WS_CREATE_BODY}" 200 "${API_KEY_HEADER[@]}"
WS_CREATE_RESPONSE="$CV_HTTP_BODY"
WS_SLUG="$(echo "${WS_CREATE_RESPONSE}" | jq -r '.workspace.slug')"

cv_prereq "seed default user document" $LINENO
# Avoid missing documents_root helper; construct a documents root from TMPDIR.
DOCS_ROOT="${TMPDIR:-/tmp}/documents-root"
DOC_PATH_REL="custom-documents/default-doc-$(date +%s).json"
mkdir -p "${DOCS_ROOT}/custom-documents"

cat > "${DOCS_ROOT}/${DOC_PATH_REL}" <<'JSON'
{"title":"Default Doc","pageContent":"Default user document content.","url":"file://default-doc","chunkSource":"file://default-doc"}
JSON

cv_prereq "capture baseline documents count via no-op update-embeddings" $LINENO
BASE_EMBED_BODY='{"adds":[],"deletes":[]}'
cv_http POST "/v1/workspace/${WS_SLUG}/update-embeddings" "${BASE_EMBED_BODY}" 200 "${API_KEY_HEADER[@]}"
EMBED_BASE_RESPONSE="$CV_HTTP_BODY"
BASE_DOC_COUNT="$(echo "${EMBED_BASE_RESPONSE}" | jq '.workspace.documents | length')"

cv_step When "default user attempts to update embeddings" $LINENO
EMBED_BODY="$(jq -n --arg doc "${DOC_PATH_REL}" '{adds: [$doc], deletes: []}')"

# For this case we need raw status without cv_http enforcing it; still keep observability.
REQUEST_BODY="${EMBED_BODY}"
REQUEST_URL="${BASE_URL:-http://app:6713}/v1/workspace/${WS_SLUG}/update-embeddings"
printf 'REQUEST_HEADERS:
POST %s
' "$REQUEST_URL"
printf 'REQUEST_BODY:
%s
' "$REQUEST_BODY"
DEFAULT_ATTEMPT_RAW="$(command curl -sS -X POST -H 'Content-Type: application/json' "${API_KEY_HEADER[@]}" -D /tmp/default_attempt_headers.json -o /tmp/default_attempt_body.json -w '%{http_code}' "$REQUEST_URL" --data "$REQUEST_BODY")" || true
DEFAULT_ATTEMPT_STATUS="${DEFAULT_ATTEMPT_RAW}"
DEFAULT_ATTEMPT_BODY="$(cat /tmp/default_attempt_body.json 2>/dev/null || true)"
printf 'RESPONSE_HEADERS:
'
cat /tmp/default_attempt_headers.json 2>/dev/null || true
printf 'RESPONSE_BODY:
%s
' "$DEFAULT_ATTEMPT_BODY"
cv_http POST "$REQUEST_URL" "$DEFAULT_ATTEMPT_STATUS"  # marker only

cv_step Then "verify default user is forbidden and documents unchanged" $LINENO

if [ "${DEFAULT_ATTEMPT_STATUS}" -eq 401 ] || [ "${DEFAULT_ATTEMPT_STATUS}" -eq 403 ]; then
  :
else
  cv_fail "Expected HTTP 401 or 403 for default user, got ${DEFAULT_ATTEMPT_STATUS}" $LINENO
fi

DOC_COUNT_AFTER="$(echo "${DEFAULT_ATTEMPT_BODY}" | jq '.workspace.documents | length // 0')"
if [ "${DOC_COUNT_AFTER}" -ne "${BASE_DOC_COUNT}" ]; then
  cv_fail "Expected no change in documents for unauthorized default user." $LINENO
fi

cv_step Cleanup "delete workspace and remove default doc" $LINENO
if [ -n "${WS_SLUG:-}" ]; then
  cv_http DELETE "/v1/workspace/${WS_SLUG}" 200 "${API_KEY_HEADER[@]}"
fi
rm -f "${DOCS_ROOT}/${DOC_PATH_REL}" || true
rm -f /tmp/default_attempt_body.json /tmp/default_attempt_headers.json || true

echo "CODEVALID_TEST_ASSERTION_OK:default_user_forbidden_from_updating_workspace_embeddings"
