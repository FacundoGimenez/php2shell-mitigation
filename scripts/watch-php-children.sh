#!/usr/bin/env bash
# watch-php-children.sh - alert when PHP / web-server workers spawn suspicious processes
#
# Polls the process table and prints an alert when php-fpm, php-cgi, lsphp,
# apache2, httpd (or a shell they spawned) starts a shell, scripting runtime,
# downloader, network tool or recon command. Also flags /dev/tcp and mkfifo.
#
# Polling can miss very short-lived processes. For full coverage use auditd
# (execve rules) or an eBPF tool such as Florian Roth's process-watcher.
#
# Usage:
#   sudo watch-php-children.sh [--interval SECONDS] [--log FILE] [--once]
#
# Exit codes (with --once): 0 = nothing found, 2 = suspicious process found

set -uo pipefail

INTERVAL=1
LOG=""
ONCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval) INTERVAL="${2:-1}"; shift 2 ;;
    --log)      LOG="${2:-}"; shift 2 ;;
    --once)     ONCE=1; shift ;;
    -h|--help)  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

[[ $EUID -eq 0 ]] || echo "Warning: not running as root, processes of other users may be hidden." >&2

PARENT_RE='^(php-fpm.*|php-cgi.*|php[0-9.]*|lsphp.*|apache2|httpd|litespeed|lshttpd)$'
CHILD_RE='^(sh|bash|dash|zsh|ksh|busybox|python[0-9.]*|perl|ruby|lua|curl|wget|nc|ncat|netcat|socat|telnet|whoami|id|uname|hostname|base64|chmod|crontab|ssh|scp)$'
ARGS_RE='/dev/tcp/|/dev/udp/|mkfifo|bash -i|sh -i|base64 -d|wget .*\| *sh|curl .*\| *(ba)?sh'

declare -A SEEN=()

alert() {
  local line="[$(date -u +%FT%TZ)] ALERT $*"
  printf '\033[31m%s\033[0m\n' "$line"
  [[ -n "$LOG" ]] && echo "$line" >> "$LOG"
  logger -t php2shell-watch -- "$*" 2>/dev/null || true
}

scan() {
  local found=0
  declare -A COMM=() PPID_OF=() ARGS=() USER_OF=()
  local pid ppid user comm args

  while read -r pid ppid user comm args; do
    COMM[$pid]="$comm"; PPID_OF[$pid]="$ppid"; USER_OF[$pid]="$user"; ARGS[$pid]="$args"
  done < <(ps -eo pid=,ppid=,user=,comm=,args= 2>/dev/null)

  for pid in "${!COMM[@]}"; do
    [[ -n "${SEEN[$pid]:-}" ]] && continue
    comm="${COMM[$pid]}"
    args="${ARGS[$pid]}"
    [[ "$comm" =~ $PARENT_RE ]] && continue

    # Walk up to 4 ancestors looking for a PHP / web-server worker
    local cur="$pid" depth=0 php_ancestor=""
    while (( depth < 4 )); do
      cur="${PPID_OF[$cur]:-0}"
      [[ "$cur" == 0 || "$cur" == 1 || -z "${COMM[$cur]:-}" ]] && break
      if [[ "${COMM[$cur]}" =~ $PARENT_RE ]]; then php_ancestor="$cur"; break; fi
      ((depth++))
    done
    [[ -z "$php_ancestor" ]] && continue

    if [[ "$comm" =~ $CHILD_RE || "$args" =~ $ARGS_RE ]]; then
      SEEN[$pid]=1
      found=1
      alert "pid=$pid user=${USER_OF[$pid]} comm=$comm parent=${COMM[$php_ancestor]}($php_ancestor) args=$args"
    fi
  done
  return $found
}

if [[ $ONCE -eq 1 ]]; then
  scan; rc=$?
  [[ $rc -eq 0 ]] && echo "No suspicious children of PHP / web-server processes found."
  exit $(( rc == 1 ? 2 : 0 ))
fi

echo "Watching for suspicious children of PHP / web-server processes (interval ${INTERVAL}s). Ctrl+C to stop."
while true; do
  scan
  sleep "$INTERVAL"
done
