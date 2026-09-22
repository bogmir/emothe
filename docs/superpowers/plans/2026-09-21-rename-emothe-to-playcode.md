# Rename `Emothe` → `Playcode` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the application's code identity from `Emothe`/`:emothe` to `Playcode`/`:playcode`, while leaving the EMOTHE corpus, brand and domain completely untouched.

**Architecture:** This backend will serve two public sites — EMOTHE and ARTELOPE — by generating static HTML for each. `Emothe.Catalogue` serving ARTELOPE is wrong, so the *code* takes a corpus-neutral name while EMOTHE remains what it has always been: one of the corpora, and a public brand. The rename is mechanical but not blind: the token `emothe` means three different things in this repo and only one of them may change.

**Tech Stack:** Elixir 1.19.5 / OTP 28.1, Phoenix 1.8.3, Ecto/PostgreSQL, gettext, Fly.io + Render deployment configs.

**Spec:** None external. The naming decision was made in conversation on 2026-09-21; the Background section below is the spec.

---

## Background: the three meanings of "emothe"

A blanket `sed -i 's/emothe/playcode/gi'` corrupts this repo. Measured counts from the working tree at `fb5cd0a`:

| Token form | Count | What it is | Action |
|---|---|---|---|
| `Emothe`, `EmotheWeb` (mixed case) | ~1083 | **Always** an Elixir module name. Verified: every occurrence outside `lib/`, `test/`, `config/`, `docs/` is `Emothe.MixProject`, `Emothe.Application`, `Emothe.Repo.Migrations.*` or `Emothe.Release`. | **Rename** |
| `emothe` (lower case) | ~820 | App identity: `:emothe` OTP app, `lib/emothe/`, `emothe_dev`, `_emothe_key`, `bin/emothe`, `tailwind emothe`, `mix emothe.*`. **Except** `emothe.uv.es` (83×), the project's real domain. | **Rename, except the domain** |
| `EMOTHE` (upper case) | ~762 | Corpus and brand: **556 play-code occurrences across 78 distinct codes** (`EMOTHE0010`, `EMOTHE0341`, …), 12 gettext UI strings (`"EMOTHE Digital Library"`), TEI fixture content. | **Never touch** |
| `emothe` as domain vocabulary | 30 | **Not the application at all.** `plays.emothe_id` is a live database column holding the EMOTHE project's identifier for a play, with `extract_emothe_idno/1`, `maybe_derive_emothe_id/1` and `emothe_id_derived?/1` around it. `@emothe_project_description` is the EMOTHE project's own blurb. `w3emothe` is the **FileMaker export's database name**, including in `@default_path "doc/w3emothe_T01_tituloEM.ndjson"` — the real file on disk. | **Never touch** |

Two further traps found by measurement:

1. **`test/fixtures/filemaker/*.ndjson` contains `"emothe"` in lower case** — five files, where it is the *FileMaker export's own table name*, mirroring the real external system. Renaming it would falsify the fixtures.
2. **`priv/gettext/**/*.po` holds 934 `#:` source-path comments** but only 12 real EMOTHE brand strings. The path comments need rewriting; the brand strings must survive. `mix gettext.extract --merge` is **not** the tool for this — CLAUDE.md records that it fuzzy-matches new strings onto unrelated translations.

## Execution log

| Task | State | Notes |
|---|---|---|
| 1. Guard test and baseline | **done** `b3a8579` | Found three would-be silent breakages; see the task. Baseline 536 tests, 83 plays, 303,389 elements. |
| 2. The code rename | **done** `68959d4` | 219 files, 549 tests 0 failures. **Task 3's mechanical file edits were folded in here**, because the guard checks the final state and would have left Task 2 red. `fly.emothe.toml` exists; `fly.toml` describes the playcode app. A fourth preserved token was discovered mid-task: `emothe-static`. |
| 3. Deployment | **runbook only** | The file edits are already committed in Task 2. What remains is the operator runbook at the end of that task — create the Fly app, move the secrets, deploy, cut over. Needs `flyctl` and account credentials. |
| 4. Development database | **done** | `ALTER DATABASE emothe_dev RENAME TO playcode_dev`, orphaned `emothe_test` dropped. Row counts identical to baseline; 64 EMOTHE + 19 AL codes intact, zero corrupted; `/plays` and a play page both serve 200. No tracked files changed. |
| 5. Documentation | **done** `16b79d7` | Six live docs; archive verified untouched. Also corrected the stale "Fly deployment pending" claim and removed the asdf PATH export that contradicted Running Commands. |
| 6. Tooling settings and final verification | **done** | `mix format --check-formatted` clean, `--warnings-as-errors` clean, 549 tests 0 failures, all 4 mix tasks registered and `playcode.import.tei --dry-run` exercised end to end. Full-diff corpus scan: no `EMOTHE####` or `emothe.uv.es` lost, no `PLAYCODE####` introduced. |
| 7. Rename the repository | pending | Optional, last, after the Fly cutover. |

## Global Constraints

