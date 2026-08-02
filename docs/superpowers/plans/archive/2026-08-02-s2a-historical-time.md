# S2a — Historical Time Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every play a curated historical setting — a period from a nine-term vocabulary and a
free-prose note — imported from the FileMaker export, editable in the admin form, and shown in a new
research-metadata panel on the public play page.

**Architecture:** Two new columns on `plays`. `Emothe.Import.Filemaker` gains a second reader for the
`T01_tituloEM` layout it currently discards, keyed by the play code hiding in the `pub_edicionWeb`
href. `Emothe.Import.FilemakerSync` gains a *fill-only* write policy for curated fields — written
when blank, reported as a conflict when they differ, overwritten only under `--force` — while the
S1 fields keep overwriting unconditionally. A new `EmotheWeb.PlayLabels` module holds the
translated vocabulary so the admin select and the public panel share one list. The panel is a
`<section id="meta-study">` that hides itself when the play has no data.

**Tech Stack:** Elixir 1.19.5 / OTP 28.1, Phoenix 1.8.3, LiveView 1.1.22, Ecto + PostgreSQL,
Jason for NDJSON, `Regex` for the index HTML, gettext for labels. **Do not add an HTML-parsing
dependency** — the markup is machine-generated and fixed.

**Spec:** `docs/superpowers/specs/2026-08-02-s2a-historical-time-design.md`
**Roadmap:** `docs/superpowers/plans/2026-08-01-filemaker-import-slices.md`, slice S2a
**Prior slices:** `docs/superpowers/plans/archive/README.md` — read the S1 section, it lists the
traps this codebase set for the last person.

## Global Constraints

- Run every command with the project PATH first:
  `export PATH="/home/bogdan/.asdf/installs/erlang/28.1/bin:/home/bogdan/.asdf/installs/elixir/1.19.5-otp-28/bin:/usr/bin:/usr/local/bin:/bin:$PATH"`
  The asdf shims do not work in this sandbox.
- **TDD is required** (`CLAUDE.md`, "How To Work In This Repo"). Write the failing test, run it,
  watch it fail, then implement. A step that says "run it to verify it fails" is not optional
  ceremony — it is the proof the test exercises anything.
- **Never claim done without the command output that proves it.**
- Run migrations in **both** environments: `mix ecto.migrate && MIX_ENV=test mix ecto.migrate`.
- `mix ecto.gen.migration` writes an empty `change do end`. `Read` the generated file before
  `Edit`ing it.
- `~r{...}` will not hold a `{2}`-style quantifier — a brace-delimited sigil closes on the inner
  `}`. Use `~r|...|`. See `lib/emothe/import/filemaker.ex:16`.
- `plays.code` is the full filename stem (`EMOTHE0038_AntonyAndCleopatra`). The FileMaker code is
  its leading token. Compare with `FilemakerSync.base_code/1`.
- **Never create a play.** A T01 record with no matching play is ignored.
- **Never fail on Artelope.** `AL####` codes are absent from the export.
- Every database write is logged through `Emothe.ActivityLog` with `action: "update"` — the allowed
  actions are `create update delete import export role_change`, do not add a new one.
- The real export `doc/w3emothe_T01_tituloEM.ndjson` is **not in git**. Tests use their own fixture
  under `test/fixtures/filemaker/`, never the real file.
- `mix format` after each task. `mix compile --warnings-as-errors` before each commit. An unused
  alias is a compile error here.
- Filter dev SQL noise from mix task output:
  `mix emothe.import.filemaker --dry-run 2>&1 | grep -Ev '^\[debug\]|^(SELECT|INSERT|UPDATE|DELETE|BEGIN|COMMIT|ROLLBACK)|↳'`

## Starting State

Everything a fresh session needs that the repository does not say by itself.

- **Branch `main`, clean.** S0, S0b and S1 are all committed and applied. Every earlier plan is in
  `docs/superpowers/plans/archive/`.
- **`emothe_dev` holds 82 plays**, the whole local TEI corpus. S1 has been applied to it: 15 plays
  corrected, 11 work families linked. `historical_time` is `NULL` on all 82 — Task 7 Step 1 asserts
  exactly that, so if it is not, someone has run this slice already.
- **`MIX_ENV=test` database is migrated** to the same point.
- **The real export lives at `doc/w3emothe_T01_tituloEM.ndjson`** — 1.7 MB, 649 lines, two layouts.
  `doc/` is git-ignored, so a fresh clone will not have it and Task 7 cannot run without it. Tasks
  1–6 do not need it; they use fixtures under `test/fixtures/filemaker/`.
- **`mix test` is green at 277 tests** before this slice starts. Any failure at Task 1 Step 2 that
  is not the new test failing is pre-existing and not yours.
- **A Phoenix server may already be running on port 4000.** `mix phx.server` will exit
  `:eaddrinuse`; use the running one.
- **Suggested skills:** superpowers:executing-plans or superpowers:subagent-driven-development to
  run this, superpowers:test-driven-development (mandatory in this repo — see `CLAUDE.md`),
  superpowers:verification-before-completion, superpowers:systematic-debugging when a test fails.

## File Structure

| File | Responsibility |
|---|---|
| `priv/repo/migrations/*_add_historical_time_to_plays.exs` | the two columns |
| `lib/emothe/catalogue/play.ex` | schema fields, `@historical_times`, `historical_times/0`, cast + validation |
| `lib/emothe/import/tei_parser.ex` | one line: both columns appended to `@platform_owned` |
| `lib/emothe/import/filemaker.ex` | `load_versions/1`, the `T01_tituloEM` reader — pure, no DB |
| `lib/emothe/import/filemaker_sync.ex` | fill-only policy, `conflicts` bucket, `force:` option |
| `lib/mix/tasks/emothe.import.filemaker.ex` | print conflicts, accept `--force` |
| `lib/emothe_web/play_labels.ex` | **new** — `historical_time_label/1`, `historical_time_options/0` |
| `lib/emothe_web/live/admin/play_form_live.ex` | "Research metadata" fieldset |
| `lib/emothe_web/live/play_show_live.ex` | `meta-study` section + sidebar entry |

`EmotheWeb.PlayLabels` is a new module rather than a private function because both the admin form
and the public page need the same nine translated labels, and five more S2 fields are coming that
will need the same treatment. The existing `relationship_type_label/1`, which is copy-pasted into
`play_show_live.ex` and `play_detail_live.ex`, is **deliberately left alone** — refactoring it is
not this slice's job.

---

### Task 1: Schema, vocabulary and re-import protection

The columns, the validation, and the `@platform_owned` entry that stops the next TEI re-import
erasing them. These ship together because a column without its protection is a trap.

**Files:**
- Create: `priv/repo/migrations/<timestamp>_add_historical_time_to_plays.exs`
- Modify: `lib/emothe/catalogue/play.ex`
- Modify: `lib/emothe/import/tei_parser.ex:23`
- Test: `test/emothe/catalogue_test.exs` (append), `test/emothe/import/tei_parser_test.exs` (append)

