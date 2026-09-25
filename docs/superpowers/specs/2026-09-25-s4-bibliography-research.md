# S4 — Bibliography: research

**Status:** research, 2026-09-25. **Not a design yet**: the shape at the end is a proposal, and
the questions under "Open questions" decide whether it holds. Slice S4 of
`../plans/2026-08-01-filemaker-import-slices.md`.

Measured across all 439 `T01_tituloEM` rows of `doc/w3emothe_T01_tituloEM.ndjson`, not only
the 22 that match plays we hold. S4 is sequenced after the ~300-play import (roadmap
question 5), so the full export is what it will actually run against. The "today" column is
the roadmap's own `Filemaker.load_versions/1` measurement.

## Summary

- Four fields, **3063 citations on ~120 versions** across the export. 318 of them fall on
  plays we hold today.
- **Every citation is FileMaker template output over a structured record.** FileMaker keeps
  the structure; all the export gives us is the rendered string.
- **What the string gives back:** the kind, the citation text, a sort year, a URL, and the
  language of translations.
- **What it does not give back:** reliable field boundaries, publication type, per-record
  language, record identity — and **~690 criticism records** that are linked in FileMaker
  but never rendered at all.
- **Order is computed, not curated:** year descending. There is no position to preserve.
- **TEI has nothing to import.** No fixture carries a secondary bibliography. The place for
  one is `text/back`, not `sourceDesc`.
- **Proposal:** one table, holding the citation verbatim plus sort and filter columns.
  Structured columns wait on question 1.

## The fields

| Field | What it is | Versions | Citations | Today |
|---|---|---|---|---|
| `pub_EdModernas` | modern editions | 120 | 823 | 84 |
| `pub_BibSelectaCritica` | criticism | 106 | 2003 | 198 |
| `pub_BibSelectaTraduccion` | translations, grouped by language | 61 | 187 | 29 |
| `pub_BibSelectaAdaptacion` | adaptations | 17 | 50 | 7 |

The translation headers are ES 44, FR 56, IT 30, DE 41 and EN 16.

Four search-index siblings sit next to these fields. They are useful for validating a
parse, but they cannot be the source:

| Field | Rows | What it holds |
|---|---|---|
| `bus_criticaAnyo` | 146 | the year of each criticism record, **digits only**, in display order: `1996/7` → `19967`, `1957-75` → `195775`. 2689 entries against 2003 published citations |
| `bus_tradAnyo` | 107 | the same for translations: `1859-79` → `185979`, `[1873-4]` → `18734` |
| `bus_tradIdioma` | 120 | a language code for every linked bibliography record, of every kind. See "Language codes" |
| `bus_tradTraductor` | 95 | translator names, one per line; blank lines and misspellings (`Strachey` / `Stratchey`) included |

## What a citation looks like

**Modern edition.** The editor comes first, then the title in italics, then the author:

```
Fassò, L., ed. <i>Il pastor Fido</i>. Guarini, Giovanni Battista. Torino: Einaudi, 1976.
Thompson, Ann; Taylor, Neil, ed. <i>Hamlet</i>. Shakespeare,  William.  In:  <i>Hamlet: The Texts of 1603 and 1623</i>. London: Thomson Learning, 2006, The Arden Shakespeare.
```

**Criticism.** The three shapes are article, chapter and book. There are **no italics**:

```
Long, Zackariah C. "The Spanish Tragedy and Hamlet: Infernal Memory in English Renaissance Revenge Tragedy". English Literary Renaissance. 2014, vol. 2, 44, p. 153-192.
Greenblatt, Stephenn. "[Introduction to] Hamlet".  Ed. Stephen Greenblatt. The Norton Shakespeare, Based on the Oxford Edition. 2nd ed ed. New York: W. W. Norton, 2008, p. 103-115.
Litvin, Margaret. Hamlet's Arab Journey. Princeton and Oxford: Princeton University Press, 2011.
```

**Translation.** Items are nested under an outer `<li>` that carries the language header:

```
<ul><li>ES:<ul><li>Shakespeare, William. Hamlet.  Tra. Pujante, Angel-Luis. Madrid: Espasa-Calpe, 1994. </li>
…</ul></li><li>FR:<ul><li>Shakespeare, William. Hamlet.  Tra. Déprats, Jean-Michel. Paris: Granit, 1986. </li>…</ul></li></ul>
```

34 translations end in `(Orig: <original title>)`.

