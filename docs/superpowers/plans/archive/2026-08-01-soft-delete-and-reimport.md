# S0b — Soft delete, re-importable plays, and protected hand-entered data

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`)
> syntax for tracking.

**Goal:** Make the database the thing of record, not the TEI file and not the FileMaker export.
Three properties, together:

1. Deleting a play archives it. Nothing is destroyed by a click.
2. Re-importing a TEI file whose code already exists updates that play in place — same `id`, same
   history, same relationships.
3. A re-import replaces only what the TEI file owns. Every record a researcher typed into the
   admin UI survives, and the importer says up front what it is about to replace.

Property 3 is the load-bearing one. Once it holds, every later slice (S2 metadata, S3 witnesses,
S4 bibliography, S5 performances) can put its data behind an admin form and the FileMaker export
becomes a one-time bootstrap: everything it carries has a permanent home in the schema and a way to
be typed in, corrected, or extended by hand without the export existing at all.

**Why now:** four things are broken or missing today.

1. `Catalogue.delete_play/1` is `Repo.delete` (`lib/emothe/catalogue.ex:92`). It cascades to
   characters, divisions, elements and statistics, nils out every child play's `parent_play_id`
   (`priv/repo/migrations/20260223100000_add_play_relationships.exs:6`), and orphans the activity
   log entries. There is no undo.
2. `mix emothe.import.tei --force` does not work. The parser rolls back with
   `{:play_already_exists, code}` on any code already in the database
   (`lib/emothe/import/tei_parser.ex:147-149`), so `--force` fails on all 81 plays it touches.
3. Nothing distinguishes a row the importer created from a row a researcher typed. The importer
   creates `play_editors` (`tei_parser.ex:391`), `play_sources` (`:527`) and
   `play_editorial_notes` (`:627`) — the same three tables the admin UI edits, and the same tables
   S3 (witnesses) and S7 (credits) will write into. Any re-import strategy that wipes and rebuilds
   destroys hand-entered data.
4. An import that overwrites an existing play gives no warning and no preview.

**Architecture:** One migration adds `plays.deleted_at`; a second adds an `origin` column to the
three mixed-ownership child tables. The unique index on `plays.code` stays global on purpose: an
archived play keeps its code reserved, which is what turns a re-import into an update of the same
row. `Emothe.Catalogue` gains a default scope hiding archived plays, plus `restore_play/1` and
`purge_play/1`. `Emothe.Import.TeiParser` replaces its `:play_already_exists` rollback with an
update path that deletes only `origin: "tei"` rows before re-importing. A new
`TeiParser.preview_import/1` reports what an import would replace, and both the admin import page
and the mix task show it before writing.

**Ownership rules — the design decisions this plan exists to fix.**

*Columns on `plays`.* TEI owns the text and the header bibliography. The platform owns `language`,
`relationship_type`, `parent_play_id` and `is_complete`, plus every column S2 adds
(`historical_time`, `place_of_action`, `composition_date`, `collection`, `legacy_url`,
`original_title`, `title_sort`). The TEI header cannot express any of them correctly — every EMOTHE
file carries `xml:lang="es"` for the editorial platform regardless of the play's real language, and
the research metadata has no TEI representation at all. A re-import that wrote those columns would
silently undo S1 and erase S2.

*Rows in child tables.* Three kinds of table:

| Table | On re-import |
|---|---|
| `characters`, `play_divisions`, `play_elements` | replaced wholesale — pure TEI, no independent identity |
| `play_editors`, `play_sources`, `play_editorial_notes` | only `origin: "tei"` rows replaced; `manual` and `filemaker` rows survive |
| `play_bibliography`, `play_performances` (S4, S5) | never touched — the importer does not know these tables |

**Tech Stack:** Elixir 1.19.5 / OTP 28.1, Phoenix 1.8.3, Ecto + PostgreSQL. No new dependency.

## Global Constraints

- Run every command with the project PATH first:
  `export PATH="/home/bogdan/.asdf/installs/erlang/28.1/bin:/home/bogdan/.asdf/installs/elixir/1.19.5-otp-28/bin:/usr/bin:/usr/local/bin:/bin:$PATH"`
- Archived plays disappear from every public read: catalogue, play page, static site export,
  statistics counts. Admin sees them behind an explicit filter.
- Never widen the change: no new UI beyond the archive filter, the restore button, and the import
  preview.
- `mix format` after each task; the repo is formatted.

---

### Task 1: The column and the scope

**Files:**
- Create: `priv/repo/migrations/<timestamp>_add_deleted_at_to_plays.exs`
- Modify: `lib/emothe/catalogue/play.ex`
- Modify: `lib/emothe/catalogue.ex`
- Test: `test/emothe/catalogue_soft_delete_test.exs`

**Interfaces:**
- `Emothe.Catalogue.delete_play(%Play{}) :: {:ok, %Play{}} | {:error, changeset}` — sets
  `deleted_at`, does not remove the row
- `Emothe.Catalogue.restore_play(%Play{}) :: {:ok, %Play{}}` — clears `deleted_at`
- `Emothe.Catalogue.purge_play(%Play{}) :: {:ok, %Play{}}` — the old destructive `Repo.delete`,
  kept for the mix task and for genuinely bad imports
- Every existing read takes an optional `include_deleted: true`

- [ ] **Step 1: Write the failing test**

Create `test/emothe/catalogue_soft_delete_test.exs`:

```elixir
defmodule Emothe.CatalogueSoftDeleteTest do
  use Emothe.DataCase, async: true

  import Emothe.TestFixtures

  alias Emothe.Catalogue

  test "delete_play/1 archives instead of destroying" do
    play = play_fixture(%{"code" => "EMOTHE9101_Archived"})

    assert {:ok, archived} = Catalogue.delete_play(play)
    assert archived.deleted_at

    assert Catalogue.list_plays() == []
    assert Catalogue.list_plays(include_deleted: true) |> Enum.map(& &1.id) == [play.id]
    assert Catalogue.count_plays() == 0
  end

  test "an archived play keeps its code reserved" do
    play = play_fixture(%{"code" => "EMOTHE9102_Reserved"})
    {:ok, _} = Catalogue.delete_play(play)

    assert {:error, changeset} =
             Catalogue.create_play(%{"code" => "EMOTHE9102_Reserved", "title" => "x"})

    assert %{code: _} = errors_on(changeset)
  end

  test "restore_play/1 brings it back" do
    play = play_fixture(%{"code" => "EMOTHE9103_Restored"})
    {:ok, archived} = Catalogue.delete_play(play)

    assert {:ok, restored} = Catalogue.restore_play(archived)
    refute restored.deleted_at
    assert Catalogue.list_plays() |> Enum.map(& &1.id) == [play.id]
  end

  test "purge_play/1 still destroys" do
    play = play_fixture(%{"code" => "EMOTHE9104_Purged"})

    assert {:ok, _} = Catalogue.purge_play(play)
    assert Catalogue.list_plays(include_deleted: true) == []
  end

  test "archived plays are excluded from the complete count" do
    play = play_fixture(%{"code" => "EMOTHE9105_Complete", "is_complete" => true})
    assert Catalogue.count_complete_plays() == 1

    {:ok, _} = Catalogue.delete_play(play)
    assert Catalogue.count_complete_plays() == 0
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
mix test test/emothe/catalogue_soft_delete_test.exs
```

Expected: FAIL — `key :deleted_at not found` / `function Emothe.Catalogue.restore_play/1 is undefined`.

- [ ] **Step 3: The migration**

```elixir
defmodule Emothe.Repo.Migrations.AddDeletedAtToPlays do
  use Ecto.Migration

  def change do
    alter table(:plays) do
      add :deleted_at, :utc_datetime
    end

    create index(:plays, [:deleted_at])
  end
