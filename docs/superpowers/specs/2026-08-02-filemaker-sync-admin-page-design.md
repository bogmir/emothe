# FileMaker sync — admin page

**Date:** 2026-08-02
**Status:** approved, not yet implemented
**Roadmap:** `docs/superpowers/plans/2026-08-01-filemaker-import-slices.md`
**Depends on:** S1 (`Emothe.Import.Filemaker`, `Emothe.Import.FilemakerSync`), S2a (curated fields, `force`)

## Why this page exists

`mix emothe.import.filemaker` does what this page does. It is unreachable by the people who need it.

1. **Mix does not exist in a release.** The Fly image runs `/app/bin/emothe`; there is no `mix`
   task in production. This is the hard reason, not a convenience argument.
2. **The researchers cannot ssh.** Every other operation in this project got an admin page for the
   same reason.
3. **Provenance.** `apply_plan/2` already accepts `:user_id` and only a LiveView has one. Today
   every FileMaker write lands in `activity_logs` as nobody, because the mix task passes `nil`.
4. **Conflicts need a human.** Fill-only exists precisely so that a curator's edit is not stomped.
   A conflict list next to a per-row checkbox is the point; the same list printed into an ssh
   session is not reviewable by the person who curated the value.

Today's fallback, which the page replaces: `fly ssh sftp shell` to push the export, then
`/app/bin/emothe rpc` — **not** `eval`, which loads the application without starting it and so has
no Repo. Not verified against the live app.

## Why it is small

The domain layer was built for this and needs **no changes**. `FilemakerSync.plan/3` is pure and
returns exactly what a preview screen needs; that is why the mix task can print it.
`apply_plan/2` already takes `:user_id` and `:force`.

Scope: one LiveView, one route in the existing admin scope, one nav entry, tests. Zero schema
changes, zero changes to `Filemaker`, `FilemakerSync` or the mix task.

The upload → preview → confirm/cancel shape already exists in
`lib/emothe_web/live/admin/import_live.ex`; `TeiParser.preview_import/1` is the precedent for a
preview that reports what would be replaced and what kept.

## Deployment context

Read from `Dockerfile`, `fly.toml` and `lib/emothe/release.ex`:

- **The export is not in the image and must not be.** The Dockerfile copies
  `mix.exs mix.lock config priv lib assets`. `doc/` is git-ignored; `test/` is not copied. Baking
  the NDJSON into `priv/` contradicts the roadmap's governing rule — *the export is a bootstrap,
  not a dependency*. The file arrives by upload, every time.
- **Ephemeral disk.** No `[mounts]` in `fly.toml`; `auto_stop_machines = 'stop'` with
  `min_machines_running = 0`. Anything written to disk survives until the next stop. This is why
  the design keeps nothing.
- Migrations already run on deploy via
  `release_command = '/app/bin/emothe eval Emothe.Release.migrate'`.

`CLAUDE.md` is stale on this point — it still lists "Fly.io deployment configuration" under things
to do, while `Dockerfile` and `fly.toml` are both present. Fix that line as part of this slice.

## Route, nav, module

```elixir
live "/admin/filemaker", FilemakerSyncLive, :index
```

Inside the existing `live_session :admin` in `lib/emothe_web/router.ex:105`, which already carries
`:require_authenticated_user`, `:require_admin_user` and the `ensure_admin` on-mount hook.

A sibling of `/admin/export` and `/admin/activity-log`, **not** under `/admin/plays/*`: the page
operates on the whole corpus, not on one play.

Nav entry `gettext("FileMaker sync")` after "Import" in
`lib/emothe_web/components/layouts/admin.html.heex:14`.

One new file: `lib/emothe_web/live/admin/filemaker_sync_live.ex`.

## Flow and state

Three states off a single assign, `@plan`:

| `@plan` | `@results` | Screen |
|---|---|---|
| `nil` | `nil` | Upload form |
| set | `nil` | Four buckets, Apply, Discard |
| — | set | Outcome table |

```elixir
allow_upload(:export, accept: ~w(.ndjson .json), max_entries: 1, max_file_size: 20_000_000)
```

20 MB matches `import_live.ex`. The real export is 1.8 MB across 649 lines, so this is an order of
magnitude of headroom and needs no thought again.

On submit, **inside** the `consume_uploaded_entries` callback: `Filemaker.load_index/1`,
`Filemaker.load_versions/1`, then `FilemakerSync.plan/3` against `FilemakerSync.all_plays()`. The
plan goes into assigns; the file is never copied anywhere. The upload's own temp path dies with the
request, so there is nothing to clean up on cancel, on apply, or on a dropped socket — the question
of what happens to the uploaded file stops being a question.

`load_index/1` returning `{:error, reason}` puts a flash and leaves the form alone. A plan with
neither `changes` nor `conflicts` renders "everything already matches" and no Apply button.

### Synchronous, deliberately

No `start_async`, no progress bar. 649 lines parsed, 82 plays diffed in memory, roughly 11 rows
updated. The work happens in the submit event. A `ponytail:` comment names the ceiling and the
upgrade path: if the export grows an order of magnitude, move the parse into `start_async`.

Confirm the timing during implementation rather than assuming it; if a plan takes longer than a
second on the real 1.8 MB export, take the async path instead of shipping a page that appears
frozen.

## Rendering the buckets

### Field-agnostic, which is the one hard constraint

