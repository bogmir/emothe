# Bare Metal Deployment with Docker

This document covers deploying EMOTHE on a self-managed server using Docker and Docker Compose — reusing the existing `Dockerfile` while managing your own infrastructure.

---

## 1. Server Provisioning

### 1.1 OS Installation

- [ ] Install Debian 12 (Bookworm) or Ubuntu 24.04 LTS
- [ ] Set hostname (e.g. `emothe.uv.es`)
- [ ] Configure timezone (`timedatectl set-timezone Europe/Madrid`)
- [ ] Enable unattended security updates (`apt install unattended-upgrades`)

### 1.2 Initial Hardening

- [ ] Create a non-root deploy user (e.g. `deploy`) with sudo access
- [ ] Add `deploy` to the `docker` group: `usermod -aG docker deploy`
- [ ] Disable root SSH login (`PermitRootLogin no` in `/etc/ssh/sshd_config`)
- [ ] Disable password SSH auth (`PasswordAuthentication no`) — use SSH keys only
- [ ] Change SSH port from 22 (optional, reduces noise)
- [ ] Install and configure `fail2ban` for SSH brute-force protection
- [ ] Set up UFW or nftables firewall:
  - Allow SSH (port 22 or custom)
  - Allow HTTP (80) and HTTPS (443)
  - Deny everything else by default
  - Note: Docker manages its own iptables rules — see section 8.2 for details

---

## 2. Docker & Docker Compose

### 2.1 Install Docker Engine

- [ ] Install Docker using the official repository (not the distro package):

```bash
# Add Docker's official GPG key and repository
apt-get update
apt-get install ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

- [ ] Verify: `docker compose version`
- [ ] Enable on boot: `systemctl enable docker`

### 2.2 Docker Compose File

- [ ] Create `/opt/emothe/docker-compose.yml`:

```yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    image: emothe:latest
    restart: unless-stopped
    ports:
      - "127.0.0.1:4000:8080"
    depends_on:
      db:
        condition: service_healthy
    env_file:
      - .env.prod
    environment:
      DATABASE_URL: ecto://emothe:${POSTGRES_PASSWORD}@db/emothe_prod
      PHX_SERVER: "true"
      PHX_HOST: "${PHX_HOST:-emothe.uv.es}"
      PORT: "8080"
      POOL_SIZE: "10"

  db:
    image: postgres:16-bookworm
    restart: unless-stopped
    volumes:
      - pgdata:/var/lib/postgresql/data
    environment:
      POSTGRES_USER: emothe
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: emothe_prod
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U emothe -d emothe_prod"]
      interval: 5s
      timeout: 5s
      retries: 5
    # Only accessible from other containers, not from host network
    expose:
      - "5432"

  # Run migrations as a one-shot job
  migrate:
    image: emothe:latest
    depends_on:
      db:
        condition: service_healthy
    env_file:
      - .env.prod
    environment:
      DATABASE_URL: ecto://emothe:${POSTGRES_PASSWORD}@db/emothe_prod
    command: /app/bin/emothe eval "Emothe.Release.migrate()"
    restart: "no"
    profiles:
      - migrate

volumes:
  pgdata:
```

### 2.3 Environment File

- [ ] Create `/opt/emothe/.env.prod` (mode 0600, owned by `deploy`):

```bash
# Required
SECRET_KEY_BASE=<generate-with-mix-phx.gen.secret>
POSTGRES_PASSWORD=<strong-random-password>
PHX_HOST=emothe.uv.es

# Email (optional — omit SMTP_HOST to disable)
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USERNAME=apikey
SMTP_PASSWORD=<smtp-password>
MAIL_FROM=noreply@emothe.uv.es

