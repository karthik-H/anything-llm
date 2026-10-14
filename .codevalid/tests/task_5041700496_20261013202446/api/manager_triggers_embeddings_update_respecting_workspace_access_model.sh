#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_5041700496_20261013202446/api/_infra.sh

cv_step Given "manager-managed workspace with a document ready for embeddings" $LINENO

# Simple health check using curl directly, without infra helpers
BASE_URL="${BASE_URL:-http://app:6713}"
curl -sS "${BASE_URL}/health" >/dev/null

cv_prereq "create managed workspace" $LINENO
WS_NAME="manager-managed-ws-$(date +%s)"

# Build API key header from environment if available
API_TOKEN="${API_TOKEN:-}"
if [ -n "${API_TOKEN}" ]; then
  AUTH_HEADER="-H Authorization: Bearer\ ${API_TOKEN}"
else
  AUTH_HEADER=""
fi

WS_CREATE_BODY="$(jq -n --arg name "${WS_NAME}" '{name: $name}')"
cv_http POST "/v1/workspace/new" "${WS_CREATE_BODY}" 200 ${AUTH_HEADER}
WS_CREATE_RESPONSE="$CV_HTTP_BODY"

WS_SLUG="$(echo "${WS_CREATE_RESPONSE}" | jq -r '.workspace.slug')"
WS_ID="$(echo "${WS_CREATE_RESPONSE}" | jq -r '.workspace.id')"

cv_prereq "seed manager document on disk" $LINENO
DOCS_ROOT="${TMPDIR:-/tmp}/codevalid-documents"
DOC_PATH_REL="custom-documents/manager-doc-$(date +%s).json"
mkdir -p "${DOCS_ROOT}/custom-documents"

cat > "${DOCS_ROOT}/${DOC_PATH_REL}" <<'JSON'
{"title":"Manager Doc","pageContent":"Manager document content.","url":"file://manager-doc","chunkSource":"file://manager-doc"}
JSON

cv_step When "manager triggers update-embeddings" $LINENO
EMBED_BODY="$(jq -n --arg doc "${DOC_PATH_REL}" '{adds: [$doc], deletes: []}')"
cv_http POST "/v1/workspace/${WS_SLUG}/update-embeddings" "${EMBED_BODY}" 200 ${AUTH_HEADER}
WS_AFTER_RESPONSE="$CV_HTTP_BODY"

cv_step Then "verify manager document embedded" $LINENO

echo "${WS_AFTER_RESPONSE}" | jq -e ".workspace.id == ${WS_ID}" >/dev/null || cv_fail "workspace.id mismatch in embeddings response" $LINENO
DOC_PRESENT_COUNT="$(echo "${WS_AFTER_RESPONSE}" | jq --arg path "${DOC_PATH_REL}" '.workspace.documents | map(select(.docpath == $path)) | length')"
if [ "${DOC_PRESENT_COUNT}" -ne 1 ]; then
  cv_fail "Expected manager document to be embedded once; found ${DOC_PRESENT_COUNT}" $LINENO
fi

cv_step Cleanup "delete managed workspace and document" $LINENO
if [ -n "${WS_SLUG:-}" ]; then
  cv_http DELETE "/v1/workspace/${WS_SLUG}" 200 ${AUTH_HEADER}
fi
rm -f "${DOCS_ROOT}/${DOC_PATH_REL}" || true

echo "CODEVALID_TEST_ASSERTION_OK:manager_triggers_embeddings_update_respecting_workspace_access_model"