end
```

The unique index on `plays.code` is deliberately left global — an archived play keeps its code, and
that is what makes a re-import an update rather than a duplicate.

- [ ] **Step 4: The schema and the scope**

Add `field :deleted_at, :utc_datetime` to `lib/emothe/catalogue/play.ex` — do **not** add it to
`changeset/2`'s cast list; it is set through its own changeset so a form can never archive a play.

In `lib/emothe/catalogue.ex`, add one scope helper and route every read through it:

```elixir
  defp scope(query, opts) do
    if opts[:include_deleted], do: query, else: where(query, [p], is_nil(p.deleted_at))
  end
```

Sites to update (all in `lib/emothe/catalogue.ex`): `list_plays/1:14`, `count_plays/1:36`,
`count_complete_plays/0:42`, `get_play!/1:48`, `get_play_by_code!/1:50`, `get_play_with_all!/1:54`,
`get_play_by_code_with_all!/1:67`, and the relationship queries at `:252`, `:275`, `:283`, `:297`,
`:316`. `get_play!/1` and friends keep raising `Ecto.NoResultsError` for an archived play, which is
what the public routes want; admin restore reads through `include_deleted: true`.

Then:

```elixir
  def delete_play(%Play{} = play) do
    play
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  def restore_play(%Play{} = play) do
    play |> Ecto.Changeset.change(deleted_at: nil) |> Repo.update()
  end

  @doc "Destroys a play and every row that hangs off it. There is no undo."
  def purge_play(%Play{} = play), do: Repo.delete(play)
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
mix ecto.migrate && mix test test/emothe/catalogue_soft_delete_test.exs
```

Expected: PASS, 5 tests.

- [ ] **Step 6: Run the whole suite**

```bash
mix test
```

Expected: PASS. Anything that fails here is a read path that bypassed `scope/2` — fix the read, not
the test.

- [ ] **Step 7: Commit**

```bash
mix format
git add priv/repo/migrations lib/emothe/catalogue.ex lib/emothe/catalogue/play.ex test/emothe/catalogue_soft_delete_test.exs
git commit -m "feat: archive plays instead of deleting them"
```

---

### Task 2: Provenance on the mixed-ownership tables

Without this, Task 3 cannot tell a researcher's witness record from an imported `<bibl>`, and a
re-import destroys the former. Do this before touching the parser.

**Files:**
- Create: `priv/repo/migrations/<timestamp>_add_origin_to_play_children.exs`
- Modify: `lib/emothe/catalogue/play_editor.ex`, `play_source.ex`, `play_editorial_note.ex`
- Modify: `lib/emothe/import/tei_parser.ex` (stamp `origin: "tei"` on create)
- Modify: `lib/emothe/catalogue.ex` (default `origin: "manual"` in the form changesets)
- Test: `test/emothe/catalogue_origin_test.exs`

**Interfaces:**
- `origin :: "tei" | "manual" | "filemaker"`, default `"manual"` — anything created without saying
  otherwise is assumed to be hand-entered, which is the safe default: a wrong `"manual"` survives an
  import it should not have, a wrong `"tei"` gets deleted.

- [ ] **Step 1: The migration**

```elixir
defmodule Emothe.Repo.Migrations.AddOriginToPlayChildren do
  use Ecto.Migration

  def change do
    for table <- [:play_editors, :play_sources, :play_editorial_notes] do
      alter table(table) do
        add :origin, :string, null: false, default: "manual"
      end

      create index(table, [:play_id, :origin])
    end

    # Everything in the database today came out of a TEI file — the admin CRUD pages
    # for these three tables predate any bulk hand-entry.
    execute "UPDATE play_editors SET origin = 'tei'", ""
    execute "UPDATE play_sources SET origin = 'tei'", ""
    execute "UPDATE play_editorial_notes SET origin = 'tei'", ""
  end
