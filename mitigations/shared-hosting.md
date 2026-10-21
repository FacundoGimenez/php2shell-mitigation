# Shared hosting, cPanel, Plesk

**On shared hosting, a WordPress or CMS plugin cannot fix this.** The bug is in PHP itself, so the server's PHP must be patched.

What you can do:

1. **Ask your provider today** to apply the official PHP update as soon as it ships, and to disable `session.upload_progress.enabled` in the meantime.
2. Try a per-account override (below). Many hosts allow it.
3. Back up your files and database.

## cPanel

- **MultiPHP INI Editor** → *Editor Mode* → select your domain → add:
  ```ini
  session.upload_progress.enabled = 0
  ```
  cPanel writes this into `.user.ini` / `php.ini` in the document root (or `.htaccess` for mod_php / LSAPI).
- Server admins (WHM): *MultiPHP INI Editor* → *Editor Mode* → each PHP version, for a server-wide change.

## Plesk

- *Websites & Domains* → your domain → **PHP Settings** → *Additional configuration directives*:
  ```ini
  session.upload_progress.enabled = 0
  ```
- Server-wide: *Tools & Settings* → *PHP Settings* → each handler → `php.ini`.

## DirectAdmin / CloudLinux

- CloudLinux **PHP Selector** → *Options*, or edit `/opt/alt/php<v>/etc/php.ini` (admin).

## No panel access

Create `.user.ini` in the document root:

```ini
session.upload_progress.enabled = 0
```

If PHP runs as mod_php, use `.htaccess` instead:

```apache
php_flag session.upload_progress.enabled off
```

PHP caches `.user.ini` for up to 5 minutes, so wait before you [verify through the web](../scripts/check-exposure.sh). `.htaccess` changes under mod_php apply immediately.

If you're not sure which one applies, add the `.user.ini`, wait 5 minutes and run the check. If it still reports EXPOSED, try the `.htaccess` (on PHP-FPM a bare `php_flag` returns a 500 error, so remove it if the site breaks).

## PHP 8.1 or older

These versions are end of life and will not receive an official fix. Disable upload progress, isolate the site, and ask the provider for a backport or a migration to a supported version.
