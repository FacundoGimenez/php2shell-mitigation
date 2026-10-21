#!/usr/bin/env bash
# check-exposure.sh - php2shell (CVE-2026-109618 / CVE-2026-109619) patch and exposure check
#
# Drops a temporary, token-protected probe into your webroot, requests it through
# your web server and reports which PHP build is *actually serving the site*.
# It compares that build against the fixed releases, looks for distro backports
# in the local package changelogs, shows the interim mitigation settings, and
# then deletes the probe. It does not send any exploit traffic.
#
# Usage:
#   check-exposure.sh --webroot /var/www/html --url https://example.com [--insecure]
#   check-exposure.sh --cli        # CLI-only check (less reliable, see README)
#
# Exit codes: 0 = patched, 2 = not patched, 1 = error / unknown

set -euo pipefail

WEBROOT=""
URL=""
INSECURE=""
CLI_ONLY=0

# Fixed upstream releases (PHP Security Advisory, 21 Oct 2026)
declare -A FIXED=([8.2]=8.2.35 [8.3]=8.3.36 [8.4]=8.4.27 [8.5]=8.5.12)
CVES=(CVE-2026-109618 CVE-2026-109619)

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
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
$ini = function ($k) { $v = ini_get($k); return $v === false ? "n/a" : ($v === "" ? "0" : $v); };
echo "probe=ok\n";
echo "pid=" . getmypid() . "\n";
echo "version=" . PHP_VERSION . "\n";
echo "sapi=" . PHP_SAPI . "\n";
echo "ini_file=" . (php_ini_loaded_file() ?: "none") . "\n";
echo "session_ext=" . (int)extension_loaded("session") . "\n";
echo "upload_progress=" . (int)filter_var(ini_get("session.upload_progress.enabled"), FILTER_VALIDATE_BOOLEAN) . "\n";
echo "memory_limit=" . $ini("memory_limit") . "\n";
echo "post_max_size=" . $ini("post_max_size") . "\n";
echo "fatal_error_backtraces=" . $ini("fatal_error_backtraces") . "\n";
'

get() { grep -m1 "^$1=" <<<"$RESULT" | cut -d= -f2- || true; }

# version_ge A B -> true if A >= B
version_ge() { [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$2" ]]; }

# Look for both CVE IDs in local distro package changelogs for this PHP branch.
distro_backport() {
  local mm="$1" text=""
  if compgen -G "/usr/share/doc/php${mm}*/changelog.Debian.gz" >/dev/null; then
    text="$(zcat /usr/share/doc/php${mm}*/changelog.Debian.gz 2>/dev/null || true)"
  fi
  if command -v rpm >/dev/null; then
    # Only packages from the same branch (e.g. 8.3.x), so a patched alt-php74 can't vouch for php 8.3
    local pkgs
    pkgs="$(rpm -qa --qf '%{NAME} %{VERSION}\n' 'php*' 'lsphp*' 'alt-php*' 2>/dev/null \
            | awk -v mm="$mm." 'index($2, mm) == 1 {print $1}' | sort -u || true)"
    [[ -n "$pkgs" ]] && text+="$(rpm -q --changelog $pkgs 2>/dev/null || true)"
  fi
  [[ -n "$text" ]] || return 1
  local c
  for c in "${CVES[@]}"; do grep -q "$c" <<<"$text" || return 1; done
  return 0
}

if [[ $CLI_ONLY -eq 1 ]]; then
  command -v php >/dev/null || { red "php not found in PATH"; exit 1; }
  yellow "CLI-only mode: the CLI may be a different build or php.ini than your web server."
  TMP_PROBE="$(mktemp --suffix=.php)"
  trap 'rm -f -- "$TMP_PROBE"' EXIT
  printf '%s' "${PROBE_PHP/__TOKEN__/cli}" > "$TMP_PROBE"
  RESULT="$(php -d display_errors=0 -r '$_GET["t"]="cli"; include $argv[1];' "$TMP_PROBE" 2>/dev/null || true)"
else
  [[ -n "$WEBROOT" && -n "$URL" ]] || { red "--webroot and --url are required (or use --cli)"; usage; }
  [[ -d "$WEBROOT" ]] || { red "Webroot not found: $WEBROOT"; exit 1; }
  command -v curl >/dev/null || { red "curl is required"; exit 1; }

  TOKEN="$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  # No leading dot: many Nginx/Apache configs deny dotfiles
  PROBE_NAME="php2shell-check-${TOKEN:0:12}.php"
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
    echo "If PHP is only executed through a front controller (index.php rewrites), run with --cli as a fallback."
    exit 1
  fi
fi

[[ "$(get probe)" == "ok" ]] || { red "Probe failed."; exit 1; }

RAW_VERSION="$(get version)"
VERSION="$(grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' <<<"$RAW_VERSION" || true)"
SAPI="$(get sapi)"
UPLOAD_PROGRESS="$(get upload_progress)"
SESSION_EXT="$(get session_ext)"
MEMORY_LIMIT="$(get memory_limit)"
POST_MAX="$(get post_max_size)"
FATAL_BT="$(get fatal_error_backtraces)"

[[ -n "$VERSION" ]] || { red "Could not parse PHP version: $RAW_VERSION"; exit 1; }
MM="$(cut -d. -f1-2 <<<"$VERSION")"

echo
echo "PHP version : $RAW_VERSION"
echo "SAPI        : $SAPI"
echo "php.ini     : $(get ini_file)"
echo

# --- Patch status ---------------------------------------------------------
STATUS=""
if [[ -n "${FIXED[$MM]:-}" ]]; then
  if version_ge "$VERSION" "${FIXED[$MM]}"; then
    STATUS="patched"
  elif distro_backport "$MM"; then
    STATUS="backport"
  else
    STATUS="vulnerable"
  fi
elif version_ge "$MM.0" "8.6.0"; then
  STATUS="patched"   # branch released after the fix
else
  # 8.1 and older: no official release, only source backports
  if distro_backport "$MM"; then STATUS="backport"; else STATUS="eol"; fi
fi

case "$STATUS" in
  patched)
    green "PATCHED: PHP $VERSION includes the fixes for ${CVES[*]}."
    ;;
  backport)
    green "PATCHED (distro backport): the local PHP $MM package changelog lists both CVEs."
    ;;
  vulnerable)
    red "NOT PATCHED: PHP $VERSION is older than ${FIXED[$MM]}, and no distro backport was found in the local package changelogs."
    echo "If PHP runs in a container or on another host, check that build's package changelog there."
    ;;
  eol)
    red "NOT PATCHED: PHP $MM is end of life and has no official release with the fix."
    echo "Upgrade to 8.2+ or install a vendor/LTS backport. PHP published source-only backports for 7.4, 8.0 and 8.1."
    ;;
