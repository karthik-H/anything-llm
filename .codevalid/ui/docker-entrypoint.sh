#!/usr/bin/env bash
# docker-entrypoint.sh
#
# Starts the mock API server and the Vite dev server, waits until both are
# ready, then hands control to the CMD / ENTRYPOINT arguments (Playwright).
#
# This script is NOT the ENTRYPOINT itself – it is sourced by the shell wrapper
# used when the Dockerfile overrides the entrypoint with `exec "$@"`.

set -e

APP_ROOT="${APP_ROOT:-/app}"

# ── 1. Start mock API server (port 3001) ──────────────────────────────────────
echo "[entrypoint] Starting mock API server on port 3001..."
node "${APP_ROOT}/.codevalid/ui/mock/mock-server.js" &
MOCK_PID=$!

# ── 2. Start Vite dev server (port 5174) ──────────────────────────────────────
echo "[entrypoint] Starting Vite dev server on port 5174..."
cd "${APP_ROOT}" && npm run dev:frontend -- --port 5174 --strictPort --host 0.0.0.0 &
VITE_PID=$!

# ── 3. Wait for mock server ────────────────────────────────────────────────────
echo "[entrypoint] Waiting for mock server..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:3001/api/ping > /dev/null 2>&1; then
        echo "[entrypoint] Mock server is up."
        break
    fi
    sleep 1
done

# ── 4. Wait for Vite dev server ────────────────────────────────────────────────
echo "[entrypoint] Waiting for Vite dev server..."
for i in $(seq 1 60); do
    if curl -sf http://localhost:5174 > /dev/null 2>&1; then
        echo "[entrypoint] Vite dev server is up."
        break
    fi
    sleep 2
done

# ── 5. Run Playwright tests ────────────────────────────────────────────────────
echo "[entrypoint] Running Playwright tests..."
exec "$@"
