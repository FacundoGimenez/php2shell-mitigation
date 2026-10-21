# php2shell mitigation

Patch guidance, exposure checks and compromise-hunting helpers for **php2shell**
(**CVE-2026-109618** / **CVE-2026-109619**), the unauthenticated RCE in PHP.

> [!IMPORTANT]
> **Official fixes were released on 21 Oct 2026. Updating is the only complete fix.**
> Fixed versions: **8.2.35**, **8.3.36**, **8.4.27**, **8.5.12**.
> PHP's own advisory says the temporary mitigations do **not** fully solve the problem.
> Official advisory: <https://www.php.net/archive/2026.php#2026-10-21-5>

## TL;DR

1. **Update PHP** to a fixed version, or to your distro's patched package. Do this on every host and for every installed PHP version.
2. **Restart every PHP worker** (PHP-FPM, Apache with mod_php, `lsphp`, `php-cgi`).
   With **mod_php**, `systemctl reload apache2` / `apachectl graceful` keeps the **old, vulnerable PHP library loaded**, so use a full `systemctl restart apache2`. We tested this; `check-exposure.sh` detects it.
3. **Verify through the web server** that the patched build is the one actually serving requests:
   ```bash
   sudo ./scripts/check-exposure.sh --webroot /var/www/html --url https://your-site
   ```
   The CLI can be a different build or `php.ini` from the one behind your site, so `php -v` alone is not proof.
4. **Hunt for compromise.** Patching does not remove a webshell that is already there. Follow the [post-patch checklist](post-patch-checklist.md).
5. **Can't update yet?** Apply the [interim mitigations](#if-you-cannot-update-yet), then update anyway.

## Fixed versions