**Adaptation.** Book-shaped, and sometimes credited with a translator:

```
Coello, Carlos. El príncipe Hamlet, drama trágico-fantástico en tres Actos y en verso, inspirado por el Hamlet de Shakespeare. Madrid: Imprenta de José Rodríguez, T. Fortanet, 1872.
```

### The template gives the record away

When a field is empty, FileMaker writes a placeholder in its place. The placeholders name
the fields:

| Placeholder | Items |
|---|---|
| `{Falta nombre editorial}` | 318 |
| `{Falta nombre ciudad}` | 254 |
| `{Falta título libro}` | 31 |
| `{Falta autor libro}` | 16 |
| `{Falta autor capítulo libro}` | 11 |
| `{Falta año pub}` | 10 |
| `{Falta nombre Universidad}` | 9 |
| `{Falta páginas capítulo}`, `{Falta título revista}` | 6 each |
| `{Falta título editado}`, `{Falta autor artículo revista}` | 3 each |
| `{Falta título artículo revista}` | 2 |
| `{Falta URL pub. electrónica}` | 1 |

**429 of 3063 items (14%) carry at least one placeholder.**

Those placeholders, together with the rendered shapes, imply roughly this record in
FileMaker. It is **inferred, not seen**:

- **People:** author, editors, translators.
- **Titles:** title, plus a container title (book, edited volume or journal).
- **Imprint:** city, publisher, year (stored as text), edition.
- **Location in the publication:** volume and total volumes, series, pages, journal volume
  and issue.
- **Type-specific:** university (for theses), URL (for electronic publications), original
  title (for translations).
- **Other:** a free note (`Reimp. Espasa-Calpe, … 1945`, `Based on Joost Daalder…`), a
  language code, and some flag that decides whether the record is published. See loss 7.

## What the export loses

1. **Field boundaries.** Fields are separated by `. `, but titles and initials contain it
   too:
   - `Ara, J..` has a doubled period on 212 criticism items.
   - `Hamlet.Tragedia de Guillermo Shakespeare. Traducida é ilustrada…` runs two fields
     together.

   The journal-article shape (`Author. "Title". Journal. Year, …, p. N-M.`) matches about
   1100 of the 2003 criticism items. Splitting everything else into fields is heuristic.
2. **Publication type.** The type is only implied by the template: quotes, `Ed.`, `, ed.`.
   It is never stated. Theses and electronic publications cannot be told apart from books
   reliably.
3. **Italics.** Only modern editions keep `<i>`. In criticism, translations and adaptations,
   a book title is plain text, so it reads the same as a journal name.
4. **Volume and issue.** `English Literary Renaissance. 2014, vol. 2, 44` is volume 44,
   issue 2, so the order is reversed. Many items carry one bare number, which could be
   either.
5. **Per-record language.** FileMaker has it (`bus_tradIdioma`), but as an unaligned union:
   its count matches the published items on **5 of 159** versions. Only translations keep a
   usable language, through their group header.
6. **Record identity.** One FileMaker record linked to several versions arrives as repeated
   text with no ID. 37 edition texts and 22 criticism texts appear on more than one
   version. There are also 8 exact duplicates inside a single version.
7. **Records that are never rendered.** On 40 versions, `bus_criticaAnyo` lists **698**
   criticism years while `pub_BibSelectaCritica` is empty. In total `bus_criticaAnyo` has
   2689 entries against 2003 published citations. `bus_tradIdioma` also exceeds the
   published count on 32 versions. `bus_publicada` does not explain the gap. This data
   **cannot be recovered from this file at all**. The field name *Bib**Selecta*** suggests
   a "selected" flag on each record.
8. **Years are text.** About 30 year values are ranges or conjectures (`1957-75`,
   `[1873-4]`, `1996/7`). A handful are `0`, and at least 4 lost a digit in the rendered
   citation (`Ricciardi, 956`, `Atenore, 985`).

Not a loss of information, but a trap for the parser:

- **`<<Hamlet>>`** marks a title inside a title (33 items).
- **`<https://…>`** is a URL in angle brackets (19 editions). Translations use
  `URL: https://…` on its own line (6 items).

  An HTML parser, or rendering the raw string as HTML, reads both as tags and drops them.
- **The translation nesting defeats the flat `@list_item` regex** in
  `lib/playcode/import/filemaker.ex`. Matched non-greedily from the outer `<li>`, it runs to
  the first inner `</li>`, so the first translation of every language absorbs the header
  and the opening `<ul>`. Match the groups first, with
  `<li>\s*([A-Z]{2})\s*:\s*<ul>(.*?)</ul>\s*</li>`, then the items inside each group.
