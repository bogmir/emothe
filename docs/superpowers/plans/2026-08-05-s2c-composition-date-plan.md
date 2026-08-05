# S2c — Composition date: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `composition_date_from` / `_to` / `_note` to `plays` — editable in the admin form, round-tripping through TEI `<creation>`, and bootstrapped from the FileMaker export.

**Context:** Slice S2c of `docs/superpowers/plans/2026-08-01-filemaker-import-slices.md`. Spec: `docs/superpowers/specs/2026-08-05-s2c-composition-date-design.md` (read it first — the two departures from the roadmap are argued there). It was chosen because it is the only remaining FileMaker slice that is editable in our UI, has a canonical TEI home, is importable from the export, and is a column on the play — so it does not wait behind the ~300-play import that gates S3/S4/S5/S9b.

**Architecture:** Three integer/text columns on `plays`. The FileMaker *index header* (`T00.pub_listaObras`) supplies from/to and attaches them **only to the family head** (`role: :editor`); `T01.pub_datacion` supplies the note. Fill-only sync via the existing `@curated` machinery. TEI `<creation><date>` inside the existing `build_profile_desc/1`.

**Tech Stack:** Elixir 1.19.5 / OTP 28.1, Phoenix 1.8.3, LiveView 1.1.22, Ecto/Postgres, Saxy (import), xml_builder (export), gettext.

## Global Constraints

- **TDD, no exceptions.** Failing test first, watch it fail, minimal implementation, watch it pass, then `mix test` (whole suite). No "done" claim without command output.
- Run mix plainly: `mix test`, no `export PATH=` prefix (see `CLAUDE.md`).
- `mix format` after every task. `mix compile --warnings-as-errors` before every commit.
- **All three columns go into `@platform_owned`** in `lib/emothe/import/tei_parser.ex` or the next TEI re-import erases them (Task 2).
- Never model the dating qualifiers (`= ≥ ≤ ≈ ?`). Years + verbatim note only.
- The importer never writes a dating onto a translation.
- Every sync write is logged by the existing `apply_plan/2` — do not add a new `ActivityLog` action.
- `mix test` excludes `:slow` (the xmllint/RelaxNG tests) by default. Leave it that way.

## File Structure

| File | Responsibility |
|---|---|
`priv/repo/migrations/<ts>_add_composition_date_to_plays.exs` | new — three columns
`lib/emothe/catalogue/play.ex` | schema fields, cast, `validate_composition_date_span/1`
`test/emothe/catalogue/play_test.exs` | new — changeset validation, no DB
`lib/emothe/import/tei_parser.ex` | `@platform_owned`, `extract_creation/1`
`lib/emothe/export/tei_xml.ex` | `build_creation/1` inside `build_profile_desc/1`
`lib/emothe/import/filemaker.ex` | index-header dating (head-only), `pub_datacion` note
`lib/emothe/import/filemaker_sync.ex` | `@curated`, curated map from both sources, `:skipped` bucket
`lib/mix/tasks/emothe.import.filemaker.ex` | print the `:skipped` bucket
`lib/emothe_web/live/admin/filemaker_sync_live.ex` | read-only `skipped` details block
`lib/emothe_web/live/admin/play_form_live.ex` | two number inputs + textarea
`lib/emothe_web/live/play_show_live.ex` | `#meta-study` row + `build_sections/1`
`priv/gettext/es/LC_MESSAGES/default.po` | Spanish for the new labels

Existing helpers to reuse, not re-implement: `find_child/2`, `attr_value/2`, `text_content/1` (tei_parser); `element/2,3` (tei_xml via xml_builder); `field/2`, `strip_tags/1`, `@first_item` (filemaker); `fills_for/2`, `conflicts_for/3`, `blank?/1`, `apply_plan/2` (filemaker_sync); `play_fixture/1` (`test/support/fixtures.ex`).

---

### Task 1: Columns, schema, changeset validation

**Files:**
- Create: `priv/repo/migrations/<timestamp>_add_composition_date_to_plays.exs`
- Create: `test/emothe/catalogue/play_test.exs`
- Modify: `lib/emothe/catalogue/play.ex` (schema block ~line 36, cast list ~line 113, validations ~line 120)

**Interfaces:**
- Produces: `plays.composition_date_from :integer`, `composition_date_to :integer`, `composition_date_note :text`; all three cast by `Play.changeset/2` and therefore by `form_changeset/2` and `Catalogue.change_play_form/2`.

- [ ] **Step 1: Write the failing test**

Create `test/emothe/catalogue/play_test.exs`:

```elixir
defmodule Emothe.Catalogue.PlayTest do
  use ExUnit.Case, async: true

  alias Emothe.Catalogue.Play

  defp changeset(attrs) do
    Play.changeset(%Play{}, Map.merge(%{"title" => "Test", "code" => "TEST01"}, attrs))
  end

  test "accepts a year range" do
    cs = changeset(%{"composition_date_from" => "1606", "composition_date_to" => "1607"})

    assert cs.valid?
    assert cs.changes.composition_date_from == 1606
    assert cs.changes.composition_date_to == 1607
  end

  test "accepts a single year as from == to" do
    cs = changeset(%{"composition_date_from" => "1614", "composition_date_to" => "1614"})

    assert cs.valid?
  end

  test "accepts a note with no years" do
    cs = changeset(%{"composition_date_note" => "alrededor de 1601"})

    assert cs.valid?
  end

  test "rejects a lone start year" do
    cs = changeset(%{"composition_date_from" => "1606"})

    refute cs.valid?
    assert {"must be given together with the end year", _} = cs.errors[:composition_date_from]
  end

  test "rejects a lone end year" do
    cs = changeset(%{"composition_date_to" => "1607"})

    refute cs.valid?
    assert {"must be given together with the start year", _} = cs.errors[:composition_date_to]
  end

  test "rejects an end year before the start year" do
    cs = changeset(%{"composition_date_from" => "1607", "composition_date_to" => "1606"})

    refute cs.valid?
    assert {"must not be before the start year", _} = cs.errors[:composition_date_to]
  end

  test "rejects a year outside the plausible range" do
    cs = changeset(%{"composition_date_from" => "160", "composition_date_to" => "160"})

    refute cs.valid?
    assert cs.errors[:composition_date_from]
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `mix test test/emothe/catalogue/play_test.exs`
Expected: FAIL — `composition_date_from` is not a field, so `cs.changes` has no such key and the error assertions find nothing.

- [ ] **Step 3: Write the migration**

Run: `mix ecto.gen.migration add_composition_date_to_plays`, then put in the generated file:

```elixir
defmodule Emothe.Repo.Migrations.AddCompositionDateToPlays do
  use Ecto.Migration

  def change do
    alter table(:plays) do
      add :composition_date_from, :integer
      add :composition_date_to, :integer
      add :composition_date_note, :text
    end
  end
end
```

No index: nothing queries on these until search arrives, and 82 rows would not use one.

Run: `mix ecto.migrate`

- [ ] **Step 4: Add the schema fields**

In `lib/emothe/catalogue/play.ex`, after `field :historical_time_note, :string`:

```elixir
    field :composition_date_from, :integer
    field :composition_date_to, :integer
    field :composition_date_note, :string