**Interfaces:**
- Produces: `Emothe.Catalogue.Play.historical_times() :: [String.t()]` — the nine slugs
- Produces: `plays.historical_time :: String.t() | nil`, `plays.historical_time_note :: String.t() | nil`
- Consumed by: every later task

- [x] **Step 1: Write the failing changeset tests**

Append to `test/emothe/catalogue_test.exs`, inside the outermost `describe` block or at module
level alongside the existing tests:

```elixir
  describe "historical_time" do
    test "accepts a slug from the vocabulary" do
      assert {:ok, play} =
               Emothe.Catalogue.create_play(%{
                 "title" => "A Play",
                 "code" => "HT0001",
                 "historical_time" => "siglo_xvii",
                 "historical_time_note" => "Contemporary. Reign of Philip IV."
               })

      assert play.historical_time == "siglo_xvii"
      assert play.historical_time_note == "Contemporary. Reign of Philip IV."
    end

    test "rejects a slug outside the vocabulary" do
      assert {:error, changeset} =
               Emothe.Catalogue.create_play(%{
                 "title" => "A Play",
                 "code" => "HT0002",
                 "historical_time" => "siglo_xxi"
               })

      assert %{historical_time: ["is invalid"]} = errors_on(changeset)
    end

    test "accepts nil" do
      assert {:ok, play} =
               Emothe.Catalogue.create_play(%{"title" => "A Play", "code" => "HT0003"})

      assert play.historical_time == nil
    end

    test "historical_times/0 lists the nine terms" do
      assert length(Emothe.Catalogue.Play.historical_times()) == 9
      assert "antiguedad_clasica" in Emothe.Catalogue.Play.historical_times()
    end
  end
```

- [x] **Step 2: Run the tests to verify they fail**

```bash
mix test test/emothe/catalogue_test.exs
```

Expected: FAIL. The first test fails because `historical_time` is not a castable field so it is
silently dropped and `play.historical_time` raises `KeyError` on the struct; the fourth fails with
`function Emothe.Catalogue.Play.historical_times/0 is undefined`.

- [x] **Step 3: Generate the migration**

```bash
mix ecto.gen.migration add_historical_time_to_plays
```

Then **Read** the generated file — it contains an empty `change do end` — and replace its body:

```elixir
  def change do
    alter table(:plays) do
      add :historical_time, :string
      add :historical_time_note, :text
    end
  end
```

- [x] **Step 4: Run the migration in both environments**

```bash
mix ecto.migrate && MIX_ENV=test mix ecto.migrate
```

- [x] **Step 5: Add the fields, the vocabulary and the validation**

In `lib/emothe/catalogue/play.ex`, add the two fields to the schema next to the other string
fields:

```elixir
    field :historical_time, :string
    field :historical_time_note, :string
```

Above `def changeset/2`, next to `@language_names`, add the vocabulary. The comment matters —
the numbers are the FileMaker codes and the next slice needs them:

```elixir
  # FileMaker bus_tiemHistorico codes, recovered by pairing the code against the rendered
  # label across all 439 rows of the export. Codes 3 and 4 do not occur.
  #   1 tiempo_indeterminado   2 antiguo_testamento   5 edad_media
  #   6 siglo_xv               7 siglo_xvi            8 siglo_xvii
  #   9 tiempo_maravilloso    10 antiguedad_clasica  11 tiempo_alegorico
  @historical_times ~w(
    tiempo_indeterminado antiguo_testamento edad_media siglo_xv siglo_xvi
    siglo_xvii tiempo_maravilloso antiguedad_clasica tiempo_alegorico
  )

  def historical_times, do: @historical_times
```

Add both fields to the `cast/3` list, after `:is_complete`:

```elixir
      :is_complete,
      :historical_time,
      :historical_time_note
```

And the validation, after the `relationship_type` one:

```elixir
    |> validate_inclusion(:historical_time, @historical_times)
```

`validate_inclusion/3` skips `nil` changes, so the nil case passes without extra work — the same
way `relationship_type` already behaves.

- [x] **Step 6: Run the tests to verify they pass**

```bash
mix test test/emothe/catalogue_test.exs
```

Expected: PASS.

- [x] **Step 7: Write the failing re-import regression test**

This is the test that proves a TEI re-import cannot erase a curated value. Append to
`test/emothe/import/tei_parser_test.exs`:

```elixir
  test "import_file/1 does not erase a curated historical time on re-import" do
    code = "HT9001"
    path = write_tei(minimal_tei(title: "Curated", code: code))

    assert {:ok, play} = TeiParser.import_file(path)

    {:ok, _} =
      Emothe.Catalogue.update_play(play, %{
        "historical_time" => "edad_media",
        "historical_time_note" => "Reinado de Juan I de Portugal (1385-1433)"
      })

    # The TEI file owns the text; the platform owns curated research metadata.
    # See @platform_owned in lib/emothe/import/tei_parser.ex and
    # docs/superpowers/plans/archive/README.md, S0b.
    assert {:ok, reimported} = TeiParser.import_file(path)
    assert reimported.id == play.id
    assert reimported.historical_time == "edad_media"
    assert reimported.historical_time_note == "Reinado de Juan I de Portugal (1385-1433)"
  end
```

- [x] **Step 8: Run it to verify it fails**

```bash
mix test test/emothe/import/tei_parser_test.exs
```

Expected: FAIL on `assert reimported.historical_time == "edad_media"` with
`Assertion with == failed / left: nil / right: "edad_media"`. The re-import wrote a fresh play
attribute map that did not include the curated columns, so they were reset.

If it *passes* at this point, stop and find out why before continuing — the protection must not
already exist.

- [x] **Step 9: Add both columns to `@platform_owned`**

In `lib/emothe/import/tei_parser.ex:23`:

```elixir
  @platform_owned [
    :language,
    :relationship_type,
    :parent_play_id,
    :is_complete,
    :historical_time,
    :historical_time_note
  ]
```

- [x] **Step 10: Run the test to verify it passes**

```bash
mix test test/emothe/import/tei_parser_test.exs
```

Expected: PASS.

- [x] **Step 11: Run the whole suite and commit**

```bash
mix format
mix compile --warnings-as-errors
mix test
git add priv/repo/migrations lib/emothe/catalogue/play.ex lib/emothe/import/tei_parser.ex \
        test/emothe/catalogue_test.exs test/emothe/import/tei_parser_test.exs
git commit -m "feat: a curated historical time on plays"
```

---

### Task 2: Read T01_tituloEM out of the export

`Emothe.Import.Filemaker` currently discards every line whose layout is not `T00_indiceEM`. Give it
a second reader. Pure functions, no database.

**Files:**
- Modify: `lib/emothe/import/filemaker.ex`
- Create: `test/fixtures/filemaker/versions_sample.ndjson`
- Test: `test/emothe/import/filemaker_test.exs` (append)

