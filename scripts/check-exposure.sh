#!/usr/bin/env bash
# check-exposure.sh - php2shell (CVE-2026-109618 / CVE-2026-109619) interim exposure check
#
# Drops a temporary, token-protected probe into your webroot, requests it through
# your web server, reports what the *web* SAPI is actually running with, and
# deletes the probe. It does not send any exploit traffic.
#
# Usage:
#   check-exposure.sh --webroot /var/www/html --url https://example.com [--insecure]
#   check-exposure.sh --cli        # CLI-only check (less reliable, see README)
#
# Exit codes: 0 = mitigated, 2 = exposed, 1 = error / unknown

set -euo pipefail

WEBROOT=""
URL=""
INSECURE=""
CLI_ONLY=0

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --webroot)  WEBROOT="${2:-}"; shift 2 ;;
    --url)      URL="${2%/}"; shift 2 ;;
    --insecure) INSECURE="-k"; shift ;;
    --cli)      CLI_ONLY=1; shift ;;
    -h|--help)  usage ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

PROBE_PHP='<?php
if (!isset($_GET["t"]) || !hash_equals("__TOKEN__", (string)$_GET["t"])) { http_response_code(404); exit; }
header("Content-Type: text/plain");
echo "probe=ok\n";
echo "version=" . PHP_VERSION . "\n";
echo "sapi=" . PHP_SAPI . "\n";
echo "ini_file=" . (php_ini_loaded_file() ?: "none") . "\n";
echo "upload_progress=" . (int)filter_var(ini_get("session.upload_progress.enabled"), FILTER_VALIDATE_BOOLEAN) . "\n";
echo "session_ext=" . (int)extension_loaded("session") . "\n";
'

get() { grep -m1 "^$1=" <<<"$RESULT" | cut -d= -f2- || true; }

if [[ $CLI_ONLY -eq 1 ]]; then
  command -v php >/dev/null || { red "php not found in PATH"; exit 1; }
  yellow "CLI-only mode: the CLI may load a different php.ini than your web server."
  TMP_PROBE="$(mktemp --suffix=.php)"
  trap 'rm -f -- "$TMP_PROBE"' EXIT
  printf '%s' "${PROBE_PHP/__TOKEN__/cli}" > "$TMP_PROBE"
  RESULT="$(php -d display_errors=0 -r '$_GET["t"]="cli"; include $argv[1];' "$TMP_PROBE" 2>/dev/null || true)"
else
  [[ -n "$WEBROOT" && -n "$URL" ]] || { red "--webroot and --url are required (or use --cli)"; usage; }
  [[ -d "$WEBROOT" ]] || { red "Webroot not found: $WEBROOT"; exit 1; }
  command -v curl >/dev/null || { red "curl is required"; exit 1; }

  TOKEN="$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  PROBE_NAME=".php2shell-check-${TOKEN:0:12}.php"
  PROBE_PATH="${WEBROOT%/}/$PROBE_NAME"

  cleanup() { rm -f -- "$PROBE_PATH"; }
  trap cleanup EXIT INT TERM

  printf '%s' "${PROBE_PHP/__TOKEN__/$TOKEN}" > "$PROBE_PATH"
  chmod 0644 "$PROBE_PATH"
  chown --reference="$WEBROOT" "$PROBE_PATH" 2>/dev/null || true

  HTTP_CODE=0
  RESULT="$(curl -sS $INSECURE --max-time 15 -w '\n__HTTP__=%{http_code}' "$URL/$PROBE_NAME?t=$TOKEN" 2>&1 || true)"
  HTTP_CODE="$(grep -o '__HTTP__=[0-9]*' <<<"$RESULT" | cut -d= -f2 || echo 0)"

  cleanup
  trap - EXIT INT TERM

  if [[ "$(get probe)" != "ok" ]]; then
    red "Could not read the probe through the web server (HTTP ${HTTP_CODE:-?})."
    echo "Check that --webroot is the document root served at --url, and that .php files are executed there."
    echo "If the site serves PHP raw or blocks dotfiles, run with --cli as a fallback."
    exit 1
  fi
fi

[[ "$(get probe)" == "ok" ]] || { red "Probe failed."; exit 1; }

VERSION="$(get version)"
SAPI="$(get sapi)"
INI_FILE="$(get ini_file)"
UPLOAD_PROGRESS="$(get upload_progress)"
SESSION_EXT="$(get session_ext)"

echo
echo "PHP version : $VERSION"
echo "SAPI        : $SAPI"
echo "php.ini     : $INI_FILE"
echo "session ext : $([[ $SESSION_EXT == 1 ]] && echo loaded || echo 'not loaded')"
echo "upload_progress.enabled : $([[ $UPLOAD_PROGRESS == 1 ]] && echo On || echo Off)"
echo

MAJOR="${VERSION%%.*}"
MINOR="$(cut -d. -f2 <<<"$VERSION")"
if (( MAJOR < 8 || (MAJOR == 8 && MINOR < 2) )); then
  yellow "PHP $MAJOR.$MINOR is end of life and will not receive an official fix. Plan an upgrade."
fi
yellow "Compare $VERSION against the official PHP advisory once it is published."
echo

if [[ "$SESSION_EXT" != 1 ]]; then
  green "Session extension not loaded: the reported upload_progress vector does not apply."
  exit 0
elif [[ "$UPLOAD_PROGRESS" == 1 ]]; then
  red "EXPOSED (likely): session.upload_progress.enabled is On."
  echo "Apply the interim mitigation for your stack: see mitigations/ in this repo."
  exit 2
else
  green "MITIGATED (interim): session.upload_progress.enabled is Off."
  echo "This is not a confirmed fix. Patch PHP as soon as the official release is out."
  exit 0
fi