end
```

The backfill is a judgement call: it assumes nothing has been hand-entered yet. Verify before
running — `select count(*) from play_sources` against the number the corpus import created. If a
researcher has already typed records, backfill by `inserted_at` instead.

- [ ] **Step 2: Schemas, changesets, and the parser**

Add `field :origin, :string, default: "manual"` to all three schemas and
`validate_inclusion(:origin, ~w(tei manual filemaker))`. Cast it in the changeset but **never**
expose it in an admin form — the form changesets leave the default alone, the parser passes
`origin: "tei"` explicitly at `tei_parser.ex:391`, `:422`, `:455`, `:491`, `:527` and `:627`.

- [ ] **Step 3: Test it**

```elixir
  test "the importer stamps its rows and the admin UI does not" do
    {:ok, play} = TeiParser.import_file(fixture_path)
    assert Enum.all?(play.sources, &(&1.origin == "tei"))

    {:ok, manual} = Catalogue.create_play_source(%{play_id: play.id, title: "Typed by hand"})
    assert manual.origin == "manual"
  end
```

- [ ] **Step 4: Format and commit**

```bash
mix format && mix test
git add priv/repo/migrations lib/emothe/catalogue lib/emothe/import/tei_parser.ex test/emothe/catalogue_origin_test.exs
git commit -m "feat: record whether a play's editors, sources and notes came from TEI or a human"
```

---

### Task 3: Re-import updates instead of failing

**Files:**
- Modify: `lib/emothe/import/tei_parser.ex`
- Test: `test/emothe/import/tei_reimport_test.exs`

**Interfaces:**
- `TeiParser.import_file/1` on an existing code returns `{:ok, play}` with the **same** `play.id`,
  its TEI-owned rows replaced and `deleted_at` cleared
- Platform-owned columns and non-`tei` child rows are untouched

- [ ] **Step 1: Write the failing test**

Create `test/emothe/import/tei_reimport_test.exs` with a minimal TEI fixture written to a tmp file
(copy the `@minimal_tei` heredoc from `test/emothe/import/tei_corpus_test.exs:46`), then:

```elixir
    test "re-importing the same code updates the same row" do
      {:ok, first} = TeiParser.import_file(path)
      {:ok, _} = Catalogue.update_play(first, %{language: "en", relationship_type: "traduccion"})

      assert {:ok, second} = TeiParser.import_file(path)
      assert second.id == first.id

      reloaded = Catalogue.get_play!(first.id)
      assert reloaded.language == "en", "TEI must not clobber the FileMaker-derived language"
      assert reloaded.relationship_type == "traduccion"
    end

    test "hand-entered records survive a re-import" do
      {:ok, play} = TeiParser.import_file(path)
      {:ok, typed} = Catalogue.create_play_source(%{play_id: play.id, title: "Typed by hand"})

      {:ok, _} = TeiParser.import_file(path)

      sources = Catalogue.list_play_sources(play.id)
      assert typed.id in Enum.map(sources, & &1.id)
      assert Enum.count(sources, &(&1.origin == "tei")) == 1
    end

    test "re-importing an archived play restores it" do
      {:ok, play} = TeiParser.import_file(path)
      {:ok, _} = Catalogue.delete_play(play)

      assert {:ok, reimported} = TeiParser.import_file(path)
      assert reimported.id == play.id
      refute Catalogue.get_play!(play.id).deleted_at
    end

    test "content is replaced, not duplicated" do
      {:ok, play} = TeiParser.import_file(path_with_one_act)
      {:ok, _} = TeiParser.import_file(path_with_one_act)

      assert Repo.aggregate(from(d in Division, where: d.play_id == ^play.id), :count) == 1
    end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