**Interfaces:**
- Consumes: nothing from Task 1
- Produces:

  ```elixir
  Emothe.Import.Filemaker.load_versions(path :: String.t()) ::
    {:ok, %{required(String.t()) => version}} | {:error, term()}

  version :: %{
    code: String.t(),                          # "EMOTHE0038"
    historical_time: String.t() | nil,         # "antiguedad_clasica"
    historical_time_note: String.t() | nil     # "First century BC. …"
  }
  ```

- [x] **Step 1: Create the test fixture**

Create `test/fixtures/filemaker/versions_sample.ndjson`. Four lines: the `_meta` envelope, a record
with a code and a note, a record with a code and empty rendered HTML, and a record with two `<li>`
entries. Copy verbatim — the escaping matters:

```
{"_meta":{"layout":"T01_tituloEM","database":"w3emothe","found_count":"3","table_count":"3","batch":200}}
{"record_id":"11","mod_id":"3","fields":{"_kp_IdTituloEM":["38"],"_IdTituloEmothe":["38"],"_IdObraEmothe":["24"],"bus_tiemHistorico":["10"],"pub_TiemHistorico":["<ul><li>Antigüedad clásica<br/>Note: First century BC. The play dramatizes events taking place between 40 and 30 BC.</li></ul>"],"pub_edicionWeb":["<a href='../biblioteca/textosEMOTHE/EMOTHE0038_AntonyAndCleopatra.php' target='_blank'>Enlace</a>"]}}
{"record_id":"12","mod_id":"3","fields":{"_kp_IdTituloEM":["211"],"_IdTituloEmothe":["211"],"_IdObraEmothe":["77"],"bus_tiemHistorico":["8"],"pub_TiemHistorico":[""],"pub_edicionWeb":["<a href='../biblioteca/textosEMOTHE/EMOTHE0211_ElCaballeroDeOlmedo.php' target='_blank'>Enlace</a>"]}}
{"record_id":"13","mod_id":"3","fields":{"_kp_IdTituloEM":["393"],"_IdTituloEmothe":["393"],"_IdObraEmothe":["99"],"bus_tiemHistorico":["7\n8"],"pub_TiemHistorico":["<ul><li>Siglo XVI<br/>Note: After the Battle of Pavia (1525).</li>\n<li>Siglo XVII</li></ul>"],"pub_edicionWeb":["<a href='../biblioteca/textosEMOTHE/HIE0393_TheSpanishBawd.php' target='_blank'>Enlace</a>"]}}
```

Three things this fixture is testing, deliberately: the accented `Antigüedad clásica` label, the
`HIE####` code that only exists in the href, and the two-`<li>` record.

- [x] **Step 2: Write the failing test**

Append to `test/emothe/import/filemaker_test.exs`, inside the module:

```elixir
  describe "load_versions/1" do
    @versions "test/fixtures/filemaker/versions_sample.ndjson"

    setup do
      {:ok, versions} = Filemaker.load_versions(@versions)
      %{versions: versions}
    end

    test "keys every version by the code in its web-edition link", %{versions: versions} do
      assert Map.keys(versions) |> Enum.sort() == ["EMOTHE0038", "EMOTHE0211", "HIE0393"]
    end

    test "decodes the historical time code into a slug", %{versions: versions} do
      assert versions["EMOTHE0038"].historical_time == "antiguedad_clasica"
      assert versions["EMOTHE0211"].historical_time == "siglo_xvii"
    end

    test "reads the note out of the rendered label", %{versions: versions} do
      assert versions["EMOTHE0038"].historical_time_note ==
               "First century BC. The play dramatizes events taking place between 40 and 30 BC."
    end

    test "a code with no rendered label still yields a slug and no note", %{versions: versions} do
      assert versions["EMOTHE0211"].historical_time == "siglo_xvii"
      assert versions["EMOTHE0211"].historical_time_note == nil
    end

    test "takes the first of several periods", %{versions: versions} do
      assert versions["HIE0393"].historical_time == "siglo_xvi"
      assert versions["HIE0393"].historical_time_note == "After the Battle of Pavia (1525)."
    end

    test "returns an error for a missing file" do
      assert {:error, :enoent} = Filemaker.load_versions("test/fixtures/filemaker/nope.ndjson")
    end
  end
```

- [x] **Step 3: Run the test to verify it fails**

```bash
mix test test/emothe/import/filemaker_test.exs
```

Expected: FAIL — `function Emothe.Import.Filemaker.load_versions/1 is undefined or private`.

- [x] **Step 4: Write the implementation**

In `lib/emothe/import/filemaker.ex`, add the layout name and the vocabulary near the existing
`@index_layout`:

```elixir
  @versions_layout "T01_tituloEM"

  # bus_tiemHistorico. Codes 3 and 4 do not occur anywhere in the export.
  @historical_times %{
    "1" => "tiempo_indeterminado",
    "2" => "antiguo_testamento",
    "5" => "edad_media",
    "6" => "siglo_xv",
    "7" => "siglo_xvi",
    "8" => "siglo_xvii",
    "9" => "tiempo_maravilloso",
    "10" => "antiguedad_clasica",
    "11" => "tiempo_alegorico"
  }

  # <a href='../biblioteca/textosEMOTHE/EMOTHE0038_AntonyAndCleopatra.php' …>
  @web_edition ~r|textosEMOTHE/([A-Za-z0-9]+)_|

  # <li>Antigüedad clásica<br/>Note: First century BC.…</li>
  @first_item ~r|<li>(.*?)</li>|s
```

Then the reader itself, alongside `load_index/1`:

```elixir
  @doc """
  Returns `{:ok, %{code => version}}` for every version record in the export.

  The version records carry the research metadata that has no home in TEI. Only the
  fields S2a needs are read; later slices add to the map this returns.
  """
  def load_versions(path \\ @default_path) do
    with {:ok, body} <- File.read(path) do
      versions =
        body
        |> String.split("\n", trim: true)
        |> Enum.reduce({nil, %{}}, &read_version_line/2)
        |> elem(1)

      {:ok, versions}
    end
  end

  defp read_version_line(line, {layout, versions}) do
    case Jason.decode(line) do
      {:ok, %{"_meta" => meta}} ->
        {meta["layout"], versions}

      {:ok, %{"fields" => fields}} when layout == @versions_layout ->
        version = build_version(fields)
        {layout, Map.put(versions, version.code, version)}

      _ ->
        {layout, versions}
    end
  end

  defp build_version(fields) do
    %{
      code: version_code(fields),
      historical_time: historical_time(fields),
      historical_time_note: historical_time_note(fields)
    }
  end

  # The href is the only place the HIE#### codes appear; the numeric id is the fallback.
  defp version_code(fields) do
    case Regex.run(@web_edition, field(fields, "pub_edicionWeb")) do
      [_all, code] ->
        code

      _ ->
        id = fields |> field("_IdTituloEmothe") |> String.to_integer()
        "EMOTHE" <> String.pad_leading(Integer.to_string(id), 4, "0")
    end
  end

  defp historical_time(fields) do
    fields
    |> field("bus_tiemHistorico")
    |> String.split("\n", trim: true)
    |> List.first()
    |> then(&Map.get(@historical_times, &1))
  end

  defp historical_time_note(fields) do
    with [_all, item] <- Regex.run(@first_item, field(fields, "pub_TiemHistorico")),
         [_label, note] <- String.split(item, ~r|<br\s*/?>\s*Note:|, parts: 2) do
      case strip_tags(note) do
        "" -> nil
        text -> text
      end
    else
      _ -> nil
    end
  end
```

