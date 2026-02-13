# Fly.io POC Deployment Guide

This guide is the fast path for a managed, deployable POC using Fly.io + GitHub Actions.

## What was scaffolded

- Fly app config: [fly.toml](fly.toml)
- Production container image: [Dockerfile](Dockerfile)
- Docker context exclusions: [.dockerignore](.dockerignore)
- GitHub Actions deploy workflow: [.github/workflows/deploy-fly.yml](.github/workflows/deploy-fly.yml)
- Release migrations via: `Emothe.Release.migrate`

## Prerequisites

- Fly.io account
- Fly CLI (`flyctl`) installed locally
- GitHub repository for this project

## 1) Create/push GitHub repository

If this project is not pushed yet, run:

```bash
git remote -v
```

If no remote exists, create one on GitHub and push:

```bash
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin git@github.com:<your-user-or-org>/emothe.git
git push -u origin main
```

If you use GitHub CLI (`gh`):

```bash
gh repo create <your-user-or-org>/emothe --private --source=. --remote=origin --push
```

## 2) Create Fly app and managed Postgres

Choose app name (must be globally unique):

```bash
fly launch --no-deploy --copy-config --name <your-fly-app-name> --region mad
```

Create managed Postgres cluster (pick a size that fits your budget):

```bash
fly postgres create --name <your-fly-postgres-name> --region mad
```

Attach database to app (injects `DATABASE_URL` secret):

```bash
fly postgres attach --app <your-fly-app-name> <your-fly-postgres-name>
```

## 3) Set required Fly secrets

Generate secret key base locally:

```bash
mix phx.gen.secret
```

Set secrets:

```bash
fly secrets set SECRET_KEY_BASE=<paste_generated_secret> --app <your-fly-app-name>
fly secrets set PHX_HOST=<your-fly-app-name>.fly.dev --app <your-fly-app-name>
```

Optional tuning:

```bash
fly secrets set POOL_SIZE=10 --app <your-fly-app-name>
```

## 4) Align `fly.toml`

Edit [fly.toml](fly.toml):

- Set `app = "<your-fly-app-name>"`
- Set `PHX_HOST` in `[env]` to your app host
- Adjust region/VM size if needed

## 5) First manual deploy

Run once locally to validate:

```bash
fly deploy --remote-only
```

Check health/logs:

```bash
fly status --app <your-fly-app-name>
fly logs --app <your-fly-app-name>
```

## 6) Enable CI/CD deploy from GitHub Actions

Generate Fly API token locally:

```bash
fly auth token
```

In GitHub repo settings, add secret:

- `FLY_API_TOKEN`

Workflow used for deploys:

- [.github/workflows/deploy-fly.yml](.github/workflows/deploy-fly.yml)

Deploy behavior:

- CI workflow (`CI`) runs on pushes/PRs
- Deploy workflow runs automatically only when `CI` succeeds for `main`
- You can still trigger deploy manually with `workflow_dispatch`

## 7) Migrations

`fly.toml` includes:

- `release_command = "/app/bin/emothe eval Emothe.Release.migrate"`

This runs DB migrations automatically at deploy time.

## 8) Notes for POC use

- Fly free-tier limits can change; verify current plan before relying on it
- For POC reliability, keep one app machine and small VM size initially
- Add a custom domain later with `fly certs add <domain>` when ready

## 9) Branch protection (recommended)

To enforce CI/CD quality gates on `main` (similar to Jenkins protected branch policies):

1. Go to GitHub repo → `Settings` → `Branches` → `Add branch protection rule`
2. Branch name pattern: `main`
3. Enable these rules:
	- `Require a pull request before merging`
	- `Require approvals` (suggested: 1)
	- `Require status checks to pass before merging`
	- `Require branches to be up to date before merging`
	- `Require conversation resolution before merging`
	- `Do not allow bypassing the above settings`

Suggested required status checks:

- `CI / test`

Optional hardening:

- Restrict who can push to matching branches
- Require signed commits
- Require linear history

With this in place, merge to `main` is blocked unless CI is green, and deploy runs only after CI success (as configured in `.github/workflows/deploy-fly.yml`).
