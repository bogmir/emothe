# FileMaker Import — Feature Slices (roadmap)

**Status:** written 2026-08-01, revised 2026-08-04.

| Slice | State |
|---|---|
| S0 — corpus baseline | **done** — `archive/README.md` |
| S0b — soft delete, re-importable plays | **done** — `archive/README.md` |
| S1 — work families and language | **done** — `archive/README.md` |
| Admin sync page (`/admin/filemaker`) | **done** — see below |
| S2 — version metadata | **in progress**, one field at a time; S2a done — `archive/README.md` |
| S2c, S2d | scoped below, **both waiting on a question to the project** |
| S2e — `legacy_url` | **dropped** — derivable from code + filename, see below |
| S2f — titles | **dropped as an import** — nothing to import, folded into S7's cross-check |
| S3–S9 | scoped below, each gets its own plan when it comes up |

Completed plans live in `archive/`, with exactly what shipped, the commit list, and what each
slice learned that its plan did not say. Read that before starting a new slice.

## How a sync is run

Two front doors onto the same pure domain layer (`Emothe.Import.Filemaker` +
`Emothe.Import.FilemakerSync`):

- `mix emothe.import.filemaker [--dry-run] [--force] [--path ...]` — the terminal path, for a bulk
  apply against a file on the server.
- **`/admin/filemaker`** — `EmotheWeb.Admin.FilemakerSyncLive`. Upload the NDJSON export, read the
  diff, tick individual conflicts, apply. Permission `:import_filemaker`, **admin only** and
  deliberately not researcher-level: a sync is corpus-wide and its force path overwrites curated
  research metadata across every play at once, where a TEI import replaces one named file's play.
  The upload is parsed inside `consume_uploaded_entries` and never stored anywhere — the plan lives
  in assigns and dies with the session.

Shipped 2026-08-03. Plan: `2026-08-03-filemaker-sync-admin-page.md`. Spec:
`../specs/2026-08-03-filemaker-sync-admin-page-design.md`. Commits `356c389`, `4fc3cea`, `f39d92f`,
`5663de5`, `3ec628e`, `2b8b6ae`, `8362e28`.

**Every later slice gets this page for free.** No template names a metadata column — field and value
labels go through `field_label/1` and `value_label/3`, both with catch-all clauses — so a new column
appears in the UI the moment `FilemakerSync.plan/3` puts it in `sets` or `conflicts`. Adding a
`field_label/1` clause is optional polish: it turns `"place of action"` into a translated label.

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
| S2c | `composition_date_from/_to` + note | `pub_datacion` | 6 | proposal below, **needs sign-off** on attribution |
| S2d | `collection` | `bus_coleccion` | 22 | labels decoded below, **blocked** on whether the field is still wanted |
| ~~S2b~~ | `place_of_action` | `pub_LugAccion` | 6 | **split out** — toponym-based, now **S9** |
| ~~S2e~~ | `legacy_url` | `pub_edicionWeb` href | 13 | **dropped** — derivable, see below |
| ~~S2f~~ | `original_title`, `title_sort` | `pub_TituloObra`, `T00.pub_tituloOrden` | 22 | **dropped as an import** — nothing left to import, see below |

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

- **Done when:** S2c and S2d have landed or been dropped — the panel renders on `/plays/:code` for
  the plays that have data, and admins can edit every field it shows. As of 2026-08-04 S2a has
  landed, S2b is now S9, S2e and S2f are dropped, so those two are all that is left of S2 and both
  are waiting on an answer from the project.

#### S2c — composition date *(proposal, needs sign-off)*

6 of our 22 plays, 97 of the 439 export rows. Each `<li>` is a **competing dating**, and
`bus_datacion` is the expanded year union — a search index, not a source:

```
EMOTHE0010  <ul><li>¿1600? y ¿1601?</li>
                <li>posterior 1600 y hasta 1601</li>
                <li>alrededor de 1601</li></ul>
EMOTHE0337  <ul><li>anterior o hasta 1602 y hasta o posterior 1609</li><li>1605</li></ul>
EMOTHE0281  <ul><li>desde 1613 y hasta 1613</li></ul>
EMOTHE0346  <ul><li>1614</li></ul>
EMOTHE0341  <ul><li>¿1694? y ¿1605?</li></ul>            ← typo in the source
```