`field/1` and `strip_tags/1` already exist in this module from S1 — do not redefine them.

The multi-`<li>` case is handled by `List.first/1` on the split codes and by `@first_item` being
non-greedy. Log nothing for it: the note test above pins the behaviour, and a warning on every run
for two records in the whole export is noise. **Ceiling, recorded:** if a play ever needs both
periods, this becomes an array column — see open question 5 in the roadmap.

- [x] **Step 5: Run the test to verify it passes**

```bash
mix test test/emothe/import/filemaker_test.exs
```

Expected: PASS, 14 tests (the 8 from S1 plus the 6 new ones).

If `historical_time_note` comes back `nil` for `EMOTHE0038`, the `<br/>Note:` split did not match —
check the fixture line has a literal `<br/>Note: ` with one space, and print
`Regex.run(@first_item, html)` in IEx against it.

- [x] **Step 6: Commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/emothe/import/filemaker.ex test/emothe/import/filemaker_test.exs \
        test/fixtures/filemaker/versions_sample.ndjson
git commit -m "feat: read historical time out of the FileMaker version records"
```

---

### Task 3: A fill-only sync policy with a conflicts bucket

`FilemakerSync.plan/2` learns a second write policy. The S1 fields keep overwriting; the curated
fields are written only when the column is blank, and a disagreement becomes a reported conflict.

**Files:**
- Modify: `lib/emothe/import/filemaker_sync.ex`
- Test: `test/emothe/import/filemaker_sync_test.exs` (append)

**Interfaces:**
- Consumes: `Filemaker.load_versions/1` output from Task 2
- Produces:

  ```elixir
  FilemakerSync.plan(index, plays, versions \\ %{}) :: plan

  plan :: %{
    changes: [%{play_id: binary(), code: String.t(), title: String.t(), sets: map()}],
    unchanged: [String.t()],
    missing: [String.t()],
    conflicts: [conflict]
  }

  conflict :: %{
    play_id: binary(), code: String.t(), title: String.t(),
    field: atom(), current: term(), indexed: term()
  }
  ```

  `plan/2` keeps working — `versions` defaults to `%{}`, which produces no curated changes and no
  conflicts.

**The policy, stated once:**

| Column now | Export says | Result |
|---|---|---|
| blank | a value | `changes` |
| set, same | same value | `unchanged` |
| set, different | a value | `conflicts`, **not** written |
| anything | blank | nothing — never blanks a set column |

- [x] **Step 1: Write the failing tests**

Append to `test/emothe/import/filemaker_sync_test.exs`, inside the module. The `index/0` and
`play/2` helpers already exist in that file from S1 — reuse them, do not redefine them:

First, at **module level** next to the existing `index/0` and `play/2` helpers — not inside the
`describe` block, so Task 4 can use it too:

```elixir
  defp versions do
    %{
      "EMOTHE0038" => %{
        code: "EMOTHE0038",
        historical_time: "antiguedad_clasica",
        historical_time_note: "First century BC."
      }
    }
  end
```

Then the tests:

```elixir
  describe "curated fields are fill-only" do
    test "fills a blank historical time" do
      original = play("EMOTHE0038_AntonyAndCleopatra", %{"language" => "en"})

      plan = FilemakerSync.plan(index(), [original], versions())

      assert [%{code: "EMOTHE0038", sets: sets}] = plan.changes
      assert sets.historical_time == "antiguedad_clasica"
      assert sets.historical_time_note == "First century BC."
      assert plan.conflicts == []
    end

    test "leaves an equal value alone" do
      original =
        play("EMOTHE0038_AntonyAndCleopatra", %{
          "language" => "en",
          "historical_time" => "antiguedad_clasica",
          "historical_time_note" => "First century BC."
        })

      plan = FilemakerSync.plan(index(), [original], versions())

      assert plan.changes == []
      assert plan.conflicts == []
      assert plan.unchanged == ["EMOTHE0038"]
    end

    test "reports a curated value that disagrees, and does not write it" do
      original =
        play("EMOTHE0038_AntonyAndCleopatra", %{
          "language" => "en",
          "historical_time" => "edad_media"
        })

      plan = FilemakerSync.plan(index(), [original], versions())

      assert [%{field: :historical_time, current: "edad_media", indexed: "antiguedad_clasica"}] =
               Enum.filter(plan.conflicts, &(&1.field == :historical_time))

      # the note was blank, so it still gets filled
      assert [%{sets: sets}] = plan.changes
      assert Map.keys(sets) == [:historical_time_note]
    end

    test "never blanks a curated column the export has nothing for" do
      original =
        play("EMOTHE0038_AntonyAndCleopatra", %{
          "language" => "en",
          "historical_time" => "edad_media"
        })

      plan = FilemakerSync.plan(index(), [original], %{})

      assert plan.changes == []
      assert plan.conflicts == []
    end

    test "the S1 fields still overwrite unconditionally" do
      # language is derived, not curated: the index is authoritative and wins.
      original = play("EMOTHE0038_AntonyAndCleopatra", %{"language" => "es"})

      plan = FilemakerSync.plan(index(), [original], %{})

      assert [%{sets: %{language: "en"}}] = plan.changes
      assert plan.conflicts == []
    end

    test "fills a play that has a version record but no index entry" do
      # EMOTHE0341 is real: it has a T01 research record and was never published,
      # so it is absent from T00. A curated fill must not depend on the index.
      orphan = play("EMOTHE0341_LaEstrellaDeSevilla")

      curated = %{
        "EMOTHE0341" => %{
          code: "EMOTHE0341",
          historical_time: "siglo_xvii",
          historical_time_note: nil
        }
      }

      plan = FilemakerSync.plan(index(), [orphan], curated)

      assert [%{code: "EMOTHE0341", sets: %{historical_time: "siglo_xvii"}}] = plan.changes
      assert plan.missing == ["EMOTHE0341"]
    end
  end
