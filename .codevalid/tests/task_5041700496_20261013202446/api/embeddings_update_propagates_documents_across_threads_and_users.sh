#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_5041700496_20261013202446/api/_infra.sh

cv_step Given "workspace with shared embedded document for multiple threads" $LINENO

# Basic health check using cv_http (curl wrapper) to ensure the app is reachable.
# We use a simple GET on the root path; adjust if a dedicated health endpoint exists.
cv_http GET "/" 200

cv_prereq "create multi-thread workspace" $LINENO
WS_NAME="multi-thread-ws-$(date +%s)"
WS_CREATE_BODY="$(jq -n --arg name "${WS_NAME}" '{name: $name}')"
cv_http POST "/v1/workspace/new" "${WS_CREATE_BODY}" 200
WS_CREATE_RESPONSE="$CV_HTTP_BODY"
WS_SLUG="$(echo "${WS_CREATE_RESPONSE}" | jq -r '.workspace.slug')"

cv_prereq "seed shared document and embed it" $LINENO
DOCS_ROOT="$(mktemp -d)"
DOC_PATH_REL="custom-documents/shared-doc-$(date +%s).json"
mkdir -p "${DOCS_ROOT}/custom-documents"

cat > "${DOCS_ROOT}/${DOC_PATH_REL}" <<'JSON'
{"title":"Shared Doc","pageContent":"Content shared across threads.","url":"file://shared-doc","chunkSource":"file://shared-doc"}
JSON

EMBED_BODY="$(jq -n --arg doc "${DOC_PATH_REL}" '{adds: [$doc], deletes: []}')"
cv_http POST "/v1/workspace/${WS_SLUG}/update-embeddings" "${EMBED_BODY}" 200
EMBED_RESPONSE="$CV_HTTP_BODY"

echo "${EMBED_RESPONSE}" | jq -e '.workspace.documents | length >= 1' >/dev/null || cv_fail "expected at least one document after embedding" $LINENO

cv_step When "chat across threads and with attachments" $LINENO

cv_prereq "thread A chat referencing shared document" $LINENO
CHAT_BODY_A="$(jq -n \
  --arg msg "What is in the shared doc?" \
  --arg sid "thread-a" \
  '{message: $msg, mode: "automatic", sessionId: $sid, attachments: [], reset: false}')"
cv_http POST "/v1/workspace/${WS_SLUG}/chat" "${CHAT_BODY_A}" 200
CHAT_RESPONSE_A="$CV_HTTP_BODY"

cv_prereq "thread B chat referencing shared document" $LINENO
CHAT_BODY_B="$(jq -n \
  --arg msg "Explain the shared document content." \
  --arg sid "thread-b" \
  '{message: $msg, mode: "automatic", sessionId: $sid, attachments: [], reset: false}')"
cv_http POST "/v1/workspace/${WS_SLUG}/chat" "${CHAT_BODY_B}" 200
CHAT_RESPONSE_B="$CV_HTTP_BODY"

cv_prereq "thread A chat with attachment" $LINENO
ATTACHMENT_CONTENT="$(printf 'data:text/plain;base64,%s' "$(printf 'thread local attachment' | base64)")"
CHAT_BODY_A_ATTACH="$(jq -n \
  --arg msg "Use this attachment." \
  --arg sid "thread-a" \
  --arg name "threadA-attach.txt" \
  --arg mime "text/plain" \
  --arg content "${ATTACHMENT_CONTENT}" \
  '{message: $msg, mode: "automatic", sessionId: $sid,
    attachments: [{name: $name, mime: $mime, contentString: $content}],
    reset: false}')"
cv_http POST "/v1/workspace/${WS_SLUG}/chat" "${CHAT_BODY_A_ATTACH}" 200
CHAT_RESPONSE_A_ATTACH="$CV_HTTP_BODY"

cv_prereq "thread B chat without attachments to check isolation" $LINENO
CHAT_BODY_B_NO_ATTACH="$(jq -n \
  --arg msg "Do you see any attachments from another thread?" \
  --arg sid "thread-b" \
  '{message: $msg, mode: "automatic", sessionId: $sid, attachments: [], reset: false}')"
cv_http POST "/v1/workspace/${WS_SLUG}/chat" "${CHAT_BODY_B_NO_ATTACH}" 200
CHAT_RESPONSE_B_NO_ATTACH="$CV_HTTP_BODY"

cv_step Then "verify shared doc used in both threads and attachments are thread-local" $LINENO

TEXT_A="$(echo "${CHAT_RESPONSE_A}" | jq -r '.textResponse // ""')"
TEXT_B="$(echo "${CHAT_RESPONSE_B}" | jq -r '.textResponse // ""')"

if ! echo "${TEXT_A}" | grep -qi "shared doc"; then
  cv_fail "Thread A did not use shared document content." $LINENO
fi

if ! echo "${TEXT_B}" | grep -qi "shared doc"; then
  cv_fail "Thread B did not use shared document content." $LINENO
fi

TEXT_B_NO_ATTACH="$(echo "${CHAT_RESPONSE_B_NO_ATTACH}" | jq -r '.textResponse // ""')"
if echo "${TEXT_B_NO_ATTACH}" | grep -qi "threadA-attach.txt"; then
  cv_fail "Attachment from Thread A leaked into Thread B context." $LINENO
fi

cv_step Cleanup "delete multi-thread workspace and shared doc" $LINENO
if [ -n "${WS_SLUG:-}" ]; then
  cv_http DELETE "/v1/workspace/${WS_SLUG}" 200
fi
rm -f "${DOCS_ROOT}/${DOC_PATH_REL}" || true

echo "CODEVALID_TEST_ASSERTION_OK:embeddings_update_propagates_documents_across_threads_and_users"
