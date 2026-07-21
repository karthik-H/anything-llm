#!/usr/bin/env bash
set -uo pipefail
RESULT_JSON="/tmp/codevalid-promptfoo-results.json"
rm -f "$RESULT_JSON"

# promptfoo exits 100 on assertion failures; do not use set -e here or the JSON export below is skipped.
set +e
promptfoo eval "$@" \
  --verbose \
  --no-table \
  --no-share \
  --no-write \
  -o "$RESULT_JSON"
rc=$?
set -e

echo "===CODEVALID_PROMPTFOO_JSON==="
if [[ -f "$RESULT_JSON" ]]; then
  cat "$RESULT_JSON"
fi
exit "$rc"
