# Implied Speakers: Editorial Convention and Workflow

## The Problem

Some plays contain speeches where the speaker is not labeled explicitly in the source
text, but is identified in a preceding stage direction. Example from *Auto da Barca do
Inferno* (Gil Vicente):

> "Diz o Diabo ao Moço da cadeira:" (v. 170)

The following speech belongs to DIABO, but the original witness has no `<speaker>` tag.
For TEI-XML encoding, every `<sp>` must have a `who` attribute linking it to a character.
The editorial question is: what should be displayed to the reader?

## Three Options

| Option | Speaker Label displayed | Character in TEI `who` attr | Example |
|--------|------------------------|-----------------------------|---------|
| 1 — Explicit label | Yes, plain text | Yes | `DIABO` shown, `<sp who="#diabo">` |
| 2 — Hidden speaker | No | Yes | Nothing shown, `<sp who="#diabo">` |
| 3 — Bracketed label | Yes, with brackets | Yes | `[DIABO]` shown, `<sp who="#diabo"><speaker>[DIABO]</speaker>` |

## Adopted Convention: Option 2 (Hidden Speaker)

We use **Option 2** for implied speakers: assign the character for TEI purposes but
display nothing to the reader. Reasons:

- Editorially honest — no label is shown that is absent from the source
- Consistent with the CET-e-quinhentos reference edition (http://www.cet-e-quinhentos.com/)
- Character attribution is still encoded in TEI for statistics and computational research
- Consistent with the earlier FileMaker workflow (add brackets in pre-mark → remove after
  linking → only the `who` attribute survives)

## How EMOTHE Supports This

Each speech element has two independent fields:

- **`speaker_label`** — the text shown in the web UI (nullable; rendered only if non-empty)
- **`character_id`** — FK to the character, used for the TEI `<sp who="#...">` attribute

Setting `character_id` without `speaker_label` produces a speech that is attributed in
TEI but invisible in the public view. This is Option 2.

## Editing Workflow in EMOTHE

Go to **Admin → Play → Content → Character Review tab**.

1. Filter by speaker label or assignment status to find the affected speeches
2. Select one or more speeches using the checkboxes
3. Choose the correct **Character** from the dropdown
4. Check **"Set label"** and leave the text field empty (to clear the label)
5. Click **Assign**

Both the character assignment and the label change are applied in a single step.
To set a label instead of clearing it, type the desired text (e.g., "DIABO") in the
field before clicking Assign.

## Known Affected Plays

### Auto da Barca do Inferno (*BARCA DO INFERNO*)
Speeches where the speaker is named only in the preceding stage direction:

| Verse | Implied speaker |
|-------|----------------|
| 170 | DIABO |
| 182 | ONZENEIRO |
| 250 | PARVO |
| 312 | SAPATEIRO |
| 369 | DIABO *(currently has explicit label — should be cleared for consistency)* |
| 481 | BRÍSIDA |
| 562 | JUDEU |
| 610, 682, 714, 742 | CORREGEDOR |
| 754 | DIABO |
| 826 | CAVALEIROS |

### Estrangeiros / Contra si faz...
These plays were imported with bracketed labels (`[CASSIANO]`, etc.) that were not
removed after character assignment. Fix: clear `speaker_label`, keep `character_id`.

## Verification

After editing:
1. **Public view** (`/plays/:code`): the affected speeches show no speaker label
2. **TEI export** (`/admin/plays/:id` → Export TEI): the `<sp who="#...">` attribute is
   present but no `<speaker>` child element exists for those speeches
3. **Statistics**: character appearance counts are unaffected (driven by `character_id`,
   not `speaker_label`)