| Branch | Fixed in | Notes |
|---|---|---|
| 8.5 | **8.5.12** | |
| 8.4 | **8.4.27** | |
| 8.3 | **8.3.36** | |
| 8.2 | **8.2.35** | 8.2 reaches end of life on 31 Dec 2026 |
| 8.1, 8.0, 7.4 | No official release | End of life. PHP published minimal **source backports** ([7.4](https://github.com/php/php-src/tree/PHP-7.4-CVE-2026-109618-109619), [8.0](https://github.com/php/php-src/tree/PHP-8.0-CVE-2026-109618-109619), [8.1](https://github.com/php/php-src/tree/PHP-8.1-CVE-2026-109618-109619)) for people building from source. Otherwise use a distro/LTS vendor backport, or upgrade |

**Distro packages:** Linux distributions and LTS vendors received the patches in advance. Their packages often keep the old upstream version number (Ubuntu's `8.3.6-0ubuntu…`, for example) even when they contain the fix. `check-exposure.sh` looks for the CVE IDs in the local package changelogs to detect this. Note that PHP says the Remi repository will not have updates on release day.

## The vulnerabilities

| CVE | What happens (per PHP) |
|---|---|
| **CVE-2026-109618**: RCE via OOM corruption | Out-of-memory handling can interrupt PHP while internal request data is only partially initialized. Request cleanup may then treat the invalid data as valid |
| **CVE-2026-109619**: RCE via stale global state | Request-owned internal state can survive after its backing memory has been freed. A later request handled by the same worker may use that stale state |

Both are rated **CVSS v4.0 9.2**.

**Who is at risk:** all PHP installations serving web requests, including PHP-FPM, Apache with mod_php, `php-cgi`, FrankenPHP and LiteSpeed. PHP considers the risk **highest for mod_php**, where an exploit has been demonstrated in which an unauthenticated request triggers the attack before any application code runs.

## If you cannot update yet

Per PHP's advisory: *"There are no complete mitigations, updating is the only safe choice."* These measures reduce exposure while you schedule the update.

| Measure | Covers | How |
|---|---|---|
| `session.upload_progress.enabled = 0` | The confirmed session paths, **not other variants** | `php.ini`, a `conf.d` file, the FPM pool, or server config (`php_admin_flag`). Restart every worker. **Not** `ini_set()`, and **not** FPM `.user.ini` |
| `memory_limit = -1`, set so apps can't override it (`php_admin_value`) | Reduces the OOM path of CVE-2026-109618 | An underlying allocation failure can still reach the vulnerable path. Pair it with a container/cgroup memory limit that kills only the affected worker. Do **not** use `RLIMIT_AS` / `RLIMIT_DATA` |
| `post_max_size = 8M` (no uploads) or `32M` (uploads), with `upload_max_filesize` below it | Reduces the OOM path | |
| Request limits at the web server / proxy | Reduces the OOM path | Body size, field count, multipart part count, header count, nesting depth. Include requests without a usable `Content-Length` |
| `fatal_error_backtraces = 0` (**PHP 8.5 only**) | The confirmed fatal-backtrace path of CVE-2026-109619 only | Restart every worker |
| Remove invalid/deprecated per-request settings and fix attacker-reachable fatal errors and timeouts | CVE-2026-109619 | Hiding diagnostics with `error_reporting`, `display_errors` or `@` does **not** help |

> [!WARNING]
> **Do not rely on `.user.ini` or `ini_set()`.** PHP's advisory explicitly says these do not apply early enough. An earlier version of this repo suggested `.user.ini`; that advice has been removed.

### Per-stack instructions

- [Apache (mod_php / PHP-FPM)](mitigations/apache.md)
- [Nginx + PHP-FPM](mitigations/nginx-fpm.md)
- [LiteSpeed / OpenLiteSpeed](mitigations/litespeed.md)
- [Docker (official `php` / `wordpress` images)](mitigations/docker.md)
- [Shared hosting, cPanel, Plesk](mitigations/shared-hosting.md)

## Scripts

| Script | What it does |
|---|---|
| [`scripts/check-exposure.sh`](scripts/check-exposure.sh) | Drops a temporary, token-protected probe into your webroot and requests it through the web server. It reports the PHP version actually serving the site, compares it against the fixed versions, checks distro package changelogs for backported fixes, and flags workers still running the old binary after an upgrade. When the site is unpatched, it shows the interim mitigation settings. Then it deletes the probe |
| [`scripts/watch-php-children.sh`](scripts/watch-php-children.sh) | Polls the process table and alerts when a PHP or web-server worker spawns a shell, downloader, network tool or recon command |
| [`scripts/find-recent-php.sh`](scripts/find-recent-php.sh) | Lists recently modified `.php` files in a webroot and flags common webshell patterns |

The scripts only read state from your own systems. None of them attempt to exploit anything.

`watch-php-children.sh` polls the process table, so it can miss commands that finish in a few milliseconds (a quick `id` or a failing `curl`). It is a lightweight first line of detection. For full coverage, use auditd `execve` rules or an eBPF tool.

```bash
git clone https://github.com/FacundoGimenez/php2shell-mitigation
cd php2shell-mitigation

sudo ./scripts/check-exposure.sh --webroot /var/www/html --url https://example.com
sudo ./scripts/watch-php-children.sh
sudo ./scripts/find-recent-php.sh /var/www/html 3
```

## Tested on

Ubuntu 24.04 with PHP 8.3:

**Patch detection** was tested against Ubuntu's real security update (`8.3.6-0ubuntu0.24.04.12` → `.13`):

| Scenario | `check-exposure.sh` result |
|---|---|
| Old package | NOT PATCHED |
| New package, PHP-FPM not restarted | NOT RESTARTED (old binary still mapped) |
| New package, PHP-FPM reloaded or restarted | PATCHED (distro backport) |
| New package, mod_php, `apachectl graceful` | NOT RESTARTED (old `libphp` still loaded) |
| New package, mod_php, full Apache restart | PATCHED (distro backport) |

**Interim mitigations:**

| Setup | Verified |
|---|---|
| Nginx + PHP-FPM | `check-exposure.sh` through the web server; `upload_progress` disabled via `conf.d` and pool `php_admin_flag` |
| Apache + mod_php | `check-exposure.sh` through the web server; `upload_progress` disabled via `conf.d`, vhost `php_admin_flag` and `.htaccess` |
| Apache + PHP-FPM | `check-exposure.sh` through the web server; `upload_progress` disabled via `conf.d` |

`upload_progress` was confirmed off with a real multipart upload, not just `ini_get()`.

The **LiteSpeed**, **Docker** and **cPanel/Plesk** instructions follow each platform's documented config layout but have **not been tested**. Reports and fixes are welcome.

## Sources

- [PHP Security Advisory, 21 Oct 2026](https://www.php.net/archive/2026.php#2026-10-21-5)
- [GHSA-w8hw-w9fx-j79w (CVE-2026-109618)](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w)
- [GHSA-6wmf-4rv5-p3rp (CVE-2026-109619)](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp)
- [PHP 8 ChangeLog](https://www.php.net/ChangeLog-8.php)
- Pre-release analysis by watchTowr and GMO Flatt Security, and community threads on X
- [syhunt/php2shell-protection](https://github.com/syhunt/php2shell-protection): multipart-blocking test kit for Apache (pre-release stopgap)
- Florian Roth: `process-watcher` (eBPF) for detecting suspicious child processes

Corrections and additional stacks are welcome via issues and PRs.

## Disclaimer

Provided as-is, with no warranty. Test changes in staging when you can, and keep backups.
This repository does not contain or link to exploit code.

## License

[MIT](LICENSE)