esac

if [[ "$STATUS" == backport ]]; then
  # The version string doesn't change with distro backports, so check that the
  # worker that answered still maps the old (replaced) PHP binary or modules.
  WPID="$(get pid)"
  if [[ $CLI_ONLY -eq 0 && "$WPID" =~ ^[0-9]+$ && -r "/proc/$WPID/maps" ]]; then
    if readlink "/proc/$WPID/exe" 2>/dev/null | grep -q '(deleted)' \
       || grep -qE '(php|libphp)[^ ]*\.so.* \(deleted\)$' "/proc/$WPID/maps" 2>/dev/null; then
      echo
      red "NOT RESTARTED: the worker that served the request (pid $WPID) is still running the old PHP binary."
      echo "Restart every PHP worker (php-fpm / apache2 / lsphp), then re-run this check."
      exit 2
    fi
  elif [[ $CLI_ONLY -eq 0 ]]; then
    yellow "Could not inspect the PHP worker process (run as root on the web server host)."
    echo "Make sure every worker was restarted after the package update."
  fi
fi

if [[ "$STATUS" == patched || "$STATUS" == backport ]]; then
  echo
  echo "Next: hunt for compromise that may predate the patch (see post-patch-checklist.md)."
  exit 0
fi

# --- Interim mitigations (only relevant while unpatched) -------------------
echo
yellow "Interim mitigations (partial only; PHP says updating is the only complete fix):"
mark() { if [[ "$1" == ok ]]; then printf '  [ok] %s\n' "$2"; else printf '  [--] %s\n' "$2"; fi; }

if [[ "$SESSION_EXT" == 1 && "$UPLOAD_PROGRESS" == 1 ]]; then
  mark no "session.upload_progress.enabled = On (set it to 0 in php.ini / FPM pool / server config)"
else
  mark ok "session.upload_progress.enabled = Off"
fi

[[ "$MEMORY_LIMIT" == "-1" ]] && mark ok "memory_limit = -1" \
  || mark no "memory_limit = $MEMORY_LIMIT (PHP suggests -1 via php_admin_value, together with a cgroup limit)"

POST_BYTES="$(numfmt --from=iec "${POST_MAX^^}" 2>/dev/null || echo 0)"
if [[ "$POST_BYTES" -gt 0 && "$POST_BYTES" -le $((32*1024*1024)) ]]; then
  mark ok "post_max_size = $POST_MAX"
else
  mark no "post_max_size = $POST_MAX (PHP suggests 8M, or 32M if you need uploads)"
fi

if [[ "$MM" == 8.5 ]]; then
  [[ "$FATAL_BT" == "0" ]] && mark ok "fatal_error_backtraces = 0" \
    || mark no "fatal_error_backtraces = $FATAL_BT (PHP 8.5: set it to 0)"
fi

echo "  Do not rely on .user.ini or ini_set(): PHP's advisory says they don't apply early enough."
exit 2
