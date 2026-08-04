# Handover — S9 Places, Phase 1

**Branch:** `s9-places-phase-1`, 16 commits ahead of `main`, working tree clean.
**Suite:** 474 tests, 0 failures (3 excluded). `mix test --include slow` → 477, 0 failures.
**Plan:** `docs/superpowers/plans/2026-08-04-s9-places-phase-1.md` (all 12 tasks done)
**Spec:** `docs/superpowers/specs/2026-08-04-s9-places-design.md`
**Ledger:** `.superpowers/sdd/2026-08-04-s9-places-phase-1/progress.md` — per-task commits,
every deferred minor, and every ruling. Read it before touching anything.

## What was built

A corpus-global gazetteer, on three tables:

- `places` — the referent. Self-referencing `parent_place_id` for containment, coordinates,
  `is_fictional`, one `(authority, authority_id)` link. **No name column** — names live in
  their own table so a denormalised copy cannot drift.
- `place_names` — surface forms tagged by language. One preferred name per place *per
  language*, enforced by a partial index, so a Spanish UI prefers `Roma` and an English one
  `Rome`.
- `play_places` — the per-play index: `role` (`setting | mentioned`), `position`, `note`,
  `origin` (`tei | manual | filemaker`).

Surfaces: `Emothe.Places` (the only context), `/admin/places`, `/admin/plays/:id/places` as a
peer context-bar tab, `#meta-places` on `/plays/:code`, the static-site renderer, and TEI
`<settingDesc>` in both directions. Wikidata sits behind `Emothe.Places.Authority`, stubbed
in test config — **no test touches the network**, and that is a property worth keeping.

## Contracts a future change must not break

- **TEI shape.** A place's own note is `<note type="place">` directly under `<place>`; a
  *link's* note is a bare `<note>` inside `<setting>`/`<placeName>`. Sibling places nest
  alphabetically by slug; nesting itself carries the parent relationship. Full sample in
  `.superpowers/sdd/2026-08-04-s9-places-phase-1/task-10-report.md`.
- **A re-import never disturbs curated data.** `find_or_create_by_slug/1` returns an existing
  place untouched, and `reset_tei_content/1` deletes only `origin: "tei"` links. Both halves
  have tests that fail if the origin filter is dropped.
- **`Emothe.Authz.can?/3` is the only authorization predicate.** Places are
  `:manage_places`, researcher-level.
- **Slugs are stable.** They are URLs and TEI `xml:id`s. `ensure_slug/2` re-derives from
  `"names"` when `"slug"` is blank, so any form touching a place must round-trip the current
  slug — there is a regression test for this.
- **The static site is deterministically English**, wrapped in
  `Gettext.with_locale(EmotheWeb.Gettext, "en", …)`, because the rest of that renderer is
  hardcoded English and an archival artifact should not change language with the ambient
  locale.

## Three plan defects that were overridden (all in the ledger)

1. `link_place/3` derived the next `position` from a row **count**, so unlink-then-link
   duplicated a position and the next `move_play_place/2` silently no-opped. Now `max + 1`.
2. `activity_logs.resource_type` is a whitelist that lacked `"place"` and `"play_place"`, so
   every place write would have logged nothing. `ActivityLog.log!/1` swallows the invalid
   changeset, so this failed silently. Both values added.
3. The static-site test asserted literal `"17th century"` while the default locale is `"es"`
   and that msgid is already translated — it would have failed on arrival. Fixed by the
   locale wrapper above.

## Next: finish the branch

1. **Run the final whole-branch review — this was never done.** It is the one remaining step
   of the subagent-driven-development loop:
   ```
   scripts/review-package docs/superpowers/plans/2026-08-04-s9-places-phase-1.md $(git merge-base main HEAD) HEAD
   ```
   Dispatch `superpowers:requesting-code-review`'s `code-reviewer.md` on the most capable
   model, and point it at the ledger's deferred-minor lines so it can triage which must be
   fixed before merge. One fix wave, one scoped re-review, then
   `superpowers:finishing-a-development-branch`.
2. Delete `.superpowers/sdd/2026-08-04-s9-places-phase-1/` once merged — git history is the
   record then.

### Deferred minors worth a decision at review time

- `place_form_component.ex` (327 lines) calls `Places.find_by_name/1` once per name field on
  every keystroke. Fine at gazetteer scale; wants a `ponytail:` comment naming the ceiling.
- `PlayPlace.changeset/2` has no `foreign_key_constraint(:play_id)`, so a bad `play_id`
  raises instead of returning a changeset error.
- `search_names/2` strips `%` and `_` from the term rather than escaping them, so a literal
  underscore in a place name is unsearchable.
- The per-play page's `link` handler maps every `{:error, changeset}` to "already linked".
- `render_places/1`'s fallback clause is unreachable; its `with_locale` wrapper currently
  guards no live gettext call (forward-compatible only).
- `unique_slug/2` reads-then-inserts, so two concurrent creates of the same name collide on
  the DB constraint instead of auto-suffixing.

## Then: design Phase 2

Brainstorm first (`superpowers:brainstorming`), then write the plan. Phase 1 deliberately
stopped at the play level; Phase 2 is where places enter the text. Scope recorded in
`CLAUDE.md`:

- **In-text mentions** — `<placeName ref>` inside the body, an `element_places` join table,
  and the tagging UI. This is the big one, and the reason `play_places` was kept separate:
  a mention is a different relation, not a row on the same table.
- **Map rendering** from the coordinates already stored (Phase 1 stores them and shows none).
- **Catalogue browse-by-place** — "every play set in Italy" is the query the shared gazetteer
  exists to make answerable; `ancestors/2` already gives the containment chain.
- **Multiple authority links per place** — the current unique `(authority, authority_id)`
  allows one. Geonames/TGN/Pleiades are already in `Place.authorities/0` and
  `Authority.registry/0` but have no implementation module.
- **FileMaker `pub_LugAccion` import** — deliberately excluded from Phase 1. It is the
  original S2b field; `find_or_create_by_slug/1` is the seam it should call, and it must
  stamp `origin: "filemaker"`.

Open questions the spec left for the project, worth resolving before planning Phase 2:
whether a mention needs its own role vocabulary distinct from `setting | mentioned`, and
whether a fictional place needs a "referenced real place" link (Atlántida → the Atlantic).

## Environment gotcha

`mix` is **not** on PATH in the tool sandbox. Every command needs:

```bash
export PATH="/home/bogdan/.asdf/installs/erlang/28.1/bin:/home/bogdan/.asdf/installs/elixir/1.19.5-otp-28/bin:/usr/bin:/usr/local/bin:/bin:$PATH"
```

Commit `780df96` took the suite from 71.5s to 3.8s: `bcrypt_elixir` at `log_rounds: 4` in
test, and `@moduletag :slow` on `test/emothe/export/tei_validator_test.exs` (three xmllint
runs at ~15s each), excluded by default in `test_helper.exs`. **Run
`mix test --include slow` before any merge** — those three validate exported TEI against the
RelaxNG schema, which is exactly what catches malformed `<settingDesc>`.
