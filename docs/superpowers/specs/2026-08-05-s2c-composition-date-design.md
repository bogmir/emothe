# S2c — Composition date

**Status:** design, 2026-08-05. Slice S2c of `../plans/2026-08-01-filemaker-import-slices.md`.
Follows S2a, which built the panel and the fill-only sync policy this reuses.

Three columns on `plays`: `composition_date_from`, `composition_date_to`,
`composition_date_note`. When the play was written, as a year range plus the competing
datings verbatim.

## Why this field, and why now

The remaining slices were scored against three tests — can a researcher edit it in our
admin UI, does it round-trip through TEI, can it be bootstrapped from the FileMaker
export. Composition date is the only one that passes all three with nothing blocked:

| Slice | Admin UI | TEI home | FileMaker source | Verdict |
|---|---|---|---|---|
| **S2c composition date** | Research Metadata fieldset exists | **`<creation><date>`** — canonical, in `profileDesc`, which the parser and exporter both already handle | index header + `pub_datacion` | **clean** |
| S3 witnesses | sources page exists | `<sourceDesc><listWit><witness>` | `pub_testimonio` | clean, but 27 → 450 child rows; sequenced after the ~300-play import (question 5) |
| S8 genre | trivial | `<textClass><keywords>` | `bus_genero` — bare codes, no labels anywhere in the export | blocked on the value lists |
| S5 performances | two new tables + cast CRUD | none — TEI `<performance>` is staging instruction, not a performance record; would need `<listEvent>` | `pub_RepAntiguas` | not clean |
| S2d collection | trivial | none | `bus_coleccion` | blocked on "what separates 1 from 3" |

Three further reasons this one goes now:

- **It is a column on the play, so it does not wait for the ~300-play import.** Open
  question 5 sequences S3/S4/S5/S6/S9b behind that import because each writes child rows
  per play. S2c is explicitly indifferent.
- **It is a first-class search field in the system we are replacing.** Field 15 of 25 on
  `https://emothe.uv.es/basededatos/findrecords.php` is "Datación", a *number* with
  `igual a / mayor o igual / menor o igual / entre` operators. Two integer columns is
  exactly the shape a future search needs. (By contrast `bus_genero` is not on that page
  at all.)
- **No fixture carries `<creation>`.** Checked all 41 TEI files, UTF-16-decoded: zero
  `<creation>`, `<listWit>`, `<witness>`, `<performance>`, `<keywords>`, `<catRef>`. So
  the element is ours to add with nothing to conflict with, and the round-trip is
  export → import against our own output.

## What the data actually looks like

Two sources, and they are not interchangeable.

### `T00_indiceEM.pub_listaObras` — the index header, the from/to source

The `<div>` that opens each work's listing carries a pre-normalized dating in a trailing
`<span>`, next to the author:

```html
<div><i>ANTONY AND CLEOPATRA</i>. William Shakespeare<span …>=1606 - =1607</span></div>
```

Measured across all 203 index records: **64 carry a dating**. Forms seen, with every
sigil that occurs (`- = > ? ≈ ≤ ≥`):

```
=1606 - =1607     exact range        ≥1598 - ≤1600    open-ended range
1600? - 1601?     conjectural        ≈1562            circa
=1610             single year        =1587 - =92      two-digit tail
```

This is **the same field S1 already parses** (`Filemaker.load_index/1`), so no new
reader is needed.

### `T01_tituloEM.pub_datacion` — the competing datings, the note source

97 of 439 rows. Each `<li>` is a *competing* dating in Spanish prose:

```
EMOTHE0010  <ul><li>¿1600? y ¿1601?</li>
                <li>posterior 1600 y hasta 1601</li>
                <li>alrededor de 1601</li></ul>
EMOTHE0038  <ul><li>desde o posterior 1605 y anterior o hasta 1607</li>
                <li>desde o posterior 1606 y anterior o hasta 1607</li>
                <li>1606</li></ul>
EMOTHE0341  <ul><li>¿1694? y ¿1605?</li></ul>            ← typo in the source
```

Vocabulary across all 97: `desde X y hasta Y`, `(desde o) posterior X`,
`anterior o hasta X`, `alrededor de X`, `¿X?`, bare year. **We do not model any of it.**

### Why the index is the from/to source and not `pub_datacion`

The roadmap proposed parsing `pub_datacion` for from/to as min/max across its `<li>`s.
Measured on our six plays that have both, they disagree once — and the disagreement says
which source is better:

| Code | `pub_datacion` min/max | index header |
|---|---|---|
| EMOTHE0010 | 1600–1601 | `1600? - 1601?` |
| **EMOTHE0038** | **1605–1607** | **`=1606 - =1607`** |
| EMOTHE0281 | 1613–1613 | `=1613 - =1613` |
| EMOTHE0337 | 1602–1609 | `≤1602 - ≥1609` |
| EMOTHE0346 | 1614–1614 | `=1614` |
| EMOTHE0341 | 1605–1694 | *(absent)* |

EMOTHE0038's `pub_datacion` union spans 1605–1607 because one rejected dating starts a
year earlier. The header says 1606–1607: **the accepted dating, not the union of
competing ones.** So the two sources do different jobs and neither competes with the
other:

- **index header → `composition_date_from` / `_to`** (min and max 4-digit year in the
  string; sigils ignored)
- **`pub_datacion` → `composition_date_note`**, every `<li>` stripped of tags and joined
  with `"; "`. Falls back to the header verbatim when `pub_datacion` is blank, so the
  `≈` / `?` qualifier is never silently dropped.

No priority rule, because the two never write the same column.

### The sanity guard survives, and gets cheaper

The roadmap's guard — a span wider than 40 years is reported as a conflict and not
written — is kept, but measured against the index it is now a guard against a source we
have never seen misbehave: **the widest of the 64 index datings is 13 years**
(`=1612 - =1625`). EMOTHE0341, the `¿1694? y ¿1605?` typo that motivated the guard, has
no index entry at all, so on present data the guard never fires. It stays because it
costs one clause and the ~300-play import triples the row count.

One index value is unparseable: a bare `'='` with no year. Reported, not written.

## The correction to the roadmap: a translation does not get the original's date

The index dating is stored **per work**, so it applies to every version in the family.
Written naively that is 18 of our 82 plays — three times `pub_datacion`'s six. That
number is wrong, and this is the one place this design departs from the roadmap.

Of those 18, **only 6 are the family head** (credited `ed.`, i.e. the original):

```
=1606 - =1607   EMOTHE0038 ed.  → EMOTHE0052, 0084, 0139 are translations
1600? - 1601?   EMOTHE0010 ed.  → EMOTHE0050, 0053, 0059 are translations
=1613 - =1613   EMOTHE0281 ed.
≤1602 - ≥1609   EMOTHE0337 ed.  → EMOTHE0678 tra.
=1614           EMOTHE0346 ed.
≈1562           EMOTHE0777 ed.  → EMOTHE0776 tra.
=1598 - =1599   EMOTHE0254 tra. — head EMOTHE0240 is not in our corpus
=1619 - =1620   EMOTHE0075 tra. — head EMOTHE0013 is not in our corpus
≥1614 - ≤1615   EMOTHE0724 tra. — head EMOTHE0579 is not in our corpus
=1610           EMOTHE0305 tra. — this work has no `ed.` version at all
```

*Antonio y Cleopatra* was not composed in 1606; *Antony and Cleopatra* was. Two
independent reasons not to write it there:

- **TEI says no.** `<creation>` holds information about the creation of *this text*. On a
  translation's file, its own creation is the translation's date, which we do not have.
  Emitting 1606 there produces a valid document that asserts something false.
- **We already model the relation.** S1 links every translation to its original through
  `parent_play_id`. Copying the parent's date into the child duplicates a fact we can
  derive and creates a second place for it to go stale.

**So the importer writes the dating only where the play is the composition being dated:**
`relationship_type` nil. That is 6 plays from the index, plus EMOTHE0341 from
`pub_datacion` alone — **7 of 82**.

At full corpus the head-only rule bounds this too, and the roadmap's "6 → 97" is the
version-row count, not the play count: 64 index records carry a dating and each yields at
most one head, so **up to 64 plays**, plus the handful reachable only through
`pub_datacion`. Still ten times the present slice, and still a column on the play — which
is why this one need not wait for that import.

Nothing stops a researcher typing a translation's own composition date into the form; the
column means the same thing there. It is only the *import* that refuses to guess.

**Inheritance display is out of scope.** Showing "original composed 1606–1607" on a
translation's page reaches through `parent_play_id`, and for four of those twelve
translations the parent is not in the corpus, so it would render on eight pages. Cheap
later, not part of this slice.

## Schema

```
composition_date_from  :integer
composition_date_to    :integer
composition_date_note  :text
```

