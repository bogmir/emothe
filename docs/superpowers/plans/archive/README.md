# Completed plans

Plans in this directory shipped. Every checkbox in them is ticked and the behaviour they describe
is in `main`. They are kept because the commit messages point back at them and because the next
slice usually needs to know what the last one decided.

A plan moves here when its acceptance task passes and the work is committed. The roadmap
(`../2026-08-01-filemaker-import-slices.md`) keeps a one-line summary and a pointer.

---

## S0 — Corpus baseline

**Shipped 2026-08-01.** Folded into the S1 plan as Task 1, so it has no plan file of its own.

`Emothe.Import.TeiCorpus` walks the fixture directories, deduplicates by play code (first directory
wins), and feeds each file to the existing TEI parser. `mix emothe.import.tei` wraps it with
`--force`, `--dir` and a summary line.

- 82 of 82 TEI files imported, 19 `AL####` and 63 others. No parse failures.
- One TEI fixture lives in a subdirectory — `EMOTHE0053_Hamlet.xml` is under
  `test/fixtures/tei_files/`, not `test/fixtures/`.

| Commit | |
|---|---|
| `534da8c` | feat: mix task to bulk-import the local TEI corpus |

Files: `lib/emothe/import/tei_corpus.ex`, `lib/mix/tasks/emothe.import.tei.ex`,
`test/emothe/import/tei_corpus_test.exs`.

---

## S0b — Soft delete, re-importable plays, protected hand-entered data

**Shipped 2026-08-01.** Plan: `2026-08-01-soft-delete-and-reimport.md`, all 7 tasks. 261 tests
passing at the time.

The slice that made "the database is the thing of record" true. Before it, deleting a play was
`Repo.delete` — it destroyed the row, its content, its activity history and its children's
`parent_play_id` — and re-importing a TEI file whose code existed rolled back with
`{:play_already_exists, code}`.

What landed:

- `plays.deleted_at`. `Catalogue.delete_play/1` archives, `restore_play/1` clears, `purge_play/1`
  is the destructive path and is wired to no button. Every Catalogue read hides archived plays;
  `include_deleted: true` for both, `archived: true` for only the archived ones. The unique index
  on `plays.code` stays global on purpose, so an archived play keeps its code reserved.
- `origin` on `play_editors`, `play_sources` and `play_editorial_notes` —
  `"tei" | "manual" | "filemaker"`, default `"manual"`. A TEI re-import deletes only its own
  `"tei"` rows.
- `TeiParser.import_file/1` updates in place, same `id`, same history, un-archived.
  `@platform_owned` in `lib/emothe/import/tei_parser.ex` lists the columns a re-import must not
  write.
- `TeiParser.preview_import/1` plus an admin preview and `mix emothe.import.tei --dry-run`.
- Admin archive filter and restore.

**The rule this slice owes every later one:** a new curated `plays` column gets appended to
`@platform_owned`, or the next re-import erases it. A new child table either carries `origin` or
stays outside the importer's reach.

| Commit | |
|---|---|
| `51af78a` | feat: archive plays and make TEI re-imports non-destructive |
| `fb582ff` | feat: say what an import replaces, and let admins archive and restore |
| `cc9d99e` | docs: require TDD, document archiving and provenance |

Also from this slice: `EMOTHE0730_LaMariana` failed on a front-matter `<head>` longer than
`play_divisions.title`'s `varchar(255)`, fixed in Task 3.

---

## S1 — Work families and language

**Shipped 2026-08-01.** Plan: `2026-08-01-s1-work-families-and-language.md`, Tasks 1–6. 277 tests
passing.

`language`, `relationship_type` and `parent_play_id` now come from the FileMaker published index
instead of being guessed from the TEI header. No migration — every column already existed.

- `Emothe.Import.Filemaker` reads `T00_indiceEM.pub_listaObras`, the rendered HTML of every
  published version of a work, into `%{code => version}`. Pure, no database.
- `Emothe.Import.FilemakerSync.plan/2` diffs it against the database and writes nothing;
  `apply_plan/2` performs the writes and logs one `activity_logs` row per play with
  `metadata.source = "filemaker_index"`.
- `mix emothe.import.filemaker [--dry-run] [--path ...]`.

**Result of the acceptance run against `emothe_dev`:** 379 indexed versions, 82 plays,
15 updated, 0 failed, 47 already correct, 20 not in the index.

The three corrections the analysis predicted landed exactly:

```
EMOTHE0010  language → "en", relationship_type → nil   (also cleared a wrong parent_play_id)
EMOTHE0038  language → "en"
EMOTHE0053  relationship_type → "traduccion"
```

Both Shakespeare families link — `EMOTHE0050`/`0053`/`0059` to `EMOTHE0010`, `EMOTHE0052`/`0084`/
`0139` to `EMOTHE0038` — plus nine more families. No `AL####` play was touched.

The 20 codes absent from the index are the 19 Artelope plays plus `EMOTHE0341`, which the project
never published.

| Commit | |
|---|---|
| `6a5f378` | feat: parse the FileMaker published index |
| `2a247c2` | feat: diff the FileMaker index against imported plays |
| `d097e0d` | feat: apply FileMaker index changes with an activity log entry |
| `1e55326` | feat: mix emothe.import.filemaker with a dry-run report |
| `48fa2c5` | docs: mark S1 complete and document the FileMaker sync task |

### Things this slice learned that its plan did not say

- **`~r{...}` will not hold a `{2}` quantifier.** A brace-delimited sigil closes on the inner `}`.
  `lib/emothe/import/filemaker.ex` uses `~r|...|`.
- **`mix ecto.gen.migration` writes an empty `change do end`** — read the generated file before
  editing it.