```

- [ ] **Step 5: Add to the cast list and the validations**

In `changeset/2`, append to the `cast/3` list after `:historical_time_note`:

```elixir
      :composition_date_from,
      :composition_date_to,
      :composition_date_note
```

After `|> validate_inclusion(:historical_time, @historical_times)`:

```elixir
    |> validate_number(:composition_date_from,
      greater_than_or_equal_to: 1000,
      less_than_or_equal_to: 2100
    )
    |> validate_number(:composition_date_to,
      greater_than_or_equal_to: 1000,
      less_than_or_equal_to: 2100
    )
    |> validate_composition_date_span()
```

And, after `changeset/2`:

```elixir
  # Both endpoints or neither: a lone year is a half-filled form, not a dating. The
  # bounds on each year are deliberately wide — the corpus is 16th–17th century, but the
  # column is a year and a curator fixing a typo should not fight the validator.
  defp validate_composition_date_span(changeset) do
    from = get_field(changeset, :composition_date_from)
    to = get_field(changeset, :composition_date_to)

    cond do
      is_nil(from) and is_nil(to) ->
        changeset

      # The error goes on the field the curator *did* fill in — that is the input
      # whose partner is missing.
      is_nil(to) ->
        add_error(changeset, :composition_date_from, "must be given together with the end year")

      is_nil(from) ->
        add_error(changeset, :composition_date_to, "must be given together with the start year")

      from > to ->
        add_error(changeset, :composition_date_to, "must not be before the start year")

      true ->
        changeset
    end
  end
```

- [ ] **Step 6: Run the test, then the suite**

Run: `mix test test/emothe/catalogue/play_test.exs` — Expected: PASS (7 tests)
Run: `mix format && mix compile --warnings-as-errors && mix test`
Expected: whole suite green.

- [ ] **Step 7: Commit**

```bash
git add priv/repo/migrations lib/emothe/catalogue/play.ex test/emothe/catalogue/play_test.exs
git commit -m "feat: composition date columns on plays"
```

---

### Task 2: Protect the columns from a TEI re-import

**Files:**
- Modify: `lib/emothe/import/tei_parser.ex:24-31` (`@platform_owned`)
- Test: `test/emothe/import/tei_reimport_test.exs`

**Interfaces:**
- Consumes: the three columns from Task 1.
- Produces: `@platform_owned` now lists them, so `import_header/1`'s `Map.drop(play_attrs, @platform_owned)` skips them on update, and `preserved_fields/1` reports them in the import preview.

- [ ] **Step 1: Write the failing test**

Append to `test/emothe/import/tei_reimport_test.exs` (match the file's existing setup for building a play and re-importing the same file — reuse whatever helper it already has for "import, edit, re-import"):

```elixir
  test "a re-import does not overwrite a curated composition date" do
    path = write_tei(minimal_tei(code: "REIMP-CD", title: "Dated Play"))

    assert {:ok, play} = TeiParser.import_file(path)

    {:ok, _edited} =
      Catalogue.update_play(play, %{
        "composition_date_from" => 1606,
        "composition_date_to" => 1607,
        "composition_date_note" => "typed by a curator"
      })

    assert {:ok, reimported} = TeiParser.import_file(path)

    assert reimported.id == play.id
    assert reimported.composition_date_from == 1606
    assert reimported.composition_date_to == 1607
    assert reimported.composition_date_note == "typed by a curator"
  end
```

If `write_tei/1` and `minimal_tei/1` are not already in that file, copy them from `test/emothe/import/tei_parser_test.exs:8-45`.

- [ ] **Step 2: Run it and watch it fail**

Run: `mix test test/emothe/import/tei_reimport_test.exs`
Expected: FAIL — the re-import writes `nil` over all three, so `reimported.composition_date_from == 1606` fails with `nil`.

(If it passes at this point, the parser is not yet emitting the keys — it will after Task 4, which is exactly why this list must be in place first.)

- [ ] **Step 3: Add the fields to `@platform_owned`**

```elixir
  @platform_owned [
    :language,
    :relationship_type,
    :parent_play_id,
    :is_complete,
    :historical_time,
    :historical_time_note,
    :composition_date_from,
    :composition_date_to,
    :composition_date_note
  ]
```

- [ ] **Step 4: Run the test, then the suite**

Run: `mix test test/emothe/import/tei_reimport_test.exs` — Expected: PASS
Run: `mix test test/emothe/import/tei_preview_test.exs` — Expected: PASS (the preview counts `@platform_owned` fields that are set; check whether any assertion pins an exact list and update it if so)
Run: `mix format && mix compile --warnings-as-errors && mix test`

- [ ] **Step 5: Commit**

```bash
git add lib/emothe/import/tei_parser.ex test/emothe/import/tei_reimport_test.exs
git commit -m "feat: composition date is platform-owned, safe from re-import"
```

---

### Task 3: TEI export — `<creation><date>`

**Files:**
- Modify: `lib/emothe/export/tei_xml.ex:288-296` (`build_profile_desc/1`)
- Test: `test/emothe/export/tei_xml_test.exs`

**Interfaces:**
- Consumes: the three columns from Task 1.
- Produces: `<profileDesc><creation><date …/></creation><langUsage>…</langUsage>…</profileDesc>`, with `when="YYYY"` when `from == to` and `notBefore`/`notAfter` otherwise, and the note as the `<date>` text.

**Note:** `<creation>` first inside `profileDesc` was verified schema-valid against the bundled `priv/schemas/tei_all.rng` with `xmllint --relaxng` (0 errors, same as the unmodified file). `profileDesc` is `(model.profileDescPart)*`, so order is unconstrained.

- [ ] **Step 1: Write the failing tests**

Add to `test/emothe/export/tei_xml_test.exs`:

```elixir
  describe "composition date" do
    test "a single year exports as @when" do
      play =
        play_fixture(%{
          "code" => "CDEXP1",
          "composition_date_from" => 1614,
          "composition_date_to" => 1614
        })

      xml = TeiXml.generate(Catalogue.get_play_with_all!(play.id))

      assert xml =~ "<creation>"
      assert xml =~ ~s(<date when="1614")
      refute xml =~ "notBefore"
    end

    test "a range exports as @notBefore/@notAfter with the note as text" do
      play =
        play_fixture(%{
          "code" => "CDEXP2",
          "composition_date_from" => 1600,
          "composition_date_to" => 1601,
          "composition_date_note" => "¿1600? y ¿1601?; alrededor de 1601"
        })

      xml = TeiXml.generate(Catalogue.get_play_with_all!(play.id))

      assert xml =~ ~s(notBefore="1600")
      assert xml =~ ~s(notAfter="1601")
      assert xml =~ "¿1600? y ¿1601?; alrededor de 1601"
    end

    test "no creation element when there is no dating" do
      play = play_fixture(%{"code" => "CDEXP3"})

      xml = TeiXml.generate(Catalogue.get_play_with_all!(play.id))

      refute xml =~ "<creation>"
    end

    test "a note without years does not produce a creation element" do
      play = play_fixture(%{"code" => "CDEXP4", "composition_date_note" => "sin fecha"})

      xml = TeiXml.generate(Catalogue.get_play_with_all!(play.id))

      refute xml =~ "<creation>"
    end
  end
```

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/emothe/export/tei_xml_test.exs -o "composition date"`
Expected: FAIL on the first two — no `<creation>` in the output. The last two pass already; they are the regression guard.