```

- [x] **Step 2: Run the tests to verify they fail**

```bash
mix test test/emothe/import/filemaker_sync_test.exs
```

Expected: FAIL — `FilemakerSync.plan/3 is undefined or private` on every new test.

- [x] **Step 3: Write the implementation**

In `lib/emothe/import/filemaker_sync.ex`, extend the module doc so the two policies are not read as
an inconsistency:

```elixir
  @moduledoc """
  Applies the FileMaker export to the plays we already have.

  `plan/3` is pure: it produces the list of changes without writing anything, so the
  mix task can print it for review. `apply_plan/2` performs the writes.

  Two write policies, deliberately:

    * **Derived fields** — `language`, `relationship_type`, `parent_play_id`. The
      published index is authoritative, so a difference is an error in our data and
      gets overwritten.
    * **Curated fields** — `historical_time`, `historical_time_note`. A researcher is
      expected to edit these in the admin form, so the export is a bootstrap: a blank
      column is filled, a disagreement is reported under `:conflicts` and left alone,
      and only `force: true` overwrites it.

  Nothing here ever creates a play. Codes with no index entry — every Artelope play,
  and anything the project never published — come back under `:missing`.
  """
```

Add the curated field list next to `@languages`:

```elixir
  @curated [:historical_time, :historical_time_note]
```

Replace `plan/2` with `plan/3`:

```elixir
  @doc "Diffs the export against the given plays. Writes nothing."
  def plan(index, plays, versions \\ %{}) do
    by_code = Map.new(plays, &{base_code(&1.code), &1})
    empty = %{changes: [], unchanged: [], missing: [], conflicts: []}

    plays
    |> Enum.reduce(empty, fn play, acc ->
      code = base_code(play.code)
      curated = Map.get(versions, code, %{})

      # The two sources are independent. A play absent from the published index is
      # still reported as missing, but it can have a T01 research record — EMOTHE0341
      # does — and that fill must not be skipped.
      {derived, acc} =
        case Map.fetch(index, code) do
          :error -> {%{}, %{acc | missing: [code | acc.missing]}}
          {:ok, version} -> {changes_for(play, version, by_code), acc}
        end

      sets = Map.merge(derived, fills_for(play, curated))
      acc = %{acc | conflicts: conflicts_for(play, curated, code) ++ acc.conflicts}

      cond do
        map_size(sets) > 0 ->
          change = %{play_id: play.id, code: code, title: play.title, sets: sets}
          %{acc | changes: [change | acc.changes]}

        Map.has_key?(index, code) ->
          %{acc | unchanged: [code | acc.unchanged]}

        true ->
          acc
      end
    end)
    |> Map.new(fn {key, list} -> {key, Enum.reverse(list)} end)
  end
```

Two things this shape is deliberate about:

- **`missing` and `changes` are not exclusive.** `missing` answers "is this code in the published
  index"; a curated fill comes from a different table. A play can be in both.
- **`unchanged` means "in the index, nothing to write".** A play whose only finding is a conflict
  lands there, because the conflict is reported in its own bucket. A play that is neither in the
  index nor has anything to write lands in `missing` only — which is what the S1 test
  `plan.missing == ["AL0514"]` with `plan.changes == []` already asserts.

Add the two curated helpers next to `changes_for/3`:

```elixir
  # Curated fields are filled only when the column is blank. See the moduledoc.
  defp fills_for(play, curated) do
    @curated
    |> Enum.filter(fn key -> blank?(Map.get(play, key)) and not blank?(Map.get(curated, key)) end)
    |> Map.new(fn key -> {key, Map.get(curated, key)} end)
  end

  defp conflicts_for(play, curated, code) do
    for key <- @curated,
        current = Map.get(play, key),
        indexed = Map.get(curated, key),
        not blank?(current),
        not blank?(indexed),
        current != indexed do
      %{play_id: play.id, code: code, title: play.title, field: key,
        current: current, indexed: indexed}
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
```

- [x] **Step 4: Run the tests to verify they pass**

```bash
mix test test/emothe/import/filemaker_sync_test.exs
```

Expected: PASS, 14 tests (8 from S1 plus 6 new).

The S1 tests call `plan/2`; the default argument keeps them green. If any of them fails on
`plan.conflicts`, it is because an S1 test asserted the whole plan map by equality — change that
assertion to check the specific keys and say why in a comment.

- [x] **Step 5: Commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/emothe/import/filemaker_sync.ex test/emothe/import/filemaker_sync_test.exs
git commit -m "feat: fill-only sync for curated fields, with a conflicts report"
```

---

### Task 4: Apply with --force, and report conflicts in the mix task

**Files:**
- Modify: `lib/emothe/import/filemaker_sync.ex` (`apply_plan/2`)
- Modify: `lib/mix/tasks/emothe.import.filemaker.ex`
- Test: `test/emothe/import/filemaker_sync_test.exs` (append)

**Interfaces:**
- Consumes: the `plan` map from Task 3
- Produces: `FilemakerSync.apply_plan(plan, opts)` where `opts` accepts `:user_id` (as today) and
  `force: boolean()` (default `false`). With `force: true` every conflict is written too.

- [x] **Step 1: Write the failing test**

Append inside the `describe "curated fields are fill-only"` block from Task 3:

```elixir
    test "force writes the conflicting value" do
      original =
        play("EMOTHE0038_AntonyAndCleopatra", %{
          "language" => "en",
          "historical_time" => "edad_media"
        })

      plan = FilemakerSync.plan(index(), [original], versions())
      results = FilemakerSync.apply_plan(plan, force: true)

      assert Enum.sort(results) == [{:ok, "EMOTHE0038"}]
      assert Emothe.Catalogue.get_play!(original.id).historical_time == "antiguedad_clasica"
    end

    test "without force the conflicting value survives" do
      original =
        play("EMOTHE0038_AntonyAndCleopatra", %{
          "language" => "en",
          "historical_time" => "edad_media"
        })

      index() |> FilemakerSync.plan([original], versions()) |> FilemakerSync.apply_plan()

      assert Emothe.Catalogue.get_play!(original.id).historical_time == "edad_media"
    end
```

- [x] **Step 2: Run the tests to verify they fail**

```bash
mix test test/emothe/import/filemaker_sync_test.exs
```

Expected: the force test FAILS on `assert ... == "antiguedad_clasica"` with
`left: "edad_media"`. The second test may already pass — that is fine, it is the guard that stops
a later change quietly turning fill-only into overwrite.

- [x] **Step 3: Write the implementation**

In `lib/emothe/import/filemaker_sync.ex`, replace `apply_plan/2`:

