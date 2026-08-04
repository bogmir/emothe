# FileMaker sync — admin page

**Date:** 2026-08-03
**Status:** approved, not yet implemented
**Roadmap:** `docs/superpowers/plans/2026-08-01-filemaker-import-slices.md`
**Depends on:** S1 (`Emothe.Import.Filemaker`, `Emothe.Import.FilemakerSync`), S2a (`historical_time`), the auth and admin UX work merged in `0696d97`

## Why this page exists

`mix emothe.import.filemaker` does what this page will do. It is unreachable by the people who
need it, for three reasons, in order of weight.

**The researchers cannot ssh.** Every other operation in this project got an admin page for the
same reason. There is no Mix in an OTP release, so the task does not exist in production at all.
The fallback that works today with zero code change is `fly ssh sftp shell` to push the export,
then `/app/bin/emothe rpc` — **not** `eval`, which loads the application without starting it and
therefore has no Repo. That is a developer's procedure, and it is what this page replaces.

**Provenance.** `apply_plan/2` already accepts `:user_id` and only a LiveView has one. Today every
FileMaker write lands in `activity_logs` attributed to nobody, because the mix task passes `nil`.

**Conflicts need a human.** Fill-only exists precisely so that a curator's edit is not stomped. A
conflict list next to a per-row force checkbox is the point of the feature; the same list printed
into an ssh session is not reviewable by the person who curated the value.

## Why it is small

The domain layer was built for this and **needs no changes**. `FilemakerSync.plan/3` is pure and
returns exactly what a preview screen needs — that is why the mix task can print it.
`TeiParser.preview_import/1` and `import_live.ex` are the precedent for upload → preview →
confirm.

Scope: one LiveView, one route, one action atom, one sidebar entry, tests. Zero schema changes,
zero changes to `Emothe.Import.Filemaker` or `Emothe.Import.FilemakerSync`, and the mix task stays
exactly as it is.

## What the data looks like

The real export is `doc/w3emothe_T01_tituloEM.ndjson` — 1.8 MB, 649 lines, git-ignored. One JSON
object per line; `Filemaker` reads two layouts out of it:

- `T00_indiceEM` → `load_index/1` → the published index, keyed by base code
- `T01_tituloEM` → `load_versions/1` → the research records, keyed by the code in the
  `pub_edicionWeb` href

Only 22 of our 82 plays appear in `T01` at all. Every `AL####` play is absent from both layouts.

## The plan, and the two write policies

`FilemakerSync.plan(index, plays, versions)` returns four buckets:

```elixir
plan :: %{changes: [...], unchanged: [...], missing: [...], conflicts: [...]}

change   :: %{play_id: binary(), code: String.t(), title: String.t(), sets: %{atom() => term()}}
conflict :: %{play_id: binary(), code: String.t(), title: String.t(),
              field: atom(), current: term(), indexed: term()}
```

Two policies live side by side, stated in the module doc and repeated here because the page has to
explain them to a curator:

| Kind | Fields | Behaviour |
|---|---|---|
| Derived | `language`, `relationship_type`, `parent_play_id` | The index is authoritative. A difference is an error in our data and is overwritten. |
| Curated | `historical_time`, `historical_time_note` | The export is a bootstrap. A blank column is filled; a disagreement is reported under `conflicts` and left alone. |

Nothing here ever creates a play.

## Route, permission, navigation

One route in the existing admin `live_session`:

```elixir
live "/admin/filemaker", FilemakerSyncLive, :index
```

Not under `/admin/plays/*` — it operates on the whole corpus, not one play. It sits beside
`/admin/export` and `/admin/activity-log`.

**Permission: a new `:import_filemaker`, admin-only.** It joins the admin block in
`lib/emothe/authz.ex`:

```elixir
@admin_actions @researcher_actions ++
                 ~w(purge_play manage_users view_activity_log deploy_site
                    view_dashboard import_filemaker)a
```

Admin-only rather than researcher-level, unlike `:import_tei`: this sync is corpus-wide and its
force path overwrites curated research metadata across every play at once, where a TEI import
replaces one named file's play.

**No new router pipeline.** The scope pipeline stays `:require_admin_area` (`:view_admin`) and the
LiveView tightens the gate itself — the pattern `user_list_live.ex` already uses for
`:manage_users`, which is likewise admin-only inside that same session:

```elixir
# Stricter than the live_session's :view_admin, declared here so admin
# sections still navigate without a full page reload.
on_mount {EmotheWeb.UserAuth, {:ensure_can, :import_filemaker}}
```

A researcher passes the scope plug and is refused at mount. They never reach that refusal in
practice, because the sidebar is permission-filtered.

**Navigation** is `sidebar_groups/1` in `lib/emothe_web/components/layouts.ex`, so a nav entry
*requires* an action atom — that filter is what keeps the router and the menu from drifting. One
entry in the "Content" group beside Plays and Import:

```elixir
%{label: gettext("FileMaker"), to: "/admin/filemaker",
  icon: "hero-circle-stack-micro", action: :import_filemaker}
```

`sidebar_active?/3` needs nothing: it picks the longest matching prefix, and `/admin/filemaker`
shares no prefix with another entry.

## The page

Three states off one assign:

| `@plan` | `@results` | Screen |
|---|---|---|
| `nil` | `nil` | Upload form only |
| set | `nil` | Four buckets, per-conflict checkboxes, Apply / Discard |
| `nil` | set | Outcome table (Apply clears the plan) |

```elixir
allow_upload(:export, accept: ~w(.ndjson .json), max_entries: 1, max_file_size: 20_000_000)
```

20 MB matches `import_live.ex` and leaves an order of magnitude of headroom over the 1.8 MB
export. `.json` is accepted alongside `.ndjson` because an export renamed on the way out of
FileMaker is a support call, not a data problem.

### The uploaded file is never kept

On submit, both readers and `plan/3` run **inside** the `consume_uploaded_entries` callback:

```elixir
defp read_plan(path) do
  with {:ok, index} <- Filemaker.load_index(path),
       {:ok, versions} <- Filemaker.load_versions(path),
       true <- map_size(index) > 0 or map_size(versions) > 0 do
    plays = FilemakerSync.all_plays()
    {:ok, FilemakerSync.plan(index, plays, versions), plays}
  else
    false -> {:error, :no_records}
    {:error, reason} -> {:error, reason}
  end
end
```

**The `:no_records` guard is load-bearing, not defensive padding.** `load_index/1` only fails when
`File.read` fails — it decodes line by line and silently drops anything that is not a record for
its layout. Upload the wrong file and both readers return `{:ok, %{}}`, which plans cleanly as
"all 82 plays are not in the published index". That screen is indistinguishable from real data
loss. The guard turns it into an error flash.

`plays` comes back alongside the plan for two reasons: the `%{play_id => code}` map that renders
`parent_play_id`, and the current value in each `changes` row — `change.sets` carries only the new
value, so "current → new" needs the play.

The file is never copied out; LiveView deletes the upload's temp path when the callback returns.
Nothing to clean up on cancel, on apply, or on a disconnect — which matters because the Fly
machine has no persistent volume and stops at zero, so "kept for re-runs" would mean "kept until
the next restart".

The plan is held in assigns, not the file. The ceiling that buys: the preview can go stale if
someone else edits a play between preview and Apply. Single-curator tool; a `ponytail:` comment
names re-planning on Apply as the upgrade path.

### Synchronous, no progress bar

649 lines parsed, 82 plays diffed in memory, roughly 11 rows updated. `import_live.ex` needs its
`handle_info` chain and progress bar because it parses up to 20 TEI files, each rebuilding a whole
play's text. This does not. A `ponytail:` comment names `start_async` as the upgrade path if the
export grows an order of magnitude. The implementation confirms the timing rather than assuming
it.

### Rendering the buckets is field-agnostic

**The single hard constraint on this design.** S2b–S2f each add a field to `load_versions/1` and
therefore a new entry to some `change.sets`. Nothing in the template may name a column. Changes
iterate `sets` as `{field, value}` pairs, and two helpers with catch-all clauses keep an unknown
field from crashing or rendering as a raw atom:

```elixir
defp field_label(:historical_time), do: gettext("Historical time")
# …one clause per field we have a translation for…
defp field_label(other), do: other |> to_string() |> String.replace("_", " ")

defp value_label(:historical_time, v, _plays), do: PlayLabels.historical_time_label(v)
defp value_label(:parent_play_id, id, plays), do: (plays[id] && plays[id].code) || "—"
defp value_label(_field, v, _plays), do: to_string(v)
```

S2b lands and the page renders it correctly with no edit at all; adding a `field_label/1` clause
is polish, not a requirement. `parent_play_id` resolves through `@plays_by_id`, built from the
`all_plays/0` call the plan already needed — a bare UUID is not reviewable.

A unit test on the catch-all clauses is what the test suite can actually guard. That a *template*
never hardcodes a column name is a review matter, not a testable one; the catch-alls are what stop
an unnamed field from crashing or rendering as `:place_of_action`.

### Four sections, not four tabs

`missing` and `changes` are **not** mutually exclusive: `EMOTHE0341` has a `T01` research record
and was never published, so it is in both. Tabs would imply otherwise. There is a test for this in
`test/emothe/import/filemaker_sync_test.exs`.

| Bucket | Treatment |
|---|---|
| `changes` | Table: code, title, one line per `sets` entry, current value → new value |
| `conflicts` | Warning card, one row per conflict: field, current value, indexed value, **checkbox** |
| `unchanged` | Count plus a collapsed `<details>` of codes |
| `missing` | Count plus a collapsed `<details>`, with "not in the published index — nothing is created" |