- **TDD is required** (CLAUDE.md). Every task runs its verification command and shows output. Never claim "done" without the command output that proves it.
- `mix format` after every task. `mix compile --warnings-as-errors` before every commit. Full `mix test` before claiming a task complete.
- **Never rename upper-case `EMOTHE`.** 556 play codes, 12 gettext brand strings, all TEI fixtures.
- **Never rename `emothe.uv.es`.** 83 occurrences: TEI licence URLs, `MAIL_FROM` default, docs.
- **Never rename `emothe_id`, `emothe_project_description` or `w3emothe`.** `plays.emothe_id` is a real Postgres column (confirmed against `emothe_dev`), and `doc/w3emothe_T01_tituloEM.ndjson` is a real file on disk. Renaming either breaks silently: nothing fails to compile, the column just stops matching and the import file stops being found. This is why the substitution carries a lookbehind and a three-way lookahead rather than being a plain replace.
- **Never modify `test/fixtures/`.** Corpus data and third-party export samples.
- **Never modify `docs/superpowers/plans/**` or `docs/superpowers/specs/**`.** They are a historical record of work done under the old namespace; rewriting them falsifies history. ~1300 of the repo's matches live there and stay there.
- **The repository directory stays `/home/bogdan/Projects/emothe`.** Renaming it breaks `.claude/settings.json` absolute paths, the IDE workspace and the git remote for no benefit. Separate, optional, manual, later.
- The public-facing name stays EMOTHE. This rename is invisible to end users by design.

## Decisions taken (change here before starting if you disagree)

| Decision | Default | Why |
|---|---|---|
| Fly.io app | **Add `playcode`, keep `emothe`** | `https://emothe.fly.dev` returns 200 and serves `/plays` — the Fly app is **live**, and CLAUDE.md's claim that `fly deploy` was never run is stale. A Fly app cannot be renamed in place, so `fly.toml` becomes the new `playcode` app and the old config survives as `fly.emothe.toml`, deployable by hand and switched off with `fly scale count 0 -a emothe`. See Task 3. |
| Render | **Out of scope** | `https://emothe-web.onrender.com` returns 404 — the blueprint was never applied, and no parallel Render service is designed here. `render.yaml` and `Dockerfile.render` still get the mechanical rename so the tree holds no dead `/app/bin/emothe` references, but nothing about Render is planned, deployed or verified. |
| Session cookie key `_emothe_key` → `_playcode_key` | **Yes** | Logs out every live session on `emothe.fly.dev` as well as dev. Acceptable: the backend is invite-only and the users are the research team, who log in again. `SECRET_KEY_BASE` on the new Fly app has the same effect regardless. |
| Dev database `emothe_dev` → `playcode_dev` | **Yes, via `ALTER DATABASE`** | Preserves the curated corpus: 82 imported plays, S2a historical time on 11, S2c composition dates on 7, the places gazetteer. Do **not** drop and re-import. |
| GitHub repository name | **Out of scope** | Independent of the code. Rename in the GitHub UI whenever; `git remote set-url` afterwards. |

## File Structure

No new modules and no restructuring — this is a pure identity change. What moves:

| From | To | Files |
|---|---|---|
| `lib/emothe/` | `lib/playcode/` | 47 |
| `lib/emothe.ex` | `lib/playcode.ex` | 1 |
| `lib/emothe_web/` | `lib/playcode_web/` | 62 |
| `lib/emothe_web.ex` | `lib/playcode_web.ex` | 1 |
| `test/emothe/` | `test/playcode/` | 25 |
| `test/emothe_web/` | `test/playcode_web/` | 18 |
| `lib/mix/tasks/emothe.*.ex` | `lib/mix/tasks/playcode.*.ex` | 4 |

Edited in place: `mix.exs`, `config/*.exs`, `test/support/*.ex`, `priv/repo/**`, `assets/js/app.js`, `assets/css/app.css`, the deployment files, `.github/workflows/*`, `CLAUDE.md`, `AGENTS.md`, `README.md`, `docs/bare-metal-*.md`, `docs/build_import_analysis.py`, `.claude/settings.json`.

New files: `fly.emothe.toml` — the previous Fly config, retained so the live `emothe` app stays deployable and switchable (Task 3). And `test/rename_guard_test.exs` — lives at the top of `test/` so it is not itself moved, and stays permanently as the regression guard.

---

### Task 1: Guard test and baseline

The regression risk in this plan is not "the app fails to compile" — the compiler catches that loudly. It is "a sed quietly rewrote 556 play codes". This task writes the test that catches exactly that, and captures the numbers later tasks compare against.

**Files:**
- Create: `test/rename_guard_test.exs`
- Create: `/tmp/claude-1000/-home-bogdan-Projects-emothe/3cd49bbd-6e5a-48ff-aa58-0a01bb75bc49/scratchpad/rename-baseline.txt`

**Interfaces:**
- Consumes: nothing.
- Produces: `test/rename_guard_test.exs`, which every later task re-runs. Baseline file holding the pre-rename test count and dev-database row counts.

- [ ] **Step 1: Create the branch**

```bash
cd /home/bogdan/Projects/emothe
git checkout -b rename-to-playcode
git status --porcelain   # must be empty
```

- [ ] **Step 2: Capture the baseline**

```bash
SCRATCH=/tmp/claude-1000/-home-bogdan-Projects-emothe/3cd49bbd-6e5a-48ff-aa58-0a01bb75bc49/scratchpad
mkdir -p "$SCRATCH"
{
  echo "## test suite, before the rename"
  mix test 2>&1 | tail -3
  echo
  echo "## dev database row counts, before the rename"
  mix run -e '
    alias Emothe.Repo
    IO.puts("plays:      #{Repo.aggregate(Emothe.Catalogue.Play, :count)}")
    IO.puts("characters: #{Repo.aggregate(Emothe.PlayContent.Character, :count)}")
    IO.puts("elements:   #{Repo.aggregate(Emothe.PlayContent.Element, :count)}")
    IO.puts("places:     #{Repo.aggregate(Emothe.Places.Place, :count)}")
    IO.puts("users:      #{Repo.aggregate(Emothe.Accounts.User, :count)}")
  '
  echo
  echo "## corpus tokens that must not change"
  printf "EMOTHE#### occurrences: "; git grep -o -E 'EMOTHE[0-9]{4}' -- test/fixtures | wc -l
  printf "distinct play codes:    "; git grep -h -o -E 'EMOTHE[0-9]{4}' -- test/fixtures | sort -u | wc -l
  printf "emothe.uv.es:           "; git grep -o 'emothe\.uv\.es' | wc -l
} | tee "$SCRATCH/rename-baseline.txt"
```

