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
