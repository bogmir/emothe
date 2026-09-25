# Test suite rework, 2026-09-25/26

Branch `test/behaviour-rework`, 28 commits on top of `e4e6633`, merged to `main`. The
suite was reshaped around one rule, from Saša Jurić: test behaviour through the
outermost API (routes, LiveViews, mix tasks), and test an internal only where that is much
simpler to set up. The working rules that came out of it are in `CLAUDE.md`, under "Test
behaviour through the outermost API".

## In numbers

| | Before | After |
|---|---|---|
| `mix test` | 555 tests, 16.4 s | 424 tests, about 5 s |
| `mix test --include slow` | 3 slow tests; no corpus file ever imported | 506 tests, 0 failures, all 83 corpus files |
| Line coverage | 52.7% | 76.6% |

Every new test was shown to catch a bug: the covered line was broken, the test went red,
the line was restored. Every deleted test names in its commit what still covers it.

## Bugs found and fixed

Each was found by a new test and fixed test-first in its own commit.

| Commit | Bug |
|---|---|
| `94e2cff` | The TEI export dropped every `induction` division with all its content: Bartholomew Fair, and every Word-imported play that has one. |
| `9f0d5c8` | The TEI export dropped every stage direction's `@type` (exit, entrance, business, location, setting, mixed, delivery). **Adds the nullable column `play_elements.stage_type`, a migration to deploy.** |
| `dd47c27` | Export → re-import → export added one duplicate editor per cycle: titleStmt editors were written into editionStmt too. |
| `e3cbdf1` | `TeiParser.import_file/1` returned the play from before its verse count was recalculated. |
| `e28c497` | Word import: verses after `{m}` (stanza) were never stored, and `{ap}` (aside) was ignored. `docs/word-import-feature.md` defines both tags. |
| `9cf3c66` | `POST /locale` with `return_to=//evil.com` crashed with a 500. |

## What is now tested that was not

- **Access control, route by route** (`c19c872`): every gated route, opened by anonymous,
  researcher, admin, deactivated and unconfirmed users. Removing `ExportSiteLive`'s
  `on_mount` used to break no test; a researcher could then have deployed the public
  site.
- **The real TEI corpus** (`d6272b6`, `4372007`): the roundtrip test had put every file on
  a skip list, so it imported none. Two tracked files now run on every `mix test`, and
  the full corpus runs under `--include slow`.
- **The main user journeys**, which had no test through their pages:
  - log in, log out, forgot password, change password (`029ed5d`);
  - TEI import through the admin page (`1caebe4`);
  - the content editor, 2,818 lines (`aed3619`);
  - the public catalogue and the play text (`bf6716a`);
  - downloads and the JSON API (`de7251f`);
  - the editors, sources and activity log pages (`59601b5`);
  - all four mix tasks (`6791285`, `32611c4`).
- **Invitation and reset emails** are read in the tests, including the link they carry.

## What the tests stopped doing

- **Asserting on storage.** Import/export tests now import a snippet, export it and query
  the XML (`c3aa170`, `7da8d52`). They used to walk `parent_id`, `position` and element
  types. The helpers are in `test/support/import_helpers.ex`.
- **Calling internals**, such as the Word parser's `parse_line/1`, the static-site
  renderer, and a LiveView's label helpers. Those Word functions are now private.
- **Mirroring code**, such as `authz_test` copying `authz.ex`'s action lists, and
  hand-built copies of the FileMaker parser's output.
- **Relying on markup details**, such as `phx-click` selectors and attribute-order
  regexes (`2f43b9b`).
- **Passing on stale values.** For example, one test passed only because
  `import_file/1` returned the stale verse count.
- **Reaching for `Repo`.** `DataCase` no longer imports `Repo` or `Ecto.Query`, and users
  are created through the invite flow.

## Code deleted

Six items nothing called, each confirmed before deletion (compiler cross-reference, grep,
git history) and deleted in its own commit: `ActivityLog.Diff` (`7f858ee`),
`Catalogue.count_complete_plays/1` (`23c6384`), `Places.Authority.registry/0` (`cb3b6f7`),
`Authz.actions/0` (`0972d45`), `PlayContent.list_divisions/1` (`4fa8df3`), and four
FileMaker index fields (`5c6d9b2`).

## Changes to the application beyond the fixes

- **Ids for test targeting.** Forms and rows the tests target gained ids.
- **Accessibility.** Icon-only buttons in the content editor and play list gained
  `aria-label`s; they had only tooltips. The active sidebar link carries
  `aria-current="page"`.

## Found, not fixed

Pinned by tests as they behave today and listed in `CLAUDE.md` under "Found by the test
rework (2026-09-26)". The two that matter most:

- Any researcher can make the server import files from any server path.
- Draft plays, although hidden from `/plays`, are served by their page, the API and the
  downloads.
