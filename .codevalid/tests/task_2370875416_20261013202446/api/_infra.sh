#!/usr/bin/env bash
set -euo pipefail

export WIREMOCK_ADMIN_URL="${WIREMOCK_ADMIN_URL:-http://wiremock:8080}"
export BASE_URL="${BASE_URL:-http://app:6713}"
export JWT_SECRET="${JWT_SECRET:-}"
export AUTH_TOKEN="${AUTH_TOKEN:-}"
export JWT_EXPIRY="${JWT_EXPIRY:-}"
export DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
export COLLECTOR_BASE_URL="${COLLECTOR_BASE_URL:-http://wiremock:8080}"
export WAIT_FOR_TCP="${WAIT_FOR_TCP:-toxiproxy:5432}"
export APP_BASE_URL="${APP_BASE_URL:-http://app:6713}"
wiremock_admin_import_mappings() {
  local dir="$1" f
  for f in "$dir"/*.json; do
    [ -e "$f" ] || { echo "no mappings in $dir" >&2; return 1; }
    curl -sS -f -o /dev/null -X POST "$WIREMOCK_ADMIN_URL/__admin/mappings" \
      -H 'Content-Type: application/json' --data-binary @"$f" \
      || { echo "wiremock import failed: $f" >&2; return 1; }
  done
}

# --- CodeValid diagnosis markers (parsed by the test runner; do not edit) ---
# cv_step  <Given|When|Then|Cleanup> "<what this section does>" $LINENO
# cv_prereq "<setup being done>" $LINENO
# cv_http  <METHOD> <url|/path> [json-body] [expected-status] [extra curl args, e.g. -H "Authorization: Bearer $T"]
#          performs the request (relative paths go to $BASE_URL), prints REQUEST_*/RESPONSE_*
#          and CV_HTTP|METHOD|url|status|ms, sets CV_HTTP_STATUS CV_HTTP_BODY CV_HTTP_MS
#          CV_HTTP_BODY_FILE CV_HTTP_HEADERS_FILE. Call it directly, never inside $(...).
#          A 3-digit expected-status (with or without a body) is asserted: a different status
#          fails the test via cv_fail. Omit it to assert on $CV_HTTP_STATUS yourself.
# cv_http  <METHOD> <url> <http_status>          (legacy: marker only, right after your own curl)
# cv_fail  "<expected X got Y>" $LINENO           (prints marker, exits 1)
cv_step() { printf 'CV_STEP|%s|%s|line=%s\n' "${1:-}" "${2:-}" "${3:-}"; }
cv_prereq() { printf 'CV_PREREQ|%s|line=%s\n' "${1:-}" "${2:-}"; }
cv_fail() { printf 'CV_ASSERT_FAIL|%s|line=%s\n' "${1:-}" "${2:-}"; exit 1; }
_cv_is_int() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
_cv_now_ms() {
  _cv_n=${EPOCHREALTIME:-}
  if [ -n "$_cv_n" ]; then _cv_secs_to_ms "$_cv_n"; return 0; fi
  _cv_n=$(date +%s%3N 2>/dev/null || true)
  _cv_is_int "$_cv_n" || _cv_n=$(( $(date +%s) * 1000 ))
  printf '%s' "$_cv_n"
}
_cv_ms_file() { printf '%s/.cv_last_ms.%s' "${TMPDIR:-/tmp}" "$$"; }
curl() {
  _cv_t0=$(_cv_now_ms)
  _cv_rc=0
  command curl "$@" || _cv_rc=$?
  _cv_t1=$(_cv_now_ms)
  printf '%s' "$((_cv_t1 - _cv_t0))" > "$(_cv_ms_file)" 2>/dev/null || :
  return $_cv_rc
}
# psql without a connection falls back to a local socket seed-test does not have; when
# DATABASE_URL is set and the call names no connection, connect through it.
psql() {
  if [ -n "${DATABASE_URL:-}" ]; then
    case " $* " in
      *" $DATABASE_URL "*|*" -h "*|*" --host"*|*" -d "*|*" --dbname"*|*"postgres://"*|*"postgresql://"*) ;;
      *) command psql "$DATABASE_URL" "$@"; return $? ;;
    esac
  fi
  command psql "$@"
}
_cv_secs_to_ms() {
  _cv_t=$(printf '%s' "${1:-0}" | tr ',' '.')
  _cv_s=${_cv_t%%.*}
  case "$_cv_t" in *.*) _cv_f=${_cv_t#*.}000 ;; *) _cv_f=000 ;; esac
  _cv_f=${_cv_f%"${_cv_f#???}"}
  while [ "${_cv_f#0}" != "$_cv_f" ]; do _cv_f=${_cv_f#0}; done
  _cv_is_int "$_cv_s" || _cv_s=0
  _cv_is_int "$_cv_f" || _cv_f=0
  printf '%s' "$(( _cv_s * 1000 + _cv_f ))"
}
_cv_is_status() { _cv_is_int "${1:-}" && [ ${#1} -eq 3 ]; }
cv_http() {
  if [ $# -ge 3 ] && [ $# -le 4 ] && _cv_is_status "$3" && { [ $# -eq 3 ] || _cv_is_int "$4"; }      && { [ -n "${4:-}" ] || [ -f "$(_cv_ms_file)" ]; }; then
    _cv_ms=${4:-}
    if [ -z "$_cv_ms" ] && [ -f "$(_cv_ms_file)" ]; then
      _cv_ms=$(cat "$(_cv_ms_file)" 2>/dev/null || true)
      rm -f "$(_cv_ms_file)" 2>/dev/null || :
    fi
    _cv_is_int "$_cv_ms" || _cv_ms=''
    printf 'CV_HTTP|%s|%s|%s%s\n' "$1" "$2" "$3" "${_cv_ms:+|$_cv_ms}"
    return 0
  fi
  _cv_method=${1:-GET}
  _cv_url=${2:-/}
  _cv_data=''
  _cv_expect=''
  if [ $# -ge 2 ]; then shift 2; else shift $#; fi
  if [ $# -ge 1 ] && ! _cv_is_status "$1"; then
    case "$1" in -*) ;; *) _cv_data=$1; shift ;; esac
  fi
  if [ $# -ge 1 ] && _cv_is_status "$1"; then _cv_expect=$1; shift; fi
  case "$_cv_url" in /*) _cv_url="${BASE_URL:-http://app:6713}$_cv_url" ;; esac
  CV_HTTP_BODY_FILE="${TMPDIR:-/tmp}/cv_http_body.$$"
  CV_HTTP_HEADERS_FILE="${TMPDIR:-/tmp}/cv_http_headers.$$"
  : > "$CV_HTTP_BODY_FILE"; : > "$CV_HTTP_HEADERS_FILE"
  printf 'REQUEST_HEADERS:\n%s %s\n' "$_cv_method" "$_cv_url"
  printf 'REQUEST_BODY:\n%s\n' "$_cv_data"
  if [ -n "$_cv_data" ]; then
    _cv_w=$(command curl -sS -X "$_cv_method" -H 'Content-Type: application/json' --data "$_cv_data" \
      -D "$CV_HTTP_HEADERS_FILE" -o "$CV_HTTP_BODY_FILE" -w '%{http_code} %{time_total}' "$@" "$_cv_url") || true
  else
    _cv_w=$(command curl -sS -X "$_cv_method" \
      -D "$CV_HTTP_HEADERS_FILE" -o "$CV_HTTP_BODY_FILE" -w '%{http_code} %{time_total}' "$@" "$_cv_url") || true
  fi
  CV_HTTP_STATUS=${_cv_w%% *}
  _cv_is_int "$CV_HTTP_STATUS" || CV_HTTP_STATUS=000
  case "$_cv_w" in *' '*) CV_HTTP_MS=$(_cv_secs_to_ms "${_cv_w#* }") ;; *) CV_HTTP_MS=0 ;; esac
  CV_HTTP_BODY=$(cat "$CV_HTTP_BODY_FILE" 2>/dev/null || true)
  printf 'RESPONSE_HEADERS:\n'; cat "$CV_HTTP_HEADERS_FILE" 2>/dev/null || true
  printf 'RESPONSE_BODY:\n%s\n' "$CV_HTTP_BODY"
  rm -f "$(_cv_ms_file)" 2>/dev/null || :
  printf 'CV_HTTP|%s|%s|%s|%s\n' "$_cv_method" "$_cv_url" "$CV_HTTP_STATUS" "$CV_HTTP_MS"
  if [ -n "$_cv_expect" ] && [ "$CV_HTTP_STATUS" != "$_cv_expect" ]; then
    cv_fail "expected HTTP $_cv_expect from $_cv_method $_cv_url got $CV_HTTP_STATUS: $(printf '%s' "$CV_HTTP_BODY" | head -c 300)" ""
  fi
  return 0
}
# --- end CodeValid diagnosis markers ---


curl_json() {
  # Usage: curl_json <METHOD> <path-or-url> <json-body> <expected-status> [extra curl args...]
  # Paths beginning with / are resolved against $BASE_URL.
  local method=${1:-POST}
  local url=${2:-/}
  local body=${3:-'{}'}
  local expect=${4:-}
  shift 4 || true
  cv_http "$method" "$url" "$body" ${expect:+$expect} "$@"
}

seed_sqlite() {
  # Prisma-based seed helper for the SQLite DB used by the app.
  # This function assumes the current working directory is the app root
  # and that prisma/schema.prisma is present and configured for SQLite.
  if ! command -v npx >/dev/null 2>&1; then
    echo "npx is required to run Prisma commands for seeding" >&2
    return 1
  fi
  # Ensure Prisma client is generated so @prisma/client is available.
  npx prisma generate
  # Apply schema to the SQLite database.
  npx prisma migrate deploy || npx prisma db push
  # Run optional seed script if defined in package.json (e.g. "prisma": { "seed": "node prisma/seed.js" }).
  if npx prisma --help >/dev/null 2>&1; then
    if npx prisma db seed --help >/dev/null 2>&1; then
      npx prisma db seed || true
    fi
  fi
}

health_check() {
  # Health check helper that delegates to the shared seed test health_check.sh script.
  # Expects HEALTH_URL to default to http://app:6713/health when not set.
  local script=".codevalid/seed_test_cases/health_check.sh"
  if [ ! -x "$script" ]; then
    echo "health_check script not found or not executable: $script" >&2
    return 1
  fi
  HEALTH_URL="${HEALTH_URL:-http://app:6713/health}" "$script"
}

auth_login_request_token() {
  # Helper to perform multi-user login via /request-token and capture the JWT token.
  # Usage: auth_login_request_token "<username>" "<password>"
  local username=${1:-}
  local password=${2:-}
  if [ -z "$username" ] || [ -z "$password" ]; then
    echo "usage: auth_login_request_token <username> <password>" >&2
    return 1
  fi

  local body
  body=$(printf '{"username":"%s","password":"%s"}' "$username" "$password")

  cv_http POST "/request-token" "$body" 200

  # Extract token from JSON response body using jq if available.
  if command -v jq >/dev/null 2>&1; then
    AUTH_TOKEN=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.token // empty')
  else
    # Fallback: naive extraction; tests should prefer jq availability.
    AUTH_TOKEN=$(printf '%s' "$CV_HTTP_BODY" | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
  fi

  if [ -z "${AUTH_TOKEN:-}" ]; then
    echo "failed to extract token from /request-token response" >&2
    return 1
  fi

  export AUTH_TOKEN
}