Vocabulary seen across all 97: `desde X y hasta Y`, `(desde o) posterior X`, `anterior o hasta X`,
`alrededor de X`, `¿X?` (conjectural), bare year.

**Proposal:**

- Three columns: `composition_date_from :integer`, `composition_date_to :integer`,
  `composition_date_note :text`.
- **from/to = min and max 4-digit year across *all* the `<li>`s.** Ordering-independent, because the
  `<li>` order carries no documented preference — and it agrees with `bus_datacion`, which is that
  same union. Do not try to model the qualifiers.
- **note = every `<li>` verbatim, joined with `"; "`.** Nothing is lost, and a curator reads the
  competing datings in the admin form.
- **Sanity guard: a span wider than 40 years is reported as a conflict and not written.** Catches
  EMOTHE0341, where `¿1694? y ¿1605?` would otherwise store 1605–1694.
- Public: one `#meta-study` row, `1605–1607`, collapsing to a single year when from == to, note
  beneath. Admin: two number inputs plus a textarea in the Research Metadata fieldset.
- Fill-only like every S2 field. All three columns go into `@platform_owned`.

**The question that needs answering before this is built:** the competing datings are
**unattributed** — the field names no scholar for any of them. If a dating has to carry its
attribution to be publishable, the shape is not three columns but a child table
(`play_datings(from, to, note, source, position)`) with its own admin CRUD, which makes this an
S3-sized slice rather than an afternoon.

Known parse edge, export-wide but outside our 22: EMOTHE0178 is `desde 1587 y hasta 92` — a
two-digit end year, so min/max yields 1587–1587. Acceptable; the note keeps the truth.

#### S2d — collection *(blocked on a question to the project)*

22 of 22, and a bare numeric code with no text counterpart anywhere in either table. Unlike S8's
`bus_genero`, **no value list is needed from FileMaker** — the mapping is unambiguous once the code
is correlated against the play code prefix and `bus_idioma` across all 439 rows:

| Code | Rows | What they are |
|---|---|---|
| `1` | 358 | every `EMOTHE####`, all five languages — the EMOTHE library proper |
| `2` | 27 | every `HIE####`, all English — old-spelling quartos |
| `3` | 53 | `EMOTHE####`, 52 English + 1 Spanish — modern-spelling English |

Our 22: nineteen `1`, three `3` (EMOTHE0337, EMOTHE0341, EMOTHE0346), zero `2` — we hold no HIE
files at all.

**Blocked, on purpose.** What editorially distinguishes collection `1` from `3` is not recoverable
from the export, and if the distinction does not survive into the new system the right move is to
delete this sub-slice rather than build it. Ask the project two things: is the collection still a
meaningful grouping, and if so what is the `1` / `3` difference. The single `3` row carrying
`bus_idioma: 1` (Spanish, in a modern-spelling *English* collection) looks like a data-entry slip on
their side and is worth raising in the same message.

#### S2e — legacy URL *(dropped 2026-08-04)*

Not built. `pub_edicionWeb` is
`<a href='../biblioteca/textosEMOTHE/EMOTHE0053_Hamlet.php'>Enlace</a>` — code plus the filename
stem, both of which we already hold, against a base URL that has to be hardcoded either way. A
column would store nothing the play row does not already imply. If the link is ever wanted on the
public page it is a one-line helper, not a migration.

Only 13 of 22 carried an href in any case. Those nine blanks are why `version_code/1` in
`lib/emothe/import/filemaker.ex` falls back to `"EMOTHE" <> padded _IdTituloEmothe`, and that
fallback stays — it is what matches all 22 records, not just the published ones.

#### S2f — titles *(dropped as an import 2026-08-04)*

Checked against the schema, the TEI parser and `emothe_dev`: **there is nothing to import.**

