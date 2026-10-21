# Nginx + PHP-FPM

Nginx does not run PHP itself, so everything below happens in PHP-FPM.

## Find the FPM version(s) and config

```bash
ls /etc/php/                                   # Debian/Ubuntu
systemctl list-units --type=service | grep -i fpm
php-fpm8.3 -i 2>/dev/null | grep 'Loaded Configuration File'
```

| Distro | `php.ini` | `conf.d` | Pools |
|---|---|---|---|
| Debian/Ubuntu | `/etc/php/<v>/fpm/php.ini` | `/etc/php/<v>/fpm/conf.d/` | `/etc/php/<v>/fpm/pool.d/` |
| RHEL/Alma/Rocky | `/etc/php.ini` | `/etc/php.d/` | `/etc/php-fpm.d/` |
| Remi SCL | `/etc/opt/remi/php<v>/php.ini` | `/etc/opt/remi/php<v>/php.d/` | `/etc/opt/remi/php<v>/php-fpm.d/` |

Do this for **every** installed FPM version.

## 1. Update (the only complete fix)

Fixed versions: **8.2.35, 8.3.36, 8.4.27, 8.5.12**, or your distro's patched package.

```bash
# Debian / Ubuntu
sudo apt update
sudo apt install --only-upgrade 'php*-fpm' 'php*-common' 'php*-cli'

# RHEL / Alma / Rocky
sudo dnf upgrade 'php*'
```

**Restart** each FPM service, not just reload:

```bash
sudo systemctl restart php8.3-fpm
```

Verify through the web server:

```bash
sudo ../scripts/check-exposure.sh --webroot /var/www/html --url https://your-site
```

## 2. If you cannot update yet

These are partial mitigations. PHP says none of them is complete.

### `conf.d` drop-in

```bash
sudo tee /etc/php/8.3/fpm/conf.d/99-php2shell.ini <<'EOF'
session.upload_progress.enabled = 0
post_max_size = 8M          ; 32M if you need uploads
upload_max_filesize = 6M    ; keep below post_max_size
EOF
sudo systemctl restart php8.3-fpm
```

### Per pool (applications can't override it)

In each pool file (e.g. `/etc/php/8.3/fpm/pool.d/www.conf`):

```ini
php_admin_flag[session.upload_progress.enabled] = off
php_admin_value[memory_limit] = -1
; PHP 8.5 only:
; php_admin_value[fatal_error_backtraces] = 0
```

```bash
sudo php-fpm8.3 -t && sudo systemctl restart php8.3-fpm
```

Only set `memory_limit = -1` together with a cgroup memory limit (for example `MemoryMax=` in a systemd drop-in for the FPM service), otherwise a single request can use all the RAM. PHP advises against `RLIMIT_AS` / `RLIMIT_DATA` for this.

**Do not use `.user.ini` or `ini_set()`**: PHP's advisory says not to rely on them.

### Request limits in Nginx

```nginx
client_max_body_size 8m;           # raise it only on upload endpoints
large_client_header_buffers 4 8k;
```

## Rollback

Remove the drop-in or pool lines and restart FPM.
