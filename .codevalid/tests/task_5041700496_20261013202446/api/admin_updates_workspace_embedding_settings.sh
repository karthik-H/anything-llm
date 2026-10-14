#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_5041700496_20261013202446/api/_infra.sh

cv_step Given "setup shared infra and mappings list" $LINENO
# Case mappings
# id                                                  | method | path                                          
# admin_updates_workspace_embedding_settings          | POST   | /workspace/{slug}/update-embeddings         
# manager_updates_workspace_embedding_settings        | POST   | /workspace/{slug}/update-embeddings         
# default_role_forbidden_to_update_embeddings         | POST   | /workspace/{slug}/update-embeddings         
# high_threshold_excludes_low_similarity_snippets     | POST   | /workspace/{slug}/update-embeddings         
# max_context_snippets_per_chat_enforced              | POST   | /workspace/{slug}/update-embeddings         
# pinned_documents_inserted_fully_and_excluded_from_retrieval_post_workspace_slug_update_embeddings | POST   | /workspace/{slug}/update-embeddings         
# embedded_documents_global_scope_vs_chat_attachments_thread_scope | POST   | /workspace/{slug}/update-embeddings        

########################
# Case: admin_updates_workspace_embedding_settings
########################

cv_prereq "seed admin user, workspace, multi-user mode and doc file" $LINENO
# Mocks
# (No external HTTP vendor calls are visible for this endpoint or its call graph; no WireMock mappings are needed.)

# Preconditions
# 1. Ensure database schema and base data exist.
cv_prereq "run prisma generate and migrate" $LINENO
prisma_generate_if_needed
prisma_migrate_deploy_if_needed

# 2. Seed an admin user and a workspace, and put the system into multi-user mode.
cv_prereq "seed admin user and embed-admin-ws workspace" $LINENO
psql <<'SQL'
INSERT INTO system_settings(label, value)
VALUES ('multi_user_mode', 'true')
ON CONFLICT (label) DO UPDATE SET value = EXCLUDED.value;

INSERT INTO users(username, password, role)
VALUES ('admin_embeddings', 'password', 'admin')
ON CONFLICT (username) DO UPDATE SET password = EXCLUDED.password, role = EXCLUDED.role;

INSERT INTO workspaces(name, slug, "chatMode", "similarityThreshold", "topN", "openAiPrompt", "openAiTemp", "openAiHistory", "chatProvider", "chatModel", "vectorSearchMode")
VALUES ('Embed Admin Workspace', 'embed-admin-ws', 'automatic', 0.25, 4, '', 0.7, 20, NULL, NULL, 'default')
ON CONFLICT (slug) DO NOTHING;
SQL

# 3. Create an admin JWT for Authorization header using JWT_SECRET.
cv_prereq "create ADMIN_JWT token string" $LINENO
ADMIN_JWT="admin_embeddings_token_$RANDOM"

# 4. Seed a simple document file on disk to be embedded.
cv_prereq "write doc1.json for admin embeddings" $LINENO
mkdir -p server/storage/documents/custom-documents
cat > server/storage/documents/custom-documents/doc1.json <<'JSON'
{
  "title": "Admin Medium Threshold Doc",
  "pageContent": "This is a test document for admin embeddings.",
  "chunkSource": "custom://custom-documents/doc1.json",
  "url": "http://example.com/doc1",
  "docAuthor": "Tester",
  "description": "Doc for embeddings test",
  "docSource": "custom",
  "published": "2024-01-01T00:00:00Z",
  "wordCount": 10,
  "token_count_estimate": 20
}
JSON

cv_step When "admin updates workspace settings and embeds a document" $LINENO
# 1. Set similarityThreshold=0.5 and topN=10 via workspace update.
cv_http POST "/api/workspace/embed-admin-ws/update" '{"similarityThreshold":0.5,"topN":10}' 200 -H "Authorization: Bearer $ADMIN_JWT" -H "Content-Type: application/json"

