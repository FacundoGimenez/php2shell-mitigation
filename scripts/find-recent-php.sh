#!/usr/bin/env bash
# find-recent-php.sh - list recently modified PHP files and flag common webshell patterns
#
# Usage:
#   find-recent-php.sh <webroot> [days=3]
#
# Heuristic only: expect false positives (plugins and frameworks use some of these
# functions legitimately) and false negatives (obfuscated shells). Review by hand.

set -uo pipefail

ROOT="${1:-}"
DAYS="${2:-3}"

[[ -n "$ROOT" && -d "$ROOT" ]] || { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
[[ "$DAYS" =~ ^[0-9]+$ ]] || { echo "days must be a number"; exit 1; }

PATTERN='eval\s*\(\s*(base64_decode|gzinflate|gzuncompress|str_rot13|\$_(GET|POST|REQUEST|COOKIE|SERVER))|assert\s*\(\s*\$_|(system|shell_exec|passthru|proc_open|popen|pcntl_exec)\s*\(\s*\$_|preg_replace\s*\(.*/e|create_function\s*\(|\$_(GET|POST|REQUEST|COOKIE)\s*\[[^]]*\]\s*\(|move_uploaded_file\s*\(.*\$_FILES|fsockopen\s*\(|/dev/tcp/'

echo "PHP-like files modified in the last $DAYS day(s) under $ROOT:"
echo

count=0
flagged=0
while IFS= read -r -d '' f; do
  ((count++))
  mtime="$(date -u -r "$f" +%FT%TZ 2>/dev/null || stat -c %y "$f")"
  if grep -Eq "$PATTERN" "$f" 2>/dev/null; then
    ((flagged++))
    printf '\033[31m[SUSPICIOUS]\033[0m %s  %s\n' "$mtime" "$f"
    grep -EnHo ".{0,40}($PATTERN).{0,40}" "$f" 2>/dev/null | head -3 | sed 's/^/      /'
  else
    printf '             %s  %s\n' "$mtime" "$f"
  fi
done < <(find "$ROOT" -type f \( -iname '*.php' -o -iname '*.phtml' -o -iname '*.php[0-9]' -o -iname '*.phar' -o -iname '.user.ini' -o -iname '.htaccess' \) -mtime "-$DAYS" -print0 2>/dev/null)

echo
echo "$count file(s) modified, $flagged flagged."

echo
echo "PHP files inside upload/cache/tmp directories (any age):"
( cd "$ROOT" && find . -type f \( -iname '*.php' -o -iname '*.phtml' -o -iname '*.php[0-9]' -o -iname '*.phar' \) \
  \( -path '*/uploads/*' -o -path '*/cache/*' -o -path '*/tmp/*' \) -print 2>/dev/null ) | sed "s|^\./|  ${ROOT%/}/|"

[[ $flagged -gt 0 ]] && exit 2 || exit 0
