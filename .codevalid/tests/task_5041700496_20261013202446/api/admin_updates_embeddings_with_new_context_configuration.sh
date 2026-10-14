#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_5041700496_20261013202446/api/_infra.sh

cv_step Given "admin workspace with high threshold, pinned doc, and embeddings" $LINENO

cv_prereq "ensure app is healthy before running tests" $LINENO
health_check

cv_prereq "create workspace via /v1/workspace/new" $LINENO
WS_NAME="admin-context-ws-$(date +%s)"
SIM_THRESHOLD_HIGH="0.75"
TOPN_MAX="3"

# Create workspace
WS_CREATE_BODY="$(jq -n --arg name "${WS_NAME}" '{name: $name}')"
cv_http POST "/v1/workspace/new" "${WS_CREATE_BODY}" 200
WS_CREATE_RESPONSE="$CV_HTTP_BODY"

echo "$WS_CREATE_RESPONSE" | jq -e '.workspace.slug' >/dev/null || cv_fail "workspace.slug missing in create response" $LINENO
WS_SLUG="$(echo "$WS_CREATE_RESPONSE" | jq -r '.workspace.slug')"
WS_ID="$(echo "$WS_CREATE_RESPONSE" | jq -r '.workspace.id')"

cv_prereq "seed two documents on disk" $LINENO
DOCS_ROOT="${DOCS_ROOT:-/data/documents}"
DOC1_PATH_REL="custom-documents/admin-doc1-$(date +%s).json"
DOC2_PATH_REL="custom-documents/admin-doc2-$(date +%s).json"
mkdir -p "${DOCS_ROOT}/custom-documents}"

cat > "${DOCS_ROOT}/${DOC1_PATH_REL}" <<'JSON'
{"title":"Admin Doc 1","pageContent":"Admin doc 1 content about high threshold.","url":"file://admin-doc1","chunkSource":"file://admin-doc1"}
JSON

cat > "${DOCS_ROOT}/${DOC2_PATH_REL}" <<'JSON'
{"title":"Admin Doc 2","pageContent":"Admin doc 2 pinned content.","url":"file://admin-doc2","chunkSource":"file://admin-doc2"}
JSON

cv_prereq "update workspace similarityThreshold and topN" $LINENO
UPDATE_BODY="$(jq -n --arg st "${SIM_THRESHOLD_HIGH}" --argjson topn ${TOPN_MAX} '{similarityThreshold: ($st|tonumber), topN: $topn}')"
cv_http POST "/v1/workspace/${WS_SLUG}/update" "${UPDATE_BODY}" 200
WS_UPDATE_RESPONSE="$CV_HTTP_BODY"

echo "$WS_UPDATE_RESPONSE" | jq -e '.workspace.similarityThreshold == 0.75' >/dev/null || cv_fail "workspace.similarityThreshold not 0.75" $LINENO
echo "$WS_UPDATE_RESPONSE" | jq -e '.workspace.topN == 3' >/dev/null || cv_fail "workspace.topN not 3" $LINENO

cv_prereq "embed both documents via update-embeddings" $LINENO
EMBED_BODY="$(jq -n --arg add1 "${DOC1_PATH_REL}" --arg add2 "${DOC2_PATH_REL}" '{adds: [$add1, $add2], deletes: []}')"
cv_http POST "/v1/workspace/${WS_SLUG}/update-embeddings" "${EMBED_BODY}" 200
EMBED_RESPONSE="$CV_HTTP_BODY"

echo "$EMBED_RESPONSE" | jq -e '.workspace.documents | length >= 2' >/dev/null || cv_fail "expected at least 2 documents after embedding" $LINENO

cv_prereq "pin second document via update-pin" $LINENO
PIN_BODY="$(jq -n --arg docPath "${DOC2_PATH_REL}" '{docPath: $docPath, pinStatus: true}')"
cv_http POST "/v1/workspace/${WS_SLUG}/update-pin" "${PIN_BODY}" 200
PIN_RESPONSE="$CV_HTTP_BODY"

echo "$PIN_RESPONSE" | jq -e '.message == "Pin status updated successfully"' >/dev/null || cv_fail "pin status update message unexpected" $LINENO

cv_step When "run vector-search and chat on admin workspace" $LINENO

cv_prereq "run vector-search" $LINENO
VECTOR_QUERY_BODY="$(jq -n --arg query "admin context high threshold" '{query: $query}')"
cv_http POST "/v1/workspace/${WS_SLUG}/vector-search" "${VECTOR_QUERY_BODY}" 200
VECTOR_RESPONSE="$CV_HTTP_BODY"

cv_prereq "run chat to observe pinned behaviour" $LINENO
CHAT_BODY="$(jq -n --arg msg "Explain the admin pinned document content." '{message: $msg, mode: "automatic", attachments: [], reset: false}')"
cv_http POST "/v1/workspace/${WS_SLUG}/chat" "${CHAT_BODY}" 200
CHAT_RESPONSE="$CV_HTTP_BODY"

cv_step Then "verify threshold, topN, pinned exclusion, and chat context" $LINENO

RESULTS_LEN="$(echo "${VECTOR_RESPONSE}" | jq '.results | length')"
if [ "${RESULTS_LEN}" -gt "${TOPN_MAX}" ]; then
  cv_fail "Expected at most ${TOPN_MAX} results, got ${RESULTS_LEN}" $LINENO
fi

LOW_SCORE_COUNT="$(echo "${VECTOR_RESPONSE}" | jq '[.results[] | select(.score != null and .score < 0.75)] | length')"
if [ "${LOW_SCORE_COUNT}" -ne 0 ]; then
  cv_fail "Found results below similarityThreshold 0.75" $LINENO
fi

PINNED_IN_RESULTS="$(echo "${VECTOR_RESPONSE}" | jq --arg url "file://admin-doc2" '[.results[] | select(.metadata.url == $url or .metadata.title == "Admin Doc 2")] | length')"
if [ "${PINNED_IN_RESULTS}" -ne 0 ]; then
  cv_fail "Pinned document appeared in retrieval results; should be excluded." $LINENO
fi

TEXT_RESPONSE="$(echo "${CHAT_RESPONSE}" | jq -r '.textResponse // ""')"
if ! echo "${TEXT_RESPONSE}" | grep -qi "admin doc 2 pinned content"; then
  cv_fail "Pinned document content not found in chat response context." $LINENO
fi

cv_step Cleanup "delete workspace and remove seeded documents" $LINENO
if [ -n "${WS_SLUG:-}" ]; then
  cv_http DELETE "/v1/workspace/${WS_SLUG}" 200
fi
rm -f "${DOCS_ROOT}/${DOC1_PATH_REL}" "${DOCS_ROOT}/${DOC2_PATH_REL}" || true

echo "CODEVALID_TEST_ASSERTION_OK:admin_updates_embeddings_with_new_context_configuration"