# OpenTelemetry (optional)
OTEL_TRACES_EXPORTER=none
```

- [ ] Never commit `.env.prod` to version control

---

## 3. Networking & DNS

### 3.1 DNS Records

- [ ] A record: `emothe.uv.es` -> server IPv4
- [ ] AAAA record: `emothe.uv.es` -> server IPv6 (if available)
- [ ] MX / SPF / DKIM records if sending email from this server

### 3.2 TLS Certificates (Let's Encrypt)

- [ ] Install certbot on the host: `apt install certbot`
- [ ] Obtain certificate: `certbot certonly --standalone -d emothe.uv.es`
- [ ] Verify auto-renewal timer: `systemctl status certbot.timer`
- [ ] Add post-renewal hook to reload nginx (see below)

### 3.3 Reverse Proxy (nginx on host)

nginx runs on the host (not in Docker) to handle TLS termination and proxy to the app container.

- [ ] Install nginx on host: `apt install nginx`
- [ ] Create `/etc/nginx/sites-available/emothe`:

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
    add_header Strict-Transport-Security "max-age=63072000" always;

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
- [ ] Remove default site: `rm /etc/nginx/sites-enabled/default`
- [ ] Test and reload: `nginx -t && systemctl reload nginx`
- [ ] Create certbot post-renewal hook `/etc/letsencrypt/renewal-hooks/post/reload-nginx.sh`:

```bash
#!/bin/bash
systemctl reload nginx
```

- [ ] `chmod +x /etc/letsencrypt/renewal-hooks/post/reload-nginx.sh`

---

## 4. First Deploy

### 4.1 Initial Setup

```bash
cd /opt/emothe
git clone https://github.com/<your-org>/emothe.git .

# Create and edit .env.prod (see section 2.3)

# Build the image
docker compose build

# Run migrations
docker compose run --rm migrate

# Start services
docker compose up -d
```

### 4.2 Verify

- [ ] `docker compose ps` — app and db should be `running`
- [ ] `docker compose logs app` — check for startup errors
- [ ] `curl -I http://localhost:4000` — should return 200
- [ ] `curl -I https://emothe.uv.es` — should return 200 via nginx

### 4.3 Create Initial Admin User

```bash
docker compose exec app /app/bin/emothe remote
# In the IEx shell:
Emothe.Accounts.get_user_by_email("admin@example.com")
|> Emothe.Accounts.User.role_changeset(%{role: "admin"})
|> Emothe.Repo.update()
```

---

## 5. Deployment Pipeline

### 5.1 Deployment Script

- [ ] Create `/opt/emothe/deploy.sh`:

```bash
#!/bin/bash
set -euo pipefail

cd /opt/emothe

# Pull latest code
git fetch origin main
git reset --hard origin/main

# Rebuild image
docker compose build

# Run migrations
docker compose run --rm migrate

# Restart app (zero-downtime-ish: new container starts before old stops)
docker compose up -d --force-recreate --no-deps app

# Clean up old images
docker image prune -f

echo "Deploy complete at $(date)"
```

- [ ] `chmod +x /opt/emothe/deploy.sh`

### 5.2 CI/CD (GitHub Actions)

- [ ] Create `.github/workflows/deploy-bare-metal.yml`:

```yaml
name: Deploy to Bare Metal

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
- [ ] Restrict the deploy SSH key via `authorized_keys` command restriction (optional)

### 5.3 Rollback Strategy

- [ ] Tag images before deploying: `docker tag emothe:latest emothe:prev`
- [ ] Rollback: `docker tag emothe:prev emothe:latest && docker compose up -d --force-recreate app`
- [ ] For database rollbacks: `docker compose exec app /app/bin/emothe eval "Emothe.Release.rollback(Emothe.Repo, <version>)"`

---

## 6. Database Management

### 6.1 Backups

- [ ] Create backup script `/opt/emothe/backup.sh`:

```bash
#!/bin/bash
set -euo pipefail

BACKUP_DIR=/var/backups/emothe
mkdir -p "$BACKUP_DIR"

docker compose exec -T db pg_dump -U emothe -Fc emothe_prod \
  > "$BACKUP_DIR/emothe_$(date +%Y%m%d_%H%M%S).dump"

