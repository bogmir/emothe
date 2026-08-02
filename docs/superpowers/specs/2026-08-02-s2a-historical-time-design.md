# S2a — Historical time

**Date:** 2026-08-02
**Status:** approved, not yet implemented
**Roadmap:** `docs/superpowers/plans/2026-08-01-filemaker-import-slices.md`, slice S2
**Depends on:** S1 (`Emothe.Import.Filemaker`, `Emothe.Import.FilemakerSync`), S0b (`@platform_owned`)

## Why this field, and why alone

S2 in the roadmap is a six-field "version metadata panel". It is being taken one field at a time:
each field gets its own migration, its own import, its own admin control and its own row in the
panel, and ships before the next one starts. This is the first of those, and it is the one that
builds the panel the rest drop into.

`historical_time` was chosen over the alternatives because it is the field with research value.
`bus_coleccion` has better coverage (22 of 22) but records which sub-collection a text belongs to —
provenance trivia. `pub_TituloObra` needs no migration and no UI at all, so it builds nothing.
`legacy_url` is a link to the old site.

## What the data actually looks like

Only **22 of our 82 imported plays** appear in `T01_tituloEM` at all. Of those 22:

- **11** have `bus_tiemHistorico`, a numeric code
- **8** have `pub_TiemHistorico`, the rendered HTML label
- the 4 in the gap — `EMOTHE0211`, `EMOTHE0254`, `EMOTHE0286`, `EMOTHE0502` — have a code and no
  rendered text at all

So the code is the more complete source and the label is the more complete *note* carrier. Both are
read; neither alone is enough.

`pub_TiemHistorico` is shaped like this:

```html
<ul><li>Antigüedad clásica<br/>Note: First century BC. The play dramatizes events
taking place between 40 and 30 BC.</li></ul>
```

The note is per-`<li>`, free prose, up to roughly 500 characters, and mixed Spanish and English
depending on who edited the play. Some cite Wiggins, *British Drama 1533–1642*, with the source's
own `<<angle quotes>>` and typographic apostrophes intact.

Two rows in the whole 439-row export carry **two** periods:

```html
<ul><li>Siglo XVI<br/>Note: After the Battle of Pavia (1525).</li>
<li>Siglo XVII</li></ul>
```

with `bus_tiemHistorico` correspondingly `"7\n8"`. Neither is one of our 22.

## The vocabulary

Recovered by pairing `bus_tiemHistorico` against `pub_TiemHistorico` across all 439 rows. Every
code that appears, appears with exactly one label. Codes `3` and `4` do not occur anywhere in the
export — they are not modelled.

| Code | Slug | Spanish | English |
|---|---|---|---|
| 1 | `tiempo_indeterminado` | Tiempo indeterminado | Indeterminate |
| 2 | `antiguo_testamento` | Antiguo Testamento | Old Testament |
| 5 | `edad_media` | Edad Media | Middle Ages |
| 6 | `siglo_xv` | Siglo XV | 15th century |
| 7 | `siglo_xvi` | Siglo XVI | 16th century |
| 8 | `siglo_xvii` | Siglo XVII | 17th century |
| 9 | `tiempo_maravilloso` | Tiempo maravilloso (intemporal) | Marvellous (timeless) |
| 10 | `antiguedad_clasica` | Antigüedad clásica | Classical antiquity |
| 11 | `tiempo_alegorico` | Tiempo alegórico | Allegorical |

The roadmap's earlier guess at this list was wrong in three places — it had `indeterminado` for
code 1, and `s.XV` / `s.XVI` / `s.XVII` for 6/7/8. The table above is what the export contains.

### Why a slug and not the code or the label

Storing `"8"` makes the database, the admin form and every activity-log entry unreadable without a
lookup table. Storing `"Siglo XVII"` verbatim gives no English rendering and lets typos fragment
the field so it can never be filtered.

A slug plus a translated label is also what this repo already does: division types are `"acto"` /
`"escena"`, `relationship_type` is `"traduccion"`, and the statistics panel deliberately stores the
raw division type and translates at display time.

A `historical_periods` lookup table with an admin CRUD page was considered and rejected: two
migrations, a join and a second admin page for nine values that have not changed in years.

## Schema

One migration, two columns on `plays`:

```elixir
add :historical_time, :string      # slug from the table above
add :historical_time_note, :text   # free prose
```

Both are added to `@platform_owned` in `lib/emothe/import/tei_parser.ex:23`. Omitting that step
means the next TEI re-import erases them; this is the standing S0b rule for every new curated
column.

`Play.changeset/2` gains `validate_inclusion(:historical_time, @historical_times)`. `nil` passes —
`validate_inclusion` skips nil changes, the same way `relationship_type` already works.