Keep this output. Task 2 and Task 5 compare against it.

- [ ] **Step 3: Write the failing guard test**

The committed test is `test/rename_guard_test.exs` — read it there rather than from a copy that can drift. It holds thirteen tests in three groups: the new namespace exists and the old one does not; the corpus keeps its identity; and no stale application identity survives in our own source.

Two scanning strategies, deliberately: source cleanliness uses `git grep`, because untracked files are not our source, while corpus protection scans the **filesystem**, because `test/fixtures/tei_files/` is git-ignored and a `perl` sweep does not care what git tracks.

**What writing this test found** — three things that would have shipped as silent breakage:

1. **`plays.emothe_id` is a live database column**, confirmed against `emothe_dev`. With `extract_emothe_idno/1`, `maybe_derive_emothe_id/1` and `emothe_id_derived?/1` around it. It holds the EMOTHE project's identifier for a play: corpus vocabulary, not the application's name.
2. **`@default_path "doc/w3emothe_T01_tituloEM.ndjson"`** in the FileMaker importer names a real file on disk. Rewriting it to `w3playcode_...` compiles perfectly and finds nothing.
3. **The TEI bulk fixtures are git-ignored** (`.gitignore:38`), so the 78-code figure in an earlier draft came from a filesystem grep. 55 fixtures are tracked as `test/fixtures/EMOTHE####_*.xml`; 41 more sit untracked in `test/fixtures/tei_files/`.

All three are now exceptions in the substitution rule and assertions in the guard.

- [ ] **Step 4: Run it and watch it fail**

```bash
mix test test/rename_guard_test.exs
```

Expected: failures on the namespace tests (`Playcode.Catalogue` does not exist, `Emothe.Catalogue` does) and on both `offenders/1` tests. The four corpus tests should already pass — they assert the state you are protecting.

- [ ] **Step 5: Commit**

```bash
git add test/rename_guard_test.exs
git commit -m "test: guard the Emothe -> Playcode rename boundary

Fails until the rename lands. Stays afterwards so a future careless
search-and-replace cannot silently rewrite the 78 EMOTHE play codes,
the gettext brand strings, emothe.uv.es or the FileMaker fixtures.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: The code rename

Indivisible. A half-renamed Elixir application does not compile, so there is no smaller step that ends in a green suite.

**Files:**
- Move: `lib/emothe/` → `lib/playcode/`, `lib/emothe.ex` → `lib/playcode.ex`, `lib/emothe_web/` → `lib/playcode_web/`, `lib/emothe_web.ex` → `lib/playcode_web.ex`, `test/emothe/` → `test/playcode/`, `test/emothe_web/` → `test/playcode_web/`, `lib/mix/tasks/emothe.*.ex` → `lib/mix/tasks/playcode.*.ex`
- Modify: every tracked file under `lib/`, `test/`, `config/`, `assets/`, `priv/repo/`, plus `mix.exs`
- Test: `test/rename_guard_test.exs` plus the full suite

**Interfaces:**
- Consumes: the guard test from Task 1.
- Produces: `Playcode.*` and `PlaycodeWeb.*` modules, OTP app `:playcode`, mix tasks `playcode.import.tei`, `playcode.import.filemaker`, `playcode.export.site`, `playcode.invite`, databases `playcode_dev` / `playcode_test`, esbuild/tailwind profile `playcode`, session key `_playcode_key`.

- [ ] **Step 1: Move the trees with `git mv` so history follows**

```bash
cd /home/bogdan/Projects/emothe
git mv lib/emothe            lib/playcode
git mv lib/emothe.ex         lib/playcode.ex
git mv lib/emothe_web        lib/playcode_web
git mv lib/emothe_web.ex     lib/playcode_web.ex
git mv test/emothe           test/playcode
git mv test/emothe_web       test/playcode_web

for f in lib/mix/tasks/emothe.*.ex; do
  git mv "$f" "${f/emothe./playcode.}"
done

git status --short | head -20
```

- [ ] **Step 2: Rewrite the identifiers**

Two rules, applied in order. The first only ever touches a capital `E`, so it cannot interfere with the second, and neither can touch upper-case `EMOTHE`.

```bash
git ls-files -z \
    lib test config mix.exs assets priv/repo \
    ':(exclude)test/fixtures' \
    ':(exclude)test/rename_guard_test.exs' \
  | xargs -0 perl -pi -e 's/\bEmothe/Playcode/g; s/(?<!w3)emothe(?!\.uv\.es|_id|_project_description)/playcode/g'
```

Why each piece:
- `\bEmothe` → `Playcode` also fixes `EmotheWeb` → `PlaycodeWeb`, since `Emothe` is its prefix.
- The lower-case rule deliberately has **no** `\b`, because `_emothe_key` in `endpoint.ex` has a word character before the `e` and a `\b` would skip it.
- `(?!\.uv\.es)` is the only exception, and it is why this is `perl` and not `sed` — GNU sed has no lookahead.
- `test/fixtures` is excluded because of the FileMaker table name; the guard test is excluded because it names the old identity on purpose.

- [ ] **Step 3: Rewrite the gettext source references**

The PO/POT files hold 934 `#:` comments pointing at `lib/emothe_web/...`. They belong in
this task because the guard test scans `priv/gettext` — leaving them would end the task
with a red suite.