# Keep last 30 days
find "$BACKUP_DIR" -name "*.dump" -mtime +30 -delete

echo "Backup complete: $(ls -t $BACKUP_DIR/*.dump | head -1)"
```

- [ ] Add to cron: `0 3 * * * /opt/emothe/backup.sh >> /var/log/emothe-backup.log 2>&1`
- [ ] Off-site backup: rsync/rclone dumps to S3, B2, or another server
- [ ] Test restore procedure:

```bash
# Create a throwaway container to test restore
docker compose exec -T db pg_restore -U emothe -d emothe_test --create \
  < /var/backups/emothe/emothe_YYYYMMDD.dump
```

### 6.2 PostgreSQL Tuning

The Compose setup uses default PostgreSQL settings. For tuning:

- [ ] Create a custom config and mount it:

```yaml
# In docker-compose.yml under db service:
volumes:
  - pgdata:/var/lib/postgresql/data
  - ./postgres.conf:/etc/postgresql/custom.conf:ro
command: postgres -c config_file=/etc/postgresql/custom.conf
```

- [ ] Use [PGTune](https://pgtune.leopard.in.ua/) to generate settings for your server specs

### 6.3 PostgreSQL Major Upgrades

- [ ] Dump before upgrade: `./backup.sh`
- [ ] Update image version in `docker-compose.yml`
- [ ] Recreate: `docker compose down db && docker compose up -d db`
- [ ] Restore if needed (major version changes may require dump/restore)

---

## 7. Monitoring & Logging

### 7.1 Container Logs

- [ ] View logs: `docker compose logs -f app`
- [ ] View db logs: `docker compose logs -f db`
- [ ] Configure Docker log rotation in `/etc/docker/daemon.json`:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "5"
  }
}
```

- [ ] Restart Docker after changing: `systemctl restart docker`

### 7.2 Health Checks

