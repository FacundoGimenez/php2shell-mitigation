# LiteSpeed / OpenLiteSpeed

LiteSpeed runs PHP through `lsphp` (LSAPI). Each `lsphp` version is a **separate package with its own `php.ini`**, so every one of them has to be updated.

## Find the lsphp installs

```bash
ls -d /usr/local/lsws/lsphp*                 # OpenLiteSpeed / LSWS packages
ls /opt/alt/php*/etc/php.ini 2>/dev/null     # CloudLinux alt-php
/usr/local/lsws/lsphp83/bin/php -v
```

## 1. Update (the only complete fix)

Fixed versions: **8.2.35, 8.3.36, 8.4.27, 8.5.12**. LiteSpeed publishes its `lsphp` builds separately, so check that a patched build is available for your version.

```bash
# Debian / Ubuntu
sudo apt update && sudo apt install --only-upgrade 'lsphp8*'

# RHEL / Alma / Rocky
sudo dnf upgrade 'lsphp8*'

# CloudLinux alt-php
sudo yum update 'alt-php*'
```

Restart so no old `lsphp` worker survives:

```bash
sudo /usr/local/lsws/bin/lswsctrl restart
sudo pkill lsphp        # lsphp workers can outlive a graceful restart
```

## 2. If you cannot update yet

These are partial mitigations. PHP says none of them is complete.

Add the following to each `lsphp` `php.ini` (for example `/usr/local/lsws/lsphp83/etc/php/8.3/litespeed/php.ini`), then restart as above:

```ini
session.upload_progress.enabled = 0
post_max_size = 8M          ; 32M if you need uploads
upload_max_filesize = 6M    ; keep below post_max_size
```

**Do not use `.user.ini` or `ini_set()`**: PHP's advisory says not to rely on them.

## Panels

- **CyberPanel**: *PHP → Edit PHP Configs → Advanced*, for each PHP version, then restart LiteSpeed.
- **cPanel with LiteSpeed**: see [shared hosting](shared-hosting.md).

## Verify

```bash
sudo ../scripts/check-exposure.sh --webroot /home/site/public_html --url https://your-site
```

*Not tested on LiteSpeed yet. Reports are welcome.*
