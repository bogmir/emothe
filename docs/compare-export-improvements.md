# Comparison Export — Pending Improvements

## Current Status

The comparison HTML export (`Emothe.Export.CompareHtml`) already covers:
- Self-contained HTML (CSS + JS embedded)
- Sync scroll between panels (by act/scene/speech key)
- 2-panel and 3-panel layouts work correctly
- Print-friendly fallback

## What Still Needs to Be Done

### 1. Fix 4-panel layout → 2×2 grid

**Problem**: Exporting 4 plays produces 4 very narrow columns in a single row.

**Fix**: In `comparison_css/1` (`lib/emothe/export/compare_html.ex`), when `panel_count == 4`:
- `grid-template-columns: repeat(2, 1fr)` (2 columns)
- `grid-template-rows: 1fr 1fr` (2 rows)
- Panel `height: 50vh` (half viewport per panel)

Same fix needed in `play_compare_live.ex` (`grid_class/1`, `panel_height/1`) so the LiveView comparison page matches.

### 2. (Deferred) Sync scroll toggle

A checkbox in a toolbar to enable/disable synchronized scrolling. Low priority — sync is always on for now.

## Out of Scope

- Spring Boot / Java implementation (we use Phoenix/Elixir)
- Raw XML + XSL transform workflow (we use DB plays)
- 5-panel support (not needed)
- Header bar "EMOTHE: PARALLEL VIEW" (current title display is fine)