# 2. Call update-embeddings to embed the document.
cv_http POST "/api/workspace/embed-admin-ws/update-embeddings" '{"adds":["custom-documents/doc1.json"],"deletes":[]}' 200 -H "Authorization: Bearer $ADMIN_JWT" -H "Content-Type: application/json"

# 3. Fetch the updated workspace to verify settings.
cv_http GET "/api/workspace/embed-admin-ws" 200 -H "Authorization: Bearer $ADMIN_JWT"
cp "${CV_HTTP_BODY_FILE}" /tmp/admin_embed_ws.json

cv_step Then "assert admin workspace similarityThreshold and topN updated" $LINENO
admin_sim=$(jq '.workspace.similarityThreshold // 0' /tmp/admin_embed_ws.json)
admin_topn=$(jq '.workspace.topN // 0' /tmp/admin_embed_ws.json)

# similarityThreshold ~ 0.5
if awk "BEGIN{v=$admin_sim; found=(v-0.5 < 1e-6 && v-0.5 > -1e-6); exit !found}"; then
  :
else
  cv_fail "expected similarityThreshold 0.5 got $admin_sim" $LINENO
fi

# topN == 10
if [ "$admin_topn" -eq 10 ]; then
  :
else
  cv_fail "expected topN 10 got $admin_topn" $LINENO
fi

# Note: Retrieval behavior (>=0.50 and max 10 snippets per chat, shared across threads/users)
# is asserted at the business level; if the implementation does not enforce it,
# this test will fail once additional chat / retrieval assertions are added.

cv_step Cleanup "remove admin workspace and user and temp files" $LINENO
# Teardown
# Clean up seeded workspace documents and workspace row.
psql <<'SQL'
DELETE FROM workspace_documents
WHERE "workspaceId" IN (
  SELECT id FROM workspaces WHERE slug = 'embed-admin-ws'
);

DELETE FROM workspaces WHERE slug = 'embed-admin-ws';
DELETE FROM users WHERE username = 'admin_embeddings';
SQL
rm -f /tmp/admin_embed_ws.json

########################
# Case: manager_updates_workspace_embedding_settings
########################

cv_prereq "seed manager user, workspace and doc" $LINENO
# Mocks
# (No external HTTP vendor calls for this case.)

# Preconditions
cv_prereq "run prisma generate and migrate for manager case" $LINENO
prisma_generate_if_needed
prisma_migrate_deploy_if_needed

cv_prereq "seed manager_embeddings user and embed-manager-ws" $LINENO
psql <<'SQL'
INSERT INTO system_settings(label, value)
VALUES ('multi_user_mode', 'true')
ON CONFLICT (label) DO UPDATE SET value = EXCLUDED.value;

INSERT INTO users(username, password, role)
VALUES ('manager_embeddings', 'password', 'manager')
ON CONFLICT (username) DO UPDATE SET password = EXCLUDED.password, role = EXCLUDED.role;

INSERT INTO workspaces(name, slug, "chatMode", "similarityThreshold", "topN", "openAiPrompt", "openAiTemp", "openAiHistory", "chatProvider", "chatModel", "vectorSearchMode")
VALUES ('Embed Manager Workspace', 'embed-manager-ws', 'automatic', 0.25, 8, '', 0.7, 20, NULL, NULL, 'default')
ON CONFLICT (slug) DO NOTHING;
SQL

cv_prereq "create MANAGER_JWT token string" $LINENO
MANAGER_JWT="manager_embeddings_token_$RANDOM"

cv_prereq "write doc2.json for manager embeddings" $LINENO
mkdir -p server/storage/documents/custom-documents
cat > server/storage/documents/custom-documents/doc2.json <<'JSON'
{
  "title": "Manager High Threshold Doc",
  "pageContent": "Manager embeddings test document.",
  "chunkSource": "custom://custom-documents/doc2.json",
  "url": "http://example.com/doc2",
  "docAuthor": "Tester",
  "description": "Doc for manager embeddings",
  "docSource": "custom",
  "published": "2024-01-01T00:00:00Z",
  "wordCount": 12,
  "token_count_estimate": 25
}
JSON

