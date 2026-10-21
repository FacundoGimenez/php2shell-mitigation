# Docker (official `php` and `wordpress` images)

## 1. Update (the only complete fix)

Move to an image built on a fixed PHP version: **8.2.35, 8.3.36, 8.4.27 or 8.5.12**.

```bash
docker compose pull
docker compose up -d
docker compose exec <service> php -v      # confirm the new version
```

If you pin tags, bump them (for example `php:8.3.36-fpm`). Floating tags (`wordpress:latest`, `php:8.3-apache`) pick up the fix once the upstream image is rebuilt. Check that the version reported above is a fixed one.

Images built `FROM` an official PHP image need a rebuild:

```bash
docker compose build --pull && docker compose up -d
```

## 2. If you cannot update yet

These are partial mitigations. PHP says none of them is complete.

The official images load every `.ini` file in `/usr/local/etc/php/conf.d/`, so you can mount one in without rebuilding.

`security.ini` next to your `compose.yaml`:

```ini
session.upload_progress.enabled = 0
post_max_size = 8M          ; 32M if you need uploads
upload_max_filesize = 6M    ; keep below post_max_size
```

Add it to the service's `volumes`, **keeping your existing entries**:

```yaml
services:
  wordpress:
    image: wordpress:latest
    volumes:
      - ./wp-data:/var/www/html          # your existing volumes
      - ./security.ini:/usr/local/etc/php/conf.d/security.ini:ro
```

Recreate only that service:

```bash
docker compose up -d --no-deps --force-recreate wordpress
```

A container memory limit (`mem_limit` / `deploy.resources.limits.memory`) also helps against the OOM path, as PHP recommends.

## Other images

- **Bitnami**: `/opt/bitnami/php/etc/conf.d/`
- **php-fpm + nginx in separate containers**: everything goes into the **PHP-FPM** container, not nginx.

*Not tested on Docker yet. Reports are welcome.*

Credit: Docker steps adapted from community posts on X.