Migration adds all three to `plays`. No index — nothing queries on them until search
arrives, and 82 rows would not use one.

Changeset, in `Emothe.Catalogue.Play`:

- all three cast
- `validate_number(:composition_date_from, greater_than_or_equal_to: 1000, less_than_or_equal_to: 2100)`, same for `_to`
- **both years or neither** — a lone endpoint is a half-entered form, not a fact. One
  `validate_change`-style clause producing "must be given together".
- `from <= to`

The bounds are wide on purpose. This is a 16th–17th century corpus, but the column is a
year and a curator correcting a typo should not fight the validator.

**All three columns go into `@platform_owned`** in `lib/emothe/import/tei_parser.ex`
(currently `:language, :relationship_type, :parent_play_id, :is_complete,
:historical_time, :historical_time_note`) — with the regression test in the same commit.
Without that a TEI re-import erases them.

Note the asymmetry, and that it is deliberate: the columns are `@platform_owned` *and*
the TEI exporter emits them. `@platform_owned` means "a re-import must not overwrite what
a curator typed", not "TEI never carries it". `is_complete` is the field that is genuinely
absent from TEI; these three are the case S0b's list also covers — a column TEI *can*
express, where our database is nonetheless the authority.

## TEI

`<creation>` is a `model.profileDescPart` member, the same slot as `<langUsage>`, which
`build_profile_desc/1` already emits at `lib/emothe/export/tei_xml.ex:288`. Order within
`profileDesc` is unconstrained; `creation` goes first, matching the TEI Guidelines'
own examples.

**Export.** Emitted only when `composition_date_from` is set:

```xml
<profileDesc>
  <creation>
    <date when="1614"/>
  </creation>
  <langUsage>…</langUsage>
</profileDesc>
```

```xml
<creation>
  <date notBefore="1600" notAfter="1601">¿1600? y ¿1601?; posterior 1600 y hasta 1601; alrededor de 1601</date>
</creation>
```

`when` when `from == to`, `notBefore`/`notAfter` otherwise. The note is the element's text
content — that is what `<date>` text is for, the human-readable form of the machine
attributes. With no note, `<date/>` is empty.

**Import.** `extract_creation/1`, a sibling of the existing `extract_language_code/1`,
reads `profileDesc/creation/date` and accepts `@when` or `@notBefore`/`@notAfter`, plus
the text as the note:

- `when="1614"` → `{1614, 1614, text}`
- `notBefore` and/or `notAfter` → whichever are present
- no parseable attribute → `{nil, nil, nil}`, and the element is ignored rather than
  erroring. A file with `<date>c. 1600</date>` and no attributes carries no machine
  dating; that is the file's problem, not an import failure.

Because the fields are `@platform_owned`, a re-import of an existing play does not apply
them — the same as `historical_time`. They are read on **first** import, which is where a
future corpus that does carry `<creation>` gets its data.

## Sync

`Emothe.Import.FilemakerSync` already has the shape this needs: `@curated` fields are
fill-only, filled when blank, reported under `:conflicts` when they differ, written on
conflict only under `force: true`. Append the three columns to `@curated` and they inherit
all of it, including the `/admin/filemaker` UI, which names no column.

One structural change. `plan/3` currently draws derived fields from `index` and curated
fields from `versions` (T01) only. The dating's from/to comes from the *index*, so the
curated map is composed from both:

```elixir
curated =
  index
  |> Map.get(code, %{})
  |> Map.take([:composition_date_from, :composition_date_to, :composition_date_note])
  |> Map.merge(reject_blank(Map.get(versions, code, %{})))
```

`reject_blank` matters: T01 supplies `composition_date_note` for 6 plays and `nil` for the
rest, and a plain `Map.merge` would erase the index's fallback note with that `nil`.