- **Dirty source data** gets imported as it is:
  - typos: `Atenore`, `Golderbg`, `Stephenn`
  - template leftovers: `2nd ed ed.`, `Oxford2007.`
  - the placeholders

## Order is computed, not curated

`bus_criticaAnyo` is in display order and descends numerically on **135 of 139** rows. The
four exceptions are bad year values (`-18981916`, `0`), not curation. `bus_tradAnyo`
descends on 56 of 59.

So FileMaker sorts on the year field with its non-digits stripped. That is why `1957-75`
(sorting as 195775) heads 17 criticism lists, above citations from 2014. The quirk is not worth
reproducing: `year desc` gives the intended order. **There is no curated position to
import, and nothing in the data asks for a reorder UI.**

## Language codes

These are the codes in `bus_tradIdioma`, decoded against the translation headers and each
play's language. They are the same codes as `bus_idioma`:

| Code | Language | Entries |
|---|---|---|
| 1 | ES | 306 |
| 2 | FR | 109 |
| 3 | EN | 939 |
| 4 | IT | 66 |
| 6 | DE | 61 |

`5` never occurs. It is probably PT, which is the only one of S1's five index languages
without a code here.

## Links into our own corpus

26 citations point at an EMOTHE edition by code: 21 modern editions and 5 translations,
covering 25 distinct `EMOTHE####` codes. For example:

- `…EMOTHE Digital Library. <https://emothe.uv.es/biblioteca/textosEMOTHE/EMOTHE0170_TheChangeling.php>`
- `Kyd, Thomas. "La tragedia española". Tra. García García, Luciano. … URL: …EMOTHE0307_…`

Each of these could become a link to a play we hold. It is optional, and cheap once the URL
is its own column.

## Proposed shape *(proposal, pending the open questions)*

```
play_bibliography
  play_id    FK plays, on delete cascade
  kind       modern_edition | criticism | translation | adaptation
  citation   text     -- display form; <i> is the only markup kept
  year       integer  -- first 4-digit year in the citation; sort only; nil when unknown
  language   string   -- ISO code as plays.language; required for translation, else optional
  url        string   -- lifted out of <…> or "URL: …"
  origin     manual | filemaker | tei
  timestamps
```

- **Sort** by `year desc nulls last, citation`. There is no `position` column.
- **Normalise on import:**
  - `<<X>>` becomes `«X»`.
  - The URL moves to `url`.
  - Collapse whitespace.
  - Everything else stays verbatim.
- **Render** by escaping everything, then re-allowing `<i>`/`</i>`.
- **Fill-only, per play and kind.** This is S2's policy applied to child rows:
  - The sync writes a play's FileMaker citations of one kind only when that play has
    **no** rows of that kind yet.
  - Otherwise it reports the play as a conflict and writes nothing.

  Matching individual rows on citation text is the obvious alternative, and it is wrong.
  Once a curator corrects a typo, the edited row no longer matches, so the next sync
  re-adds the original. And a citation a curator deleted comes back. Fill-only avoids
  both problems without a key column or tombstones, and a second run writes nothing.
- **Admin:** one page per play, grouped by kind, with add, edit and delete. It needs a
  filter or search box, since Hamlet alone has 62 criticism items.

**Rejected for now:**

- **Structured columns now** (author, title, container title, volume, issue, pages…).
  Filling them by parsing strings would leave about 1000 rows for a person to review. They
  pay for themselves only if FileMaker delivers structured records (question 1). Adding
  them later is a purely additive migration, and `citation` stays as the display form.
- **A corpus-global `bibliography_entries` table** joined to plays, the way the places
  gazetteer works. 59 repeated texts out of about 2900 do not justify it. Record IDs from
  FileMaker would. That also belongs to question 1.

## TEI

**There is nothing to import.** I checked all 96 fixture files after UTF-16 decoding:

- zero `<listBibl>`, `<biblStruct>` or `<relatedItem>`
- `<back>` is empty in 94 files
- the only `<bibl>` elements are the `sourceDesc` base-text entries, which are already
  `play_sources`

So a bibliography in TEI would be ours to add. Its round-trip is export, then import,
against our own output — the same situation as S2c's `<creation>`.

