# FileMaker Import — Feature Slices (roadmap)

**Status:** written 2026-08-01. S0 is done. Slices with a full implementation plan:
S1 — `docs/superpowers/plans/2026-08-01-s1-work-families-and-language.md`;
S0b — `docs/superpowers/plans/2026-08-01-soft-delete-and-reimport.md`.
The rest are scoped here and get their own plan when they come up.

**Interactive companion:** `doc/filemaker-import-analysis.html` — field-by-field verdicts,
work families, and the exact corrections slice 1 makes. Regenerate after any corpus change:

```bash
python3 docs/build_import_analysis.py
```

---

## What we are importing from

`doc/w3emothe_T01_tituloEM.ndjson`, pulled from the FileMaker Data API at
`artelopefms.uv.es`. One file, two tables, each wrapped in its own `_meta` / `_end` envelope:

| Table | Records | Grain | What it holds |
|---|---|---|---|
| `T00_indiceEM` | 203 | one per **work** | `pub_listaObras`: rendered HTML listing every published version — language tag, code, title, credit + role (`ed.` / `tra.`), TEI download path |
| `T01_tituloEM` | 439 | one per **version** | 48 research fields: historical time, place of action, dating, witnesses, bibliography, performances, dramatis personae, genre codes |

An earlier CSV export of the same data is at `doc/emothe_export.csv`. **Do not use it** — FileMaker
flattened every repeating related record into one space-joined cell. The JSON keeps the
publication HTML (`<ul><li>` per related record), which is what makes slices S3–S5 possible at all.

## The point of the exercise

The export is a **bootstrap, not a dependency**. When these slices are done, every field FileMaker
holds has a permanent column or table in our schema *and* a way for a researcher to type it,
correct it and extend it in the admin UI. At that point `w3emothe_T01_tituloEM.ndjson` can be
deleted: it is one convenient way to fill those fields the first time, not the only way, and not the
thing of record.

Two consequences that bind every slice:

1. **No import without an editor.** A slice that writes a field but gives no admin form is not
   done. Data you can only obtain by re-running an import against a file outside git is data you do
   not really own.
2. **An import must never silently destroy what a human typed.** Handled once, in S0b: rows carry
   an `origin`, the importer replaces only its own, and it says what it is about to replace before
   it writes.

## Scope decision

**Only plays we already hold.** The export describes 379 published plays. We are not building a
catalogue of the archive and we are not fetching the 317 TEI files we lack — that is a separate
decision needing permission from the project. Every slice applies to plays that exist in our
database.

Consequences, measured:

| Set | Count | Notes |
|---|---|---|
| TEI files on disk (`test/fixtures/**/*.xml`) | 82 | 14 basenames appear in two directories; dedupe by code |
| …of which Artelope (`AL####`) | 19 | absent from this export entirely — they get nothing, ever, from FileMaker |
| …covered by the published index | 62 | these get language, work family, credits |
| …with a `T01` research record | 22 | hard ceiling for metadata, witnesses, bibliography, performances |
| Currently imported into `emothe_dev` | 8 | 3 of them have a wrong language or relationship today |

That 62 / 22 split is why the index slice goes first: it is the only one that touches most of the
corpus, and it needs no new columns.

## The join, once

```
T00_indiceEM.pub_listaObras   one <li> per published version
  → code (EMOTHE0053, HIE0393)     27 versions are HIE####, never format the number yourself
  = split_part(plays.code, '_', 1) our plays.code is the full filename stem
T00._IdIndiceCtce = T01._IdObraEmothe   the work family — validated, 152 works, 0 title disagreements
```

`_kp_IdIndiceEM` is **not** the work key (3 agreements out of 144). `pub_TituloWP` is wrong on
50 of 95 rows and must never be used.

## Slices

Each slice is a vertical: parse → persist → show. Each ends with something visible in the app.

### S0 — Corpus baseline *(prerequisite, folded into S1's plan as Task 1)*

Import the 82 local TEI files so the later slices have rows to attach to. Dedupe by code, skip
codes already present unless forced.

- **From:** the files themselves, no FileMaker data
- **Into:** `plays`, `characters`, `divisions`, `elements`
- **Scale:** 82 plays (8 already done)
- **Done when:** `mix emothe.import.tei` imports every file the admin UI would, idempotently

**Done 2026-08-01:** 81 of 82 imported — 19 `AL####`, 62 `EMOTHE`/`HIE`, which is exactly the set
S1 needs. `EMOTHE0730_LaMariana` failed on a front-matter `<head>` longer than
`play_divisions.title`'s `varchar(255)`; fixed in S0b Task 3.