- [ ] **Step 3: Implement `build_creation/1`**

In `lib/emothe/export/tei_xml.ex`, change `build_profile_desc/1` to:

```elixir
  defp build_profile_desc(play) do
    {ident, label} = Map.get(@language_ident_labels, play.language || "es", {"es-ES", "Español"})

    children =
      build_creation(play) ++
        [element(:langUsage, [element(:language, %{ident: ident}, label)])]

    element(:profileDesc, children ++ build_setting_desc(play))
  end

  # <creation> is where TEI records when the text *in this file* was composed. Emitted
  # only when we hold machine-readable years, so a note with no dating stays out of the
  # XML rather than arriving as an undated <date>. The note is the element's text — the
  # human-readable form of the machine attributes.
  defp build_creation(%{composition_date_from: nil}), do: []

  defp build_creation(play) do
    attrs =
      if play.composition_date_from == play.composition_date_to do
        %{when: to_string(play.composition_date_from)}
      else
        %{
          notBefore: to_string(play.composition_date_from),
          notAfter: to_string(play.composition_date_to)
        }
      end

    date =
      case play.composition_date_note do
        nil -> element(:date, attrs)
        note -> element(:date, attrs, note)
      end

    [element(:creation, [date])]
  end
```

- [ ] **Step 4: Run the tests, then the suite**

Run: `mix test test/emothe/export/tei_xml_test.exs` — Expected: PASS
Run: `mix format && mix compile --warnings-as-errors && mix test`

- [ ] **Step 5: Confirm the output is schema-valid**

Run: `mix test test/emothe/export/tei_validator_test.exs --include slow`
Expected: PASS. ~15s per test, which is why it is excluded by default.

- [ ] **Step 6: Commit**

```bash
git add lib/emothe/export/tei_xml.ex test/emothe/export/tei_xml_test.exs
git commit -m "feat: export composition date as TEI creation/date"
```

---

### Task 4: TEI import — read `<creation><date>` back

**Files:**
- Modify: `lib/emothe/import/tei_parser.ex` (`extract_play_attrs/3` at :328, its returned map at ~:390, new `extract_creation/1` beside `extract_language_code/1` at ~:420)
- Test: `test/emothe/import/tei_parser_test.exs`

