#!/usr/bin/env bash
set -euo pipefail

# 1. Wait for each dependency *through toxiproxy* (host:port pairs from env).
for hp in ${WAIT_FOR_TCP:-}; do
  host="${hp%%:*}"; port="${hp##*:}"
  echo "waiting for ${host}:${port} ..."
  until nc -z "$host" "$port"; do sleep 1; done
done

# 2. Run migrations / schema sync (see §6.4).
${MIGRATE_CMD:-true}

# 3. Hand off to the real server on 6713.
exec "$@"