`historical_time_note` is not validated. It is prose.

## Reading the export

`Emothe.Import.Filemaker` currently discards every line whose layout is not `T00_indiceEM`. It
gains a second reader:

```elixir
Filemaker.load_versions(path) :: {:ok, %{code => version}} | {:error, term()}

version :: %{
  code: String.t(),
  historical_time: String.t() | nil,
  historical_time_note: String.t() | nil
}
```

Keyed by the code in the `pub_edicionWeb` href — `<a href='../biblioteca/textosEMOTHE/
HIE0393_TheSpanishBawd.php'>` — because that is the only place the `HIE####` codes appear. When
the href is missing, fall back to `"EMOTHE" <> zero-padded _IdTituloEmothe`, which is what
`docs/build_import_analysis.py` does.

The slug comes from `bus_tiemHistorico` through the code table. The note comes from the text after
`<br/>Note:` inside the first `<li>` of `pub_TiemHistorico`, tags stripped, whitespace collapsed.

A record with more than one `<li>` takes the first and logs a warning naming the code. This is a
deliberate ceiling: zero of our 22 plays need more, and two of 439 in the whole export do. If a
later import needs both periods, the column becomes an array or a join table then, not now.

## Sync

`FilemakerSync.plan/2` gains the two new keys, but they do **not** behave like the S1 fields.

`language`, `relationship_type` and `parent_play_id` are derived facts the index is authoritative
for, so the index overwrites them. `historical_time` and `historical_time_note` are research
metadata a curator is expected to edit, so the export is a bootstrap and must not stomp them:

| Database | Index | Result |
|---|---|---|
| blank | has a value | `changes` — written |
| set, equal | same value | `unchanged` |
| set, different | has a value | `conflicts` — reported, **not** written |
| anything | blank | `unchanged` — never blanks a set column |

`plan/2`'s return map gains a fourth key:

```elixir
plan :: %{changes: [...], unchanged: [...], missing: [...], conflicts: [...]}

conflict :: %{play_id: binary(), code: String.t(), title: String.t(),
              field: atom(), current: term(), indexed: term()}
```

`apply_plan/2` takes `force: true`, which folds every conflict into the writes. The mix task grows
`--force` and prints the conflicts either way.

The two policies living side by side in one module will read as an inconsistency to whoever opens
it next, so the module doc says which fields are which and why.

## Admin

A "Research metadata" fieldset in `lib/emothe_web/live/admin/play_form_live.ex`:

- `historical_time` — a select of the nine translated labels plus a blank option
- `historical_time_note` — a textarea

Both are plain `<.input>` calls in the existing form. No new page, no new route, no new context
function: `Catalogue.update_play/2` already handles them once they are in the changeset.

## Public page

A new `<section id="meta-study">` after the header in
`lib/emothe_web/live/play_show_live.ex:322`, rendered only when `historical_time` is set:

```
Historical time
Classical antiquity
First century BC. The play dramatizes events taking place between 40 and 30 BC.
```

`meta-study` is appended to `@metadata_sections` so the existing sidebar scroll-spy lists it beside
Sources and Editors. The section is invisible for the 71 plays with no period, which is why it is a
section and not a third tab — a tab bar that gains and loses a tab between plays is worse than a
section that is simply absent.

Each later S2 field adds a row to this same section. It is the panel.

## Testing

Following the repo's TDD rule — failing test first, every time.

- **Parser** — a new `test/fixtures/filemaker/versions_sample.ndjson`, four lines: a `_meta`
  envelope for `T01_tituloEM`, a record with code and note, a record with a code and empty
  `pub_TiemHistorico`, and a record with two `<li>`s. Assert the slug, the note text, the
  code-only case yielding a slug and a nil note, and the multi-`<li>` case taking the first.
- **Sync** — fill, equal, conflict, and `force: true` promoting a conflict. Plus one asserting the
  S1 fields still overwrite, so the two policies do not get accidentally unified later.
- **Changeset** — an invalid slug is rejected, `nil` is accepted.
- **Re-import** — a TEI re-import of a play with a historical time leaves both columns intact.
  This is the `@platform_owned` regression test; without it the omission is silent.
- **LiveView** — `meta-study` present with data, absent without.
- **Whole suite** — `mix test`, currently 277 passing, before any completion claim.

## Out of scope

`place_of_action`, `composition_date`, `collection`, `legacy_url`, `original_title` and
`title_sort` are each a follow-up slice reusing the T01 reader and the panel this one builds.

No network access, no new dependency, no change to the TEI importer beyond the `@platform_owned`
line.