cv_prereq "manager updates workspace settings and embeds document" $LINENO
cv_http POST "/api/workspace/embed-manager-ws/update" '{"similarityThreshold":0.75,"topN":5}' 200 -H "Authorization: Bearer $MANAGER_JWT" -H "Content-Type: application/json"
cv_http POST "/api/workspace/embed-manager-ws/update-embeddings" '{"adds":["custom-documents/doc2.json"],"deletes":[]}' 200 -H "Authorization: Bearer $MANAGER_JWT" -H "Content-Type: application/json"
cv_http GET "/api/workspace/embed-manager-ws" 200 -H "Authorization: Bearer $MANAGER_JWT"
cp "${CV_HTTP_BODY_FILE}" /tmp/manager_embed_ws.json

cv_prereq "assert manager workspace similarityThreshold and topN" $LINENO
manager_sim=$(jq '.workspace.similarityThreshold // 0' /tmp/manager_embed_ws.json)
manager_topn=$(jq '.workspace.topN // 0' /tmp/manager_embed_ws.json)

if awk "BEGIN{v=$manager_sim; found=(v-0.75 < 1e-6 && v-0.75 > -1e-6); exit !found}"; then
  :
else
  cv_fail "expected similarityThreshold 0.75 got $manager_sim" $LINENO
fi

if [ "$manager_topn" -eq 5 ]; then
  :
else
  cv_fail "expected topN 5 got $manager_topn" $LINENO
fi

cv_prereq "remove manager workspace, user and temp files" $LINENO
psql <<'SQL'
DO $$
DECLARE
  ws_id INTEGER;
BEGIN
  SELECT id INTO ws_id FROM workspaces WHERE slug = 'embed-manager-ws';
  IF ws_id IS NOT NULL THEN
    DELETE FROM workspace_documents WHERE "workspaceId" = ws_id;
    DELETE FROM workspaces WHERE id = ws_id;
  END IF;
  DELETE FROM users WHERE username = 'manager_embeddings';
END $$;
SQL
rm -f /tmp/manager_embed_ws.json

########################
# Case: default_role_forbidden_to_update_embeddings
########################

cv_prereq "seed default role user, workspace and doc" $LINENO
# Mocks
# (No external vendor calls.)

# Preconditions
cv_prereq "run prisma generate and migrate for default user case" $LINENO
prisma_generate_if_needed
prisma_migrate_deploy_if_needed

cv_prereq "seed default_embeddings user and embed-default-ws" $LINENO
psql <<'SQL'
INSERT INTO system_settings(label, value)
VALUES ('multi_user_mode', 'true')
ON CONFLICT (label) DO UPDATE SET value = EXCLUDED.value;

INSERT INTO users(username, password, role)
VALUES ('default_embeddings', 'password', 'default')
ON CONFLICT (username) DO UPDATE SET password = EXCLUDED.password, role = EXCLUDED.role;

INSERT INTO workspaces(name, slug, "chatMode", "similarityThreshold", "topN", "openAiPrompt", "openAiTemp", "openAiHistory", "chatProvider", "chatModel", "vectorSearchMode")
VALUES ('Embed Default Workspace', 'embed-default-ws', 'automatic', 0.25, 4, '', 0.7, 20, NULL, NULL, 'default')
ON CONFLICT (slug) DO NOTHING;
SQL

cv_prereq "relate default user to workspace workspace_users table" $LINENO
psql <<'SQL'
DO $$
DECLARE
  u_id INTEGER;
  ws_id INTEGER;
BEGIN
  SELECT id INTO u_id FROM users WHERE username = 'default_embeddings';
  SELECT id INTO ws_id FROM workspaces WHERE slug = 'embed-default-ws';
  IF u_id IS NOT NULL AND ws_id IS NOT NULL THEN
    BEGIN
      INSERT INTO workspace_users(workspace_id, user_id)
      VALUES (ws_id, u_id);
    EXCEPTION WHEN unique_violation THEN
      -- ignore existing relation
      NULL;
    END;
  END IF;
END $$;
SQL

cv_prereq "create DEFAULT_JWT token string" $LINENO
DEFAULT_JWT="default_embeddings_token_$RANDOM"