```elixir
  @doc """
  Writes every change in the plan and logs it. Returns one result per play written.

  `force: true` also writes the conflicts — the curated values a researcher edited that
  disagree with the export. Without it they are left alone.
  """
  def apply_plan(plan, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)
    force = Keyword.get(opts, :force, false)

    plan
    |> writes(force)
    |> Enum.map(fn change ->
      play = Catalogue.get_play!(change.play_id)

      case Catalogue.update_play(play, change.sets) do
        {:ok, updated} ->
          ActivityLog.log!(%{
            user_id: user_id,
            play_id: updated.id,
            action: "update",
            resource_type: "play",
            resource_id: updated.id,
            changes: stringify(change.sets),
            metadata: %{"source" => "filemaker_index"}
          })

          {:ok, change.code}

        {:error, changeset} ->
          {:error, change.code, changeset}
      end
    end)
  end

  defp writes(plan, false), do: plan.changes

  defp writes(plan, true) do
    forced =
      Enum.reduce(plan.conflicts, %{}, fn conflict, acc ->
        Map.update(
          acc,
          conflict.play_id,
          %{
            play_id: conflict.play_id,
            code: conflict.code,
            title: conflict.title,
            sets: %{conflict.field => conflict.indexed}
          },
          fn change -> put_in(change.sets[conflict.field], conflict.indexed) end
        )
      end)

    # A play can be in both buckets — one field filled, another conflicting.
    plan.changes
    |> Enum.map(fn change ->
      case Map.pop(forced, change.play_id) do
        {nil, _rest} -> change
        {extra, _rest} -> %{change | sets: Map.merge(change.sets, extra.sets)}
      end
    end)
    |> Kernel.++(
      Enum.reject(Map.values(forced), fn forced_change ->
        Enum.any?(plan.changes, &(&1.play_id == forced_change.play_id))
      end)
    )
  end
```

- [x] **Step 4: Run the tests to verify they pass**

```bash
mix test test/emothe/import/filemaker_sync_test.exs
```

Expected: PASS, 16 tests.

- [x] **Step 5: Wire the mix task**

In `lib/mix/tasks/emothe.import.filemaker.ex`, add `force` to the switches:

```elixir
  @switches [dry_run: :boolean, path: :string, force: :boolean]
```

Load the version records next to the index, in `run/1`:

```elixir
    case Filemaker.load_index(path) do
      {:ok, index} ->
        {:ok, versions} = Filemaker.load_versions(path)
        sync(index, versions, path, opts)

      {:error, reason} ->
        Mix.raise("cannot read #{path}: #{inspect(reason)}")
    end
```

`load_versions/1` cannot fail here — `load_index/1` already read the same file — so the match is
deliberate: if it ever does, the task should crash loudly rather than sync half the data.

Change `sync/3` to `sync/4` and pass `versions` into `plan/3`:

```elixir
  defp sync(index, versions, path, opts) do
    plays = FilemakerSync.all_plays()
    plan = FilemakerSync.plan(index, plays, versions)
```

Print the conflicts after the change list, before the counts:

```elixir
    Enum.each(plan.conflicts, fn conflict ->
      Mix.shell().info(
        "#{conflict.code}  #{conflict.title}\n" <>
          "    #{conflict.field}: kept #{inspect(conflict.current)}, " <>
          "index says #{inspect(conflict.indexed)}"
      )
    end)
```

Add the conflict count to the summary line:

```elixir
    Mix.shell().info(
      "\n#{length(plan.changes)} to change, #{length(plan.conflicts)} conflicting, " <>
        "#{length(plan.unchanged)} already correct, #{length(plan.missing)} not in the index"
    )

    if plan.conflicts != [] and not opts[:force] do
      Mix.shell().info("conflicts left alone; re-run with --force to overwrite them")
    end
```

And pass the flag through at the write:

```elixir
      results = FilemakerSync.apply_plan(plan, force: opts[:force] || false)
```

Finally document it in the `@moduledoc`:

```
      mix emothe.import.filemaker --force            # also overwrite curated conflicts
```

- [x] **Step 6: Verify the task compiles and the dry run works**

```bash
mix compile --warnings-as-errors
mix emothe.import.filemaker --dry-run 2>&1 | grep -Ev '^\[debug\]|^(SELECT|INSERT|UPDATE|DELETE|BEGIN|COMMIT|ROLLBACK)|↳'
```

Expected: the same 15 plays S1 already corrected are now `0 to change` (S1 applied them), and 11
plays gain a `historical_time`. `0 conflicting`, because nothing has been curated by hand yet.
Record the actual counts — Task 7 compares against them.

- [x] **Step 7: Commit**

```bash
mix format
git add lib/emothe/import/filemaker_sync.ex lib/mix/tasks/emothe.import.filemaker.ex \
        test/emothe/import/filemaker_sync_test.exs
git commit -m "feat: --force to overwrite curated conflicts, and report them either way"
```

---

### Task 5: The admin form

**Files:**
- Create: `lib/emothe_web/play_labels.ex`
- Modify: `lib/emothe_web/live/admin/play_form_live.ex`
- Test: `test/emothe_web/live/admin/play_form_live_test.exs` (append)

**Interfaces:**
- Consumes: `Emothe.Catalogue.Play.historical_times/0` from Task 1
- Produces:
  - `EmotheWeb.PlayLabels.historical_time_label(slug :: String.t()) :: String.t()`
  - `EmotheWeb.PlayLabels.historical_time_options() :: [{String.t(), String.t()}]` — `{label, slug}`
    pairs with a leading blank, ready for `<.input type="select" options={...}>`

- [x] **Step 1: Write the failing test**

Append to `test/emothe_web/live/admin/play_form_live_test.exs`, inside the existing
`describe "Play form behaviors"` block. That file already has a `log_in_admin/1` helper and aliases
`Catalogue` and `TestFixtures` — use them, do not add new ones. Existing tests submit via
`element("form[phx-submit]") |> render_submit(params)`; match that:

```elixir
    test "given a historical time when saving then it is persisted", %{conn: conn} do
      conn = log_in_admin(conn)
      play = TestFixtures.play_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")

      assert has_element?(view, "select[name='play[historical_time]']")
      assert has_element?(view, "textarea[name='play[historical_time_note]']")

      view
      |> element("form[phx-submit]")
      |> render_submit(%{
        "play" => %{
          "title" => play.title,
          "code" => play.code,
          "historical_time" => "siglo_xvii",
          "historical_time_note" => "Contemporary. Reign of Philip IV."
        }
      })

      updated = Catalogue.get_play!(play.id)
      assert updated.historical_time == "siglo_xvii"
      assert updated.historical_time_note == "Contemporary. Reign of Philip IV."
    end
```

`title` and `code` are resubmitted because they are `validate_required` — omitting them makes the
changeset invalid and the test fails for the wrong reason.

- [x] **Step 2: Run the test to verify it fails**

```bash
mix test test/emothe_web/live/admin/play_form_live_test.exs
```

Expected: FAIL on the `has_element?` assertion — the select does not exist.

- [x] **Step 3: Create the labels module**

Create `lib/emothe_web/play_labels.ex`:

