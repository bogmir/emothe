# Public Catalogue Comparison — Design

**Date:** 2026-06-21
**Status:** Approved design, pending spec review

## Goal

Make the side-by-side play comparison (currently admin-only at `/admin/plays/:id/compare`)
available to the public. In the catalogue (`/plays`), show a comparison icon — the same
`hero-arrows-right-left` icon used in the admin play-detail context bar — on a play row,
but **only when that play group has at least one linked play**. Clicking it opens a public
comparison view of the available related plays.

## Background

- The N-panel sync-scroll comparison UI already exists:
  [play_compare_live.ex](../../../lib/emothe_web/live/admin/play_compare_live.ex).
- It uses the reusable `<.play_body>` component and a `SyncScroll` JS hook.
- The "family" concept (root/original play + all derived translations/adaptations) is already
  computed by `build_family/1` and auto-adds the parent panel for translations.
- The catalogue already groups plays: each main row is an original play with its
  `derived_plays` nested beneath it ([play_catalogue_live.ex:81-119](../../../lib/emothe_web/live/play_catalogue_live.ex)).
  So `play.derived_plays != []` is exactly the "has at least one linked play" signal.

## Decisions

- **Public UI scope:** Full clone of the admin comparison UI — same N-panel layout, the same
  display toggles (line numbers, stage directions, asides, split verses, verse type), the
  add-play dropdown, and sync scroll.
- **Icon placement:** Main (original/parent) play row only, shown when the group has ≥1
  derived play. Opens the comparison of the whole family. Derived rows get no separate icon.
- **HTML export button:** **Dropped** on the public page. The admin "Export HTML" button
  points at the admin-only `/admin/plays/compare/export/html` endpoint; exposing a public
  comparison-export endpoint is out of scope for this change. (Single-play TEI/HTML/PDF/EPUB
  exports remain available from the catalogue as today.)

## Architecture

### 1. New public LiveView: `EmotheWeb.PlayCompareLive`

A public sibling of the admin `Admin.PlayCompareLive`, placed at
`lib/emothe_web/live/play_compare_live.ex`.

Differences from the admin version:

- **Mount by `:code`** (public routes are code-based), not `:id`:
  `Catalogue.get_play_by_code_with_all!(code)`.
- **No admin chrome:** no `:breadcrumbs`, no `:play_context` assigns. Renders inside the public
  `:app` layout.
- **No "Export HTML" button** in the toolbar.
- A **"Back to play"** / "Back to catalogue" link suited to the public layout (e.g. link to
  `~p"/plays/#{@play.code}"`).

Everything else is carried over verbatim:

- `build_family/1`, the parent auto-add behaviour, `available_plays/2`, `grid_class/1`,
  `panel_height/1`, `@max_panels` (4).
- Event handlers: `toggle_line_numbers`, `toggle_stage_directions`, `toggle_asides`,
  `toggle_split_verses`, `toggle_verse_type`, `add_play`, `remove_panel`.
- The N-panel render with `phx-hook="SyncScroll"` and `<.play_body ... sync_keys={true}>`.

> Implementation note: the admin and public LiveViews share substantial logic. During
> implementation, decide whether to (a) extract the shared family/panel helpers into a small
> module (e.g. `EmotheWeb.PlayComparison`) consumed by both, or (b) accept a focused copy.
> Lean toward extraction if it stays clean; the toggles/handlers are short enough that a copy
> is acceptable if extraction adds indirection. This is a quality call to make against the
> code at implementation time, not a new feature.

### 2. Route

Add inside the existing `:public` `live_session` in
[router.ex:57-62](../../../lib/emothe_web/router.ex):

```elixir
live "/plays/:code/compare", PlayCompareLive, :compare
```

Placed alongside `live "/plays/:code", PlayShowLive, :show`. Public layout, no auth.

### 3. Catalogue icon

In [play_catalogue_live.ex](../../../lib/emothe_web/live/play_catalogue_live.ex), on the main
play row (the `flex items-center gap-3` block, before/next to `<.export_buttons>`), add:

```elixir
<.link
  :if={play.derived_plays != []}
  navigate={~p"/plays/#{play.code}/compare"}
  class="btn btn-xs btn-ghost btn-square text-base-content/50 hover:text-primary tooltip tooltip-bottom"
  data-tip={gettext("Compare")}
>
  <.icon name="hero-arrows-right-left-mini" class="size-3.5" />
</.link>
```

- Uses the `-mini` icon variant to match the catalogue's existing export-button icons (the
  admin context bar uses `-micro`; this keeps visual consistency with the catalogue row).
- The `:if={play.derived_plays != []}` guard is the "at least one linked play" condition.
  No query changes needed — `derived_plays` is already loaded for catalogue rows.

## Data flow

1. User on `/plays` sees the compare icon only on rows whose group has derived plays.
2. Click → `navigate` to `/plays/:code/compare`.
3. `PlayCompareLive.mount/3` loads the play by code, builds the family, seeds the first panel
   (and the parent panel when the play is a translation), assigns display-toggle defaults.
4. User toggles display options, adds/removes panels (up to 4) from the family; sync scroll
   keeps panels aligned.

## Error handling

- Unknown `:code` → `get_play_by_code_with_all!/1` raises `Ecto.NoResultsError` → standard
  404, same as `PlayShowLive`.
- A play with no family members: the icon is not shown in the catalogue, so the page is
  normally only reached for plays with links. If reached directly (manual URL) for a play with
  no relatives, the add-play dropdown is simply empty and a single panel renders — acceptable,
  no special handling.

## Testing

- LiveView test: catalogue shows the compare icon for a group with a derived play and hides it
  for a standalone play.
- LiveView test: `/plays/:code/compare` mounts for a translation, auto-includes the parent
  panel, and renders both play titles.
- LiveView test: `add_play` / `remove_panel` events add and remove panels; the `@max_panels`
  cap is enforced.
- Route test: the public compare route requires no authentication.

## Out of scope

- Public comparison HTML export.
- A compare icon on the public play-show page (`/plays/:code`) — could be a follow-up.
- Comparing arbitrary unrelated plays (only the family is offered, same as admin).