- Both columns exist and both are already filled from TEI — `title[@key="orden"]` → `title_sort`,
  `title[@type="original"]` → `original_title` (`lib/emothe/import/tei_parser.ex:329-375`). Both
  round-trip through the exporter and both are editable on the play form.
- `title_sort` is populated on **82 of 82** plays. `original_title` is set on 36 and blank on 46 —
  blank exactly where the play *is* the original, which is correct, not a gap.
- **`pub_TituloObra` is not the original title.** It is the work-family title with the leading
  article stripped: `Le Cid` → `Cid`, `La vida es sueño` → `vida es sueño`,
  `La verdad sospechosa` → `verdad sospechosa`. S1 already links every version to its work through
  `parent_play_id`, so that value is derivable from data we hold and adds nothing.
- `T01.pub_TituloOrden` differs from ours only in convention — `"Cid, Le"` against our `"Cid Le"` —
  and ours is deliberate.

What the comparison *did* find is two defects on our side, both inherited from the TEI and both a
hand fix rather than an import: EMOTHE0254 has `title_sort: "JULES CÉSAR"` (shouting, from
`title[@key="orden"]` in the file) and EMOTHE0341 has `"Eastward Ho"`, having lost the `!`.

**"But the columns exist, so the importer can just fill them"** — it can, in about ten lines and no
migration, and it is still wrong. Measured against `emothe_dev` on 2026-08-04:

- `title_sort` is set on 82 of 82 plays, so fill-only never fires: **0 writes, 13 conflicts**, of
  which 11 differ only by FileMaker's comma (`"Cid, Le"` against our `"Cid Le"`). Accepting them
  under `--force` flips our sort convention to theirs — a style decision dressed as an import.
- `original_title` is blank on 12 of the 22, so fill-only *would* write, and **all 12 writes are
  wrong**: every blank is a play that *is* the original, and `pub_TituloObra` there is its own title
  minus the article. It would stamp `Le Cid` as a version of `Cid`.
- Corpus-wide, **0 of 82 plays have a `parent_play_id` and a blank `original_title`.** There is no
  row anywhere the import could legitimately fill.

The fill-only policy points the wrong way for both fields: the one that is safe to write is never
blank, and the one that is blank must stay blank. So this becomes a report, not a migration — folded
into **S7**, which is already a cross-check slice.

Two findings from that check that outlive S2f:

- **21 plays have `original_title` set but `parent_play_id` nil** — translations S1 never linked.
  Not fixable from this export and not fixable from our own data either: all 21 originals were
  title-matched against the corpus and **none of them is a play we hold**. Real gap in the work
  families, no cheap fix, tracked as open question 9.
- The lost punctuation on EMOTHE0341 and EMOTHE0211 (`Cortigiana 1525`, missing the parentheses) is
  a sort-title handling defect in the TEI import, worth fixing at the source rather than papering
  over per play.

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

**Carries the dropped S2f with it:** report where our `title_sort` / `original_title` disagree with
`T01.pub_TituloOrden` / `pub_TituloObra`, same as the credits comparison and for the same reason —
a difference is a question for a curator, not a write. Two known hits already: EMOTHE0254 and
EMOTHE0341, see S2f.

### S8 — Genre *(blocked)*

`bus_genero` and `bus_generoAnnals` are bare numeric codes with **no text counterpart anywhere in
either table**. This is the only outstanding request to the FileMaker side: send the value lists
for `bus_genero`, `bus_generoAnnals` and `bus_repCircunstancia`. Everything else the CSV was
missing, the JSON supplied.

What is blocked is the *import*, not the field. An editable `genre` on the play form can ship
whenever it is wanted — 5 plays is an afternoon of typing. The value lists only decide whether the
existing codes can be turned into labels automatically or have to be re-entered by hand.

### S9 — Place of action *(was S2b; designed 2026-08-04)*

