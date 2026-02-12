# Release & Deployment Strategy

This document summarizes the deployment track currently kept in this repository.

For now, we keep a Fly.io-first strategy for fastest POC delivery.

## Current implementation status

The repository currently includes a complete Fly.io POC path:

- CI workflow: [.github/workflows/ci.yml](.github/workflows/ci.yml)
- Fly deploy workflow: [.github/workflows/deploy-fly.yml](.github/workflows/deploy-fly.yml)
- Fly app config: [fly.toml](fly.toml)
- Container build config: [Dockerfile](Dockerfile)
- Release migration module: [lib/emothe/release.ex](lib/emothe/release.ex)
- Step-by-step setup: [docs/fly-poc-deployment.md](docs/fly-poc-deployment.md)

## How the Fly POC flow works

### Build & deploy pipeline

On push to `main` (or manual dispatch):

1. GitHub Actions runs Fly deploy workflow
2. Fly builds/deploys using [fly.toml](fly.toml) and [Dockerfile](Dockerfile)
3. Release command runs migrations: `Emothe.Release.migrate`
4. App becomes available via Fly-managed runtime and networking

### Runtime responsibilities

- Fly runs the app container and routing/TLS
- Fly managed Postgres can provide `DATABASE_URL`
- GitHub Actions deploys with `flyctl`

### Important note about Elixir/Erlang

No Elixir/Erlang installation is needed on your own VM when using Fly for deployment.

## Deployment plan (Fly)

### Phase 1: bootstrap (one time)

- Create Fly app and Fly Postgres
- Configure secrets (`SECRET_KEY_BASE`, host, etc.)
- Validate first manual deploy

### Phase 2: connect CI/CD

- Add `FLY_API_TOKEN` in GitHub Actions secrets
- Trigger Fly deploy workflow manually once (`workflow_dispatch`)

### Phase 3: operational baseline

- Enable basic monitoring/log checks in Fly dashboard
- Add DB backup strategy for managed Postgres
- Define rollback playbook (`fly releases` / rollback)

## Docker + Docker Compose option

This project can still be deployed with Docker/Compose later if you want to leave Fly.

### What changes with Docker

- You run app + (optionally) database as containers
- Deploy target runs Docker engine and Compose plugin
- CI/CD builds and pushes images to a registry, server pulls and restarts containers

### Typical Compose architecture

- `app` container: Phoenix release image
- `db` container: Postgres (or use managed DB and skip db container)
- `reverse-proxy` container (nginx/Traefik) or host-level nginx

### Docker operational tradeoffs

Pros:

- Consistent runtime between environments
- Easier image versioning/rollback (`docker compose pull && up -d`)
- Familiar workflow if you already use Compose

Cons:

- Extra moving parts (registry, image lifecycle, container networks/volumes)
- More layers for debugging than plain `systemd`
- You still need TLS, backups, and monitoring

## Suggested decision framework

Choose Fly now if:

- you want fastest managed POC delivery
- you prefer lower ops overhead for TLS/network/runtime
- you want managed Postgres integration

Choose Docker/Compose later if:

- your team already operates with Compose routinely
- you want image-based promotion/rollback
- you plan to run multiple services using the same container patterns

## Next step

- Follow [docs/fly-poc-deployment.md](docs/fly-poc-deployment.md) for first deploy
- Keep Docker/Compose as a future optional path if needed

## Fly.io POC track

If fastest managed delivery is the goal, use the Fly.io path documented in:

- [docs/fly-poc-deployment.md](docs/fly-poc-deployment.md)

Scaffolded Fly assets:

- [fly.toml](fly.toml)
- [Dockerfile](Dockerfile)
- [.github/workflows/deploy-fly.yml](.github/workflows/deploy-fly.yml)