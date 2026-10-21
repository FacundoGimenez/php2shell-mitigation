# Nginx + PHP-FPM

Nginx does not run PHP itself, so the change goes into PHP-FPM.

## Find the FPM version(s) and config

```bash
ls /etc/php/                                   # Debian/Ubuntu
systemctl list-units --type=service | grep -i fpm
php-fpm8.3 -i 2>/dev/null | grep 'Loaded Configuration File'
```

Typical paths:

| Distro | `php.ini` | `conf.d` | Pools |
|---|---|---|---|
| Debian/Ubuntu | `/etc/php/<v>/fpm/php.ini` | `/etc/php/<v>/fpm/conf.d/` | `/etc/php/<v>/fpm/pool.d/` |
| RHEL/Alma/Rocky | `/etc/php.ini` | `/etc/php.d/` | `/etc/php-fpm.d/` |
| Remi SCL | `/etc/opt/remi/php<v>/php.ini` | `/etc/opt/remi/php<v>/php.d/` | `/etc/opt/remi/php<v>/php-fpm.d/` |

Repeat for **every** installed FPM version.

## Option A: `conf.d` drop-in (preferred)

```bash
echo 'session.upload_progress.enabled = 0' | sudo tee /etc/php/8.3/fpm/conf.d/99-php2shell.ini
sudo systemctl reload php8.3-fpm
```

## Option B: per pool

In each pool file (e.g. `/etc/php/8.3/fpm/pool.d/www.conf`):

```ini
php_admin_flag[session.upload_progress.enabled] = off
```

```bash
sudo php-fpm8.3 -t && sudo systemctl reload php8.3-fpm
```

## Option C: `.user.ini` (no root access)

Create `.user.ini` in the document root:

```ini
session.upload_progress.enabled = 0
```

PHP caches `.user.ini` for `user_ini.cache_ttl` seconds (300 by default). Reload PHP-FPM if you can. If you can't, wait 5 minutes before running the check, because a check run right away can still report EXPOSED.

Make sure Nginx does not serve the file:

```nginx
location ~ /\.user\.ini$ { deny all; }
```

(A generic `location ~ /\. { deny all; }` rule covers it too.)

## Verify

```bash
sudo ../scripts/check-exposure.sh --webroot /var/www/html --url https://your-site
```

## Rollback

Remove the drop-in / pool line and reload FPM.