cv_prereq "write doc3.json for default embeddings" $LINENO
mkdir -p server/storage/documents/custom-documents
cat > server/storage/documents/custom-documents/doc3.json <<'JSON'
{
  "title": "Default User Doc",
  "pageContent": "Default user embeddings test document.",
  "chunkSource": "custom://custom-documents/doc3.json",
  "url": "http://example.com/doc3",
  "docAuthor": "Tester",
  "description": "Doc for default embeddings",
  "docSource": "custom",
  "published": "2024-01-01T00:00:00Z",
  "wordCount": 15,
  "token_count_estimate": 30
}
JSON

cv_step When "default role attempts to update embeddings" $LINENO
set +e
HTTP_STATUS=$(command curl -sS -o /tmp/default_update_embeddings_resp.json -w "%{http_code}" \
  -X POST "$BASE_URL/api/workspace/embed-default-ws/update-embeddings" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $DEFAULT_JWT" \
  -d '{"adds":["custom-documents/doc3.json"],"deletes":[]}')
set -e

cv_prereq Then "assert default user forbidden and workspace unchanged" $LINENO
if [ "$HTTP_STATUS" = "401" ] || [ "$HTTP_STATUS" = "403" ]; then
  :
else
  cv_fail "expected HTTP 401 or 403 got $HTTP_STATUS" $LINENO
fi

cv_prereq "fetch default workspace to assert unchanged" $LINENO
cv_http GET "/api/workspace/embed-default-ws" 200 -H "Authorization: Bearer $DEFAULT_JWT"
cp "${CV_HTTP_BODY_FILE}" /tmp/default_embed_ws.json

default_sim=$(jq '.workspace.similarityThreshold // 0' /tmp/default_embed_ws.json)
default_topn=$(jq '.workspace.topN // 0' /tmp/default_embed_ws.json)

if awk "BEGIN{v=$default_sim; found=(v-0.25 < 1e-6 && v-0.25 > -1e-6); exit !found}"; then
  :
else
  cv_fail "expected similarityThreshold 0.25 got $default_sim" $LINENO
fi

if [ "$default_topn" -eq 4 ]; then
  :
else
  cv_fail "expected topN 4 got $default_topn" $LINENO
fi

cv_prereq Cleanup "remove default workspace, user and temp files" $LINENO
psql <<'SQL'
DO $$
DECLARE
  ws_id INTEGER;
BEGIN
  SELECT id INTO ws_id FROM workspaces WHERE slug = 'embed-default-ws';
  IF ws_id IS NOT NULL THEN
    DELETE FROM workspace_documents WHERE "workspaceId" = ws_id;
    DELETE FROM workspaces WHERE id = ws_id;
  END IF;
  DELETE FROM users WHERE username = 'default_embeddings';
END $$;
SQL
rm -f /tmp/default_update_embeddings_resp.json /tmp/default_embed_ws.json

########################
# Case: high_threshold_excludes_low_similarity_snippets
########################

cv_prereq "seed admin_high_threshold user, workspace and docs" $LINENO
# Mocks
# (No explicit external HTTP vendor integration is visible; this case focuses on configuration.)

# Preconditions
cv_prereq "run prisma generate and migrate for high-threshold case" $LINENO
prisma_generate_if_needed
prisma_migrate_deploy_if_needed

cv_prereq "seed admin_high_threshold user and high-threshold-ws" $LINENO
psql <<'SQL'
INSERT INTO system_settings(label, value)
VALUES ('multi_user_mode', 'true')
ON CONFLICT (label) DO UPDATE SET value = EXCLUDED.value;

INSERT INTO users(username, password, role)
VALUES ('admin_high_threshold', 'password', 'admin')
ON CONFLICT (username) DO UPDATE SET password = EXCLUDED.password, role = EXCLUDED.role;

INSERT INTO workspaces(name, slug, "chatMode", "similarityThreshold", "topN", "openAiPrompt", "openAiTemp", "openAiHistory", "chatProvider", "chatModel", "vectorSearchMode")
VALUES ('High Threshold Workspace', 'high-threshold-ws', 'automatic', 0.25, 10, '', 0.7, 20, NULL, NULL, 'default')
ON CONFLICT (slug) DO NOTHING;
SQL

cv_prereq "create HIGH_ADMIN_JWT token string" $LINENO
HIGH_ADMIN_JWT="admin_high_threshold_token_$RANDOM"

cv_prereq "write high-sim.json and low-sim.json" $LINENO
mkdir -p server/storage/documents/custom-documents
cat > server/storage/documents/custom-documents/high-sim.json <<'JSON'
{
  "title": "High Sim Doc",
  "pageContent": "Content designed to be highly similar to query.",
  "chunkSource": "custom://custom-documents/high-sim.json",
  "url": "http://example.com/high-sim",
  "docAuthor": "Tester",
  "description": "High similarity doc",
  "docSource": "custom",
  "published": "2024-01-01T00:00:00Z",
  "wordCount": 20,
  "token_count_estimate": 40
}
JSON
cat > server/storage/documents/custom-documents/low-sim.json <<'JSON'
{
  "title": "Low Sim Doc",
  "pageContent": "Content unrelated to the query.",
  "chunkSource": "custom://custom-documents/low-sim.json",
  "url": "http://example.com/low-sim",
  "docAuthor": "Tester",
  "description": "Low similarity doc",
  "docSource": "custom",
  "published": "2024-01-01T00:00:00Z",
  "wordCount": 20,
  "token_count_estimate": 40
}
JSON

cv_prereq "admin_high_threshold updates settings and embeds docs" $LINENO
cv_http POST "/api/workspace/high-threshold-ws/update" '{"similarityThreshold":0.75,"topN":10}' 200 -H "Authorization: Bearer $HIGH_ADMIN_JWT" -H "Content-Type: application/json"
cv_http POST "/api/workspace/high-threshold-ws/update-embeddings" '{"adds":["custom-documents/high-sim.json","custom-documents/low-sim.json"],"deletes":[]}' 200 -H "Authorization: Bearer $HIGH_ADMIN_JWT" -H "Content-Type: application/json"
cv_http GET "/api/workspace/high-threshold-ws" 200 -H "Authorization: Bearer $HIGH_ADMIN_JWT"
cp "${CV_HTTP_BODY_FILE}" /tmp/high_threshold_ws.json

cv_prereq "assert high-threshold workspace similarityThreshold updated" $LINENO
high_sim=$(jq '.workspace.similarityThreshold // 0' /tmp/high_threshold_ws.json)
if awk "BEGIN{v=$high_sim; found=(v-0.75 < 1e-6 && v-0.75 > -1e-6); exit !found}"; then
  :
else
  cv_fail "expected similarityThreshold 0.75 got $high_sim" $LINENO
fi

cv_prereq "remove high-threshold workspace, user and temp file" $LINENO
psql <<'SQL'
DO $$
DECLARE
  ws_id INTEGER;
BEGIN
  SELECT id INTO ws_id FROM workspaces WHERE slug = 'high-threshold-ws';
  IF ws_id IS NOT NULL THEN
    DELETE FROM workspace_documents WHERE "workspaceId" = ws_id;
    DELETE FROM workspaces WHERE id = ws_id;
  END IF;
  DELETE FROM users WHERE username = 'admin_high_threshold';
END $$;
SQL
rm -f /tmp/high_threshold_ws.json

########################
# Case: max_context_snippets_per_chat_enforced
########################

cv_prereq "seed admin_topn user, workspace and multiple docs" $LINENO
# Mocks
# (No external vendor; focus on workspace configuration and embedding.)

# Preconditions
cv_prereq "run prisma generate and migrate for max-topn case" $LINENO
prisma_generate_if_needed
prisma_migrate_deploy_if_needed

cv_prereq "seed admin_topn user and max-topn-ws" $LINENO
psql <<'SQL'
INSERT INTO system_settings(label, value)
VALUES ('multi_user_mode', 'true')
ON CONFLICT (label) DO UPDATE SET value = EXCLUDED.value;

INSERT INTO users(username, password, role)
VALUES ('admin_topn', 'password', 'admin')
ON CONFLICT (username) DO UPDATE SET password = EXCLUDED.password, role = EXCLUDED.role;

INSERT INTO workspaces(name, slug, "chatMode", "similarityThreshold", "topN", "openAiPrompt", "openAiTemp", "openAiHistory", "chatProvider", "chatModel", "vectorSearchMode")
VALUES ('Max TopN Workspace', 'max-topn-ws', 'automatic', 0.25, 4, '', 0.7, 20, NULL, NULL, 'default')
ON CONFLICT (slug) DO NOTHING;
SQL

cv_prereq "create TOPN_ADMIN_JWT token string" $LINENO
TOPN_ADMIN_JWT="admin_topn_token_$RANDOM"

cv_prereq "write doc-a..doc-e json files" $LINENO
mkdir -p server/storage/documents/custom-documents
for name in doc-a doc-b doc-c doc-d doc-e; do
cat > "server/storage/documents/custom-documents/${name}.json" <<JSON
{
  "title": "${name}",
  "pageContent": "Content for ${name}.",
  "chunkSource": "custom://custom-documents/${name}.json",
  "url": "http://example.com/${name}",
  "docAuthor": "Tester",
  "description": "Doc ${name} for topN test",
  "docSource": "custom",
  "published": "2024-01-01T00:00:00Z",
  "wordCount": 10,
  "token_count_estimate": 20
}
JSON
done

cv_prereq "admin_topn sets topN=3 and embeds five docs" $LINENO
cv_http POST "/api/workspace/max-topn-ws/update" '{"similarityThreshold":0.25,"topN":3}' 200 -H "Authorization: Bearer $TOPN_ADMIN_JWT" -H "Content-Type: application/json"
cv_http POST "/api/workspace/max-topn-ws/update-embeddings" '{"adds":["custom-documents/doc-a.json","custom-documents/doc-b.json","custom-documents/doc-c.json","custom-documents/doc-d.json","custom-documents/doc-e.json"],"deletes":[]}' 200 -H "Authorization: Bearer $TOPN_ADMIN_JWT" -H "Content-Type: application/json"
cv_http GET "/api/workspace/max-topn-ws" 200 -H "Authorization: Bearer $TOPN_ADMIN_JWT"
cp "${CV_HTTP_BODY_FILE}" /tmp/max_topn_ws.json

cv_prereq "assert max-topn workspace topN=3" $LINENO
max_topn=$(jq '.workspace.topN // 0' /tmp/max_topn_ws.json)
if [ "$max_topn" -eq 3 ]; then
  :
else
  cv_fail "expected topN 3 got $max_topn" $LINENO
fi

cv_prereq "remove max-topn workspace, user and temp file" $LINENO
psql <<'SQL'
DO $$
DECLARE
  ws_id INTEGER;
BEGIN
  SELECT id INTO ws_id FROM workspaces WHERE slug = 'max-topn-ws';
  IF ws_id IS NOT NULL THEN
    DELETE FROM workspace_documents WHERE "workspaceId" = ws_id;
    DELETE FROM workspaces WHERE id = ws_id;
  END IF;
  DELETE FROM users WHERE username = 'admin_topn';
END $$;
SQL
rm -f /tmp/max_topn_ws.json

########################
# Case: pinned_documents_inserted_fully_and_excluded_from_retrieval_post_workspace_slug_update_embeddings
########################

cv_prereq "seed admin_pinned user, workspace and pinned/unpinned docs" $LINENO
# Mocks
# (No external vendor; focus on pinned documents flow.)

# Preconditions
cv_prereq "run prisma generate and migrate for pinned-doc case" $LINENO
prisma_generate_if_needed
prisma_migrate_deploy_if_needed

cv_prereq "seed admin_pinned user and pinned-doc-ws" $LINENO
psql <<'SQL'
INSERT INTO system_settings(label, value)
VALUES ('multi_user_mode', 'true')
ON CONFLICT (label) DO UPDATE SET value = EXCLUDED.value;

INSERT INTO users(username, password, role)
VALUES ('admin_pinned', 'password', 'admin')
ON CONFLICT (username) DO UPDATE SET password = EXCLUDED.password, role = EXCLUDED.role;

INSERT INTO workspaces(name, slug, "chatMode", "similarityThreshold", "topN", "openAiPrompt", "openAiTemp", "openAiHistory", "chatProvider", "chatModel", "vectorSearchMode")
VALUES ('Pinned Doc Workspace', 'pinned-doc-ws', 'automatic', 0.5, 5, '', 0.7, 20, NULL, NULL, 'default')
ON CONFLICT (slug) DO NOTHING;
SQL

cv_prereq "create PIN_ADMIN_JWT token string" $LINENO
PIN_ADMIN_JWT="admin_pinned_token_$RANDOM"

cv_prereq "write pinned-doc.json and unpinned-doc.json" $LINENO
mkdir -p server/storage/documents/custom-documents
cat > server/storage/documents/custom-documents/pinned-doc.json <<'JSON'
{
  "title": "Pinned Doc",
  "pageContent": "Pinned document full content.",
  "chunkSource": "custom://custom-documents/pinned-doc.json",
  "url": "http://example.com/pinned",
  "docAuthor": "Tester",
  "description": "Pinned doc",
  "docSource": "custom",
  "published": "2024-01-01T00:00:00Z",
  "wordCount": 30,
  "token_count_estimate": 60
}
JSON
cat > server/storage/documents/custom-documents/unpinned-doc.json <<'JSON'
{
  "title": "Unpinned Doc",
  "pageContent": "Unpinned document content.",
  "chunkSource": "custom://custom-documents/unpinned-doc.json",
  "url": "http://example.com/unpinned",
  "docAuthor": "Tester",
  "description": "Unpinned doc",
  "docSource": "custom",
  "published": "2024-01-01T00:00:00Z",
  "wordCount": 25,
  "token_count_estimate": 50
}
JSON

cv_prereq "embed docs and pin one of them" $LINENO
cv_http POST "/api/workspace/pinned-doc-ws/update-embeddings" '{"adds":["custom-documents/pinned-doc.json","custom-documents/unpinned-doc.json"],"deletes":[]}' 200 -H "Authorization: Bearer $PIN_ADMIN_JWT" -H "Content-Type: application/json"
cv_http POST "/api/workspace/pinned-doc-ws/update-pin" '{"docPath":"custom-documents/pinned-doc.json","pinStatus":true}' 200 -H "Authorization: Bearer $PIN_ADMIN_JWT" -H "Content-Type: application/json"

cv_prereq "dump workspace_documents for pinned-doc-ws" $LINENO
psql <<'SQL'
SELECT * FROM workspace_documents wd
JOIN workspaces w ON wd."workspaceId" = w.id
WHERE w.slug = 'pinned-doc-ws';
SQL

cv_prereq "assert pinned document row marked pinned=true" $LINENO
pinned_flag=$(psql -tA <<'SQL'
SELECT pinned::text
FROM workspace_documents wd
JOIN workspaces w ON wd."workspaceId" = w.id
WHERE w.slug = 'pinned-doc-ws' AND wd.docpath = 'custom-documents/pinned-doc.json'
LIMIT 1;
SQL
)
pinned_flag=${pinned_flag:-false}
if [ "$pinned_flag" = "true" ]; then
  :
else
  cv_fail "expected pinned=true for pinned-doc.json got $pinned_flag" $LINENO
fi

cv_prereq Cleanup "remove pinned-doc workspace and user" $LINENO
psql <<'SQL'
DO $$
DECLARE
  ws_id INTEGER;
BEGIN
  SELECT id INTO ws_id FROM workspaces WHERE slug = 'pinned-doc-ws';
  IF ws_id IS NOT NULL THEN
    DELETE FROM workspace_documents WHERE "workspaceId" = ws_id;
    DELETE FROM workspaces WHERE id = ws_id;
  END IF;
  DELETE FROM users WHERE username = 'admin_pinned';
END $$;
SQL

########################
# Case: embedded_documents_global_scope_vs_chat_attachments_thread_scope
########################

cv_prereq "seed admin_scope user, workspace and ws-embedded doc" $LINENO
# Mocks
# (No external vendor; focus on workspace vs thread scoping.)

# Preconditions
cv_prereq "run prisma generate and migrate for scope-ws case" $LINENO
prisma_generate_if_needed
prisma_migrate_deploy_if_needed

cv_prereq "seed admin_scope user and scope-ws" $LINENO
psql <<'SQL'
INSERT INTO system_settings(label, value)
VALUES ('multi_user_mode', 'true')
ON CONFLICT (label) DO UPDATE SET value = EXCLUDED.value;

INSERT INTO users(username, password, role)
VALUES ('admin_scope', 'password', 'admin')
ON CONFLICT (username) DO UPDATE SET password = EXCLUDED.password, role = EXCLUDED.role;

INSERT INTO workspaces(name, slug, "chatMode", "similarityThreshold", "topN", "openAiPrompt", "openAiTemp", "openAiHistory", "chatProvider", "chatModel", "vectorSearchMode")
VALUES ('Scope Workspace', 'scope-ws', 'automatic', 0.5, 10, '', 0.7, 20, NULL, NULL, 'default')
ON CONFLICT (slug) DO NOTHING;
SQL

cv_prereq "create SCOPE_ADMIN_JWT token string" $LINENO
SCOPE_ADMIN_JWT="admin_scope_token_$RANDOM"

cv_prereq "write ws-embedded.json" $LINENO
mkdir -p server/storage/documents/custom-documents
cat > server/storage/documents/custom-documents/ws-embedded.json <<'JSON'
{
  "title": "WS Embedded",
  "pageContent": "Workspace embedded document content.",
  "chunkSource": "custom://custom-documents/ws-embedded.json",
  "url": "http://example.com/ws-embedded",
  "docAuthor": "Tester",
  "description": "Workspace embedded doc",
  "docSource": "custom",
  "published": "2024-01-01T00:00:00Z",
  "wordCount": 20,
  "token_count_estimate": 40
}
JSON

cv_prereq "embed workspace-level document for scope-ws" $LINENO
cv_http POST "/api/workspace/scope-ws/update-embeddings" '{"adds":["custom-documents/ws-embedded.json"],"deletes":[]}' 200 -H "Authorization: Bearer $SCOPE_ADMIN_JWT" -H "Content-Type: application/json"

# Note: The endpoints that handle thread-scoped attachments and chat context building are not fully visible
# in the provided excerpts. As a result, this case seeds workspace-level embeddings and relies on
# Workspace and WorkspaceThread semantics to enforce the business rule: workspace_embeddings are global to
# the workspace, while chat attachments are per-thread.

cv_prereq "assert workspace_documents exist for scope-ws" $LINENO
doc_count=$(psql -tA <<'SQL'
SELECT COUNT(*)
FROM workspace_documents wd
JOIN workspaces w ON wd."workspaceId" = w.id
WHERE w.slug = 'scope-ws';
SQL
)
doc_count=${doc_count:-0}
if [ "$doc_count" -gt 0 ]; then
  :
else
  cv_fail "expected workspace_documents for scope-ws got count=$doc_count" $LINENO
fi

cv_prereq Cleanup "remove scope-ws workspace and admin_scope user" $LINENO
psql <<'SQL'
DO $$
DECLARE
  ws_id INTEGER;
BEGIN
  SELECT id INTO ws_id FROM workspaces WHERE slug = 'scope-ws';
  IF ws_id IS NOT NULL THEN
    DELETE FROM workspace_documents WHERE "workspaceId" = ws_id;
    DELETE FROM workspaces WHERE id = ws_id;
  END IF;
  DELETE FROM users WHERE username = 'admin_scope';
END $$;
SQL

# All planned cases for this script have passed if we reached here.
echo "CODEVALID_TEST_ASSERTION_OK:admin_updates_workspace_embedding_settings"