Do **not** reach for `mix gettext.extract --merge` here. CLAUDE.md records that it
fuzzy-matches new strings onto unrelated existing translations, and there is nothing to
extract: only paths moved. Three literal path substitutions, so a `msgid` can never be
caught:

```bash
perl -pi -e '
  s{lib/emothe_web}{lib/playcode_web}g;
  s{lib/emothe}{lib/playcode}g;
  s{test/emothe}{test/playcode}g;
' priv/gettext/default.pot priv/gettext/*/LC_MESSAGES/default.po
```

Then confirm the paths are clean and the twelve brand strings survived:

```bash
grep -rn 'emothe' priv/gettext/ | grep -v 'EMOTHE' || echo "paths clean"
grep -E '^(msgid|msgstr)' priv/gettext/es/LC_MESSAGES/default.po | grep -c 'EMOTHE'
grep -c 'msgstr "Biblioteca Digital EMOTHE"' priv/gettext/es/LC_MESSAGES/default.po
```

Expected: `paths clean`, then `12`, then `1`.

- [ ] **Step 4: Clear the build, including the colocated-hooks directory**

`assets/js/app.js` imports from `phoenix-colocated/emothe`, which Phoenix generates into `_build/<env>/phoenix-colocated/<otp_app>/`. Step 2 rewrote the import; the stale directory must go or esbuild resolves the old path.

```bash
rm -rf _build
```

- [ ] **Step 5: Format and compile**

```bash
mix format
mix compile --warnings-as-errors
```

Expected: clean compile. If a module is reported undefined, it is almost certainly a string-built module name that the regex could not see — search for it with `git grep -n 'Module.concat\|String.to_existing_atom'`.

- [ ] **Step 6: Run the full suite**

```bash
mix test
```

Expected: the same pass/fail counts as `rename-baseline.txt` from Task 1 Step 2, and `test/rename_guard_test.exs` now fully green. The test database `playcode_test` is created automatically by the `test` alias.

- [ ] **Step 7: Drop the orphaned test database**

```bash
psql -lqt | cut -d'|' -f1 | grep -w emothe_test && dropdb emothe_test || echo "already gone"
```

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor: rename the application namespace Emothe -> Playcode

The backend will generate the static sites for both EMOTHE and ARTELOPE,
so Emothe.Catalogue was the wrong name for shared code. Renames the
module namespace, the :emothe OTP app, the lib/ and test/ trees, the mix
tasks, the asset profiles, the session cookie key and the database names.

Leaves untouched, deliberately: the EMOTHE play codes, the EMOTHE brand
in the UI copy, emothe.uv.es, and the FileMaker export fixtures.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Deployment — add `playcode`, keep `emothe` switchable

Measured on 2026-09-21, not assumed:

```
https://emothe.fly.dev          200, /plays 200, serves the real app
https://emothe-web.onrender.com 404, the blueprint was never applied
```

So the Fly app is **live** and the Render blueprint is not. That asymmetry drives the whole task.

Four consequences, each of which the steps below handle:

1. **A Fly app cannot be renamed.** You create a second app and cut over. `fly.toml` becomes `playcode`; the old config survives as `fly.emothe.toml`.
2. **Merging this branch deploys.** `.github/workflows/deploy-fly.yml` runs on `workflow_run` when CI succeeds on `main`. If `fly.toml` says `app = 'playcode'` and that app does not exist yet, the deploy fails with `Could not find App 'playcode'`. **The Fly app must be created before this branch reaches `main`** — see the Operator runbook at the end of this task, which is a human step, not an agent one.
3. **The release binary follows the code, not the app.** After Task 2 the release is `playcode`, so *both* configs must call `/app/bin/playcode eval Playcode.Release.migrate` — including the one whose Fly app is still named `emothe`.
4. **Fly secrets cannot be read back.** `fly secrets list` prints names and digests only. Before creating the new app you need the *values* of `DATABASE_URL`, `ADMIN_EMAILS`, `SMTP_HOST`, `SMTP_USERNAME`, `SMTP_PASSWORD` from wherever they came from originally. `SECRET_KEY_BASE` is the exception — regenerate it and accept that everyone logs in again.

**Files:**
- Create: `fly.emothe.toml`
- Modify: `fly.toml`, `Dockerfile`, `Dockerfile.render`, `entrypoint.sh`, `render.yaml`, `.gitignore`, `.github/workflows/ci.yml`, `.github/workflows/deploy-fly.yml`

**Interfaces:**
- Consumes: release name `playcode` and module `Playcode.Release` from Task 2.
- Produces: release binary at `/app/bin/playcode`; Fly app `playcode` as the CI deploy target; Fly app `emothe` retained, hand-deployable, and switchable off; CI database `playcode_test`.

- [ ] **Step 1: Preserve the current Fly config as the legacy one**

```bash
cd /home/bogdan/Projects/emothe
cp fly.toml fly.emothe.toml
```

Then edit `fly.emothe.toml` so it keeps the old **app identity** but the new **release binary**, and explains itself:

```toml
# Legacy Fly app for the backend, from before the 2026-09-21 rename to Playcode.
#
# The app is still called 'emothe' because a Fly app cannot be renamed; the
# release binary is 'playcode' because that follows the code, which was renamed.
#
# CI does NOT deploy this file — .github/workflows/deploy-fly.yml deploys fly.toml
# (the playcode app). Deploy this one by hand only:
#
#     fly deploy --config fly.emothe.toml
#
# To switch it off once playcode has taken over, destroy its machines. With no
# machines, auto_start_machines has nothing to start, so it stops serving:
#
#     fly scale count 0 -a emothe
#     fly status -a emothe          # confirm zero machines
#
# To bring it back:  fly scale count 1 -a emothe
# To retire it for good, once you are certain:  fly apps destroy emothe

app = 'emothe'
primary_region = 'cdg'
kill_signal = 'SIGTERM'
kill_timeout = '30s'

[build]
  dockerfile = 'Dockerfile'

[deploy]
  release_command = '/app/bin/playcode eval Playcode.Release.migrate'

[env]
  PHX_HOST = 'emothe.fly.dev'
  PHX_SERVER = 'true'
  POOL_SIZE = '10'
  PORT = '8080'

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = 'stop'
  auto_start_machines = true
  min_machines_running = 0
  processes = ['app']

  [http_service.concurrency]
    type = 'connections'
    hard_limit = 250
    soft_limit = 200

[[vm]]
  memory = '1gb'
  cpu_kind = 'shared'
  cpus = 1
  memory_mb = 1024
```

- [ ] **Step 2: Point `fly.toml` at the new app**

Change exactly four lines; leave the rest of the file identical so the two configs stay easy to diff.

```bash
perl -pi -e "
  s/generated for emothe on/generated for playcode on/;
  s/^app = 'emothe'\$/app = 'playcode'/;
  s{/app/bin/emothe eval Emothe\.Release\.migrate}{/app/bin/playcode eval Playcode.Release.migrate};
  s/^  PHX_HOST = 'emothe\.fly\.dev'\$/  PHX_HOST = 'playcode.fly.dev'/;
" fly.toml

diff fly.emothe.toml fly.toml
```

Expected diff: the header comment block, `app`, `PHX_HOST`. Nothing else.

- [ ] **Step 3: Rewrite the shared build and run files**

`Dockerfile` and `entrypoint.sh` are shared by both Fly apps, so they follow the release binary unconditionally.

`Dockerfile.render` and `render.yaml` ride along. Render itself is out of scope — the blueprint was never applied and no Render service is being designed — but leaving them behind would strand `/app/bin/emothe` references in a tree where no such binary exists. One command, no design work.

```bash
perl -pi -e 's/\bEmothe/Playcode/g; s/(?<!w3)emothe(?!\.uv\.es|_id|_project_description)/playcode/g' \
  Dockerfile Dockerfile.render entrypoint.sh render.yaml .gitignore

git diff --stat Dockerfile Dockerfile.render entrypoint.sh render.yaml .gitignore
```

Expected: `_build/prod/rel/emothe` → `.../playcode` and `/app/bin/emothe` → `/app/bin/playcode` in both Dockerfiles, both lines of `entrypoint.sh`, the `playcode-db` / `playcode-web` / `preDeployCommand` lines in `render.yaml`, and `emothe-*.tar` → `playcode-*.tar` in `.gitignore`.

- [ ] **Step 4: Update CI**

The test database name follows the code. The health check follows the new Fly app.

```bash
perl -pi -e 's/emothe_test/playcode_test/g' .github/workflows/ci.yml
perl -pi -e 's{https://emothe\.fly\.dev}{https://playcode.fly.dev}' .github/workflows/deploy-fly.yml

grep -n 'playcode' .github/workflows/ci.yml .github/workflows/deploy-fly.yml
```

Expected: `POSTGRES_DB: playcode_test`, the CI `DATABASE_URL` ending `/playcode_test`, and the smoke test hitting `https://playcode.fly.dev`. `--config fly.toml` in the deploy step is already correct and needs no change.

- [ ] **Step 5: Verify the release builds under the new name**

The only check that proves `mix release` and both Dockerfiles agree on the path.

```bash
MIX_ENV=prod mix release --overwrite 2>&1 | tail -5
ls -l _build/prod/rel/playcode/bin/playcode
grep -n 'rel/playcode\|bin/playcode' Dockerfile Dockerfile.render entrypoint.sh
```

Expected: the release builds, the binary exists at exactly that path, and every reference in the three files points at it.

- [ ] **Step 6: Verify nothing stale is left**

```bash
git grep -n -P '(?<!w3)emothe(?!\.uv\.es|_id|_project_description)|\bEmothe' -- \
  Dockerfile Dockerfile.render fly.toml render.yaml entrypoint.sh .gitignore .github
```

Expected: **no output.** `fly.emothe.toml` is deliberately absent from the path list, because it is supposed to still say `emothe`. Anything this command prints is a genuine miss. To see the legacy file's intentional hits, ask for them: `git grep -n emothe -- fly.emothe.toml`.

- [ ] **Step 7: Commit**