The other 2 files hold a `<div type="epilogo">` in `<back>`. The parser ignores `<back>`
entirely, so those epilogues are silently dropped on import. That is a separate bug, found
here, and a parser change to read `<back>` should fix it in the same pass.

**Do not put it in `sourceDesc/listBibl`.** The parser already reads
`sourceDesc/listBibl/bibl` into `play_sources` (`lib/playcode/import/tei_parser.ex:729-733`),
so criticism placed there would come back as base-text sources. It would also be wrong in
principle: `sourceDesc` describes the sources of this electronic text, which is where S3's
witnesses belong. Secondary bibliography is not a source.

**Put it in `<back>`.** The `type` values are in Spanish, to match the corpus's
`acto`/`escena`/`elenco`:

```xml
<back>
  <div type="bibliografia">
    <listBibl type="ediciones_modernas">
      <bibl>Fassò, L., ed. <title>Il pastor Fido</title>. Guarini, Giovanni Battista. Torino: Einaudi, <date when="1976">1976</date>.</bibl>
    </listBibl>
    <listBibl type="critica">…</listBibl>
    <listBibl type="traducciones">
      <bibl xml:lang="fr">Shakespeare, William. Hamlet. Tra. Déprats, Jean-Michel. Paris: Granit, 1986.</bibl>
    </listBibl>
    <listBibl type="adaptaciones">…</listBibl>
  </div>
</back>
```

- **Use `<bibl>`, not `<biblStruct>`.** `<biblStruct>` requires `analytic`, `monogr` and
  `imprint` parts that a string cannot honestly fill. `<bibl>` is mixed content, so the
  citation goes in as text:
  - `<i>` becomes `<title>`
  - `url` becomes `<ptr target>`
  - `year` becomes `<date when>`
- **If structured records arrive later** (question 1), they map directly onto
  `<biblStruct>`, or onto a tagged `<bibl>`: `<author>`, `<editor role="translator">`,
  `<title level="a|m|j">`, `<pubPlace>`, `<publisher>`,
  `<biblScope unit="volume|issue|page">`.
- **Round-trip.** The parser reads `back/div[@type="bibliografia"]` and writes rows with
  `origin: "tei"`. A re-import deletes only that play's `tei` rows, and **skips any bibl
  whose normalised citation already exists under another origin**. That is S9's
  leave-alone rule for places. Without it, exporting and re-importing a file duplicates
  every `manual` and `filemaker` row.
- **Why bother.** The static site publishes `plays/<CODE>/<CODE>.xml`. With the
  bibliography in `<back>`, that file is self-contained, which is the Endings argument.
- **Sequence.** The table, admin page and FileMaker import come first. TEI in both
  directions is the slice's last task.

## Open questions

**For the FileMaker side.** These go in the same message as the genre value lists and
`bus_lugAccion` (roadmap question 4):

1. **Can you export the bibliography table directly?** That means one row per record with
   its fields and ID, plus the table linking records to versions. This is the question that
   changes the design: it removes losses 1–6 and 8, and it turns the structured columns and
   possibly the shared-entries table from rejected into obvious.
2. **What decides whether a record appears in `pub_BibSelecta*`?** Is it a "selected" flag?
   698 criticism records on 40 versions render nothing. Should the new system hold the
   unselected ones too, perhaps as non-public?
3. **Is language code `5` Portuguese?** And are 1 ES, 2 FR, 3 EN, 4 IT, 6 DE right?
4. **What is the value list for record types?** For example libro, capítulo, artículo,
   tesis, edición electrónica, edición moderna.

**For us:**

5. **Per version or per work?** FileMaker attaches bibliography to versions, and 84 of the
   129 versions carrying any bibliography are English-language versions. Should a translation's
   page also show its family head's list, through `parent_play_id`?
6. **Order.** Is it automatic year-descending, as FileMaker does it, or do curators want a
   hand order? A hand order brings back `position` and a reorder UI for lists that run to
   62 items.
7. **Placeholders.** `{Falta …}`: import them verbatim and flag them in the admin list, or
   also hide them on public pages? Stripping them from the text is fiddly —
   `{Falta nombre ciudad}: {Falta nombre editorial}, 1991` leaves `: , 1991` behind.

## Reproducing the numbers

Every count above is per `T01` row and does not depend on matching rows to our plays. So
the roadmap's `version_code/1` trap (href-only matching finds 13 of 22) does not apply. Any
count *per play we hold* must go through `Filemaker.load_versions/1`. The only
non-obvious parse is the translation nesting described under the parser traps.