An empty `changes` and empty `conflicts` renders "everything already matches" and no Apply button.
A file with no recognisable records flashes an error and leaves the form as it was.

### Apply

Selected conflicts are a `MapSet` of `{play_id, field}`, toggled by one event. Apply is one path:

```elixir
%{plan | conflicts: Enum.filter(plan.conflicts, &selected?(&1, selected))}
|> FilemakerSync.apply_plan(user_id: socket.assigns.current_user.id, force: true)
```

Always `force: true`; **the selection is the force list.** An empty selection reduces exactly to
`force: false`, because `writes/2` folds an empty conflict list into nothing. This is why
per-conflict granularity costs no domain change — the honest UI for "a researcher curated this
value" falls out of narrowing the plan before handing it over.

`apply_plan/2` returns `[{:ok, code} | {:error, code, changeset}]` and already writes one
`activity_logs` row per play with `metadata: %{"source" => "filemaker_index"}`. Passing `user_id`
is the second reason this page exists.

### Page shell

`mx-auto max-w-5xl px-4 py-8` with an `h1.text-3xl font-semibold tracking-tight`, following
`user_list_live.ex`. `assign(:page_title, gettext("FileMaker sync"))`. **No `:breadcrumbs`
assign** — breadcrumbs left the admin layout in the auth and admin UX work.
No `:play_context`, so the sidebar starts open,
which is right for a corpus-wide page.

## Testing

Following the repo's TDD rule — failing test first, every time.

The page uploads **one** file carrying both layouts, which is what the real export is; the existing
fixtures are split one layout per file. So `test/fixtures/filemaker/export_sample.ndjson` is the
concatenation of `index_sample.ndjson` and `versions_sample.ndjson` — both readers key off the
`_meta` envelope lines and ignore the other layout's records, so concatenation is all it takes.

Against that fixture and a five-play corpus, the plan is (verified by running `plan/3`, not
guessed): **3 changes** (`EMOTHE0038`, `EMOTHE0211`, `HIE0393`), **2 conflicts** (`EMOTHE0038` and
`HIE0393`, both `historical_time`), **1 unchanged** (`EMOTHE0052`), **2 missing** (`EMOTHE0211`,
`AL0001`) — `EMOTHE0211` in both `changes` and `missing`, which is the case the not-tabs decision
exists for.

Assertions go through `Gettext.gettext(EmotheWeb.Gettext, "…")` rather than literal English, the
convention in `user_list_live_test.exs:85`. The default locale is `"es"`, so a literal-English
assertion passes only until the string is translated.

**Two existing files change first, and their failure is the intended signal, not noise:**

- `test/emothe/authz_test.exs` hardcodes `@admin_only_actions` as a literal. `:import_filemaker`
  goes in it. That literal is the tripwire that catches an action added to the module and nowhere
  else.
- `test/emothe_web/live/admin/layout_test.exs` — the admin test asserts the new href, the
  researcher test refutes it.

**New:**

- A researcher reaching `/admin/filemaker` is refused at mount, mirroring the `:manage_users` test
  in `user_list_live_test.exs`.
- Uploading a fixture renders all four buckets with the right counts. Driven with
  `file_input(lv, "#upload-form", :export, …)`.
- A play in **both** `missing` and `changes` appears in both — the regression test for the
  not-tabs decision.
- Tick one conflict, Apply: that field is written and the other conflicting field is not.
- Apply with nothing ticked: fills are written, no curated value is overwritten.
- The `activity_logs` row carries the logged-in admin's `user_id`.
- A `change.sets` entry for a field with no `field_label/1` clause renders without crashing — this
  guards the S2b–S2f constraint, which is otherwise a promise with nothing enforcing it.
- An unparseable upload flashes an error and writes nothing.
- `mix test` whole suite — 299 passing today — before any completion claim.

## Out of scope

Scheduled or automatic sync. Storing the export anywhere, in `priv/` or on disk: the roadmap's
governing rule is "the export is a bootstrap, not a dependency", and the Dockerfile copies only
`mix.exs mix.lock config priv lib assets` while `doc/` is git-ignored. Editing field values on
this page — that is the play form. Any change to `Filemaker`, `FilemakerSync`, the schema, or the
mix task, which stays as the way a developer works locally and is what the S1 and S2a archive
entries document.

`place_of_action`, `composition_date`, `collection`, `legacy_url`, `original_title` and
`title_sort` are S2b–S2f. Each reuses this page with no edit to it.

## Housekeeping noticed while specifying

- `CLAUDE.md` lists "Fly.io deployment configuration" as still to do. `Dockerfile` and `fly.toml`
  both exist; what is left is setting secrets and running `fly deploy`.