mix test test/emothe/import/tei_reimport_test.exs
```

Expected: FAIL — the transaction rolls back with `{:play_already_exists, "EMOTHE9001_TestPlay"}`.

- [ ] **Step 3: Replace the rollback with an update**

In `lib/emothe/import/tei_parser.ex:146-159`:

```elixir
    play =
      case Repo.get_by(Play, code: play_attrs.code) do
        %Play{} = existing ->
          reset_tei_content(existing)

          case Catalogue.update_play(existing, tei_owned(play_attrs)) do
            {:ok, play} -> play |> Ecto.Changeset.change(deleted_at: nil) |> Repo.update!()
            {:error, changeset} -> Repo.rollback(changeset)
          end

        nil ->
          case Catalogue.create_play(play_attrs) do
            {:ok, play} -> play
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end
```

with, alongside it:

```elixir
  # Columns the platform owns, not the TEI file. `language` in particular: every EMOTHE
  # file carries xml:lang="es" for the editorial platform, so a re-import would undo the
  # FileMaker sync (see docs/superpowers/plans/2026-08-01-s1-work-families-and-language.md).
  # The S2 research columns join this list when they are added.
  @platform_owned [:language, :relationship_type, :parent_play_id, :is_complete]

  defp tei_owned(attrs), do: Map.drop(attrs, @platform_owned)

  # A re-import replaces the text wholesale, but only the editors, sources and notes it
  # created itself. Anything a researcher typed — and everything S3/S4/S5 add — stays.
  defp reset_tei_content(%Play{id: id}) do
    for schema <- [Element, Division, Character] do
      Repo.delete_all(from(r in schema, where: r.play_id == ^id))
    end

    for schema <- [PlayEditor, PlaySource, PlayEditorialNote] do
      Repo.delete_all(from(r in schema, where: r.play_id == ^id and r.origin == "tei"))
    end
  end
