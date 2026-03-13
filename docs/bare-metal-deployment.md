# Bare Metal Server Deployment Checklist

This document covers everything needed to deploy EMOTHE on a self-managed bare metal (or dedicated/VPS) server running Debian/Ubuntu, without Docker.

---

## 1. Server Provisioning

### 1.1 OS Installation

- [ ] Install Debian 12 (Bookworm) or Ubuntu 24.04 LTS
- [ ] Set hostname (e.g. `emothe.uv.es`)
- [ ] Configure timezone (`timedatectl set-timezone Europe/Madrid`)
- [ ] Enable unattended security updates (`apt install unattended-upgrades`)

### 1.2 Initial Hardening

- [ ] Create a non-root deploy user (e.g. `deploy`) with sudo access
- [ ] Disable root SSH login (`PermitRootLogin no` in `/etc/ssh/sshd_config`)
- [ ] Disable password SSH auth (`PasswordAuthentication no`) — use SSH keys only
- [ ] Change SSH port from 22 (optional, reduces noise)
- [ ] Install and configure `fail2ban` for SSH brute-force protection
- [ ] Set up UFW or nftables firewall:
  - Allow SSH (port 22 or custom)
  - Allow HTTP (80) and HTTPS (443)
  - Allow PostgreSQL (5432) only from localhost
  - Deny everything else by default

---

## 2. Networking & DNS

### 2.1 DNS Records

- [ ] A record: `emothe.uv.es` -> server IPv4
- [ ] AAAA record: `emothe.uv.es` -> server IPv6 (if available)
- [ ] MX / SPF / DKIM records if sending email from this server

### 2.2 TLS Certificates (Let's Encrypt)

- [ ] Install certbot: `apt install certbot`
- [ ] Obtain certificate: `certbot certonly --standalone -d emothe.uv.es`
- [ ] Verify auto-renewal timer: `systemctl status certbot.timer`
- [ ] Configure post-renewal hook to reload nginx (see section 4)

### 2.3 Reverse Proxy (nginx)

- [ ] Install nginx: `apt install nginx`
- [ ] Create site config `/etc/nginx/sites-available/emothe`:

```nginx
upstream emothe {
    server 127.0.0.1:4000;
}

server {
    listen 80;
    server_name emothe.uv.es;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name emothe.uv.es;

    ssl_certificate /etc/letsencrypt/live/emothe.uv.es/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/emothe.uv.es/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # WebSocket support (LiveView)
    location /live/websocket {
        proxy_pass http://emothe;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
    }

    location / {
        proxy_pass http://emothe;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    client_max_body_size 50M;  # TEI file uploads
}
```

- [ ] Enable site: `ln -s /etc/nginx/sites-available/emothe /etc/nginx/sites-enabled/`
- [ ] Test and reload: `nginx -t && systemctl reload nginx`
- [ ] Add certbot post-renewal hook: `/etc/letsencrypt/renewal-hooks/post/reload-nginx.sh`

```bash
#!/bin/bash
systemctl reload nginx
```

---

## 3. Database (PostgreSQL)

### 3.1 Installation

- [ ] Install PostgreSQL 16: `apt install postgresql-16`
- [ ] Verify running: `systemctl status postgresql`

### 3.2 Configuration

- [ ] Create database and user:

```sql
CREATE USER emothe WITH PASSWORD '<strong-password>';
CREATE DATABASE emothe_prod OWNER emothe;
ALTER DATABASE emothe_prod SET timezone TO 'UTC';
```

- [ ] Enable `uuid-ossp` extension (needed for UUID PKs):

