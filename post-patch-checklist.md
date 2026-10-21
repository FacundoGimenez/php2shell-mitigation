# Post-patch checklist

Patching closes the hole. It does **not** remove anything an attacker already planted.

## 1. Patch and confirm

- [ ] Update PHP on every host and every installed version (FPM, mod_php, `lsphp`, `php-cgi`, containers).
- [ ] Restart, not just reload, so old workers are gone:
  ```bash
  sudo systemctl restart php8.3-fpm      # each version
  sudo systemctl restart apache2         # or httpd
  sudo /usr/local/lsws/bin/lswsctrl restart && sudo pkill lsphp
  ```
- [ ] Confirm the **web-served** version is the patched one:
  ```bash
  sudo ./scripts/check-exposure.sh --webroot /var/www/html --url https://your-site
  ```
- [ ] Docker: `docker compose pull && docker compose up -d`, and confirm the new image tag.
- [ ] Keep `session.upload_progress.enabled = 0` until you have confirmed that the patch covers both CVEs, unless you rely on upload progress.

## 2. Hunt for webshells and persistence

Focus on the window between public disclosure and your patch.

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
- [ ] Web server access logs: multipart POSTs to unusual endpoints, followed by requests to new `.php` files.

## 3. If you find something

- [ ] Isolate the host, preserve logs and copies of the suspicious files before deleting anything.
- [ ] Rotate **everything** the PHP user could read: DB credentials, `wp-config.php` salts, API keys, `.env` secrets.
- [ ] Restore from a backup made **before** the disclosure date, or rebuild.
- [ ] Assume the database may have been read.

## 4. Afterwards

- [ ] Remove the temporary WAF / multipart blocks if you added any.
- [ ] Keep the process monitoring (`watch-php-children.sh`, auditd or eBPF) in place.
- [ ] Plan the upgrade off any end-of-life PHP version.
