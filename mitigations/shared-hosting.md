# Shared hosting, cPanel, Plesk

**On shared hosting, a WordPress or CMS plugin cannot fix this, and neither can your own config.** The bug is in PHP itself, so your provider has to update PHP on the server.

1. **Ask your provider today** to install the fixed PHP builds (**8.2.35, 8.3.36, 8.4.27, 8.5.12**, or their vendor's patched packages) and restart all PHP workers.
2. If your account is on **PHP 8.1 or older**, switch to 8.2+ in the panel (MultiPHP Manager, PHP Selector, PHP Settings) after testing your site. These versions get no official release.
3. Back up your files and database.
4. Once the provider confirms the update, [verify through the web](../scripts/check-exposure.sh) and go through the [post-patch checklist](../post-patch-checklist.md).

## Per-account settings are not a reliable mitigation

PHP's advisory says mitigations must be applied in `php.ini`, the FPM pool or server configuration, and **not** through `.user.ini` or `ini_set()`. On most shared hosts, the per-account editors (cPanel *MultiPHP INI Editor*, Plesk *Additional configuration directives*, CloudLinux *PHP Selector options*) write exactly those per-directory files. So they don't count as protection.

If you run your own server with WHM or Plesk, use the server-wide editors instead, then restart PHP:

- **WHM**: *MultiPHP INI Editor* → *Editor Mode* → each PHP version.
- **Plesk**: *Tools & Settings* → *PHP Settings* → each handler → `php.ini`.

The settings are listed in the [README](../README.md#if-you-cannot-update-yet).