```sql
\c emothe_prod
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

- [ ] Tune `postgresql.conf` for server RAM (use [PGTune](https://pgtune.leopard.in.ua/)):
  - `shared_buffers` (25% of RAM)
  - `effective_cache_size` (75% of RAM)
  - `work_mem`, `maintenance_work_mem`
  - `max_connections` (default 100 is fine)
- [ ] Restrict connections to localhost in `pg_hba.conf`:

```
local   all   emothe   scram-sha-256
host    all   emothe   127.0.0.1/32   scram-sha-256
```

### 3.3 Backups

- [ ] Set up daily `pg_dump` via cron:

```bash
# /etc/cron.d/emothe-backup
0 3 * * * postgres pg_dump -Fc emothe_prod > /var/backups/emothe/emothe_$(date +\%Y\%m\%d).dump
```

- [ ] Retention policy: keep last 30 daily + 12 monthly dumps
- [ ] Add cleanup cron: `find /var/backups/emothe -name "*.dump" -mtime +30 -delete`
- [ ] Off-site backup: rsync/rclone dumps to S3, B2, or another server
- [ ] Test restore procedure at least once:

```bash
pg_restore -d emothe_prod_test /var/backups/emothe/emothe_YYYYMMDD.dump
```

---

## 4. Elixir/Erlang Runtime

### 4.1 Option A: Build on Server (simpler)

- [ ] Install asdf (or mise) on the server
- [ ] Install Erlang/OTP 28.1 and Elixir 1.19.5:

```bash
asdf plugin add erlang
asdf plugin add elixir
asdf install erlang 28.1
asdf install elixir 1.19.5-otp-28
```

- [ ] Install Node.js (for asset build): `asdf plugin add nodejs && asdf install nodejs 22.x`
- [ ] Clone repo, build release:

```bash
cd /opt/emothe
git pull
export MIX_ENV=prod
mix deps.get --only prod
mix compile
mix assets.deploy
mix release
```

### 4.2 Option B: Build Elsewhere, Deploy Release Tarball (recommended)

- [ ] Build the release on a CI server or local machine (same OS/arch)
- [ ] Transfer tarball to server: `scp _build/prod/rel/emothe-*.tar.gz deploy@server:/opt/emothe/`
- [ ] Unpack and run — no Elixir/Erlang needed on server
- [ ] Runtime dependencies still required on server:

```bash
apt install libstdc++6 openssl libncurses6 chromium locales ca-certificates
```

### 4.3 Chromium (for PDF export)

- [ ] Install chromium: `apt install chromium`
- [ ] Verify headless works: `chromium --headless --disable-gpu --dump-dom https://example.com`

---

## 5. Application Service (systemd)

### 5.1 Service Unit

- [ ] Create `/etc/systemd/system/emothe.service`:

```ini
[Unit]
Description=EMOTHE Phoenix Application
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=exec
User=deploy
Group=deploy
WorkingDirectory=/opt/emothe
ExecStart=/opt/emothe/bin/emothe start
ExecStop=/opt/emothe/bin/emothe stop
Restart=on-failure
RestartSec=5
SyslogIdentifier=emothe

# Environment
Environment=PHX_SERVER=true
Environment=PHX_HOST=emothe.uv.es
Environment=PORT=4000
Environment=DATABASE_URL=ecto://emothe:<password>@localhost/emothe_prod
Environment=POOL_SIZE=10
Environment=LANG=en_US.UTF-8

# Load secrets from a protected file
EnvironmentFile=/etc/emothe/env

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/opt/emothe
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

### 5.2 Secrets File

- [ ] Create `/etc/emothe/env` (owned by root, mode 0600):

```bash
SECRET_KEY_BASE=<generate-with-mix-phx.gen.secret>
SMTP_HOST=smtp.example.com
SMTP_USERNAME=apikey
SMTP_PASSWORD=<smtp-password>
MAIL_FROM=noreply@emothe.uv.es
```

### 5.3 Enable and Start

- [ ] `systemctl daemon-reload`
- [ ] `systemctl enable emothe`
- [ ] `systemctl start emothe`
- [ ] Run migrations: `/opt/emothe/bin/emothe eval "Emothe.Release.migrate()"`
- [ ] Verify: `systemctl status emothe` and `curl -I http://localhost:4000`

---

## 6. Deployment Pipeline

### 6.1 Deployment Script

- [ ] Create `/opt/emothe/deploy.sh`:

```bash
#!/bin/bash
set -euo pipefail

REPO_DIR=/opt/emothe/repo
RELEASE_DIR=/opt/emothe

cd "$REPO_DIR"
git fetch origin main
git reset --hard origin/main

export MIX_ENV=prod
mix deps.get --only prod
mix compile
mix assets.deploy
mix release --overwrite

# Run migrations
"$RELEASE_DIR/_build/prod/rel/emothe/bin/emothe" eval "Emothe.Release.migrate()"

# Restart
sudo systemctl restart emothe

echo "Deploy complete."
```

### 6.2 CI/CD (GitHub Actions)

- [ ] Option: SSH-based deploy from GitHub Actions:

```yaml
# .github/workflows/deploy-bare-metal.yml
on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy via SSH
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: deploy
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          script: /opt/emothe/deploy.sh
```

- [ ] Add `SERVER_HOST` and `SSH_PRIVATE_KEY` to GitHub repository secrets
- [ ] Restrict the deploy SSH key to only run the deploy script (via `authorized_keys` command restriction)

### 6.3 Rollback Strategy

- [ ] Keep previous N releases (symlink-based or timestamped dirs)
- [ ] Rollback = point symlink to previous release + restart systemd
- [ ] Always test migration reversibility (`mix ecto.rollback`)

---

## 7. Monitoring & Logging

### 7.1 Application Logs

- [ ] journald captures stdout/stderr automatically: `journalctl -u emothe -f`
- [ ] Optional: forward to a log aggregation service (Loki, Papertrail, etc.)
- [ ] Configure log rotation in journald (`/etc/systemd/journald.conf`):

