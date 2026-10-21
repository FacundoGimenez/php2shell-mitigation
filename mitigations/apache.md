# Apache

First, find out how Apache runs PHP:

```bash
apachectl -M 2>/dev/null | grep -Ei 'php|proxy_fcgi'
```

- `php_module` / `php7_module` / `php8_module` → **mod_php**
- `proxy_fcgi_module` with no PHP module → **PHP-FPM** (follow the FPM steps below)

## mod_php

### Option A: global `php.ini` (preferred)

```bash
php --ini   # CLI only, but usually shows the conf.d layout
# Debian/Ubuntu: /etc/php/<version>/apache2/php.ini
# RHEL/Alma/Rocky: /etc/php.ini
```

Set:

```ini
session.upload_progress.enabled = 0
```

Or drop a file into the Apache SAPI `conf.d` directory (Debian/Ubuntu):

```bash
echo 'session.upload_progress.enabled = 0' | sudo tee /etc/php/8.3/apache2/conf.d/99-php2shell.ini
sudo systemctl restart apache2     # httpd on RHEL
```

### Option B: vhost / `httpd.conf`

```apache
<VirtualHost *:443>
    # ...
    php_admin_flag session.upload_progress.enabled off
</VirtualHost>
```

`php_admin_flag` cannot be overridden by `.htaccess` or the application.

### Option C: `.htaccess` (no root access)

```apache
<IfModule mod_php.c>
    php_flag session.upload_progress.enabled off
</IfModule>
<IfModule mod_php7.c>
    php_flag session.upload_progress.enabled off
</IfModule>
```

Requires `AllowOverride Options` (or `All`). With PHP-FPM, `php_flag` in `.htaccess` causes a 500 error; use `.user.ini` instead.

## PHP-FPM behind Apache

Same as [Nginx + PHP-FPM](nginx-fpm.md): change the FPM `php.ini` or pool, then reload `php<version>-fpm`.

## Verify

Check through the web server, not the CLI:

```bash
sudo ../scripts/check-exposure.sh --webroot /var/www/html --url https://your-site
```

## Rollback

Remove the line / file and restart Apache.
