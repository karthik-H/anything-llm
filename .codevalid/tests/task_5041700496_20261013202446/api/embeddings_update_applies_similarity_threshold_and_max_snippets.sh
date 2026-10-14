#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_5041700496_20261013202446/api/_infra.sh

cv_step Given "workspace configured with high similarityThreshold and topN" $LINENO

cv_prereq "ensure app is healthy before running tests" $LINENO
HEALTH_URL="${BASE_URL:-http://app:6713}/health"
curl -sS -o /dev/null "${HEALTH_URL}"

cv_prereq "create threshold/topN workspace" $LINENO
API_KEY_HEADER='-H Authorization: Bearer test-api-key'
WS_NAME="threshold-topn-ws-$(date +%s)"
WS_CREATE_BODY="$(jq -n --arg name "${WS_NAME}" '{name: $name}')"
cv_http POST "/v1/workspace/new" "${WS_CREATE_BODY}" 200 ${API_KEY_HEADER}
WS_CREATE_RESPONSE="$CV_HTTP_BODY"
WS_SLUG="$(echo "${WS_CREATE_RESPONSE}" | jq -r '.workspace.slug')"

cv_prereq "seed threshold test document" $LINENO
DOCS_ROOT="${PWD}/documents"
DOC_PATH_REL="custom-documents/threshold-doc-$(date +%s).json"
mkdir -p "${DOCS_ROOT}/custom-documents"

cat > "${DOCS_ROOT}/${DOC_PATH_REL}" <<'JSON'
{"title":"Threshold Doc","pageContent":"Content with multiple semantic regions for similarity tests.","url":"file://threshold-doc","chunkSource":"file://threshold-doc"}
JSON

cv_prereq "set similarityThreshold to 0.75 and topN to 3" $LINENO
SIM_THRESHOLD_HIGH="0.75"
TOPN_MAX="3"
UPDATE_BODY="$(jq -n --arg st "${SIM_THRESHOLD_HIGH}" --argjson topn ${TOPN_MAX} '{similarityThreshold: ($st|tonumber), topN: $topn}')"
cv_http POST "/v1/workspace/${WS_SLUG}/update" "${UPDATE_BODY}" 200 ${API_KEY_HEADER}
WS_UPDATE_RESPONSE="$CV_HTTP_BODY"

echo "${WS_UPDATE_RESPONSE}" | jq -e '.workspace.similarityThreshold == 0.75' >/dev/null || cv_fail "workspace.similarityThreshold not 0.75" $LINENO
echo "${WS_UPDATE_RESPONSE}" | jq -e '.workspace.topN == 3' >/dev/null || cv_fail "workspace.topN not 3" $LINENO

cv_prereq "embed threshold doc under new configuration" $LINENO
EMBED_BODY="$(jq -n --arg doc "${DOC_PATH_REL}" '{adds: [$doc], deletes: []}')"
cv_http POST "/v1/workspace/${WS_SLUG}/update-embeddings" "${EMBED_BODY}" 200 ${API_KEY_HEADER}
EMBED_RESPONSE="$CV_HTTP_BODY"

echo "${EMBED_RESPONSE}" | jq -e '.workspace.documents | length >= 1' >/dev/null || cv_fail "expected at least one document after embedding" $LINENO

cv_step When "run vector-search and chat under threshold/topN settings" $LINENO

cv_prereq "run vector-search" $LINENO
VECTOR_QUERY_BODY="$(jq -n --arg query "similarity threshold test content" '{query: $query}')"
cv_http POST "/v1/workspace/${WS_SLUG}/vector-search" "${VECTOR_QUERY_BODY}" 200 ${API_KEY_HEADER}
VECTOR_RESPONSE="$CV_HTTP_BODY"

cv_prereq "run chat" $LINENO
CHAT_BODY="$(jq -n --arg msg "Test retrieval respecting threshold and max snippets." '{message: $msg, mode: "automatic", attachments: [], reset: false}')"
cv_http POST "/v1/workspace/${WS_SLUG}/chat" "${CHAT_BODY}" 200 ${API_KEY_HEADER}
CHAT_RESPONSE="$CV_HTTP_BODY"

cv_step Then "verify vector threshold and chat snippet limits" $LINENO

RESULTS_LEN="$(echo "${VECTOR_RESPONSE}" | jq '.results | length')"
if [ "${RESULTS_LEN}" -gt "${TOPN_MAX}" ]; then
  cv_fail "Expected <= ${TOPN_MAX} vector results; got ${RESULTS_LEN}" $LINENO
fi

LOW_SCORE_COUNT="$(echo "${VECTOR_RESPONSE}" | jq '[.results[] | select(.score != null and .score < 0.75)] | length')"
if [ "${LOW_SCORE_COUNT}" -ne 0 ]; then
  cv_fail "Found vector-search results with score below 0.75 threshold." $LINENO
fi

CHAT_SOURCES_LEN="$(echo "${CHAT_RESPONSE}" | jq '.sources | length // 0')"
if [ "${CHAT_SOURCES_LEN}" -gt "${TOPN_MAX}" ]; then
  cv_fail "Expected chat sources length <= ${TOPN_MAX}; got ${CHAT_SOURCES_LEN}" $LINENO
fi

cv_step Cleanup "delete threshold/topN workspace and document" $LINENO
if [ -n "${WS_SLUG:-}" ]; then
  cv_http DELETE "/v1/workspace/${WS_SLUG}" 200 ${API_KEY_HEADER}
fi
rm -f "${DOCS_ROOT}/${DOC_PATH_REL}" || true

echo "CODEVALID_TEST_ASSERTION_OK:embeddings_update_applies_similarity_threshold_and_max_snippets"