### S0b — Soft delete, re-importable plays, protected hand-entered data *(has a full plan)*

`docs/superpowers/plans/2026-08-01-soft-delete-and-reimport.md`. Carries no FileMaker data at all —
it is the slice that makes "the database is the thing of record" true, so every slice after it can
put its data behind an admin form and stop depending on the export.

Three problems, one fix. Deleting a play is `Repo.delete` today: it destroys the row, its content,
its activity history and its children's `parent_play_id`. Re-importing a TEI file whose code exists
rolls back with `{:play_already_exists, code}`, so `mix emothe.import.tei --force` fails on all 81
plays. And nothing distinguishes a row the importer created from a row a researcher typed — the
importer writes `play_editors`, `play_sources` and `play_editorial_notes`, exactly the tables the
admin UI edits and exactly where S3 and S7 will write.

- **Into:** new `plays.deleted_at`; `origin` on `play_editors` / `play_sources` /
  `play_editorial_notes`; `Catalogue.delete_play/1` archives, `restore_play/1` and `purge_play/1`
  added; `TeiParser.import_file/1` updates in place keeping the same `id`; an import preview in the
  admin UI and `--dry-run` on the mix task
- **Ownership:** the TEI file owns the text, the cast list and the rows it stamped `origin: "tei"`.
  The platform owns `language`, `relationship_type`, `parent_play_id`, `is_complete`, every column
  S2 adds, and every row a human typed. Without this rule a re-import silently undoes S1 and erases
  S2–S5.
- **Done when:** archive a play, add a source by hand, re-import its TEI — same row id, curated
  fields intact, hand-entered source still there, and the UI said so before writing
- **Owed by every later slice:** new `plays` columns get appended to `@platform_owned`; new child
  tables either carry `origin` or stay outside the importer's reach

### S1 — Work families & language *(first — has a full plan)*

Set `language`, `relationship_type` and `parent_play_id` from the published index instead of
guessing from the TEI. The TEI header's `xml:lang` is always `es` in EMOTHE files (it marks the
editorial platform, not the play), which is why `EMOTHE0038` — the English *Antony and Cleopatra* —
is stored as Spanish today.

- **From:** `T00_indiceEM.pub_listaObras` (language tag + `ed.`/`tra.` credit)
- **Into:** `plays.language`, `plays.relationship_type`, `plays.parent_play_id`
- **Scale:** 62 plays, 43 work families, 23 of them held complete
- **Done when:** a dry run reports the 3 known corrections, an apply run fixes them, and the
  existing relationship UI (admin combobox, catalogue grouping, compare view) shows the families
  without any UI change
- **Note:** `original_title` is deliberately *not* set here — the index titles are upper-cased
  display strings. It comes from `T01.pub_TituloObra` in S2.

### S2 — Version metadata panel

The research metadata that has no home in TEI.

- **From:** `T01`: `pub_TiemHistorico` (label + `<br/>Note:` commentary), `pub_LugAccion`,
  `pub_datacion` (one `<li>` per competing dating), `bus_coleccion`, `pub_edicionWeb` (href),
  `pub_TituloObra`, `pub_TituloOrden`
- **Into:** new `plays` columns — `historical_time`, `historical_time_note`, `place_of_action`,
  `composition_date`, `collection`, `legacy_url` — plus `original_title` and `title_sort`;
  admin form fields and a public play-page panel
- **Scale:** 22 plays (8 with a historical time, 6 a place of action, 6 a dating)
- **Vocabulary:** `bus_tiemHistorico` decodes to 1 indeterminado, 2 Antiguo Testamento, 5 Edad
  Media, 6 s.XV, 7 s.XVI, 8 s.XVII, 9 tiempo maravilloso, 10 Antigüedad clásica, 11 tiempo
  alegórico. `bus_coleccion` decodes to 1 = EMOTHE, 2 = HIE (English old-spelling quartos),
  3 = modern-spelling English under EMOTHE codes.
- **Done when:** the panel renders on `/plays/:code` for the plays that have data, and admins can
  edit every new field

### S3 — Witnesses (testimonios)

- **From:** `T01.pub_testimonio` — one `<li>` per witness: `<i>Title</i>. Author. City. Publisher.
  Year. Format. Notes.`
- **Into:** existing `play_sources` (title, author, pub_place, publisher, pub_date already fit),
  plus new `source_type` (from `bus_testSoporte`) and `format` columns
- **Scale:** 7 plays, 27 witness records
- **Cross-check:** `bus_testCiudad` / `bus_testAnyo` / `bus_testFormato` line counts match the
  `<li>` count on 75 of 105 rows across the whole export — use them to validate the parse, not as
  the source