The head-only rule lives in the parse, not the sync: `Filemaker.load_index/1` attaches the
dating **only to the version whose `role` is `:editor`**, which is one condition inside the
existing `add_work/2` where the family is already known. Works with no `ed.` version
(EMOTHE0305's) get no dating anywhere, which is correct — we do not know which version the
date belongs to.

Reporting, alongside the existing buckets:

- **`:conflicts`** — a play with a dating already typed that disagrees with the export.
  Per-field, one row per column, exactly as `historical_time` does today.
- **span > 40 years** — reported as a conflict with the reason, never written, so it
  reaches a human through `/admin/filemaker` rather than a log line.
- **unparseable index dating** (the bare `'='`) — reported and skipped.

Every write is logged through `Emothe.ActivityLog` with `action: "update"` and
`metadata: %{source: "filemaker_index"}`, which `apply_plan/2` already does for the whole
`sets` map.

## Admin

Two number inputs and a textarea in the existing Research Metadata fieldset of
`EmotheWeb.Admin.PlayFormLive`, immediately after Historical Time
(`lib/emothe_web/live/admin/play_form_live.ex:703`) — the same fieldset, no new section:

```
Composition date    [ from ] – [ to ]
Composition note    [ textarea ]
```

`type="number"` so the browser gives the numeric keypad and step arrows for free.
Placeholder on the note: the competing datings, and the evidence for each. Labels through
`gettext`, Spanish translations in the same commit.

No `PlayLabels` entry — there is no vocabulary here, unlike `historical_time`.

## Public page

One row in the existing `#meta-study` section of `EmotheWeb.PlayShowLive`
(`lib/emothe_web/live/play_show_live.ex:332`), under Historical time:

```
Composition    1606–1607
               desde o posterior 1605 y anterior o hasta 1607; …
```

An en dash, collapsing to a single year when `from == to`. Note beneath in the same
smaller, dimmer style the historical-time note uses.

`build_sections/1` at line 428 currently shows the Study section when
`historical_time != nil`; that becomes `historical_time != nil or
composition_date_from != nil`, so a play with only a dating still gets its sidebar entry.

## Testing

TDD, per `CLAUDE.md`: the failing test first, at every step.

**Parse — `test/emothe/import/filemaker_test.exs`**, no database:

- `=1606 - =1607` → `{1606, 1607}`; `=1614` → `{1614, 1614}`; `≥1598 - ≤1600` →
  `{1598, 1600}`; `1600? - 1601?` → `{1600, 1601}`; `≈1562` → `{1562, 1562}`
- `=1587 - =92` → `{1587, 1587}`, the documented two-digit-tail loss
- bare `'='` → no dating
- the dating attaches to the `ed.` version and **not** to the `tra.` versions of the same
  work — asserted on the real EMOTHE0038 family, since that is the rule most likely to
  regress
- `pub_datacion` with three `<li>`s → the three joined with `"; "`, tags stripped
- no `pub_datacion` → note falls back to the header verbatim

**Sync — `test/emothe/import/filemaker_sync_test.exs`**:

- blank columns are filled
- a differing typed value lands in `:conflicts` and is not written
- `force: true` writes it
- idempotent: the second `plan/3` reports `unchanged`
- span > 40 is a conflict, not a write — the EMOTHE0341 case
- a play with `relationship_type: "traduccion"` gets no dating from the index

**TEI round-trip — `test/emothe/export/tei_xml_test.exs` and the parser test**:

- `from == to` exports `when`; a range exports `notBefore`/`notAfter`
- the note is the `<date>` text
- import of our own export returns all three values unchanged
- `<creation>` is absent when `composition_date_from` is nil
- `<date>` with neither attribute imports as no dating and does not raise
- a re-import does **not** overwrite the three columns — the `@platform_owned` regression
  test

**LiveView — `test/emothe_web/live/admin/play_form_live_test.exs`**: the three inputs
render, submit, and a lone `from` shows the "must be given together" error.

`RoundtripTest` needs no change: no fixture carries `<creation>`, so its counts are
unaffected.

## Out of scope

- **Modelling the qualifiers** (`≈`, `?`, `≥`, `desde … y hasta …`). from/to plus the
  verbatim note carries every one of them in a form a human reads. A `certainty` column
  would need a vocabulary the export does not define.
- **Per-dating attribution.** Roadmap open question 2 asked whether competing datings must
  name their scholar before this is publishable. **Answering it is not a prerequisite:**
  the export attributes none of the 97 rows, so there is nothing to attribute yet. If
  attribution arrives later, `play_datings(from, to, note, source, position)` is an
  additive migration and the note column holds the text meanwhile. This slice does not
  block on it, and open question 2 stays open for the *next* source, not this one.
- **Inheriting a work's dating onto its translations** on the public page — see the
  correction section above. Eight pages, later.
- **Searching by date.** The columns are the right shape for it (see the old system's
  numeric operators) and nothing more is needed here.
- `bus_datacion`, the expanded year union. It is FileMaker's search index over the same
  data, derived from `pub_datacion`, and a source of record for nothing.