```elixir
defmodule EmotheWeb.PlayLabels do
  @moduledoc """
  Translated labels for the play metadata vocabularies.

  Lives here rather than in `Emothe.Catalogue.Play` because the labels are gettext
  strings and the schema has no business knowing about the web layer's locale, and
  rather than in a LiveView because the admin form and the public page need the same
  list. Later S2 fields — place of action, collection — add their vocabularies here.
  """

  use Gettext, backend: EmotheWeb.Gettext

  alias Emothe.Catalogue.Play

  @doc "The Spanish-or-English name of a historical period slug."
  def historical_time_label("tiempo_indeterminado"), do: gettext("Indeterminate")
  def historical_time_label("antiguo_testamento"), do: gettext("Old Testament")
  def historical_time_label("edad_media"), do: gettext("Middle Ages")
  def historical_time_label("siglo_xv"), do: gettext("15th century")
  def historical_time_label("siglo_xvi"), do: gettext("16th century")
  def historical_time_label("siglo_xvii"), do: gettext("17th century")
  def historical_time_label("tiempo_maravilloso"), do: gettext("Marvellous (timeless)")
  def historical_time_label("antiguedad_clasica"), do: gettext("Classical antiquity")
  def historical_time_label("tiempo_alegorico"), do: gettext("Allegorical")
  def historical_time_label(_other), do: ""

  @doc "`{label, slug}` pairs for a select, blank first."
  def historical_time_options do
    [{"", nil} | Enum.map(Play.historical_times(), &{historical_time_label(&1), &1})]
  end
end
```

Check the gettext backend name against an existing LiveView before writing this — if the repo uses
`use EmotheWeb, :verified_routes`-style helpers or an older `import EmotheWeb.Gettext`, match what
`lib/emothe_web/live/play_show_live.ex` does.

- [x] **Step 4: Add the fieldset to the form**

In `lib/emothe_web/live/admin/play_form_live.ex`, add the alias at the top of the module:

```elixir
  alias EmotheWeb.PlayLabels
```

Then a new fieldset, immediately after the "Project & Editorial" block, matching its markup exactly
so the form stays visually consistent:

```heex
        <div class="space-y-3 rounded-box border border-base-300 bg-base-50 p-4">
          <h3 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
            {gettext("Research Metadata")}
          </h3>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Historical Time")}</span>
            </label>
            <.input
              field={@form[:historical_time]}
              type="select"
              options={PlayLabels.historical_time_options()}
            />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Historical Time Note")}</span>
            </label>
            <.input
              field={@form[:historical_time_note]}
              type="textarea"
              placeholder={gettext("When the action is set, and the evidence for it")}
            />
          </div>
        </div>
```

- [x] **Step 5: Run the test to verify it passes**

```bash
mix test test/emothe_web/live/admin/play_form_live_test.exs
```

Expected: PASS.

- [x] **Step 6: Commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/emothe_web/play_labels.ex lib/emothe_web/live/admin/play_form_live.ex \
        test/emothe_web/live/admin/play_form_live_test.exs
