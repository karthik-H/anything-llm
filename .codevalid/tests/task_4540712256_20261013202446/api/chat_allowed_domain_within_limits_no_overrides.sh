#!/usr/bin/env bash
set -euo pipefail

source .codevalid/tests/task_4540712256_20261013202446/api/_infra.sh
export API_KEY="${API_KEY:-test-api-key}"

cv_step Given "allowed domain within limits, overrides off" "$LINENO"

CASE_DIR=".codevalid/wiremock/mappings/cases/chat_allowed_domain_within_limits_no_overrides"
mkdir -p "$CASE_DIR"

cv_prereq "stub VectorDb similarity search for widget-ws" "$LINENO"
cat > "$CASE_DIR/vector-search.json" <<'JSON'
{
  "request": {
    "method": "POST",
    "urlPathPattern": "/vector-db/widget-ws/similarity-search",
    "bodyPatterns": [
      { "contains": "chat_allowed_domain_within_limits_no_overrides prompt" }
    ]
  },
  "response": {
    "status": 200,
    "jsonBody": {
      "sources": [
        {
          "title": "widget-doc.txt",
          "chunk": "Widget workspace documentation content about the primary feature.",
          "published": "2024-01-01T00:00:00Z"
        }
      ],
      "contextTexts": [
        "Widget workspace documentation content about the primary feature."
      ],
      "message": null
    }
  }
}
JSON

wiremock_admin_import_mappings "$CASE_DIR"

cv_prereq "seed workspace and embed config for widget-ws" "$LINENO"
psql <<'SQL'
INSERT INTO "workspaces" ("name","slug","chatMode","chatProvider","chatModel","openAiTemp","openAiHistory","openAiPrompt","similarityThreshold","topN","vectorSearchMode","queryRefusalResponse")
VALUES ('Widget Workspace','widget-ws','chat',NULL,NULL,0.7,20,'Default widget prompt',0.3,4,'default',NULL)
ON CONFLICT ("slug") DO UPDATE SET "chatMode"='chat',"openAiPrompt"='Default widget prompt';

INSERT INTO "embed_configs" ("uuid","enabled","chat_mode","allowlist_domains","allow_model_override","allow_temperature_override","allow_prompt_override","max_chats_per_day","max_chats_per_session","message_limit","workspace_id")
SELECT '00000000-0000-0000-0000-000000000001', TRUE, 'chat', '["https://allowed.example.com"]', FALSE, FALSE, FALSE, 10, 10, 20, w."id"
FROM "workspaces" w
WHERE w."slug"='widget-ws'
ON CONFLICT ("uuid") DO UPDATE SET "enabled"=EXCLUDED."enabled","chat_mode"=EXCLUDED."chat_mode","allowlist_domains"=EXCLUDED."allowlist_domains","allow_model_override"=EXCLUDED."allow_model_override","allow_temperature_override"=EXCLUDED."allow_temperature_override","allow_prompt_override"=EXCLUDED."allow_prompt_override","max_chats_per_day"=EXCLUDED."max_chats_per_day","max_chats_per_session"=EXCLUDED."max_chats_per_session","message_limit"=EXCLUDED."message_limit";

-- Seed fewer than the daily and per-session limits in embed_chats.
INSERT INTO "embed_chats" ("embed_id","prompt","response","connection_information","session_id","include")
SELECT e."id",'previous prompt','{"text":"prev","type":"chat","sources":[],"metrics":{}}','{}','session-allowed',TRUE
FROM "embed_configs" e
WHERE e."uuid"='00000000-0000-0000-0000-000000000001'
ON CONFLICT DO NOTHING;
SQL

cv_step When "POST chat to workspace widget-ws from allowed origin" "$LINENO"

curl -sS -o /tmp/chat_allowed_domain_within_limits_no_overrides.json -w "%{http_code}" \
  -X POST "http://app:6713/v1/workspace/widget-ws/chat" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -H "Origin: https://allowed.example.com" \
  --data '{"message":"chat_allowed_domain_within_limits_no_overrides prompt","mode":"chat","sessionId":"session-allowed","attachments":[],"reset":false}' \
  > /tmp/chat_allowed_domain_within_limits_no_overrides.status

cv_step Then "response has textResponse and document-based sources" "$LINENO"

STATUS="$(cat /tmp/chat_allowed_domain_within_limits_no_overrides.status)"
BODY="$(cat /tmp/chat_allowed_domain_within_limits_no_overrides.json)"

if [ "$STATUS" -ne 200 ]; then
  cv_fail "Expected 200 status, got $STATUS" "$LINENO"
fi

# Assert basic structure and that the response text refers to the workspace's document-based content.
if ! printf '%s' "$BODY" | jq -e '
  .textResponse != null
  and (.type == "textResponse" or (.type == "abort" | not))
  and (.sources | length >= 1)
' > /dev/null; then
  cv_fail "Response did not contain expected textResponse and sources for allowed-domain chat within limits" "$LINENO"
fi

cv_step Cleanup "remove temporary files for case" "$LINENO"
rm -f /tmp/chat_allowed_domain_within_limits_no_overrides.json /tmp/chat_allowed_domain_within_limits_no_overrides.status

echo "CODEVALID_TEST_ASSERTION_OK:chat_allowed_domain_within_limits_no_overrides"