```bash
git add fly.toml fly.emothe.toml Dockerfile Dockerfile.render entrypoint.sh \
        render.yaml .gitignore .github
git commit -m "chore: add the playcode deployment target, keep emothe switchable

emothe.fly.dev is live, and a Fly app cannot be renamed in place. fly.toml
now describes a new 'playcode' app, which is what CI deploys; the previous
config survives as fly.emothe.toml for hand deploys and carries the commands
to switch it off once the cutover is done.

Both configs run /app/bin/playcode — the release binary follows the code,
not the app name. Render is out of scope: its blueprint was never applied
(emothe-web.onrender.com 404), so render.yaml and Dockerfile.render get the
mechanical rename only, to avoid stranding dead /app/bin/emothe references.
Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

#### Operator runbook — human steps, before this branch merges

Not agent steps: `flyctl` is not installed here and needs your account credentials. Do these in order. **Do not merge to `main` until Step R3 succeeds**, because CI auto-deploys `fly.toml` on merge.

- [ ] **R1. Collect the secret values.** `fly secrets list -a emothe` shows names only; Fly never returns the values. You need `DATABASE_URL`, `ADMIN_EMAILS`, `SMTP_HOST`, `SMTP_USERNAME`, `SMTP_PASSWORD` from your own records or from the Postgres provider's dashboard.

- [ ] **R2. Create the app and give it the same database.** Pointing both apps at one database is what makes this a cutover rather than a migration — no data moves, no divergence, and rollback is "start the old machines again".

```bash
fly apps create playcode --org <your-org>
fly secrets set -a playcode   DATABASE_URL='<same value the emothe app uses>'   SECRET_KEY_BASE="$(mix phx.gen.secret)"   ADMIN_EMAILS='<same comma-separated list>'   SMTP_HOST='...' SMTP_USERNAME='...' SMTP_PASSWORD='...'
```

`ADMIN_EMAILS` unset means **zero admins** on the new app — `AdminBootstrap` reconciles it at boot. With `SMTP_HOST` unset the mailer silently falls back to the Local adapter and every invitation is dropped.

- [ ] **R3. Deploy the branch by hand and verify.**

```bash
fly deploy --config fly.toml --remote-only
curl -fsSIL https://playcode.fly.dev
curl -s -o /dev/null -w '%{http_code}\n' https://playcode.fly.dev/plays
```

Expected: `200` for both. Log in and confirm the admin area works, since the new `SECRET_KEY_BASE` means fresh sessions.

- [ ] **R4. Merge.** CI now deploys `playcode` on every green build of `main`.

- [ ] **R5. Switch the old app off, once you are satisfied.** Destroying the machines is the real off switch: `auto_start_machines` cannot start a machine that does not exist.

```bash
fly scale count 0 -a emothe
fly status -a emothe                     # expect zero machines
curl -s -o /dev/null -w '%{http_code}\n' https://emothe.fly.dev   # expect a failure, not 200
```

Rollback at any point: `fly scale count 1 -a emothe`. Retire it permanently only when you are sure: `fly apps destroy emothe`.

---

### Task 4: Rename the development database

`emothe_dev` holds real curated work — 82 imported plays, historical time on 11, composition dates on 7, the places gazetteer, user accounts. Rename it in place. Do not drop and re-import: the FileMaker sync is fill-only and a re-import would not reproduce hand-curated values.

**Files:** none. This is a database operation plus a verification.

**Interfaces:**
- Consumes: `config/dev.exs`, which Task 2 already pointed at `playcode_dev`.
- Produces: a `playcode_dev` database whose contents match the Task 1 baseline exactly.

- [ ] **Step 1: Stop anything holding a connection**

`ALTER DATABASE ... RENAME` fails while any session is connected. Stop `mix phx.server`, any `iex -S mix`, and any open database GUI.

```bash
psql -d postgres -c "SELECT count(*) AS open_connections FROM pg_stat_activity WHERE datname = 'emothe_dev';"
```

Expected: `0`. If not, close them, or terminate with:

```bash
psql -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'emothe_dev';"
```

- [ ] **Step 2: Rename**

```bash
psql -d postgres -c "ALTER DATABASE emothe_dev RENAME TO playcode_dev;"
psql -lqt | cut -d'|' -f1 | grep -w playcode_dev
```

- [ ] **Step 3: Verify the corpus came through intact**

```bash
mix run -e '
  alias Playcode.Repo
  IO.puts("plays:      #{Repo.aggregate(Playcode.Catalogue.Play, :count)}")
  IO.puts("characters: #{Repo.aggregate(Playcode.PlayContent.Character, :count)}")
  IO.puts("elements:   #{Repo.aggregate(Playcode.PlayContent.Element, :count)}")
  IO.puts("places:     #{Repo.aggregate(Playcode.Places.Place, :count)}")
  IO.puts("users:      #{Repo.aggregate(Playcode.Accounts.User, :count)}")
'
```

Expected: identical to the "dev database row counts" block in `rename-baseline.txt`. Diff them rather than eyeballing.

- [ ] **Step 4: Verify the play codes in the database are still EMOTHE codes**

The strongest single check that no rename reached the data.

```bash
mix run -e '
  import Ecto.Query
  codes = Playcode.Repo.all(from p in Playcode.Catalogue.Play, select: p.code, order_by: p.code)
  emothe = Enum.count(codes, &String.starts_with?(&1, "EMOTHE"))
  IO.puts("total plays: #{length(codes)}, codes beginning EMOTHE: #{emothe}")
  IO.puts("sample: #{inspect(Enum.take(codes, 5))}")
'
```

Expected: the EMOTHE-prefixed count matches the baseline, and the sample shows codes like `["AL0001", "EMOTHE0010", ...]` — **never** `PLAYCODE0010`. If you see a renamed code, stop: the substitution reached the database and you must restore from the pre-rename state.

- [ ] **Step 5: Boot the application against it**

```bash
mix phx.server
```

Visit `http://localhost:4000/plays`, confirm the catalogue lists plays, open one and confirm the text renders. Stop the server.

- [ ] **Step 6: Nothing to commit**

