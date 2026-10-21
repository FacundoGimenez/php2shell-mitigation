# LiteSpeed / OpenLiteSpeed

LiteSpeed runs PHP through `lsphp` (LSAPI), and each `lsphp` version has its **own** `php.ini`.

## Find the lsphp installs

```bash
ls -d /usr/local/lsws/lsphp*                 # OpenLiteSpeed / LSWS packages
ls /opt/alt/php*/etc/php.ini 2>/dev/null     # CloudLinux alt-php
/usr/local/lsws/lsphp83/bin/php -i | grep 'Loaded Configuration File'
```

Typical paths:

- `/usr/local/lsws/lsphp83/etc/php/8.3/litespeed/php.ini` (Debian/Ubuntu packages)
- `/usr/local/lsws/lsphp83/etc/php.ini` (RHEL packages)
- `/usr/local/lsws/lsphp83/etc/php/8.3/mods-available/` (drop-ins)

Repeat for **every** `lsphp` version on the server.

## Apply

Add to each `php.ini` (or a drop-in in its `mods-available` directory):

```ini
session.upload_progress.enabled = 0
```

Then restart so running `lsphp` processes pick it up:

```bash
sudo /usr/local/lsws/bin/lswsctrl restart
sudo pkill lsphp        # lsphp workers can outlive a graceful restart
```

## `.htaccess` (LiteSpeed Enterprise)

LiteSpeed Enterprise honours Apache-style PHP directives in `.htaccess`:

```apache
php_flag session.upload_progress.enabled off
```

OpenLiteSpeed does not read `php_flag` from `.htaccess`. Use `php.ini` or `.user.ini`.

## Panels

- **CyberPanel**: *PHP → Edit PHP Configs → Advanced*, for each PHP version, then restart LiteSpeed.
- **cPanel with LiteSpeed**: see [shared hosting](shared-hosting.md).

## Verify

```bash
sudo ../scripts/check-exposure.sh --webroot /home/site/public_html --url https://your-site
```