```
SystemMaxUse=1G
MaxRetentionSec=30day
```

### 7.2 Health Checks

- [ ] Add a `/health` endpoint to the app (returns 200 OK)
- [ ] Set up an external uptime monitor (UptimeRobot, Uptime Kuma, etc.)
- [ ] Optional: local systemd watchdog or a simple cron curl check

### 7.3 System Monitoring

- [ ] Install basic monitoring: `apt install htop iotop`
- [ ] Optional: set up node_exporter + Prometheus + Grafana for dashboards
- [ ] Monitor disk space (alert at 80%): cron job or monit
- [ ] Monitor PostgreSQL: `pg_stat_activity`, connection count, slow queries

### 7.4 OpenTelemetry (optional)

- [ ] Set `OTEL_TRACES_EXPORTER=otlp` in env file
- [ ] Run an OpenTelemetry Collector on the server or point to external endpoint
- [ ] Phoenix, Ecto, and Bandit are already auto-instrumented

---

## 8. Security Maintenance

### 8.1 Ongoing

- [ ] Enable unattended-upgrades for security patches: `dpkg-reconfigure -plow unattended-upgrades`
- [ ] Subscribe to Debian/Ubuntu security mailing list
- [ ] Periodically update Erlang/Elixir and `mix deps.update` for security fixes
- [ ] Review `fail2ban` logs: `fail2ban-client status sshd`

### 8.2 Firewall Audit

- [ ] Verify firewall rules quarterly: `ufw status verbose` or `nft list ruleset`
- [ ] Check for open ports: `ss -tlnp`

### 8.3 SSL/TLS

- [ ] Verify certificate auto-renewal: `certbot renew --dry-run`
- [ ] Test SSL config: [SSL Labs](https://www.ssllabs.com/ssltest/)
- [ ] Set HSTS header in nginx (`add_header Strict-Transport-Security "max-age=63072000" always;`)

---

## 9. Maintenance Responsibilities

### Daily (automated)

| Task | How |
|------|-----|
| Database backup | cron pg_dump (section 3.3) |
| Security patches | unattended-upgrades |
| Log rotation | journald auto-rotation |
| Uptime check | External monitor pings `/health` |

### Weekly (manual review)

| Task | How |
|------|-----|
| Review logs for errors | `journalctl -u emothe -p err --since "1 week ago"` |
| Check disk usage | `df -h` |
| Review fail2ban bans | `fail2ban-client status sshd` |

### Monthly

| Task | How |
|------|-----|
| Test backup restore | Restore latest dump to a test database |
| Review system updates | `apt list --upgradable` |
| Check certificate expiry | `certbot certificates` |
| Review PostgreSQL stats | Connection count, slow queries, table bloat |

### Quarterly

| Task | How |
|------|-----|
| Firewall audit | Verify rules, scan open ports |
| Dependency audit | `mix deps.audit` / `mix hex.audit` |
| SSL Labs test | Re-test TLS configuration |
| OS version check | Plan upgrades if nearing EOL |

### As Needed

| Task | How |
|------|-----|
| Elixir/Erlang upgrades | Update asdf versions, rebuild release |
| PostgreSQL major upgrades | `pg_upgrade` or dump/restore |
| OS major upgrades | Plan migration, test on staging first |

---

## 10. Minimum Server Specs (Recommendation)

For a low-traffic academic application like EMOTHE:

| Resource | Minimum | Comfortable |
|----------|---------|-------------|
| CPU | 2 cores | 4 cores |
| RAM | 2 GB | 4 GB |
| Disk | 20 GB SSD | 50 GB SSD |
| Network | 100 Mbps | 1 Gbps |

Notes:
- Chromium (for PDF generation) is the heaviest component; it benefits from extra RAM
- PostgreSQL with the full corpus (~40 plays) is small — a few hundred MB at most
- BEAM VM is very lightweight for this workload
- SSD is strongly recommended for PostgreSQL performance

---

## 11. Environment Variables Summary

| Variable | Required | Example |
|----------|----------|---------|
| `DATABASE_URL` | Yes | `ecto://emothe:pass@localhost/emothe_prod` |
| `SECRET_KEY_BASE` | Yes | 64+ char random string |
| `PHX_HOST` | Yes | `emothe.uv.es` |
| `PHX_SERVER` | Yes | `true` |
| `PORT` | No (default 4000) | `4000` |
| `POOL_SIZE` | No (default 10) | `10` |
| `SMTP_HOST` | No | `smtp.example.com` |
| `SMTP_PORT` | No (default 587) | `587` |
| `SMTP_USERNAME` | No | `apikey` |
| `SMTP_PASSWORD` | No | `SG.xxx` |
| `MAIL_FROM` | No | `noreply@emothe.uv.es` |
| `OTEL_TRACES_EXPORTER` | No | `none`, `stdout`, `otlp` |
