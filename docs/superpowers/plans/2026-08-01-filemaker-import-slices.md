# FileMaker Import — Feature Slices (roadmap)

**Status:** written 2026-08-01, revised 2026-08-02.

| Slice | State |
|---|---|
| S0 — corpus baseline | **done** — `archive/README.md` |
| S0b — soft delete, re-importable plays | **done** — `archive/README.md` |
| S1 — work families and language | **done** — `archive/README.md` |
| S2 — version metadata | **in progress**, one field at a time; S2a done — `archive/README.md`, S2b next |
| S3–S8 | scoped below, each gets its own plan when it comes up |

Completed plans live in `archive/`, with exactly what shipped, the commit list, and what each
slice learned that its plan did not say. Read that before starting a new slice.

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
| Imported into `emothe_dev` | 82 | all of them, since S0 |

That 62 / 22 split is why the index slice went first: it is the only one that touches most of the
corpus, and it needed no new columns. Everything from S2 on is capped at those 22 plays, so the
panel and the tables it fills will be empty for 60 of 82 — by design, not by omission.

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

### S0, S0b, S1 — done

Corpus baseline, soft delete and re-importable plays, work families and language. What shipped,
the commit list, and the traps each one hit: **`archive/README.md`**.

The one rule they leave behind that binds everything below: **a new curated `plays` column gets
appended to `@platform_owned` in `lib/emothe/import/tei_parser.ex`, or the next TEI re-import
erases it.** A new child table either carries `origin` or stays outside the importer's reach.

### S2 — Version metadata panel *(in progress, one field at a time)*

The research metadata that has no home in TEI. Taken **field by field**: each sub-slice is its own
migration, import, admin control and row in the panel, and ships before the next starts. The first
one builds the panel; the rest add rows to it.

Everything here is capped at the 22 plays with a `T01` record.

| | Field | Source | Coverage (of 22) | State |
|---|---|---|---|---|
| **S2a** | `historical_time` + `historical_time_note` | `bus_tiemHistorico` + `pub_TiemHistorico` | 11 coded, 4 with a note | **done** — `archive/README.md` |
| S2b | `place_of_action` | `pub_LugAccion` | 6 | scoped |
| S2c | `composition_date` | `pub_datacion` | 6 | scoped — one `<li>` per *competing* dating, so the shape is a genuine open question |
| S2d | `collection` | `bus_coleccion` | 22 | scoped — 1 EMOTHE, 2 HIE old-spelling quartos, 3 modern-spelling English |
| S2e | `legacy_url` | `pub_edicionWeb` href | 13 | scoped |
| S2f | `original_title`, `title_sort` | `pub_TituloObra`, `T00.pub_tituloOrden` | 22 | scoped — both columns and both admin fields already exist, so this is import-only |

**S2a — historical time. Done, 2026-08-02.** Spec:
`../specs/2026-08-02-s2a-historical-time-design.md`. Plan and outcome:
`archive/2026-08-02-s2a-historical-time.md` and the S2a section of `archive/README.md`.
Establishes three things every later sub-slice reuses:

1. `Filemaker.load_versions/1`, the `T01_tituloEM` reader, keyed by the code in the
   `pub_edicionWeb` href.
2. A **fill-only** sync policy with a `conflicts` bucket and `--force`. The S1 fields stay
   overwrite-always — the index is authoritative for those. Research metadata a curator edits is
   never stomped.
3. `<section id="meta-study">` on `/plays/:code`, hidden when empty, in the sidebar scroll-spy.

The vocabulary in the earlier draft of this roadmap was wrong. Correct, recovered by pairing the
code against the rendered label across all 439 rows: 1 Tiempo indeterminado, 2 Antiguo Testamento,
5 Edad Media, 6 Siglo XV, 7 Siglo XVI, 8 Siglo XVII, 9 Tiempo maravilloso (intemporal),
10 Antigüedad clásica, 11 Tiempo alegórico. Codes 3 and 4 do not occur.

- **Done when:** every sub-slice has landed — the panel renders on `/plays/:code` for the plays
  that have data, and admins can edit every field it shows

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
- **Two write policies, on purpose.** Fields the index is *authoritative* for — `language`,
  `relationship_type`, `parent_play_id` — are overwritten whenever they differ. Fields a curator is
  expected to *edit* — everything from S2 on — are fill-only: written when blank, reported as a
  conflict when they differ, overwritten only under `--force`. Introduced in S2a. This is the
  "bootstrap, not a dependency" rule made operational; without it the second import undoes a
  researcher's afternoon.
- **New curated column ⇒ `@platform_owned`.** Append it in `lib/emothe/import/tei_parser.ex`, or
  the next TEI re-import erases it. Add the regression test in the same commit.

## Open questions

1. **Fetching the other 317 plays.** The index gives a download path for every published play
   (`textosXML/<code>_<Name>.xml`). Out of scope until someone asks the project for permission and
   a rate.
2. **`bus_publicada` vs `is_complete`.** 61 rows are flagged published, but 301 have a real
   web-edition href. Our `is_complete` gates the static-site export, so nothing should write to it
   automatically.
3. **Genre value lists** — see S8.
4. **Character re-import identity.** A TEI re-import still replaces the whole cast list, so a
   manual `xml_id` fix on a character is lost. Protecting those needs per-character identity
   matching — bigger than S0b, not scoped anywhere. Blocks nothing in S2–S5; blocks S6.
5. **Multi-valued `pub_datacion` and multi-`<li>` historical times.** S2a takes the first `<li>`
   and logs. Two of 439 export rows carry two historical periods; `pub_datacion` carries competing
   datings as a matter of course. S2c has to decide the shape for real, and may retro-fit S2a.
