# Docker (official `php` and `wordpress` images)

The official images load every `.ini` file in `/usr/local/etc/php/conf.d/`, so you can mount one in without rebuilding.

## 1. Create `security.ini` next to your `compose.yaml`

```ini
; php2shell interim mitigation
session.upload_progress.enabled = 0

; Optional session hardening (does not address php2shell by itself)
session.use_strict_mode = 1
session.use_only_cookies = 1
session.cookie_httponly = 1
```

## 2. Mount it

Add the line to the PHP/WordPress service's `volumes`, **keeping your existing entries**:

```yaml
services:
  wordpress:
    image: wordpress:latest
    volumes:
      - ./wp-data:/var/www/html          # your existing volumes
      - ./security.ini:/usr/local/etc/php/conf.d/security.ini:ro
```

## 3. Recreate only that service

```bash
docker compose up -d --no-deps --force-recreate wordpress
```

## 4. Verify

```bash
docker compose exec wordpress php -r 'var_dump(ini_get("session.upload_progress.enabled"));'
```

In these images the CLI and the web SAPI read the same `conf.d`, so this is a fair check. To confirm through the web server anyway:

```bash
./scripts/check-exposure.sh --webroot ./wp-data --url http://localhost:8080
```

## Other images

- **Bitnami**: `/opt/bitnami/php/etc/conf.d/`
- **php-fpm + nginx in separate containers**: mount the file into the **PHP-FPM** container, not nginx.
- **Your own Dockerfile**: bake it in:

```dockerfile
RUN echo 'session.upload_progress.enabled = 0' > /usr/local/etc/php/conf.d/zz-php2shell.ini
```

## After the official patch

Pull and recreate:

```bash
docker compose pull && docker compose up -d
```

Pin a patched tag if you were on a floating one.

Credit: Docker steps adapted from community posts on X.
