# php2shell mitigation

Interim mitigations, exposure checks and detection helpers for **php2shell**
(**CVE-2026-109618** / **CVE-2026-109619**), the reported pre-auth RCE in PHP 8.x.

> [!WARNING]
> **There is no confirmed fix or official workaround yet.**
> As of 21 Oct 2026, PHP has not published the affected versions, the root cause or the patch.
> watchTowr's own FAQ states there is no confirmed workaround.
> Everything here is a **stopgap** based on third-party analysis. It buys time; it does not replace patching.
> This repo will be updated when the official release lands.

## TL;DR

1. **Disable session upload progress** and reload PHP:
   ```ini
   session.upload_progress.enabled = 0
   ```
   Then reload `php-fpm` / Apache / LiteSpeed (stack-specific steps below).
2. **Verify through the web server**, not the CLI. `php -i` can read a different `php.ini` than the one serving your site.
   Use [`scripts/check-exposure.sh`](scripts/check-exposure.sh).
3. **Inventory every PHP install** you own (`php -v`, cPanel/Plesk, appliances that bundle `php-cgi`). Prioritise anything internet-facing.
4. **Back up** sites and databases now, and schedule a change window for the official patch.
5. **Watch for compromise**: `php-fpm`, `php-cgi`, `apache2`, `httpd` or `lsphp` spawning shells, `curl`, `wget`, `nc`...
   Use [`scripts/watch-php-children.sh`](scripts/watch-php-children.sh).
6. **Patch as soon as it is released**, then follow the [post-patch checklist](post-patch-checklist.md). Patching does not remove a webshell that is already there.

## What is known

| | Status |
|---|---|
| Official patch | Expected 21 Oct 2026, ~09:00 UTC-5 (14:00 UTC) |
| Affected versions | Not officially published. Public write-ups reference PHP 8.x before the patch |
| Root cause | Not officially published. Leading theory: heap use-after-free in the `session.upload_progress` handler (`ext/session`) |
| Default config vulnerable? | Reportedly yes: `session.upload_progress.enabled` is **On** by default |
| Public PoC | Reportedly circulating. **Do not run untrusted PoCs against your servers** |
| PHP 8.1 and older | End of life, will not get an official fix. Disable upload progress, isolate, push your vendor for a backport |

## Mitigations, ranked by confidence

| Confidence | Mitigation | Notes |
|---|---|---|
| **High** (no downside) | Inventory, backups, change window, monitoring | Do this regardless |
| **Medium** | `session.upload_progress.enabled = 0` | Proposed by GMO Flatt Security, who believe the bug is in Session Upload Progress. Reversible, only disables upload progress tracking. **Not guaranteed** to cover both CVEs or the real vector |
| **Low** (hardening) | `session.use_strict_mode = 1`, `session.use_only_cookies = 1`, `session.cookie_httponly = 1` | Good session hygiene. Does **not** address this bug on its own |
| **Unverified / risky** | Blocking `multipart/form-data` POSTs at the WAF / web server | One researcher claims a second multipart-parser path that the ini change does not cover. Not validated by any vendor, can break forms and uploads. See [syhunt/php2shell-protection](https://github.com/syhunt/php2shell-protection) if you decide to test it |

### Per-stack instructions

- [Apache (mod_php / PHP-FPM)](mitigations/apache.md)
- [Nginx + PHP-FPM](mitigations/nginx-fpm.md)
- [LiteSpeed / OpenLiteSpeed](mitigations/litespeed.md)
- [Docker (official `php` / `wordpress` images)](mitigations/docker.md)
- [Shared hosting, cPanel, Plesk](mitigations/shared-hosting.md)

> Note: `ini_set('session.upload_progress.enabled', 0)` inside your application does **not** work.
> Upload progress is handled while PHP reads the request body, before your code runs.
> The setting must be applied in `php.ini`, a `conf.d` file, the FPM pool, `.user.ini` or `.htaccess`.

## Scripts

| Script | What it does |
|---|---|
| [`scripts/check-exposure.sh`](scripts/check-exposure.sh) | Drops a temporary probe into your webroot, requests it through the web server, reports the PHP version and whether `session.upload_progress.enabled` is on, then deletes the probe |
| [`scripts/watch-php-children.sh`](scripts/watch-php-children.sh) | Polls the process table and alerts when a PHP/web-server worker spawns a shell, downloader, network tool or recon command |
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

| Setup | Mitigations verified |
|---|---|
| Nginx + PHP-FPM | `conf.d` drop-in, pool `php_admin_flag`, `.user.ini` |
| Apache + mod_php | `conf.d` drop-in, vhost `php_admin_flag`, `.htaccess` |
| Apache + PHP-FPM | `conf.d` drop-in, `.user.ini` |

For each one, the check script was run through the web server, and a real multipart upload was used to confirm that upload progress is no longer recorded in the session, not just that `ini_get()` reports Off.

The **LiteSpeed**, **Docker** and **cPanel/Plesk** instructions follow each platform's documented config layout but have **not been tested yet**. Reports and fixes are welcome.

## Sources

- watchTowr: public FAQ on CVE-2026-109618 / CVE-2026-109619 (no confirmed workaround)
- GMO Flatt Security: analysis pointing at Session Upload Progress
- [syhunt/php2shell-protection](https://github.com/syhunt/php2shell-protection): multipart-blocking test kit for Apache
- Florian Roth: `process-watcher` (eBPF) for detecting suspicious child processes
- Community threads on X
- [PHP manual: Session Upload Progress](https://www.php.net/manual/en/session.upload-progress.php)

Corrections and additional stacks are welcome via issues and PRs.

## Disclaimer

Provided as-is, with no warranty. Test changes in staging when you can, and keep backups.
This repository does not contain or link to exploit code.

## License

[MIT](LICENSE)