Each later sub-slice — S2b `place_of_action`, then S2c–S2f — adds a field to `load_versions/1` and
therefore a new entry in `sets` and a new possible `conflict.field`. **Nothing in the template names
a column.** Changes iterate `change.sets` as `{field, value}` pairs. Two helpers with catch-all
clauses keep an unknown field from crashing or rendering as a bare atom:

```elixir
defp field_label(:historical_time), do: gettext("Historical time")
# …one clause per field we already know about…
defp field_label(other), do: other |> to_string() |> String.replace("_", " ")

defp value_label(:historical_time, value), do: PlayLabels.historical_time_label(value)
defp value_label(:parent_play_id, id), do: codes_by_id(id)
defp value_label(_field, value), do: to_string(value)
```

`codes_by_id/1` reads a `%{play_id => code}` map built from the `all_plays/0` call the plan already
needed — a raw UUID in a researcher-facing diff is not a value.

S2b lands and this page renders it correctly with no edit at all. Adding a `field_label/1` clause is
polish, not a requirement.

### Four sections, not tabs

`missing` and `changes` are **not** mutually exclusive. A play can be absent from the published
index and still carry a `T01` research record; `EMOTHE0341` is exactly that, and
`test/emothe/import/filemaker_sync_test.exs` has a test for it. Tabs would imply an exclusivity that
does not hold, so the buckets are stacked sections.

| Bucket | Treatment |
|---|---|
| `changes` | Table: code, title, one line per `sets` entry — field label, new value |
| `conflicts` | Warning card, one row per conflict: field, current value, indexed value, **checkbox** |
| `unchanged` | Count, plus a collapsed `<details>` of codes |
| `missing` | Count, plus a collapsed `<details>`, with "not in the published index — nothing is created" |

The `missing` copy matters: every `AL####` play is permanently in that bucket and a curator seeing
60 codes under a heading needs to know it is normal, not a failure.

## Apply

Ticked conflicts live in a `MapSet` of `{play_id, field}`, toggled by one event. Apply is one
expression:

```elixir
%{plan | conflicts: Enum.filter(plan.conflicts, &selected?(&1, selected))}
|> FilemakerSync.apply_plan(user_id: current_user.id, force: true)
```

`force: true` always. **The selection is the force list.** `writes/2`'s force branch folds
`plan.conflicts` into the writes, so narrowing that list before the call gives per-conflict force
for free, and an empty selection reduces exactly to `force: false` — an empty `forced` map leaves
`plan.changes` untouched and appends nothing. One code path, no branch on whether anything was
ticked, and no signature change anywhere in the domain layer.

Per-conflict was chosen over a single all-or-nothing force button because it is the honest UI for
"a researcher curated this value", and it turned out to cost nothing. Had it required changing
`apply_plan/2`'s signature, the all-or-nothing button would have been the right call.

`apply_plan/2` already writes one `activity_logs` row per play, with
`metadata: %{"source" => "filemaker_index"}` and the `sets` as `changes`. Passing `user_id` is the
whole point of reason 3 above.

Its return value is a list of `{:ok, code}` and `{:error, code, changeset}`. The results screen
shows the successes as a count and the failures as rows with the changeset errors; a flash carries
the summary.

**Known ceiling:** the plan is computed at upload and applied later, so it can go stale if another
curator edits a play in between. This is a single-curator tool run a handful of times a year; the
upgrade path — hold the parsed index and versions maps and re-plan at Apply — goes in a `ponytail:`
comment, not in this slice.

**Open on another branch:** `redesign-auth-admin` is reworking authentication. Whether the current
user arrives as `@current_user` (as `import_live.ex` reads it today) or as `@current_scope` is
settled by that work, not by this spec.

## The page sits beside the mix task

The task is how a developer works locally, and it is what the S1 and S2a archive entries document.
It is not deprecated and not deleted. The two share `plan/3` and `apply_plan/2`, so they cannot
drift.

## Testing

TDD, failing test first, per the top of `CLAUDE.md`. Fixtures already exist:
`test/fixtures/filemaker/index_sample.ndjson` and `versions_sample.ndjson`.

- **Buckets** — an uploaded fixture renders all four with the right counts.
- **Overlap** — a play in both `missing` and `changes` appears in both. Regression test for the
  non-exclusivity above.
- **Selective force** — tick one conflict, Apply, assert that field written and the unticked one
  untouched.
- **Fill-only default** — Apply with nothing ticked writes the fills and overwrites no curated
  value.
- **Provenance** — the `activity_logs` row carries the logged-in admin's `user_id`, not `nil`.
- **Forward compatibility** — a `sets` entry for a field with no `field_label/1` clause renders
  without crashing. This is the test that protects S2b–S2f.
- **Bad upload** — an unparseable file flashes an error and writes nothing.
- **Access** — a non-admin is redirected.
- **Whole suite** — `mix test`, currently 299 passing, before any completion claim.

## Out of scope

- Scheduled or automatic sync. The export arrives by hand because it is produced by hand.
- Storing the export anywhere, in `priv/` or on disk. See the deployment section.
- Editing values on this page. Curation happens in the play form; this page only applies the
  export.
- Any change to `Filemaker`, `FilemakerSync`, the schema, or the mix task.
- S2b–S2f fields. They need no change to this page, which is the point of the field-agnostic
  rendering.