```

`play_elements` rows reference each other through `parent_id` and `element_characters`; delete
elements first and let the existing FK cascades handle the join rows. Deleting `characters` drops
the `element_characters` links with them, which is correct — the `who` attributes are re-read from
the file.

- [ ] **Step 4: Run the tests**

```bash
mix test test/emothe/import/tei_reimport_test.exs && mix test
```

Expected: PASS. `test/emothe/roundtrip_test.exs` imports the same fixtures repeatedly — it may have
relied on a fresh row per test; if it fails, read the failure before changing it.

- [ ] **Step 5: Verify `--force` finally works**

```bash
mix emothe.import.tei --force 2>&1 | tail -3
```

Expected: `imported 81, skipped 0, failed 1` — every existing play updated in place, `EMOTHE0730`
still failing on its over-long division title (Task 4).

- [ ] **Step 6: Commit**

```bash
mix format
git add lib/emothe/import/tei_parser.ex test/emothe/import/tei_reimport_test.exs
git commit -m "feat: re-importing a TEI file updates the play in place"
```

---

### Task 4: The over-long division title

Now that a re-import is an update, the one file that failed the S0 corpus run can be fixed and
re-imported without destroying anything.

**Files:**
- Create: `priv/repo/migrations/<timestamp>_change_division_title_to_text.exs`

- [ ] **Step 1: The migration**

```elixir
defmodule Emothe.Repo.Migrations.ChangeDivisionTitleToText do
  use Ecto.Migration

  def change do
    alter table(:play_divisions) do
      modify :title, :text, from: :string
    end
  end
end
```

`play_divisions.title` is `varchar(255)`; `EMOTHE0730_LaMariana` has a front-matter `<head>` longer
than that, which raised `Postgrex.Error 22001` at `lib/emothe/import/tei_parser.ex:716` during the
S0 run. Same precedent as
`priv/repo/migrations/20260226164241_change_speaker_label_to_text.exs`.

- [ ] **Step 2: Import the file that failed**

```bash
mix ecto.migrate && mix emothe.import.tei
```

Expected: `imported 1, skipped 81, failed 0`, and 82 rows in `plays`.

- [ ] **Step 3: Commit**

```bash
git add priv/repo/migrations
git commit -m "fix: division titles longer than 255 characters"
```

---

### Task 5: Say what an import will replace, before it writes

An import that lands on an existing play is now non-destructive to hand-entered records — but it
still replaces the entire text, the cast list, and every TEI-sourced editor, source and note. The
researcher must see that before it happens.

**Files:**
- Modify: `lib/emothe/import/tei_parser.ex` (add `preview_import/1`)
- Modify: `lib/emothe_web/live/admin/import_live.ex`
- Modify: `lib/emothe/import/tei_corpus.ex`, `lib/mix/tasks/emothe.import.tei.ex` (`--dry-run`)
- Test: `test/emothe/import/tei_preview_test.exs`

**Interfaces:**
- `TeiParser.preview_import(path) :: {:ok, preview} | {:error, term()}` where

  ```elixir
  preview :: %{
    code: String.t(),
    title: String.t(),
    existing: %Play{} | nil,      # nil for a new play
    archived: boolean(),          # existing and deleted_at set — the import will restore it
    replaces: %{divisions: n, elements: n, characters: n, editors: n, sources: n, notes: n},
    preserves: %{editors: n, sources: n, notes: n},   # the non-"tei" rows
    preserves_fields: [atom()]    # @platform_owned that have a value today
  }
  ```

  It reads the header only — no `Repo.transaction`, no writes.

- [ ] **Step 1: Write the failing test**

```elixir
  test "preview reports what a re-import would replace and what it would keep" do
    {:ok, play} = TeiParser.import_file(path)
    {:ok, _} = Catalogue.create_play_source(%{play_id: play.id, title: "Typed by hand"})
    {:ok, _} = Catalogue.update_play(play, %{language: "en"})

    assert {:ok, preview} = TeiParser.preview_import(path)
    assert preview.existing.id == play.id
    assert preview.replaces.sources == 1
    assert preview.preserves.sources == 1
    assert :language in preview.preserves_fields
  end

  test "preview of an unknown code reports a new play" do
    assert {:ok, %{existing: nil, replaces: %{elements: 0}}} = TeiParser.preview_import(new_path)
  end