git commit -m "feat: edit a play's historical time in the admin form"
```

---

### Task 6: The public panel

**Files:**
- Modify: `lib/emothe_web/live/play_show_live.ex`
- Test: `test/emothe_web/live/play_show_live_test.exs` (append)

**Interfaces:**
- Consumes: `EmotheWeb.PlayLabels.historical_time_label/1` from Task 5

- [x] **Step 1: Write the failing test**

Append to `test/emothe_web/live/play_show_live_test.exs`, at module level alongside the existing
tests. That file aliases `Emothe.TestFixtures` and imports `Phoenix.LiveViewTest` already:

```elixir
  test "renders the research metadata panel when the play has a historical time", %{conn: conn} do
    play =
      TestFixtures.play_fixture(%{
        "historical_time" => "antiguedad_clasica",
        "historical_time_note" => "First century BC."
      })

    {:ok, view, html} = live(conn, ~p"/plays/#{play.code}")

    assert has_element?(view, "#meta-study")
    assert has_element?(view, "#scroll-spy-nav a[href='#meta-study']")
    assert html =~ "Classical antiquity"
    assert html =~ "First century BC."
  end

  test "omits the research metadata panel when there is no historical time", %{conn: conn} do
    play = TestFixtures.play_fixture()

    {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

    refute has_element?(view, "#meta-study")
    refute has_element?(view, "#scroll-spy-nav a[href='#meta-study']")
  end
```

**The locale matters.** The existing test at line 68 of that file asserts on the Spanish string
`"no puede estar en blanco"`, so this suite runs in Spanish. If `html =~ "Classical antiquity"`
fails while `#meta-study` is present, assert on `"Antigüedad clásica"` instead — and say so in a
comment, because the reason is not obvious to the next reader.

- [x] **Step 2: Run the tests to verify they fail**

```bash
mix test test/emothe_web/live/play_show_live_test.exs
```

Expected: the first FAILS on `assert html =~ "meta-study"`; the second passes, which is correct —
it is the guard that the section really is conditional.

- [x] **Step 3: Add the section and the sidebar entry**

In `lib/emothe_web/live/play_show_live.ex`, add the alias at the top of the module:

```elixir
  alias EmotheWeb.PlayLabels
```

Add the section immediately after the closing `</header>` (currently line 322), before the
editorial-notes block:

```heex
          <%!-- Research metadata --%>
          <section
            :if={@play.historical_time}
            id="meta-study"
            class="mb-8 max-w-2xl mx-auto scroll-mt-20 text-sm"
          >
            <dl class="grid grid-cols-[max-content_1fr] gap-x-4 gap-y-1">
              <dt class="text-base-content/50">{gettext("Historical time")}</dt>
              <dd>
                {PlayLabels.historical_time_label(@play.historical_time)}
                <p :if={@play.historical_time_note} class="mt-1 text-xs text-base-content/60">
                  {@play.historical_time_note}
                </p>
              </dd>
            </dl>
          </section>
```

The `<dl>` is a grid so the rows the later S2 fields add line up under the same label column.

Then register it with the sidebar, in `build_metadata_sections/1` (currently line 369). It goes
after Overview and before Source, which is the order the sections appear in the page:

```elixir
  defp build_metadata_sections(play) do
    base = [%{id: "meta-overview", label: gettext("Overview")}]

    base
    |> maybe_add_section(play.historical_time != nil, "meta-study", gettext("Study"))
    |> maybe_add_section(play.sources != [], "meta-sources", gettext("Source"))
    |> maybe_add_section(play.editors != [], "meta-editors", gettext("Editors"))
    |> Kernel.++(build_editorial_note_sections(play.editorial_notes))
  end
```

- [x] **Step 4: Run the tests to verify they pass**

```bash
mix test test/emothe_web/live/play_show_live_test.exs
```

Expected: PASS.

- [x] **Step 5: Add the Spanish translations**

```bash
mix gettext.extract --merge
```

Then open `priv/gettext/es/LC_MESSAGES/default.po` and fill in every new `msgid`:

| msgid | msgstr |
|---|---|
| `Research Metadata` | `Metadatos de investigación` |
| `Historical Time` | `Tiempo histórico` |
| `Historical time` | `Tiempo histórico` |
| `Historical Time Note` | `Nota sobre el tiempo histórico` |
| `When the action is set, and the evidence for it` | `Cuándo transcurre la acción, y en qué se basa` |
| `Study` | `Estudio` |
| `Indeterminate` | `Tiempo indeterminado` |
| `Old Testament` | `Antiguo Testamento` |
| `Middle Ages` | `Edad Media` |
| `15th century` | `Siglo XV` |
| `16th century` | `Siglo XVI` |
| `17th century` | `Siglo XVII` |
| `Marvellous (timeless)` | `Tiempo maravilloso (intemporal)` |
| `Classical antiquity` | `Antigüedad clásica` |
| `Allegorical` | `Tiempo alegórico` |

**`mix gettext.extract --merge` fuzzy-matches new strings onto unrelated existing translations** —
in the last slice it turned `"Restore"` into `"Nueva fuente"`. Check every entry it marked
`#, fuzzy`, fix the wrong ones, and remove the `fuzzy` flag from the ones you corrected.

- [x] **Step 6: Run the whole suite and commit**

```bash
mix format
mix compile --warnings-as-errors
mix test
git add lib/emothe_web/live/play_show_live.ex test/emothe_web/live/play_show_live_test.exs \
        priv/gettext
git commit -m "feat: a research metadata panel on the public play page"
```

---

### Task 7: Apply for real and check it in the app

**Files:** none — this is the acceptance pass.

- [x] **Step 1: Snapshot the current state**

```bash
PGPASSWORD=postgres psql -U postgres -h localhost -d emothe_dev -tAF'|' \
  -c "select split_part(code,'_',1), coalesce(historical_time,'-') from plays order by code" \
  > /tmp/historical-before.txt
grep -cv '|-$' /tmp/historical-before.txt
```

Expected: `0` — nothing has a historical time yet.

- [x] **Step 2: Dry run**

```bash
mix emothe.import.filemaker --dry-run 2>&1 | grep -Ev '^\[debug\]|^(SELECT|INSERT|UPDATE|DELETE|BEGIN|COMMIT|ROLLBACK)|↳'
```

Expected: 11 plays listed with a `historical_time`, of which 8 also get a
`historical_time_note`. `0 conflicting`. No `AL####` code anywhere in the change list.

The 11 are `EMOTHE0008`, `EMOTHE0010`, `EMOTHE0038`, `EMOTHE0211`, `EMOTHE0254`, `EMOTHE0281`,
`EMOTHE0286`, `EMOTHE0337`, `EMOTHE0341`, `EMOTHE0346`, `EMOTHE0502`.

`EMOTHE0341` must be in that list **and** still listed under "not in the index" — it has a T01
research record but was never published, so it appears in both buckets. Task 3 has a test for
exactly this; if the dry run omits it here, that test is passing for the wrong reason.

`EMOTHE0033` has an empty `<ul><li></li></ul>` and no code, so it correctly gets nothing.

- [x] **Step 3: Apply**

```bash
mix emothe.import.filemaker 2>&1 | grep -Ev '^\[debug\]|^(SELECT|INSERT|UPDATE|DELETE|BEGIN|COMMIT|ROLLBACK)|↳' | tail -5
```

Expected: `updated 11, failed 0`.

- [x] **Step 4: Verify the writes**

```bash
PGPASSWORD=postgres psql -U postgres -h localhost -d emothe_dev -tAF'|' -c \
  "select split_part(code,'_',1), historical_time, left(coalesce(historical_time_note,'-'), 40)
   from plays where historical_time is not null order by code"
```

Expected exactly 11 rows, including:

```
EMOTHE0010|tiempo_indeterminado|The play’s story combines references to
EMOTHE0038|antiguedad_clasica|First century BC. The play dramatizes eve
EMOTHE0211|siglo_xvii|-
```

- [x] **Step 5: Verify the fill-only policy against the live database**

```bash
PGPASSWORD=postgres psql -U postgres -h localhost -d emothe_dev -c \
  "update plays set historical_time = 'edad_media' where code like 'EMOTHE0038%'"
mix emothe.import.filemaker --dry-run 2>&1 | grep -A2 EMOTHE0038
```

Expected: `EMOTHE0038` reported under conflicts as
`historical_time: kept "edad_media", index says "antiguedad_clasica"`, and `1 conflicting` in the
summary. Then put it back:

```bash
mix emothe.import.filemaker --force 2>&1 | tail -3
PGPASSWORD=postgres psql -U postgres -h localhost -d emothe_dev -tAc \
  "select historical_time from plays where code like 'EMOTHE0038%'"
```

Expected: `antiguedad_clasica`.

- [x] **Step 6: Look at the app**

```bash
mix phx.server
```

Port 4000 may already be in use — if `mix phx.server` exits with `:eaddrinuse`, a server is already
running and you can use it. Check:

- `/plays/EMOTHE0038_AntonyAndCleopatra` — the Study panel shows "Classical antiquity" and the
  note, and "Study" appears in the sidebar between Overview and Source
- `/plays/EMOTHE0211_ElCaballeroDeOlmedo` — the panel shows the period with no note
- any `AL####` play, e.g. `/plays/AL0514_ElAusenteEnElLugar` — no Study panel, no sidebar entry
- `/admin/plays/<id>/edit` — the Research Metadata fieldset saves and reloads correctly
- switch the locale to Spanish and confirm the panel reads "Tiempo histórico" / "Antigüedad clásica"

- [x] **Step 7: Run the whole suite**

```bash
mix test
```

Expected: PASS. 277 before this slice, plus roughly 18 new.

- [x] **Step 8: Update the docs and commit**

- Tick every checkbox in this plan.
- Move this file to `docs/superpowers/plans/archive/` and add an S2a section to
  `docs/superpowers/plans/archive/README.md` recording what shipped, the commit list, the actual
  row counts from Step 4, and anything this slice learned that the plan did not say.
- In `docs/superpowers/plans/2026-08-01-filemaker-import-slices.md`, mark S2a **done** in the
  sub-slice table and point it at the archive.
- In `CLAUDE.md`, move `historical_time` out of the S2 pending line and note the two new columns
  under "Archiving and provenance" as `@platform_owned`.

```bash
git add docs CLAUDE.md
git commit -m "docs: S2a done, archive the plan"
```

---

## Notes for whoever picks this up

- **Why the code and not the label.** `bus_tiemHistorico` is set on 11 of our 22 T01 plays;
  `pub_TiemHistorico` on only 8. Four plays — `EMOTHE0211`, `EMOTHE0254`, `EMOTHE0286`,
  `EMOTHE0502` — have a code and no rendered text at all. The label is only read for its note.
- **Why fill-only.** The roadmap's governing rule is that the export is a bootstrap, not a
  dependency. A field a researcher is expected to curate cannot be overwritten by re-running an
  import against a file that is not even in git.
- **Why a section and not a tab.** 71 of 82 plays have no historical time. A tab bar that gains and
  loses a tab between plays is worse than a section that is simply absent.
- **The ceiling this slice accepts:** one period per play. Two of 439 export rows carry two. If that
  ever matters, the column becomes an array — roadmap open question 5.
- **Next sub-slice:** S2b, `place_of_action` from `pub_LugAccion`, 6 of 22 plays. It adds one row to
  the panel this slice built and one field to `load_versions/1`. No new module, no new policy.