**Interfaces:**
- Consumes: `@platform_owned` from Task 2, the exporter from Task 3.
- Produces: `extract_play_attrs/3` returns `composition_date_from`, `composition_date_to`, `composition_date_note`. Because they are `@platform_owned`, they are applied on **first** import only — a re-import drops them (Task 2's test).

- [ ] **Step 1: Extend the `minimal_tei/1` helper**

`minimal_tei/1` in `test/emothe/import/tei_parser_test.exs:15-45` emits no `<profileDesc>`. Add an opt:

```elixir
    profile = Keyword.get(opts, :profile, "")
```

and insert `#{profile}` between `</fileDesc>` and `</teiHeader>` in the heredoc.

- [ ] **Step 2: Write the failing tests**

```elixir
  describe "composition date" do
    test "reads @when as a single year" do
      path =
        write_tei(
          minimal_tei(
            code: "CDIMP1",
            profile: "<profileDesc><creation><date when=\"1614\"/></creation></profileDesc>"
          )
        )

      assert {:ok, play} = TeiParser.import_file(path)
      assert play.composition_date_from == 1614
      assert play.composition_date_to == 1614
    end

    test "reads @notBefore/@notAfter and the note text" do
      path =
        write_tei(
          minimal_tei(
            code: "CDIMP2",
            profile:
              "<profileDesc><creation><date notBefore=\"1600\" notAfter=\"1601\">¿1600? y ¿1601?</date></creation></profileDesc>"
          )
        )

      assert {:ok, play} = TeiParser.import_file(path)
      assert play.composition_date_from == 1600
      assert play.composition_date_to == 1601
      assert play.composition_date_note == "¿1600? y ¿1601?"
    end

    test "a date with no usable attribute imports as no dating and does not raise" do
      path =
        write_tei(
          minimal_tei(
            code: "CDIMP3",
            profile: "<profileDesc><creation><date>c. 1600</date></creation></profileDesc>"
          )
        )

      assert {:ok, play} = TeiParser.import_file(path)
      assert play.composition_date_from == nil
      assert play.composition_date_to == nil
    end

    test "a lone endpoint is not stored — the changeset forbids half a range" do
      path =
        write_tei(
          minimal_tei(
            code: "CDIMP4",
            profile: "<profileDesc><creation><date notAfter=\"1601\"/></creation></profileDesc>"
          )
        )

      assert {:ok, play} = TeiParser.import_file(path)
      assert play.composition_date_from == nil
      assert play.composition_date_to == nil
    end

    test "no creation element leaves the columns nil" do
      path = write_tei(minimal_tei(code: "CDIMP5"))

      assert {:ok, play} = TeiParser.import_file(path)
      assert play.composition_date_from == nil
    end
  end
```

And a round-trip test in `test/emothe/export/tei_xml_test.exs`:

```elixir
    test "round-trips through export and import" do
      play =
        play_fixture(%{
          "code" => "CDRT01",
          "composition_date_from" => 1605,
          "composition_date_to" => 1607,
          "composition_date_note" => "desde o posterior 1605 y anterior o hasta 1607; 1606"
        })

      xml = TeiXml.generate(Catalogue.get_play_with_all!(play.id))
      path = write_tei(String.replace(xml, "CDRT01", "CDRT02"))

      assert {:ok, imported} = TeiParser.import_file(path)
      assert imported.composition_date_from == 1605
      assert imported.composition_date_to == 1607
      assert imported.composition_date_note == "desde o posterior 1605 y anterior o hasta 1607; 1606"
    end
```

The code is rewritten because `@platform_owned` means a re-import of the *same* code would not apply the fields — the round-trip must land on a new play. If `String.replace/3` proves too blunt for the generated XML, write the second play's code into the fixture attrs and generate from a play created with the target code.

**Deviation from the spec, deliberate:** the spec says `notBefore`/`notAfter` → "whichever are present". Task 1's changeset forbids a lone endpoint, so a single attribute cannot be stored. Mirroring it (`from = to = 1601`) would assert a precision the file did not, so a lone endpoint is dropped. The fourth test pins this.

- [ ] **Step 3: Run them and watch them fail**

Run: `mix test test/emothe/import/tei_parser_test.exs -o "composition date"`
Expected: FAIL on the first two with `nil` != `1614` / `1600`.

- [ ] **Step 4: Implement the extraction**

In `extract_play_attrs/3`, next to `language = extract_language_code(profile_desc)`:

```elixir
    {composition_from, composition_to, composition_note} = extract_creation(profile_desc)
```

and in the returned map, after `language: language || "es"`:

```elixir
      composition_date_from: composition_from,
      composition_date_to: composition_to,
      composition_date_note: composition_note
```

Beside `extract_language_code/1`:

```elixir
  # profileDesc/creation/date. @when is a single year; @notBefore + @notAfter a range.
  # A lone endpoint is dropped rather than mirrored: the changeset forbids half a range,
  # and inventing the missing year would assert a precision the file does not carry.
  defp extract_creation(nil), do: {nil, nil, nil}

  defp extract_creation({_name, _attrs, children}) do
    with creation when not is_nil(creation) <- find_child(children, "creation"),
         date when not is_nil(date) <- find_child(elem(creation, 2), "date"),
         {from, to} when not is_nil(from) and not is_nil(to) <- creation_years(elem(date, 1)) do
      {from, to, creation_note(date)}
    else
      _ -> {nil, nil, nil}
    end
  end

  defp creation_years(attrs) do
    case creation_year(attr_value(attrs, "when")) do
      nil -> {creation_year(attr_value(attrs, "notBefore")), creation_year(attr_value(attrs, "notAfter"))}
      exact -> {exact, exact}
    end
  end

  defp creation_year(nil), do: nil

  defp creation_year(value) do
    case Integer.parse(String.trim(value)) do
      {year, _rest} -> year
      :error -> nil
    end
  end

  defp creation_note(date) do
    case date |> text_content() |> String.trim() do
      "" -> nil
      text -> text
    end
  end
```

- [ ] **Step 5: Run the tests, then the suite**

Run: `mix test test/emothe/import/tei_parser_test.exs test/emothe/export/tei_xml_test.exs` — Expected: PASS
Run: `mix format && mix compile --warnings-as-errors && mix test`
Expected: green, including `test/emothe/roundtrip_test.exs` — no fixture carries `<creation>`, so its counts are unaffected.

- [ ] **Step 6: Commit**

```bash
git add lib/emothe/import/tei_parser.ex test/emothe/import/tei_parser_test.exs test/emothe/export/tei_xml_test.exs
git commit -m "feat: import TEI creation/date into the composition date columns"
```

---

### Task 5: Parse the dating out of the FileMaker index header

**Files:**
- Modify: `lib/emothe/import/filemaker.ex` (`add_work/2` at ~:140, new module attrs and `parse_dating/1`)
- Modify: `test/fixtures/filemaker/index_sample.ndjson` (add a dating to the header)
- Test: `test/emothe/import/filemaker_test.exs`

**Interfaces:**
- Produces: each index version map may gain `composition_date_from`, `composition_date_to`, `composition_date_note` — **only when `role: :editor`** — or `composition_date_skipped: {:span | :unparseable, String.t()}`. Versions with no dating gain no keys at all.

- [ ] **Step 1: Add a dating to the fixture**

In `test/fixtures/filemaker/index_sample.ndjson`, in record 72's `pub_listaObras`, change

```
<div><i>ANTONY AND CLEOPATRA</i>. William Shakespeare</div>
```

to

```
<div><i>ANTONY AND CLEOPATRA</i>. William Shakespeare<span style=\"font-size: small;margin-left: 25px;\">=1606 - =1607</span></div>
```

(escaped `\"` — it is inside a JSON string). Leave the HIE0393 record alone; it has no `<div>`, which is the no-header case.

- [ ] **Step 2: Write the failing tests**

Add to `test/emothe/import/filemaker_test.exs`:

```elixir
  test "reads the work dating from the index header", %{index: index} do
    assert index["EMOTHE0038"].composition_date_from == 1606
    assert index["EMOTHE0038"].composition_date_to == 1607
    assert index["EMOTHE0038"].composition_date_note == "=1606 - =1607"
  end

  test "the dating goes to the original, never to a translation", %{index: index} do
    refute Map.has_key?(index["EMOTHE0052"], :composition_date_from)
    refute Map.has_key?(index["EMOTHE0052"], :composition_date_note)
  end

  test "a work with no header dating gains no dating keys", %{index: index} do
    refute Map.has_key?(index["HIE0393"], :composition_date_from)
  end

  describe "dating forms" do
    defp dating(header) do
      html =
        ~s(<div><i>T</i>. A<span style="x">#{header}</span></div>\n<ul>\n) <>
          ~s(<li><span style="font-size: x-small">[EN] </span>) <>
          ~s(<a href="textosEMOTHE/EMOTHE9001_T.php"><i>T</i></a>) <>
          ~s(<span>Someone, ed.</span></li>\n</ul>)

      line =
        Jason.encode!(%{
          "fields" => %{
            "_kp_IdIndiceEM" => ["1"],
            "_IdIndiceCtce" => ["1"],
            "pub_listaObras" => [html]
          }
        })

      meta = Jason.encode!(%{"_meta" => %{"layout" => "T00_indiceEM"}})
      path = Path.join(System.tmp_dir!(), "fm-#{System.unique_integer([:positive])}.ndjson")
      File.write!(path, meta <> "\n" <> line <> "\n")
      on_exit(fn -> File.rm(path) end)

      {:ok, index} = Filemaker.load_index(path)
      index["EMOTHE9001"]
    end

    test "exact range" do
      assert %{composition_date_from: 1606, composition_date_to: 1607} = dating("=1606 - =1607")
    end

    test "single year" do
      assert %{composition_date_from: 1610, composition_date_to: 1610} = dating("=1610")
    end

    test "open-ended range" do
      assert %{composition_date_from: 1598, composition_date_to: 1600} = dating("≥1598 - ≤1600")
    end

    test "conjectural" do
      assert %{composition_date_from: 1600, composition_date_to: 1601} = dating("1600? - 1601?")
    end

    test "circa" do
      assert %{composition_date_from: 1562, composition_date_to: 1562} = dating("≈1562")
    end

    test "two-digit tail collapses to the start year, and the note keeps the truth" do
      assert %{
               composition_date_from: 1587,
               composition_date_to: 1587,
               composition_date_note: "=1587 - =92"
             } = dating("=1587 - =92")
    end

    test "a header with no year is skipped, not guessed" do
      assert %{composition_date_skipped: {:unparseable, "="}} = dating("=")
      refute Map.has_key?(dating("="), :composition_date_from)
    end

    test "an implausibly wide span is skipped" do
      assert %{composition_date_skipped: {:span, "¿1694? y ¿1605?"}} = dating("¿1694? y ¿1605?")
      refute Map.has_key?(dating("¿1694? y ¿1605?"), :composition_date_from)
    end
  end
```

- [ ] **Step 3: Run them and watch them fail**

Run: `mix test test/emothe/import/filemaker_test.exs`
Expected: FAIL — `index["EMOTHE0038"].composition_date_from` raises `KeyError`.

- [ ] **Step 4: Implement it**

Add the module attributes near `@version` in `lib/emothe/import/filemaker.ex`:

```elixir
  # The work header: <div><i>TITLE</i>. Author<span …>=1606 - =1607</span></div>. The
  # sigils (= ≥ ≤ ≈ ?) are qualifiers we deliberately do not model — the years are what
  # we store, and the string itself becomes the note.
  @work_dating ~r|<div>.*?<span[^>]*>([^<]*)</span>\s*</div>|s
  @four_digit_year ~r|\b(1[0-9]{3})\b|

  # Wider than this is a data-entry error in the export, not a dating: the widest real
  # header is 13 years (=1612 - =1625). Skipped rather than reported as a conflict,
  # because a conflict is tickable in /admin/filemaker and a force-write of a bad span
  # is precisely what this guard exists to prevent.
  @max_composition_span 40
```

Rewrite `add_work/2`:

```elixir
  defp add_work(index, fields) do
    work = field(fields, "_IdIndiceCtce")
    html = field(fields, "pub_listaObras")
    versions = parse_versions(html, work)
    family = Enum.map(versions, &Map.take(&1, [:code, :role]))
    dating = parse_dating(html)

    Enum.reduce(versions, index, fn version, acc ->
      version =
        version
        |> Map.put(:family, family)
        |> Map.merge(dating_for(version, dating))

      Map.put(acc, version.code, version)
    end)
  end

  # The header dating belongs to the *work*, so it is the composition date of the
  # original. A translation was composed centuries later and the export does not say
  # when, so it gets nothing — see the spec's "a translation does not get the original's
  # date". A work with no `ed.` version gets nothing anywhere: we cannot tell whose
  # composition it is.
  defp dating_for(%{role: :editor}, dating), do: dating
  defp dating_for(_version, _dating), do: %{}

  defp parse_dating(html) do
    case Regex.run(@work_dating, html) do
      [_all, text] -> dating_from(String.trim(text))
      _ -> %{}
    end
  end

  defp dating_from(""), do: %{}

  defp dating_from(text) do
    years =
      @four_digit_year
      |> Regex.scan(text)
      |> Enum.map(fn [_all, year] -> String.to_integer(year) end)

    case years do
      [] ->
        %{composition_date_skipped: {:unparseable, text}}

      years ->
        from = Enum.min(years)
        to = Enum.max(years)

        if to - from > @max_composition_span do
          %{composition_date_skipped: {:span, text}}
        else
          %{
            composition_date_from: from,
            composition_date_to: to,
            composition_date_note: text
          }
        end
    end
  end
```

- [ ] **Step 5: Run the tests, then the suite**

Run: `mix test test/emothe/import/filemaker_test.exs` — Expected: PASS
Run: `mix format && mix compile --warnings-as-errors && mix test`

- [ ] **Step 6: Sanity-check against the real export**

Run:

```bash
mix run -e 'Emothe.Import.Filemaker.load_index() |> elem(1) |> Map.values() |> Enum.filter(&Map.has_key?(&1, :composition_date_from)) |> length() |> IO.inspect(label: "heads with a dating")'
```

Expected: `64` or very close — one head per dated work. Report the number you get.

- [ ] **Step 7: Commit**

```bash
git add lib/emothe/import/filemaker.ex test/emothe/import/filemaker_test.exs test/fixtures/filemaker/index_sample.ndjson
git commit -m "feat: read the composition dating from the FileMaker index header"
```

---

### Task 6: The note from `pub_datacion`

**Files:**
- Modify: `lib/emothe/import/filemaker.ex` (`build_version/1`, rename `@first_item` → `@list_item`)
- Modify: `test/fixtures/filemaker/versions_sample.ndjson` (add a `pub_datacion`)
- Test: `test/emothe/import/filemaker_test.exs`

**Interfaces:**
- Produces: `build_version/1`'s map gains `composition_date_note` — the `<li>`s of `pub_datacion`, tags stripped, joined with `"; "`, or `nil`. This *outranks* the index header's note once Task 7 merges them, which is what makes the header a fallback rather than the answer.

- [ ] **Step 1: Add a `pub_datacion` to the versions fixture**

Read `test/fixtures/filemaker/versions_sample.ndjson` first to match its shape, then add to the EMOTHE0038 record's `fields`:

```json
"pub_datacion":["<ul><li>desde o posterior 1605 y anterior o hasta 1607</li>\n<li>1606</li></ul>"]
```

- [ ] **Step 2: Write the failing tests**

Add to `test/emothe/import/filemaker_test.exs` (in whichever describe block already loads `versions_sample.ndjson` — match its setup):

```elixir
  test "joins the competing datings into the note" do
    {:ok, versions} = Filemaker.load_versions("test/fixtures/filemaker/versions_sample.ndjson")

    assert versions["EMOTHE0038"].composition_date_note ==
             "desde o posterior 1605 y anterior o hasta 1607; 1606"
  end

  test "no pub_datacion means no note" do
    {:ok, versions} = Filemaker.load_versions("test/fixtures/filemaker/versions_sample.ndjson")

    assert versions["EMOTHE0052"].composition_date_note == nil
  end
```

Adjust `"EMOTHE0052"` to whatever second code that fixture actually holds.

- [ ] **Step 3: Run them and watch them fail**

Run: `mix test test/emothe/import/filemaker_test.exs`
Expected: FAIL — `KeyError` on `composition_date_note`.

- [ ] **Step 4: Implement it**

Rename `@first_item` to `@list_item` — the same regex now serves both a `Regex.run` (first `<li>`, historical time) and a `Regex.scan` (all `<li>`s, datings). Update the one existing use in `historical_time_note/1`.

```elixir
  # <li>Antigüedad clásica<br/>Note: First century BC.…</li> — one item of a rendered
  # list. Used with Regex.run for the first item and Regex.scan for all of them.
  @list_item ~r|<li>(.*?)</li>|s
```

Add to `build_version/1`:

```elixir
      composition_date_note: composition_date_note(fields)
```

and:

```elixir
  # Every <li> is a *competing* dating, unattributed. All of them verbatim, so a curator
  # reads the disagreement; the years come from the index header, which carries the
  # accepted dating rather than the union of the competing ones.
  defp composition_date_note(fields) do
    @list_item
    |> Regex.scan(field(fields, "pub_datacion"))
    |> Enum.map(fn [_all, item] -> strip_tags(item) end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("; ")
    |> case do
      "" -> nil
      note -> note
    end
  end
```

- [ ] **Step 5: Run the tests, then the suite**

Run: `mix test test/emothe/import/filemaker_test.exs` — Expected: PASS
Run: `mix format && mix compile --warnings-as-errors && mix test`

- [ ] **Step 6: Commit**

```bash
git add lib/emothe/import/filemaker.ex test/emothe/import/filemaker_test.exs test/fixtures/filemaker/versions_sample.ndjson
git commit -m "feat: the competing datings become the composition date note"
```

---

### Task 7: Sync — fill-only from both sources, plus a `:skipped` bucket

**Files:**
- Modify: `lib/emothe/import/filemaker_sync.ex` (`@curated` :31, `plan/3` :42-76, new `reject_blank/1` and `skipped_for/3`)
- Modify: `lib/mix/tasks/emothe.import.filemaker.ex` (`sync/4`)
- Modify: `lib/emothe_web/live/admin/filemaker_sync_live.ex` (the `#counts` card, ~:233-264)
- Test: `test/emothe/import/filemaker_sync_test.exs`, `test/emothe_web/live/admin/filemaker_sync_live_test.exs`

**Interfaces:**
- Consumes: Task 5's index keys and Task 6's version key.
- Produces: `plan/3` returns a fifth bucket, `skipped: [%{play_id, code, title, reason, value}]`. `apply_plan/2` ignores it — a skipped dating is never written and never tickable.

- [ ] **Step 1: Write the failing tests**

Extend the `index/0` and `versions/0` helpers at the top of `test/emothe/import/filemaker_sync_test.exs` — add to the `"EMOTHE0038"` index entry:

```elixir
        composition_date_from: 1606,
        composition_date_to: 1607,
        composition_date_note: "=1606 - =1607",
```

and to the `"EMOTHE0038"` versions entry:

```elixir
        composition_date_note: "desde o posterior 1605 y anterior o hasta 1607; 1606"
```

Then:

```elixir
  describe "composition date" do
    test "fills blank columns from the index, with T01's note winning" do
      original = play("EMOTHE0038_AntonyAndCleopatra", %{"language" => "en"})

      plan = FilemakerSync.plan(index(), [original], versions())

      assert [%{code: "EMOTHE0038", sets: sets}] = plan.changes
      assert sets.composition_date_from == 1606
      assert sets.composition_date_to == 1607
      assert sets.composition_date_note == "desde o posterior 1605 y anterior o hasta 1607; 1606"
    end

    test "falls back to the header note when T01 has none" do
      original = play("EMOTHE0038_AntonyAndCleopatra", %{"language" => "en"})

      plan = FilemakerSync.plan(index(), [original], %{})

      assert [%{sets: sets}] = plan.changes
      assert sets.composition_date_note == "=1606 - =1607"
    end

    test "a translation gets no dating" do
      original = play("EMOTHE0038_AntonyAndCleopatra", %{"language" => "en"})
      translation = play("EMOTHE0052_AntonioYCleopatra")

      plan = FilemakerSync.plan(index(), [original, translation], versions())

      change = Enum.find(plan.changes, &(&1.code == "EMOTHE0052"))
      refute Map.has_key?(change.sets, :composition_date_from)
    end

    test "a typed dating that disagrees is a conflict, not a write" do
      original =
        play("EMOTHE0038_AntonyAndCleopatra", %{
          "language" => "en",
          "composition_date_from" => 1600,
          "composition_date_to" => 1601
        })

      plan = FilemakerSync.plan(index(), [original], versions())

      assert Enum.any?(plan.conflicts, &(&1.field == :composition_date_from and &1.current == 1600))
      assert Enum.all?(plan.changes, &(not Map.has_key?(&1.sets, :composition_date_from)))
    end

    test "force writes the conflicting dating" do
      original =
        play("EMOTHE0038_AntonyAndCleopatra", %{
          "language" => "en",
          "composition_date_from" => 1600,
          "composition_date_to" => 1601
        })

      plan = FilemakerSync.plan(index(), [original], versions())
      assert [{:ok, "EMOTHE0038"}] = FilemakerSync.apply_plan(plan, force: true)

      assert Emothe.Catalogue.get_play!(original.id).composition_date_from == 1606
    end

    test "a skipped dating is reported and never written" do
      indexed =
        put_in(index()["EMOTHE0038"], %{
          index()["EMOTHE0038"]
          | composition_date_from: nil
        })

      indexed =
        Map.put(
          indexed,
          "EMOTHE0038",
          indexed["EMOTHE0038"]
          |> Map.drop([:composition_date_from, :composition_date_to, :composition_date_note])
          |> Map.put(:composition_date_skipped, {:span, "¿1694? y ¿1605?"})
        )

      original = play("EMOTHE0038_AntonyAndCleopatra", %{"language" => "en"})

      plan = FilemakerSync.plan(indexed, [original], %{})

      assert [%{code: "EMOTHE0038", reason: :span, value: "¿1694? y ¿1605?"}] = plan.skipped
      assert Enum.all?(plan.changes, &(not Map.has_key?(&1.sets, :composition_date_from)))
    end

    test "running twice changes nothing the second time" do
      original = play("EMOTHE0038_AntonyAndCleopatra", %{"language" => "en"})

      plan = FilemakerSync.plan(index(), [original], versions())
      FilemakerSync.apply_plan(plan)

      second = FilemakerSync.plan(index(), FilemakerSync.all_plays(), versions())

      assert second.changes == []
      assert second.conflicts == []
    end
  end
```

Simplify the `put_in`/`Map.put` gymnastics in the skipped test if a plain literal map reads better — the point is only that the index entry carries `composition_date_skipped` and no years.

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/emothe/import/filemaker_sync_test.exs -o "composition date"`
Expected: FAIL — `sets` has no `composition_date_from`, and `plan.skipped` raises `KeyError`.

- [ ] **Step 3: Implement it**

`@curated` becomes:

```elixir
  @curated [
    :historical_time,
    :historical_time_note,
    :composition_date_from,
    :composition_date_to,
    :composition_date_note
  ]

  # The columns of a dating the index carries but the version record does not.
  @index_curated [:composition_date_from, :composition_date_to, :composition_date_note]
```

Rewrite the body of `plan/3`'s reducer:

```elixir
    plays
    |> Enum.reduce(empty, fn play, acc ->
      code = base_code(play.code)
      indexed = Map.get(index, code, %{})

      # The two sources are independent. A play absent from the published index is
      # still reported as missing, but it can have a T01 research record — EMOTHE0341
      # does — and that fill must not be skipped.
      {derived, acc} =
        case Map.fetch(index, code) do
          :error -> {%{}, %{acc | missing: [code | acc.missing]}}
          {:ok, version} -> {changes_for(play, version, by_code), acc}
        end

      # The composition dating splits across both sources: the index header carries the
      # accepted years, T01 the competing datings. T01's note wins, but only when it has
      # one — a plain merge would let its nils erase the header fallback.
      curated =
        indexed
        |> Map.take(@index_curated)
        |> Map.merge(reject_blank(Map.get(versions, code, %{})))

      sets = Map.merge(derived, fills_for(play, curated))

      acc = %{
        acc
        | conflicts: conflicts_for(play, curated, code) ++ acc.conflicts,
          skipped: skipped_for(indexed, play, code) ++ acc.skipped
      }

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
```

with `empty` gaining the bucket:

```elixir
    empty = %{changes: [], unchanged: [], missing: [], conflicts: [], skipped: []}
```

(The trailing `Map.new(… Enum.reverse …)` already reverses every list-valued key, so `:skipped` needs nothing there.)

And:

```elixir
  # T01 supplies a note for a handful of plays and nil for the rest. Those nils must not
  # win the merge against the index header.
  defp reject_blank(curated) do
    Map.reject(curated, fn {_key, value} -> blank?(value) end)
  end

  # A dating the parse refused — too wide a span, or a header with no year. Its own
  # bucket rather than :conflicts, because a conflict is tickable in /admin/filemaker and
  # force-writing a bad span is exactly what the guard exists to prevent.
  defp skipped_for(%{composition_date_skipped: {reason, value}}, play, code) do
    [%{play_id: play.id, code: code, title: play.title, reason: reason, value: value}]
  end

  defp skipped_for(_indexed, _play, _code), do: []
```

Add `:skipped` to the moduledoc's description of the buckets.

- [ ] **Step 4: Run the tests**

Run: `mix test test/emothe/import/filemaker_sync_test.exs` — Expected: PASS

- [ ] **Step 5: Report the bucket in the mix task**

In `lib/mix/tasks/emothe.import.filemaker.ex`, after the conflicts loop:

```elixir
    Enum.each(plan.skipped, fn skipped ->
      Mix.shell().info(
        "#{skipped.code}  #{skipped.title}\n" <>
          "    dating not imported (#{skipped.reason}): #{inspect(skipped.value)}"
      )
    end)
```

and extend the summary line with `#{length(plan.skipped)} dating(s) skipped`.

- [ ] **Step 6: Show it on the admin page**

In `lib/emothe_web/live/admin/filemaker_sync_live.ex`, widen the `#counts` card's condition to include `or @plan.skipped != []` and add a third `<details>` beside `#unchanged` and `#missing`:

```heex
          <details :if={@plan.skipped != []} id="skipped">
            <summary class="cursor-pointer text-sm">
              {gettext("%{count} dating(s) not imported", count: length(@plan.skipped))}
            </summary>
            <p class="mt-2 text-xs text-base-content/70">
              {gettext(
                "The export gives no usable years for these — an implausible span, or a header with no date in it. Nothing is written and there is nothing to tick: enter the dating by hand if you have it."
              )}
            </p>
            <ul class="mt-1 space-y-1 font-mono text-xs text-base-content/70">
              <li :for={skipped <- @plan.skipped}>{skipped.code}: {skipped.value}</li>
            </ul>
          </details>
```

- [ ] **Step 7: Test the admin page**

Add to `test/emothe_web/live/admin/filemaker_sync_live_test.exs`, following the file's existing upload-and-preview pattern:

```elixir
  test "lists datings the parse refused", %{conn: conn} do
    # upload an export whose header dating is a bare "=", then:
    assert html =~ "not imported"
  end
```

Read the existing tests first to see how they feed an NDJSON upload; reuse that helper and add a small fixture under `test/fixtures/filemaker/` if one is needed.

- [ ] **Step 8: Run the suite**

Run: `mix format && mix compile --warnings-as-errors && mix test`

- [ ] **Step 9: Commit**

```bash
git add lib/emothe/import/filemaker_sync.ex lib/mix/tasks/emothe.import.filemaker.ex lib/emothe_web/live/admin/filemaker_sync_live.ex test/emothe/import/filemaker_sync_test.exs test/emothe_web/live/admin/filemaker_sync_live_test.exs
git commit -m "feat: sync the composition date fill-only, and report what it skips"
```

---

### Task 8: Admin form

**Files:**
- Modify: `lib/emothe_web/live/admin/play_form_live.ex` (Research Metadata fieldset, after the Historical Time Note block at ~:710-720)
- Test: `test/emothe_web/live/admin/play_form_live_test.exs`

**Interfaces:**
- Consumes: Task 1's cast list, via `Catalogue.change_play_form/2`.

- [ ] **Step 1: Write the failing tests**

Following the file's existing form-submission pattern:

```elixir
  test "saves a composition date", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/plays/new")

    view
    |> form("#play-form", play: %{...existing required fields...,
         composition_date_from: "1606",
         composition_date_to: "1607",
         composition_date_note: "1606; 1607"
       })
    |> render_submit()

    play = Emothe.Catalogue.get_play_by_code!("...")
    assert play.composition_date_from == 1606
    assert play.composition_date_note == "1606; 1607"
  end

  test "rejects a lone start year", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/plays/new")

    html =
      view
      |> form("#play-form", play: %{...existing required fields..., composition_date_from: "1606"})
      |> render_submit()

    assert html =~ "must be given together with the end year"
  end
```

Copy the required-field map and the form selector from a passing test in the same file — do not invent them.

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/emothe_web/live/admin/play_form_live_test.exs`
Expected: FAIL — the inputs do not exist, so the params are dropped and `composition_date_from` is `nil`.

- [ ] **Step 3: Add the inputs**

Inside the Research Metadata fieldset, after the Historical Time Note `<div>`:

```heex
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Composition Date")}</span>
            </label>
            <div class="flex items-center gap-2">
              <.input
                field={@form[:composition_date_from]}
                type="number"
                placeholder={gettext("From")}
              />
              <span class="text-base-content/50">–</span>
              <.input
                field={@form[:composition_date_to]}
                type="number"
                placeholder={gettext("To")}
              />
            </div>
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Composition Date Note")}</span>
            </label>
            <.input
              field={@form[:composition_date_note]}
              type="textarea"
              placeholder={gettext("Competing datings, and the evidence for each")}
            />
          </div>
```

No `PlayLabels` entry — unlike `historical_time` there is no vocabulary here.

- [ ] **Step 4: Run the tests, then the suite**

Run: `mix test test/emothe_web/live/admin/play_form_live_test.exs` — Expected: PASS
Run: `mix format && mix compile --warnings-as-errors && mix test`

- [ ] **Step 5: Commit**

```bash
git add lib/emothe_web/live/admin/play_form_live.ex test/emothe_web/live/admin/play_form_live_test.exs
git commit -m "feat: edit the composition date in the play form"
```

---

### Task 9: Public page

**Files:**
- Modify: `lib/emothe_web/live/play_show_live.ex` (`#meta-study` at :330-344, `build_sections/1` at :428)
- Test: `test/emothe_web/live/play_show_live_test.exs`

**Interfaces:**
- Consumes: Task 1's columns.
- Produces: a `Composition` row in `#meta-study`, and the Study sidebar entry appears for a play that has a dating but no historical time.

- [ ] **Step 1: Write the failing tests**

```elixir
  test "shows the composition date range", %{conn: conn} do
    play =
      play_fixture(%{
        "code" => "CDPUB1",
        "composition_date_from" => 1606,
        "composition_date_to" => 1607,
        "composition_date_note" => "1606; 1607"
      })

    {:ok, _view, html} = live(conn, ~p"/plays/#{play.code}")

    assert html =~ "1606–1607"
    assert html =~ "1606; 1607"
  end

  test "collapses a single year", %{conn: conn} do
    play =
      play_fixture(%{
        "code" => "CDPUB2",
        "composition_date_from" => 1614,
        "composition_date_to" => 1614
      })

    {:ok, _view, html} = live(conn, ~p"/plays/#{play.code}")

    assert html =~ "1614"
    refute html =~ "1614–1614"
  end

  test "the study section appears for a dating alone", %{conn: conn} do
    play =
      play_fixture(%{
        "code" => "CDPUB3",
        "composition_date_from" => 1614,
        "composition_date_to" => 1614
      })

    {:ok, _view, html} = live(conn, ~p"/plays/#{play.code}")

    assert html =~ ~s(id="meta-study")
  end
```

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/emothe_web/live/play_show_live_test.exs`
Expected: FAIL — no `1606–1607` in the markup, and `#meta-study` is absent when `historical_time` is nil.

- [ ] **Step 3: Add the row**

Widen the section's `:if` and make each `<dt>`/`<dd>` pair conditional:

```heex
          <section
            :if={@play.historical_time || @play.composition_date_from}
            id="meta-study"
            class="mb-8 max-w-2xl mx-auto scroll-mt-20 text-sm"
          >
            <dl class="grid grid-cols-[max-content_1fr] gap-x-4 gap-y-1">
              <dt :if={@play.historical_time} class="text-base-content/50">
                {gettext("Historical time")}
              </dt>
              <dd :if={@play.historical_time}>
                {PlayLabels.historical_time_label(@play.historical_time)}
                <p :if={@play.historical_time_note} class="mt-1 text-xs text-base-content/60">
                  {@play.historical_time_note}
                </p>
              </dd>

              <dt :if={@play.composition_date_from} class="text-base-content/50">
                {gettext("Composition")}
              </dt>
              <dd :if={@play.composition_date_from}>
                {composition_date(@play)}
                <p :if={@play.composition_date_note} class="mt-1 text-xs text-base-content/60">
                  {@play.composition_date_note}
                </p>
              </dd>
            </dl>
          </section>
```

with the helper beside `sorted_places/1`:

```elixir
  # An en dash, collapsing when the dating is a single year.
  defp composition_date(%{composition_date_from: from, composition_date_to: to}) when from == to,
    do: to_string(from)

  defp composition_date(%{composition_date_from: from, composition_date_to: to}),
    do: "#{from}–#{to}"
```

And in `build_sections/1`:

```elixir
    |> maybe_add_section(
      play.historical_time != nil or play.composition_date_from != nil,
      "meta-study",
      gettext("Study")
    )
```

- [ ] **Step 4: Run the tests, then the suite**

Run: `mix test test/emothe_web/live/play_show_live_test.exs` — Expected: PASS
Run: `mix format && mix compile --warnings-as-errors && mix test`

- [ ] **Step 5: Commit**

```bash
git add lib/emothe_web/live/play_show_live.ex test/emothe_web/live/play_show_live_test.exs
git commit -m "feat: show the composition date on the public play page"
```

---

### Task 10: Spanish translations, and a green suite

**Files:**
- Modify: `priv/gettext/es/LC_MESSAGES/default.po`, `priv/gettext/en/LC_MESSAGES/default.po`

- [ ] **Step 1: Extract**

Run: `mix gettext.extract --merge`

**Check every entry it marks `#, fuzzy`** — it fuzzy-matches new strings onto unrelated existing translations (see `CLAUDE.md`). Remove the flag only after confirming the translation, and fix the ones it got wrong.

- [ ] **Step 2: Translate**

New strings and their Spanish:

| msgid | msgstr |
|---|---|
| `Composition Date` | `Datación` |
| `Composition Date Note` | `Nota sobre la datación` |
| `Composition` | `Datación` |
| `From` | `Desde` |
| `To` | `Hasta` |
| `Competing datings, and the evidence for each` | `Dataciones propuestas y la evidencia de cada una` |
| `%{count} dating(s) not imported` | `%{count} datación(es) no importada(s)` |
| `The export gives no usable years for these — an implausible span, or a header with no date in it. Nothing is written and there is nothing to tick: enter the dating by hand if you have it.` | `La exportación no aporta años utilizables: un intervalo inverosímil, o un encabezado sin fecha. No se escribe nada y no hay nada que marcar: introduzca la datación a mano si la tiene.` |

`Datación` is what the old system's search page calls this field, so it is the term the researchers already use.

- [ ] **Step 3: Verify nothing is missing**

Run the manual check from `CLAUDE.md`:

```bash
grep -rho 'gettext("[^"]*")' lib/ | sed 's/.*gettext("\(.*\)")/\1/' | sort -u > /tmp/code_strings.txt
grep '^msgid ' priv/gettext/es/LC_MESSAGES/default.po | sed 's/msgid "\(.*\)"/\1/' | sort -u > /tmp/po_strings.txt
comm -23 /tmp/code_strings.txt /tmp/po_strings.txt
```

Expected: no new S2c strings in the output.

- [ ] **Step 4: Full verification**

Run: `mix format`
Run: `mix compile --warnings-as-errors`
Run: `mix test`
Run: `mix test --include slow` (the RelaxNG validation — ~15s per test)

Paste all four outputs. Nothing is "done" without them.

- [ ] **Step 5: Commit**

```bash
git add priv/gettext
git commit -m "i18n: Spanish for the composition date"
```

---

### Task 11: Apply it to `emothe_dev`, and record what it did

**Files:**
- Modify: `CLAUDE.md`, `docs/superpowers/plans/2026-08-01-filemaker-import-slices.md`

- [ ] **Step 1: Dry run**

Run: `mix emothe.import.filemaker --dry-run`

Read the output. Expect roughly: **7 plays gaining a dating** (6 from the index header — EMOTHE0010, 0038, 0281, 0337, 0346, 0777 — plus EMOTHE0341 note-only from `pub_datacion`), zero conflicts on a fresh database, and every `AL####` under "not in the index".

If the numbers differ materially from that, stop and report rather than applying — the spec's measurements are the specification here.

- [ ] **Step 2: Apply**

Run: `mix emothe.import.filemaker`

Record the actual counts.

- [ ] **Step 3: Look at it**

Run: `mix phx.server`, then visit `/plays/EMOTHE0038_AntonyAndCleopatra` (use the real code from the dry-run output) and confirm the Study section shows `1606–1607` with the note beneath, and `/admin/plays/<id>/edit` shows the same values in the Research Metadata fieldset.

Also download the TEI from `/admin/plays/<id>/export/tei` and confirm `<creation><date notBefore="1606" notAfter="1607">` is in the header.

- [ ] **Step 4: Update the docs**

In `CLAUDE.md`:
- add the three columns to the `plays` description and to the "Archiving and provenance" note about `@platform_owned`
- add an S2c line to "What Has Been Implemented", with the applied counts from Step 2
- add `<creation>` to the TEI-XML Format mapping list

In `docs/superpowers/plans/2026-08-01-filemaker-import-slices.md`:
- the slice table: S2c → **done**
- the S2 sub-slice table: S2c row → done, with the spec path
- open question 2 (per-dating attribution): note that S2c shipped without it and why, and that it now applies to a future source rather than this one
- the "Why the index is the from/to source" finding and the head-only rule are worth one line each in the roadmap, since S7 will re-read the same header

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md docs/superpowers/plans/2026-08-01-filemaker-import-slices.md docs/superpowers/specs/2026-08-05-s2c-composition-date-design.md
git commit -m "docs: S2c composition date shipped"
```

---

## Verification

End-to-end, after every task is done:

1. `mix test` — whole suite green, including `roundtrip_test.exs` over the real fixture corpus.
2. `mix test --include slow` — the exported TEI validates against the bundled TEI P5 RelaxNG schema.
3. `mix emothe.import.filemaker --dry-run` — 7 plays gain a dating, no conflicts on a fresh database, `AL####` reported as not in the index.
4. Re-run it: the second report is all `unchanged` (idempotence).
5. `mix emothe.import.tei --force` after the sync — the datings survive (this is what `@platform_owned` buys, and Task 2's test asserts it in miniature).
6. `/plays/<code>` shows the Study row; `/admin/plays/<id>/edit` round-trips it through the form; `/admin/plays/<id>/export/tei` carries `<creation>`.
7. `/admin/filemaker` — upload `doc/w3emothe_T01_tituloEM.ndjson`, confirm the preview lists the datings under changes and any refused ones under the new read-only "not imported" block.

## Self-review notes

Spec coverage: schema → Task 1; `@platform_owned` → Task 2; TEI export → Task 3; TEI import + round-trip → Task 4; index parse, head-only rule, span guard, unparseable → Task 5; note from `pub_datacion` → Task 6; fill-only sync, conflicts, force, idempotence, reporting → Task 7; admin → Task 8; public page → Task 9; i18n → Task 10; apply + docs → Task 11.

Two deliberate deviations from the spec, both flagged in place:

1. **Task 4** drops a lone `notBefore`/`notAfter` instead of storing "whichever are present" — Task 1's changeset forbids half a range, and mirroring the year would invent precision.
2. **Task 7** puts refused datings in a new `:skipped` bucket rather than `:conflicts`. The spec asks for both "reported as a conflict" and "never written", and those contradict each other: `/admin/filemaker` renders every conflict as a tickable checkbox whose tick force-writes `conflict.indexed`. A separate read-only bucket is the only shape that reports without offering to write.
