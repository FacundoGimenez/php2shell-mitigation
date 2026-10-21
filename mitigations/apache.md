# Apache

PHP considers **mod_php the highest-risk setup**: an unauthenticated exploit has been demonstrated against it. Update first.

Find out how Apache runs PHP:

```bash
apachectl -M 2>/dev/null | grep -Ei 'php|proxy_fcgi'
```

- `php_module` / `php7_module` / `php8_module` → **mod_php**
- `proxy_fcgi_module` with no PHP module → **PHP-FPM** (see [Nginx + PHP-FPM](nginx-fpm.md) for the PHP side)

## 1. Update (the only complete fix)

Fixed versions: **8.2.35, 8.3.36, 8.4.27, 8.5.12**, or your distro's patched package.

```bash
# Debian / Ubuntu (distro or ondrej/sury packages)
sudo apt update
sudo apt install --only-upgrade 'libapache2-mod-php*' 'php*-common' 'php*-cli'

# RHEL / Alma / Rocky
sudo dnf upgrade 'php*'
```

Then do a **full restart**:

```bash
sudo systemctl restart apache2     # httpd on RHEL
```

> [!WARNING]
> With mod_php, `systemctl reload apache2` and `apachectl graceful` **do not** reload the PHP module. We tested this: after a package upgrade and a graceful restart, Apache kept serving requests with the old, deleted `libphp` still in memory. Only a full restart loads the patched library. `check-exposure.sh` reports this as NOT RESTARTED.

Check through the web server:

```bash
sudo ../scripts/check-exposure.sh --webroot /var/www/html --url https://your-site
```

## 2. If you cannot update yet

These are partial mitigations. PHP says none of them is complete.

### `php.ini` / `conf.d` (preferred)

```bash
# Debian/Ubuntu, mod_php: /etc/php/<version>/apache2/conf.d/
sudo tee /etc/php/8.3/apache2/conf.d/99-php2shell.ini <<'EOF'
session.upload_progress.enabled = 0
post_max_size = 8M          ; 32M if you need uploads
upload_max_filesize = 6M    ; keep below post_max_size
EOF
sudo systemctl restart apache2
```

### vhost / `httpd.conf` (applications can't override it)

```apache
<VirtualHost *:443>
    # ...
    php_admin_flag  session.upload_progress.enabled off
    php_admin_value memory_limit -1
</VirtualHost>
```

Only set `memory_limit -1` together with a container or cgroup memory limit, otherwise a single request can use all the RAM. PHP advises against `RLIMIT_AS` / `RLIMIT_DATA` for this.

On PHP 8.5, also add `php_admin_value fatal_error_backtraces 0`.

### `.htaccess` (mod_php only, last resort)

```apache
<IfModule mod_php.c>
    php_flag session.upload_progress.enabled off
</IfModule>
```

PHP's advisory doesn't list this option, so prefer server config. It needs `AllowOverride Options` (or `All`). Debian and Ubuntu ship `AllowOverride None` under `/var/www`, and with that Apache **silently ignores** the file. Under PHP-FPM a bare `php_flag` causes a 500 error, and the `<IfModule>` version is skipped silently.

**Do not use `.user.ini` or `ini_set()`**: PHP's advisory says not to rely on them.

### Request limits

```apache
LimitRequestBody 8388608        # 8 MB; raise it only where uploads are needed
LimitRequestFields 100
```

## Rollback

Remove the lines or files and restart Apache.