**Spec: `../specs/2026-08-04-s9-places-design.md`.** Split out of S2 because it is not a text field
and turned out to be a feature rather than a column: a corpus-global gazetteer with a three-layer
place / place-name / mention model, Wikidata as a swappable authority, and TEI `<listPlace>` +
`<setting>` in both directions. **Phase 1 is the app; the `pub_LugAccion` import is a later slice and
ships no FileMaker code.** `plays.place_of_action` is never created.

`pub_LugAccion` is a **toponym**, and a play carries several:

```
EMOTHE0010  <ul><li>Helsingør. [Denmark]. Europe</li></ul>
EMOTHE0038  <ul><li>Rome. [Italy]. Europe</li>
                <li>Alexandria. [Egypt]. Africa</li>
                <li>Athens. [Greece]. Europe</li>
                <li>( Miseno ) [Italy]. Europe</li></ul>
EMOTHE0337  <ul><li>Jerusalem. [Israel]. Asia</li></ul>
```

So the shape FileMaker uses is already `place . [modern country] . continent`, one row per place,
with parentheses apparently marking a place mentioned rather than staged (EMOTHE0038's `( Miseno )`
— unconfirmed). 6 of our 22 plays, 4 places at most.

That is a small gazetteer, not a string column, and a gazetteer has consequences the rest of S2 does
not: shared place records across plays, a modern-vs-historical name distinction, coordinates and
external authority links. All of that is settled in the spec; the parenthesised `( Miseno )` becomes
`role: "mentioned"` on the play link.

## Shared conventions

Fixed once here so every slice looks the same:

- **Module namespace:** `Emothe.Import.Filemaker` (pure parsing, no DB) and
  `Emothe.Import.Filemaker<Thing>Sync` (reads the DB, writes the DB). Parsing modules must be
  testable without a database.
- **HTML parsing with `Regex`.** There is no HTML library in `mix.exs` and this is a fixed,
  machine-generated markup shape. Do not add Floki for it.
- **Dry run first.** Every sync mix task takes `--dry-run` and prints the report without writing.
  Since 2026-08-03 the same review happens in the browser at `/admin/filemaker`, which previews
  before it applies and can accept conflicts one at a time. That page is the review mechanism for
  the researchers; `--dry-run` is the one for us.
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

Ordered by what is actually blocking work.

1. **Is `collection` still wanted, and what separates code `1` from `3`?** Blocks S2d, and the
   answer may delete it. See S2d for the decoded label table and the one suspect row.
2. **Do competing composition datings need per-dating attribution?** Blocks the *shape* of S2c:
   three columns if no, a child table with admin CRUD if yes. See S2c.
3. **Place of action requirements** — S9. Toponyms with country and continent, up to 4 per play.
   Waiting on Bogdan.
4. **Genre value lists** — S8. The only outstanding request to the FileMaker side.
5. **Fetching the other 317 plays.** The index gives a download path for every published play
   (`textosXML/<code>_<Name>.xml`). Out of scope until someone asks the project for permission and
   a rate.
6. **`bus_publicada` vs `is_complete`.** 61 rows are flagged published, but 301 have a real
   web-edition href. Our `is_complete` gates the static-site export, so nothing should write to it
   automatically.
7. **Character re-import identity.** A TEI re-import still replaces the whole cast list, so a
   manual `xml_id` fix on a character is lost. Protecting those needs per-character identity
   matching — bigger than S0b, not scoped anywhere. Blocks nothing in S2–S5; blocks S6.
8. **Multi-`<li>` historical times.** S2a takes the first `<li>` and logs; two of 439 export rows
   carry two historical periods. If S2c settles on a child table for datings, revisit whether S2a
   should follow it.
9. **21 unlinked translations.** They carry an `original_title` but no `parent_play_id`, and none of
   their originals is a play we hold, so neither FileMaker nor our own data can close the family.
   Either those originals get imported (see question 5) or work families stay partial and the UI has
   to say so. Found while dropping S2f.

Closed since 2026-08-01: the multi-valued `pub_datacion` shape is now a written proposal (S2c) rather
than an open question, and `legacy_url` (S2e) and the title import (S2f) are dropped outright.