No tracked files changed. Note the completed rename in the task log and move on.

---

### Task 5: Documentation

Update the docs that describe how to *work in* this repo. Leave the docs that *record what was done* in it.

**Files:**
- Modify: `CLAUDE.md`, `AGENTS.md`, `README.md`, `docs/bare-metal-deployment.md`, `docs/bare-metal-docker-deployment.md`, `docs/build_import_analysis.py`
- Explicitly not modified: `docs/superpowers/plans/**`, `docs/superpowers/specs/**`

**Interfaces:**
- Consumes: the final command names from Tasks 2 and 4.
- Produces: accurate onboarding instructions.

- [ ] **Step 1: Rewrite the live docs**

```bash
perl -pi -e 's/\bEmothe/Playcode/g; s/(?<!w3)emothe(?!\.uv\.es|_id|_project_description)/playcode/g' \
  CLAUDE.md AGENTS.md README.md \
  docs/bare-metal-deployment.md docs/bare-metal-docker-deployment.md \
  docs/build_import_analysis.py
```

- [ ] **Step 2: Fix what the regex cannot know**

Three things in `CLAUDE.md` need a human edit, because they are prose about identity rather than identity itself:

1. **The title line.** It reads `# EMOTHE - Digital Theatre Play Management System`. Step 1 left it alone, because the heading is upper-case `EMOTHE` and the rules never touch that form. Correct for a brand string, wrong for a heading that names the application. Replace it by hand with:

```markdown
# Playcode — Digital Theatre Play Management System

The backend behind the EMOTHE and ARTELOPE public sites. It manages,
catalogues and exports digitized early modern European theatre plays
(16th–17th century), and generates the static HTML those sites publish.
EMOTHE and ARTELOPE remain the public brands; Playcode is the internal
platform. Reference site: https://emothe.uv.es
```

2. Add a note under **How To Work In This Repo** so future readers are not confused by the archive:

```markdown
**Naming:** the application was renamed `Emothe` → `Playcode` on 2026-09-21.
Plans and specs under `docs/superpowers/` written before that date use the
old namespace and are left as written — they are a record of work done, not
instructions. Upper-case `EMOTHE` is never the application: it is a play
code (`EMOTHE0010`), the corpus, or the public brand.
```

3. Check the "Running Commands" and corpus-loading sections now read `mix playcode.import.tei`, `mix playcode.import.filemaker`, `mix playcode.export.site`, `mix playcode.invite`, and that the break-glass line reads `bin/playcode rpc 'Playcode.Release.invite_url("...")'`.

4. **Correct the stale deployment claim.** The "What Still Needs To Be Done" list says Fly.io deployment is unfinished — "What is left is setting the secrets and running `fly deploy`". It is done: `emothe.fly.dev` served a 200 on 2026-09-21. Replace that bullet with:

```markdown
- [x] **Fly.io deployment** — live. `fly.toml` deploys the `playcode` app
  (`playcode.fly.dev`); `.github/workflows/deploy-fly.yml` deploys it on every
  green CI run on `main`. The pre-rename app survives as `fly.emothe.toml`
  (`emothe.fly.dev`), hand-deployed only, switched off with
  `fly scale count 0 -a emothe`. Secrets required on each app: `DATABASE_URL`,
  `SECRET_KEY_BASE`, `ADMIN_EMAILS` (**unset means zero admins**), `SMTP_HOST`,
  `SMTP_USERNAME`, `SMTP_PASSWORD`. With `SMTP_HOST` unset the mailer falls back
  to the Local adapter and **every invitation is silently dropped** — use
  `bin/playcode rpc 'Playcode.Release.invite_url("...")'` instead.
- [ ] **Render** — `render.yaml` exists but has never been applied.
```

```bash
grep -n 'mix playcode\.\|bin/playcode\|Playcode.Release' CLAUDE.md
```

- [ ] **Step 3: Confirm the archive was not touched**

```bash
git status --porcelain docs/superpowers/ || echo "archive untouched"
```

Expected: no output from `git status` for those paths.

- [ ] **Step 4: Confirm the domain survived the docs pass**

```bash
git grep -c 'emothe\.uv\.es' -- CLAUDE.md docs/
```

Expected: non-zero, and unchanged from the baseline count.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md AGENTS.md README.md docs/bare-metal-deployment.md \
        docs/bare-metal-docker-deployment.md docs/build_import_analysis.py
git commit -m "docs: describe the repo as Playcode

Live documentation only. Plans and specs under docs/superpowers/ keep the
old namespace: they record work already done and rewriting them would
falsify the history.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Tooling settings and final verification

**Files:**
- Modify: `.claude/settings.json`

**Interfaces:**
- Consumes: everything above.
- Produces: a branch ready to merge.

- [ ] **Step 1: Fix the stale test path in the permission rules**

`.claude/settings.json` holds absolute paths into `/home/bogdan/Projects/emothe`, which is **still the correct directory** — the repo folder is not being renamed. Only the paths *inside* the repo moved. Change just those:

```bash
perl -pi -e 's{test/emothe/}{test/playcode/}g' .claude/settings.json
grep -n 'Projects/emothe' .claude/settings.json
```

Expected: `Projects/emothe` still appears (correct — the directory did not move), and no `test/emothe/` remains.

- [ ] **Step 2: Full verification sweep**

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

Expected: formatted, no warnings, and the same pass count as `rename-baseline.txt` plus the new guard test's assertions.

- [ ] **Step 3: Confirm the mix tasks are registered under the new names**

```bash
mix help | grep playcode
```