- [ ] Add a `/health` endpoint to the app (returns 200 OK)
- [ ] Add healthcheck to app service in Compose:

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 30s
```

- [ ] Set up external uptime monitor (UptimeRobot, Uptime Kuma, etc.)

### 7.3 System Monitoring

- [ ] Monitor disk space — Docker images/volumes can grow: `docker system df`
- [ ] Periodic cleanup: `docker system prune -f` (removes stopped containers, dangling images)
- [ ] Optional: set up node_exporter + Prometheus + Grafana
- [ ] Optional: cAdvisor for per-container resource metrics

### 7.4 OpenTelemetry (optional)

- [ ] Set `OTEL_TRACES_EXPORTER=otlp` in `.env.prod`
- [ ] Add an OTel Collector container to Compose, or point to an external endpoint
- [ ] Phoenix, Ecto, and Bandit are already auto-instrumented

---

## 8. Security

### 8.1 Ongoing Maintenance

- [ ] Enable unattended-upgrades for host OS security patches
- [ ] Periodically update base images: rebuild with `docker compose build --pull`
- [ ] Update app dependencies: `mix deps.update --all` and rebuild
- [ ] Review `fail2ban` logs: `fail2ban-client status sshd`

### 8.2 Docker & Firewall Interaction

Docker modifies iptables directly, which can bypass UFW rules. To prevent Docker from exposing ports you didn't intend:

- [ ] Always bind published ports to `127.0.0.1` (as done in the Compose file: `"127.0.0.1:4000:8080"`)
- [ ] Or disable Docker's iptables management in `/etc/docker/daemon.json`:

```json
{
  "iptables": false
}
```

  (If you disable iptables, you'll need to manually set up NAT rules for container networking.)

### 8.3 SSL/TLS

- [ ] Verify certificate auto-renewal: `certbot renew --dry-run`
- [ ] Test SSL config: [SSL Labs](https://www.ssllabs.com/ssltest/)

### 8.4 Container Security

- [ ] The existing Dockerfile already runs as `nobody` (non-root) — keep this
- [ ] Don't run `docker compose` as root in production; use the `deploy` user in the `docker` group
- [ ] Keep `.env.prod` with restrictive permissions (`chmod 600`)

---

## 9. Maintenance Responsibilities

### Daily (automated)

| Task | How |
|------|-----|
| Database backup | cron runs `backup.sh` (section 6.1) |
| Host OS security patches | unattended-upgrades |
| Log rotation | Docker json-file driver (section 7.1) |
| Uptime check | External monitor pings `/health` |

### Weekly (manual review)

| Task | How |
|------|-----|
| Review app logs | `docker compose logs --since 7d app \| grep -i error` |
| Check disk usage | `df -h` and `docker system df` |
| Review fail2ban | `fail2ban-client status sshd` |

### Monthly

| Task | How |
|------|-----|
| Test backup restore | Restore latest dump to a test database |
| Review host updates | `apt list --upgradable` |
| Check certificate expiry | `certbot certificates` |
| Clean unused Docker resources | `docker system prune -f` |
| Rebuild with latest base images | `docker compose build --pull` |

### Quarterly

| Task | How |
|------|-----|
| Firewall audit | Verify rules, check `ss -tlnp` for open ports |
| Dependency audit | `mix deps.audit` / `mix hex.audit` |
| SSL Labs test | Re-test TLS configuration |
| OS version check | Plan upgrades if nearing EOL |
| PostgreSQL version check | Plan upgrades if nearing EOL |

### As Needed

| Task | How |
|------|-----|
| App dependency upgrades | `mix deps.update`, rebuild image |
| PostgreSQL major upgrades | Dump, update image tag, restore |
| Docker Engine upgrades | Follow Docker's upgrade guide |
| OS major upgrades | Plan migration, test on staging |

---

## 10. Minimum Server Specs (Recommendation)

For a low-traffic academic application like EMOTHE:

| Resource | Minimum | Comfortable |
|----------|---------|-------------|
| CPU | 2 cores | 4 cores |
| RAM | 3 GB | 6 GB |
| Disk | 30 GB SSD | 60 GB SSD |
| Network | 100 Mbps | 1 Gbps |

Notes:
- Docker overhead adds ~500 MB RAM and ~5 GB disk vs bare process deployment
- Chromium inside the app container is the heaviest component
- PostgreSQL data volume will be small (~few hundred MB for the full corpus)
- SSD is strongly recommended for both PostgreSQL and Docker image layers
- Leave headroom for Docker image builds (they use temporary disk space)

---

## 11. Environment Variables Summary

| Variable | Required | Example |
|----------|----------|---------|
| `SECRET_KEY_BASE` | Yes | 64+ char random string |
| `POSTGRES_PASSWORD` | Yes | Strong random password |
| `PHX_HOST` | Yes | `emothe.uv.es` |
| `SMTP_HOST` | No | `smtp.example.com` |
| `SMTP_PORT` | No (default 587) | `587` |
| `SMTP_USERNAME` | No | `apikey` |
| `SMTP_PASSWORD` | No | `SG.xxx` |
| `MAIL_FROM` | No | `noreply@emothe.uv.es` |
| `OTEL_TRACES_EXPORTER` | No | `none`, `stdout`, `otlp` |

Note: `DATABASE_URL`, `PHX_SERVER`, and `PORT` are set in `docker-compose.yml` directly — no need to duplicate in `.env.prod`.

---

## 12. Comparison with Other Deployment Options

| Aspect | Bare Metal + Docker | Fly.io | Render |
|--------|---------------------|--------|--------|
| TLS | You manage (certbot + nginx) | Automatic | Automatic |
| Database | You manage (container or host) | Managed Postgres | Managed Postgres |
| Backups | You manage (cron + offsite) | Fly manages | Render manages |
| Scaling | Manual | `fly scale` | Dashboard slider |
| Cost | Fixed server cost | Pay per usage | Pay per usage |
| Control | Full | Limited | Limited |
| Ops burden | High | Low | Low |
| Downtime risk | You're the on-call | Fly SRE | Render SRE |