- **Done when:** witnesses appear in the existing sources admin page and on the public page

### S4 — Bibliography

- **From:** `T01.pub_EdModernas`, `pub_BibSelectaCritica`, `pub_BibSelectaTraduccion` (nested: the
  outer `<li>` is a language header `FR:` / `EN:` / `IT:` / `DE:`), `pub_BibSelectaAdaptacion`
- **Into:** new `play_bibliography` table with `kind` (`modern_edition`, `criticism`,
  `translation`, `adaptation`), `citation`, `language`, `position`
- **Scale:** 7 plays, ~326 citations
- **Done when:** a bibliography section renders per play grouped by kind, **and** admins can add,
  edit, reorder and delete citations without an import
- **S0b:** the new table stays outside the importer's reach, so a TEI re-import never touches it

### S5 — Historical performances

- **From:** `T01.pub_RepAntiguas` — labelled `<b>Company</b>`, `<b>Venue</b>`, `<b>Date</b>`,
  `<b>Cast</b>` (nested `<ul>`, one `<li>` per actor), `<b>Location</b>`, `<b>Venue type</b>`,
  `<b>Note</b>`, `<b>Information source</b>`
- **Into:** new `play_performances` + `play_performance_cast` tables
- **Scale:** 5 plays, 12 performances
- **Sources:** CATCOM and Wiggins, *British Drama 1533-1642* — keep the attribution text, it is
  a licensing requirement of CATCOM
- **Done when:** performances render per play with their source attribution, **and** admins can add
  a performance and its cast by hand — the 12 rows FileMaker holds are a seed, not the ceiling
- **S0b:** both new tables stay outside the importer's reach

### S6 — Character reconciliation

Not an import: TEI stays the source of truth for characters. `T01.bus_personaje` (one name per
line, 18 of our 22 plays) is a completeness check — flag characters present in FileMaker but
missing from the imported cast list, and vice versa. Feeds the "review character in text" UI
already on the roadmap in `CLAUDE.md`.

### S7 — Editor & translator credits

Cross-check `play_editors` against the credits printed in the index (`Tronch, Jesús, ed.`,
`Hugo, François-Victor, tra.`). Same parse as S1, kept separate so S1 stays small.
`bus_autorAdaptacion` supplies the sort form of each name, `bus_traductor` the display form.

### S8 — Genre *(blocked)*

`bus_genero` and `bus_generoAnnals` are bare numeric codes with **no text counterpart anywhere in
either table**. This is the only outstanding request to the FileMaker side: send the value lists
for `bus_genero`, `bus_generoAnnals` and `bus_repCircunstancia`. Everything else the CSV was
missing, the JSON supplied.

What is blocked is the *import*, not the field. An editable `genre` on the play form can ship
whenever it is wanted — 5 plays is an afternoon of typing. The value lists only decide whether the
existing codes can be turned into labels automatically or have to be re-entered by hand.

## Shared conventions

Fixed once here so every slice looks the same:

- **Module namespace:** `Emothe.Import.Filemaker` (pure parsing, no DB) and
  `Emothe.Import.Filemaker<Thing>Sync` (reads the DB, writes the DB). Parsing modules must be
  testable without a database.
- **HTML parsing with `Regex`.** There is no HTML library in `mix.exs` and this is a fixed,
  machine-generated markup shape. Do not add Floki for it.
- **Dry run first.** Every sync mix task takes `--dry-run` and prints the report without writing.
  That is the review mechanism for the researchers.
- **Never create plays.** A FileMaker record with no matching play is reported as unmatched and
  skipped. No stub plays, ever.
- **Never touch Artelope.** `AL####` codes are absent from the export; they must come out of every
  report as "not in index", not as an error.
- **Every write is logged** via `Emothe.ActivityLog` with `action: "update"` and
  `metadata: %{source: "filemaker_index"}` — the allowed action list in
  `Emothe.ActivityLog.Entry` is `create update delete import export role_change`, so do not invent
  a new action.
- **Idempotent.** Running a sync twice changes nothing the second time; the second report is all
  "unchanged".

## Open questions

1. **Fetching the other 317 plays.** The index gives a download path for every published play
   (`textosXML/<code>_<Name>.xml`). Out of scope until someone asks the project for permission and
   a rate.
2. **`bus_publicada` vs `is_complete`.** 61 rows are flagged published, but 301 have a real
   web-edition href. Our `is_complete` gates the static-site export, so nothing should write to it
   automatically.
3. **Genre value lists** — see S8.
