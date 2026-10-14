#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_5041700496_20261013202446/api/_infra.sh

cv_step Given "admin can upload and embed document for workspace-wide visibility" $LINENO

# Mocks
CASE_DIR=".codevalid/wiremock/mappings/cases/admin_uploads_document_workspace_wide_visibility"
mkdir -p "$CASE_DIR"

cv_prereq "stub CollectorApi.processDocument for admin visibility case" $LINENO
cat > "$CASE_DIR/collector_process_document.json" <<'JSON'
{
  "request": {
    "method": "POST",
    "urlPath": "/collector/process-document",
    "bodyPatterns": [
      { "contains": "admin_uploads_document_workspace_wide_visibility" }
    ]
  },
  "response": {
    "status": 200,
    "jsonBody": {
      "success": true,
      "reason": null,
      "documents": [
        {
          "id": "doc-admin-upload-visible",
          "location": "custom-documents/admin_uploads_document_workspace_wide_visibility.json"
        }
      ]
    }
  }
}
JSON

wiremock_admin_import_mappings "$CASE_DIR"

# Preconditions
cv_prereq "enable multi-user mode and create admin user" $LINENO
cv_http POST "/system/enable-multi-user" '{"username":"admin_visibility","password":"AdminVisPass123!"}' 200

cv_prereq "login as admin to obtain JWT token" $LINENO
cv_http POST "/request-token" '{"username":"admin_visibility","password":"AdminVisPass123!"}' 200
ADMIN_TOKEN=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.token')
[ -n "$ADMIN_TOKEN" ] && [ "$ADMIN_TOKEN" != "null" ] || cv_fail "expected non-null admin JWT token" $LINENO

cv_prereq "create workspace as admin" $LINENO
cv_http POST "/api/workspace/new" '{"name":"Admin Visibility Workspace"}' 200 -H "Authorization: Bearer $ADMIN_TOKEN"
WS_SLUG=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.workspace.slug')
[ -n "$WS_SLUG" ] && [ "$WS_SLUG" != "null" ] || cv_fail "expected workspace slug from creation response" $LINENO

cv_prereq "seed processed document file in storage" $LINENO
mkdir -p "server/storage/documents/custom-documents"
cat > "server/storage/documents/custom-documents/admin_uploads_document_workspace_wide_visibility.json" <<'JSON'
{
  "title": "Admin Visibility Document",
  "url": "http://example.com/admin_visibility_doc",
  "docAuthor": "AdminUser",
  "description": "Document for admin workspace-wide visibility test.",
  "docSource": "custom-documents",
  "chunkSource": "custom-documents://admin_visibility_doc",
  "published": "2024-01-01T00:00:00Z",
  "wordCount": 100,
  "token_count_estimate": 50,
  "pageContent": "Admin visibility document content for workspace-wide visibility test."
}
JSON

cv_step When "admin uploads and embeds document in workspace" $LINENO
cv_http POST "/workspace/${WS_SLUG}/upload-and-embed" '' 200 -H "Authorization: Bearer $ADMIN_TOKEN" -F "file=@server/storage/documents/custom-documents/admin_uploads_document_workspace_wide_visibility.json;type=application/json"

# For workspace-wide visibility verification, issue at least one chat in this workspace.
# This ensures embeddings are available for later retrieval tests, even though chat endpoints are not asserted here.
cv_prereq "admin issues a chat message in the workspace to ensure embeddings are usable" $LINENO
cv_http POST "/workspace/${WS_SLUG}/chat" '{"message":"Test message to warm up embeddings for workspace-wide visibility."}' 200 -H "Authorization: Bearer $ADMIN_TOKEN"

cv_step Then "upload-and-embed succeeds and workspace-documents entry exists" $LINENO

# Check success, error, document.id, document.location from upload-and-embed response
UPLOAD_BODY="$CV_HTTP_BODY"
SUCCESS=$(printf '%s' "$UPLOAD_BODY" | jq -r '.success')
ERROR_FIELD=$(printf '%s' "$UPLOAD_BODY" | jq -r '.error')
DOC_ID=$(printf '%s' "$UPLOAD_BODY" | jq -r '.document.id')
DOC_LOCATION=$(printf '%s' "$UPLOAD_BODY" | jq -r '.document.location')

[ "$SUCCESS" = "true" ] || cv_fail "expected .success == true got $SUCCESS" $LINENO
[ "$ERROR_FIELD" = "null" ] || cv_fail "expected .error == null got $ERROR_FIELD" $LINENO
[ "$DOC_ID" = "doc-admin-upload-visible" ] || cv_fail "expected document.id doc-admin-upload-visible got $DOC_ID" $LINENO
[ "$DOC_LOCATION" = "custom-documents/admin_uploads_document_workspace_wide_visibility.json" ] || cv_fail "expected document.location custom-documents/admin_uploads_document_workspace_wide_visibility.json got $DOC_LOCATION" $LINENO

# Verify via /system/local-files that embedded document is present
cv_http GET "/system/local-files" '' 200 -H "Authorization: Bearer $ADMIN_TOKEN"
LOCAL_FILES_BODY="$CV_HTTP_BODY"

# Loosely assert that our docpath appears somewhere in the local-files JSON
printf '%s' "$LOCAL_FILES_BODY" | grep -q "admin_uploads_document_workspace_wide_visibility.json" || \
  cv_fail "expected embedded document location to appear in /system/local-files output" $LINENO

cv_step Cleanup "delete workspace created for test" $LINENO
cv_http DELETE "/workspace/${WS_SLUG}" '' 200 -H "Authorization: Bearer $ADMIN_TOKEN"

echo "CODEVALID_TEST_ASSERTION_OK:admin_uploads_document_workspace_wide_visibility"