```

- [ ] **Step 2: Implement `preview_import/1`, then the UI**

`import_live.ex:39` (upload) and `:61` (directory) currently call
`TeiParser.import_file/1` straight through at `:141`. Insert a confirmation step: preview first,
render the counts, and only import on an explicit "Replace" click. For a new play the preview is
trivially empty and the button reads "Import".

Wording that matters, because it is what the researcher acts on:

> **EMOTHE0053_Hamlet already exists.** Importing replaces its text (5 divisions, 1 204 elements,
> 23 characters) and 3 records imported from TEI. **2 records you entered by hand are kept**, and
> language, relationship and completeness are kept.

- [ ] **Step 3: `--dry-run` on the mix task**

`mix emothe.import.tei --dry-run` prints one preview line per file and writes nothing. This is the
same review mechanism every FileMaker sync task uses (see the roadmap's shared conventions).

- [ ] **Step 4: Format, test, commit**

```bash
mix format && mix test
git add lib/emothe/import lib/emothe_web/live/admin/import_live.ex lib/mix/tasks/emothe.import.tei.ex test/emothe/import/tei_preview_test.exs priv/gettext
git commit -m "feat: preview what a TEI import replaces before writing"
```

---

### Task 6: Admin UI — archive, filter, restore

**Files:**
- Modify: `lib/emothe_web/live/admin/play_list_live.ex`
- Modify: `priv/gettext/es/LC_MESSAGES/default.po`

- [ ] **Step 1: The filter and the restore action**

`play_list_live.ex:65` already calls `Catalogue.delete_play/1`, so it archives with no change. Add:

- an "Archived" toggle passing `include_deleted: true`, showing only archived rows
- a badge on archived rows
- a `restore` event calling `Catalogue.restore_play/1`
- the confirm text on delete changed from "delete permanently" to "archive"

- [ ] **Step 2: Log it**

Both actions go through `Emothe.ActivityLog` with `action: "delete"` and `action: "update"` — the
allowed list is `create update delete import export role_change`, do not invent an `archive` action.

- [ ] **Step 3: Translations, format, commit**

```bash
mix format
git add lib/emothe_web/live/admin/play_list_live.ex priv/gettext
git commit -m "feat: archive and restore plays from the admin list"
```

---

### Task 7: Acceptance

- [ ] **Step 1: The round trip, on a real play**

```bash
PGPASSWORD=postgres psql -U postgres -h localhost -d emothe_dev -tAF'|' -c \
  "select id, language, coalesce(relationship_type,'-') from plays where code like 'EMOTHE0053%'"
```

Add a source by hand at `/admin/plays/<id>/sources`, archive the play in the admin list, then:

```bash
mix emothe.import.tei --force --dir test/fixtures
```

Re-run the query. Expected: **the same `id`**, the same `language`, the same `relationship_type`,
the play un-archived, and the hand-entered source still on its sources page. That is the whole
slice — identity, curated fields and hand-entered records all survive a delete-and-re-import, so the
FileMaker sync never has to be re-run to repair them.

- [ ] **Step 2: The public site does not show archived plays**

Archive a play, then check `/plays`, `/plays/:code` (expect a 404), and
`mix emothe.export.site --all` (expect it absent from `_site/plays/`).

- [ ] **Step 3: Whole suite**

```bash
mix test
```

---

## Notes for whoever picks this up

- **Why the unique index on `code` stays global:** an archived play must keep its code, otherwise a
  re-import creates a second row and the two compete for the same code the moment the first is
  restored. Reserving the code is the mechanism, not a side effect.
- **Why `origin` defaults to `"manual"`:** the two failure modes are not symmetric. A row wrongly
  marked `manual` survives an import that should have replaced it — visible, fixable. A row wrongly
  marked `tei` is deleted — silent, unrecoverable. Default to the safe one.
- **Why `purge_play/1` still exists:** a genuinely bad import — wrong file, wrong code — should be
  removable. It is not wired to any button; call it from IEx or a mix task.
- **What every later slice owes this one:** each new column added to `plays` by S2 must be appended
  to `@platform_owned` in `tei_parser.ex`, and each new child table (S4 bibliography, S5
  performances) must either carry `origin` or stay outside the importer's reach. Skip that and the
  first re-import erases the slice.
- **Not in this slice:** soft delete for characters, divisions, elements or sources. Those are
  re-created wholesale by an import and have no independent identity worth preserving.