Expected: `mix playcode.export.site`, `mix playcode.import.filemaker`, `mix playcode.import.tei`, `mix playcode.invite`.

- [ ] **Step 4: Exercise one task end to end**

A registered task is not a working task. The dry-run writes nothing.

```bash
mix playcode.import.tei --dry-run 2>&1 | tail -20
```

Expected: a report naming EMOTHE play codes and what it would do. The codes in that output must still read `EMOTHE####`.

- [ ] **Step 5: Confirm the guard passes on the whole tree**

```bash
mix test test/rename_guard_test.exs --trace
```

Expected: every test green, including both `offenders/1` scans.

- [ ] **Step 6: Review the complete diff for corpus damage**

The last human check. Look specifically for any line where a play code, a domain or a brand string changed.

```bash
git diff main...HEAD -- . ':(exclude)priv/gettext' | grep -E '^[-+].*(EMOTHE[0-9]|emothe\.uv\.es|PLAYCODE[0-9])' | sort -u
```

Expected: **no output**. Any `+PLAYCODE0010` or `-EMOTHE0010` line is a corrupted play code — stop and fix before merging.

- [ ] **Step 7: Commit and finish the branch**

```bash
git add .claude/settings.json
git commit -m "chore: point the tooling permission rules at the renamed test tree

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

Then use the `superpowers:finishing-a-development-branch` skill to decide how this integrates.

---

### Task 7: Rename the repository (optional, do it last)

Run this only after Tasks 1–6 are merged and the Fly cutover (runbook R5) is done. It touches nothing inside the application, and nothing here is reversible by `git checkout`.

**Decision: rename the existing repository. Do not create a new `playcode` repo and copy the changed files into it.** Copying loses the history that links every plan under `docs/superpowers/` to the commits that implemented it, loses `git blame` on the TEI parser and the exporters, and loses the repository's issues, Actions secrets and `production` environment. It also performs none of the work: a new repository does not rename a single module. GitHub's own rename preserves all of that and redirects the old URL, so clones keep working until their remote is updated.

**Files:**
- Modify: `.claude/settings.json`
- Outside the repo: the GitHub repository name, the working directory, the assistant's project-memory directory

- [ ] **Step 1: Remove the stray remote**

`git remote -v` shows a `bitbucket` remote pointing at `git@bitbucket.org:c57-nl/socialplatforms.git` — an unrelated work repository. A stray `git push bitbucket` from here would publish this project into it.

```bash
git remote -v
git remote remove bitbucket
git remote -v
```

Expected: only `origin` remains.

- [ ] **Step 2: Rename on GitHub**

Settings → Repository name → `playcode` → Rename. GitHub redirects `bogmir/emothe` to `bogmir/playcode` and keeps issues, Actions secrets and the `production` environment.

- [ ] **Step 3: Point the remote at the new name**

The redirect means the old URL keeps working, so this is hygiene rather than repair — but do it before the redirect confuses someone.

```bash
git remote set-url origin https://github.com/bogmir/playcode.git
git remote -v
git fetch origin
```

- [ ] **Step 4: Rename the working directory**

Close the editor and every shell sitting inside the directory first, or the move leaves them pointing at a path that no longer exists.

```bash
cd ~/Projects
mv emothe playcode
cd playcode
```

- [ ] **Step 5: Rebuild from scratch**

Elixir build artifacts and fetched dependencies embed absolute paths. Without this, compilation fails with paths under the old directory.

```bash
rm -rf _build deps
mix deps.get
mix compile --warnings-as-errors
mix test
```

Expected: full green, matching the counts in `rename-baseline.txt`.

- [ ] **Step 6: Fix the absolute paths in the tooling settings**

```bash
perl -pi -e 's{/home/bogdan/Projects/emothe}{/home/bogdan/Projects/playcode}g' .claude/settings.json
perl -pi -e 's{cd ~/Projects/emothe.*}{cd ~/Projects/playcode}' CLAUDE.md
grep -n 'Projects/' .claude/settings.json CLAUDE.md
```

`CLAUDE.md`'s Getting Started block deliberately still says `cd ~/Projects/emothe`, with a comment pointing here, because until this task runs that is the directory that exists.

Expected: every path now reads `Projects/playcode`.

- [ ] **Step 7: Move the assistant's project memory**

Claude Code keys its per-project memory on the directory path, so renaming the directory otherwise starts from an empty memory.

```bash
mv /home/bogdan/.claude/projects/-home-bogdan-Projects-emothe \
   /home/bogdan/.claude/projects/-home-bogdan-Projects-playcode
ls /home/bogdan/.claude/projects/-home-bogdan-Projects-playcode/memory/
```

Expected: `MEMORY.md`, `mix-path-not-needed.md`, `places-slug-async-deadlock.md`, `sales-pitch.md`.

- [ ] **Step 8: Commit**

```bash
git add .claude/settings.json
git commit -m "chore: point the tooling paths at the renamed directory

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Rollback

Every task is its own commit on a branch, and nothing outside the repo changes except the dev database. To abandon:

```bash
git checkout main
git branch -D rename-to-playcode
psql -d postgres -c "ALTER DATABASE playcode_dev RENAME TO emothe_dev;"
rm -rf _build
mix deps.get && mix compile
```

## Deliberately not in scope

- Rewriting `docs/superpowers/plans/**` and `docs/superpowers/specs/**`.
- Any change to the public EMOTHE brand, the 78 play codes, or `emothe.uv.es`.
- Adding ARTELOPE as a second corpus. That is the work this rename unblocks, not part of it.
