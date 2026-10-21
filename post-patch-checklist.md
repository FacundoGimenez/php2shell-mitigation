# Post-patch checklist

Patching closes the hole. It does **not** remove anything an attacker already planted.

## 1. Patch and confirm

- [ ] Update PHP on every host and every installed version (FPM, mod_php, `lsphp`, `php-cgi`, FrankenPHP, containers) to **8.2.35 / 8.3.36 / 8.4.27 / 8.5.12**, or to your distro's patched package.
- [ ] Restart, not just reload, so no old worker survives. With mod_php, `apachectl graceful` keeps the old PHP library loaded:
  ```bash
  sudo systemctl restart php8.3-fpm      # each version
  sudo systemctl restart apache2         # or httpd
  sudo /usr/local/lsws/bin/lswsctrl restart && sudo pkill lsphp
  ```
- [ ] Confirm that the **web-served** build is patched:
  ```bash
  sudo ./scripts/check-exposure.sh --webroot /var/www/html --url https://your-site
  ```
  Distro packages may still report the old upstream version (e.g. `8.3.6` on Ubuntu). The script checks the package changelog for the CVE IDs. You can also check by hand:
  ```bash
  zgrep -l 'CVE-2026-10961[89]' /usr/share/doc/php*/changelog.Debian.gz   # Debian/Ubuntu
  rpm -qa --changelog 'php*' | grep 'CVE-2026-10961[89]'                 # RHEL family
  ```
- [ ] Docker: pull or rebuild, recreate, then run `docker compose exec <service> php -v`.
- [ ] Optional: keep `session.upload_progress.enabled = 0` as defense in depth if you don't use upload progress.

## 2. Hunt for webshells and persistence

Focus on the window between the 20 Oct pre-announcement and your patch.

- [ ] Recently modified PHP files:
  ```bash
  sudo ./scripts/find-recent-php.sh /var/www 7
  ```
- [ ] PHP files where they should not be (`uploads/`, `cache/`, `tmp/`):
  ```bash
  find /var/www -type f -name '*.ph*' \( -path '*/uploads/*' -o -path '*/cache/*' -o -path '*/tmp/*' \)
  ```
- [ ] Unknown WordPress plugins, mu-plugins and admin users:
  ```bash
  wp plugin list --allow-root; ls wp-content/mu-plugins
  wp user list --role=administrator --allow-root
  ```
- [ ] Cron jobs for the web user and root:
  ```bash
  sudo crontab -l -u www-data; sudo crontab -l; ls -la /etc/cron.* /var/spool/cron/ 2>/dev/null
  ```
- [ ] New system users or SSH keys:
  ```bash
  awk -F: '$3 >= 1000' /etc/passwd; sudo find / -name authorized_keys -newer /etc/hostname 2>/dev/null
  ```
- [ ] Systemd units and `.bashrc` / `.profile` changes for the web user.
- [ ] Unexpected outbound connections:
  ```bash
  sudo ss -tunap | grep -Ei 'php|apache|httpd|nginx|lsphp'
  ```
- [ ] Web server access logs: unusual multipart POSTs, oversized or malformed requests, followed by requests to new `.php` files.
- [ ] PHP-FPM / Apache error logs: bursts of out-of-memory or fatal errors and worker crashes (segfaults) since 20 Oct.

## 3. If you find something

- [ ] Isolate the host. Preserve logs and copies of the suspicious files before deleting anything.
- [ ] Rotate **everything** the PHP user could read: DB credentials, `wp-config.php` salts, API keys, `.env` secrets.
- [ ] Restore from a backup made **before** 20 Oct, or rebuild.
- [ ] Assume the database may have been read.

## 4. Afterwards

- [ ] Remove temporary WAF / multipart blocks and `memory_limit = -1` overrides if you added them.
- [ ] Keep the process monitoring (`watch-php-children.sh`, auditd or eBPF) in place.
- [ ] Plan the upgrade off any end-of-life PHP version. PHP 8.2 reaches end of life on 31 Dec 2026.