- **Run migrations in both environments:** `mix ecto.migrate && MIX_ENV=test mix ecto.migrate`.
- **`defp import(...)` does not compile** — it collides with `Kernel.import`.
- **`mix gettext.extract --merge` fuzzy-matches new strings onto unrelated translations.** It
  turned `"Restore"` into `"Nueva fuente"`. Audit every fuzzy entry. Roughly 15 pre-existing bad
  ones remain in `priv/gettext/es/LC_MESSAGES/default.po` — known, worth a separate pass.
- **Filter dev SQL noise from mix output:**
  `mix emothe.import.tei 2>&1 | grep -Ev '^\[debug\]|^(SELECT|INSERT|UPDATE|DELETE|BEGIN|COMMIT|ROLLBACK)|↳'`
- **A minimal TEI fixture produces 2 divisions**, not 1 — the front-matter `elenco` div counts.

---

## S2a — Historical time

**Shipped 2026-08-02.** Plan: `2026-08-02-s2a-historical-time.md`, Tasks 1–7. Spec:
`../../specs/2026-08-02-s2a-historical-time-design.md`. 299 tests passing.

Every play can now carry a curated historical setting: a period from a nine-term vocabulary and a
free-prose note. Bootstrapped from the FileMaker export, editable in the admin form, shown in a
new "Study" section on the public play page.

- `plays.historical_time` (`varchar`) and `plays.historical_time_note` (`text`). The vocabulary
  lives in `Emothe.Catalogue.Play.historical_times/0` and is enforced with `validate_inclusion`.
- Both columns are `@platform_owned` in `lib/emothe/import/tei_parser.ex`, so a TEI re-import
  cannot erase them and the import preview lists them as preserved.
- `Emothe.Import.Filemaker.load_versions/1` reads the `T01_tituloEM` layout the module previously
  discarded, keyed by the play code hiding in the `pub_edicionWeb` href — the only place the
  `HIE####` codes appear. Pure, no database.
- `FilemakerSync.plan/3` gained a **fill-only** write policy for curated fields: written when
  blank, reported under `:conflicts` when they differ, overwritten only under
  `apply_plan(plan, force: true)`. The S1 derived fields keep overwriting unconditionally.
- `mix emothe.import.filemaker --force` overwrites the conflicts; without it they are printed and
  left alone.
- `EmotheWeb.PlayLabels` holds the nine translated labels so the admin select and the public panel
  share one list.

**Result of the acceptance run against `emothe_dev`:** 11 plays gained a `historical_time`, 4 of
them with a note, 0 conflicting, 0 failed.

```
EMOTHE0008|edad_media           EMOTHE0286|antiguedad_clasica
EMOTHE0010|tiempo_indeterminado (note)   EMOTHE0337|antiguedad_clasica (note)
EMOTHE0038|antiguedad_clasica (note)     EMOTHE0341|siglo_xvii
EMOTHE0211|siglo_xvii           EMOTHE0346|siglo_xvii
EMOTHE0254|tiempo_indeterminado EMOTHE0502|siglo_xv
EMOTHE0281|siglo_xvii (note)
```

`EMOTHE0341` appears in both `changes` and `missing`, as designed: it has a T01 research record but
was never published, so it is absent from the T00 index. `EMOTHE0033` has an empty
`<ul><li></li></ul>` and no code, so it correctly gets nothing. No `AL####` play was touched.

| Commit | |
|---|---|
| `b588bf8` | feat: a curated historical time on plays |
| `c8016ed` | feat: read historical time out of the FileMaker version records |
| `2711282` | feat: fill-only sync for curated fields, with a conflicts report |
| `d17837b` | feat: --force to overwrite curated conflicts, and report them either way |
| `143c855` | feat: edit a play's historical time in the admin form |
| `eacd822` | feat: a research metadata panel on the public play page |

### Things this slice learned that its plan did not say

- **`@platform_owned` was never the thing protecting curated columns.** The plan predicted Task 1
  Step 8 would fail; it passed. A TEI re-import calls `Catalogue.update_play/2` with an attrs map
  built from the file, and Ecto only changes the keys it is given — a column the parser never
  emits is preserved whether or not it is on the list. `@platform_owned` matters for columns the
  parser *does* emit (`language` carries `xml:lang="es"` on every EMOTHE file). Both columns were
  added anyway: the list is also what the import preview reports as preserved, which is real user
  value, and it future-proofs the day the parser learns to emit them.
- **`not opts[:force]` does not compile-and-run.** `not` is strict boolean in Elixir and
  `OptionParser` yields `nil` for an absent switch, so `not nil` raises `ArgumentError` — and only
  on the path that has conflicts and no `--force`, i.e. the common one. Use `!`.
- **A pre-existing async test flake, fixed here.** The S1 test "reports codes that are not in the
  index" inserted a play with code `AL0514_ElAusenteEnElLugar`, the same code the roundtrip and
  TEI-validator suites import from the real fixture. Under load the async insert blocked on the
  unique index on `plays.code` until their sandbox transactions ended, and the statement timed out
  with `Postgrex.Error 57014 (query_canceled)`. It now uses `AL9999_NoEstaEnElIndice`, a code no
  fixture uses. **A test that inserts a play must not reuse a code from `test/fixtures/tei_files/`.**
- **The plan's note count was optimistic.** It predicted 8 of the 11 plays would get a
  `historical_time_note`; the real export yields 4. `pub_TiemHistorico` is populated for 8 T01
  records overall, but only 4 of those are plays we have.
- **The public LiveView suite runs in Spanish.** `assert html =~ "Classical antiquity"` fails;
  the label renders as `Antigüedad clásica`. The plan warned about this and it happened.
- **`mix gettext.extract --merge` fuzzy-matched again:** it proposed `"Research Metadata"` →
  `"Investigador"`. One bad entry out of 15 new strings, caught and corrected.
