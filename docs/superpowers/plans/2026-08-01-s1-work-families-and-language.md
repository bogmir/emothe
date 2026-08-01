# S1 — Work Families & Language Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import the 82 local TEI files, then set each play's `language`, `relationship_type` and
`parent_play_id` from the FileMaker published index instead of guessing them from the TEI header.

**Architecture:** Two new modules. `Emothe.Import.TeiCorpus` walks `test/fixtures` and feeds files
to the existing `Emothe.Import.TeiParser`, deduplicating by play code. `Emothe.Import.Filemaker`
reads the NDJSON export and turns `T00_indiceEM.pub_listaObras` into a `%{code => version}` map —
pure functions, no database. `Emothe.Import.FilemakerSync` diffs that map against the plays in the
database and produces a change list; applying it is a separate call, so `--dry-run` is the same
code path minus the write. Two mix tasks wrap them. No schema migration: every column this slice
writes already exists.

**Tech Stack:** Elixir 1.19.5 / OTP 28.1, Phoenix 1.8.3, Ecto + PostgreSQL, Jason (already a
dependency) for NDJSON, `Regex` for the index HTML. **Do not add an HTML-parsing dependency** —
the markup is machine-generated and fixed.

## Global Constraints

- Run every command with the project PATH first:
  `export PATH="/home/bogdan/.asdf/installs/erlang/28.1/bin:/home/bogdan/.asdf/installs/elixir/1.19.5-otp-28/bin:/usr/bin:/usr/local/bin:/bin:$PATH"`
  The asdf shims do not work in this sandbox.
- `plays.code` is the full filename stem (`EMOTHE0010_TheTragedyOfHamletPrinceOfDenmark`). The
  FileMaker code is its leading token. Always compare on `String.split(code, "_") |> List.first()`.
- Codes are **not** all `EMOTHE####` — 27 published versions are `HIE####`. Never build a code by
  formatting a number; always read it out of the link.
- Never create a play. An index entry with no matching play is reported and skipped.
- Never fail on Artelope: `AL####` codes are absent from the export and must be reported as
  "not in index", not as an error.
- Every database write is logged through `Emothe.ActivityLog` with `action: "update"` — the
  allowed actions are `create update delete import export role_change`, do not add a new one.
- Do not touch `is_complete`, `title`, `author_name` or `original_title` in this slice.
- The source file is `doc/w3emothe_T01_tituloEM.ndjson`. It is not in git (the `doc/` directory is
  ignored), so tests must use their own fixture, never the real export.
- `mix format` after each task; the repo is formatted.

---

### Task 1: Corpus baseline — import the local TEI files

Today the database has 8 plays and the corpus has 82 files. Every later step needs rows to attach
to. The admin UI at `/admin/plays/import` can already import a directory one file at a time; this
task gives the same thing a mix task, deduplicated, so it can be re-run.

**Files:**
- Create: `lib/emothe/import/tei_corpus.ex`
- Create: `lib/mix/tasks/emothe.import.tei.ex`
- Test: `test/emothe/import/tei_corpus_test.exs`

**Interfaces:**
- Consumes: `Emothe.Import.TeiParser.import_file/1` → `{:ok, %Play{}}` | `{:error, reason}`
- Produces:
  - `Emothe.Import.TeiCorpus.collect_files(dirs :: [String.t()]) :: [{code :: String.t(), path :: String.t()}]`
    sorted by code, one entry per code, first directory wins
  - `Emothe.Import.TeiCorpus.import_all(files :: [{String.t(), String.t()}], opts :: keyword()) :: [result]`
    where `result` is `{:ok, code, %Play{}}` | `{:skipped, code}` | `{:error, code, term()}`;
    option `:force` (default `false`) re-imports codes already in the database
  - `Emothe.Import.TeiCorpus.base_code(code :: String.t()) :: String.t()`

- [ ] **Step 1: Write the failing test for file collection**

Create `test/emothe/import/tei_corpus_test.exs`:

```elixir
defmodule Emothe.Import.TeiCorpusTest do
  use Emothe.DataCase, async: true

  alias Emothe.Import.TeiCorpus

  defp tmp_dir(name) do
    dir = Path.join(System.tmp_dir!(), "corpus-#{name}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  describe "base_code/1" do
    test "takes the leading token of a filename stem" do
      assert TeiCorpus.base_code("EMOTHE0010_TheTragedyOfHamletPrinceOfDenmark") == "EMOTHE0010"
      assert TeiCorpus.base_code("AL0514") == "AL0514"
    end
  end

  describe "collect_files/1" do
    test "returns one path per code, sorted, with the first directory winning" do
      first = tmp_dir("first")
      second = tmp_dir("second")

      File.write!(Path.join(first, "EMOTHE0038_AntonyAndCleopatra.xml"), "<TEI/>")
      File.write!(Path.join(second, "EMOTHE0038_AntonyAndCleopatra.xml"), "<TEI/>")
      File.write!(Path.join(second, "AL0514_ElAusenteEnElLugar.xml"), "<TEI/>")

      assert [{"AL0514", al_path}, {"EMOTHE0038", emothe_path}] =
               TeiCorpus.collect_files([first, second])

      assert al_path == Path.join(second, "AL0514_ElAusenteEnElLugar.xml")
      assert emothe_path == Path.join(first, "EMOTHE0038_AntonyAndCleopatra.xml")
    end

    test "ignores non-xml files and missing directories" do
      dir = tmp_dir("mixed")
      File.write!(Path.join(dir, "notes.txt"), "hello")
      File.write!(Path.join(dir, "EMOTHE0050_Amleto.xml"), "<TEI/>")

      assert [{"EMOTHE0050", _}] = TeiCorpus.collect_files([dir, "/nonexistent/path"])
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
mix test test/emothe/import/tei_corpus_test.exs
```

Expected: FAIL with `** (UndefinedFunctionError) function Emothe.Import.TeiCorpus.base_code/1 is undefined (module Emothe.Import.TeiCorpus is not available)`.

- [ ] **Step 3: Write the implementation**

Create `lib/emothe/import/tei_corpus.ex`:

```elixir
defmodule Emothe.Import.TeiCorpus do
  @moduledoc """
  Bulk-imports the TEI files we hold locally, one per play code.

  The same file often exists in more than one fixture directory; `collect_files/1`
  keeps the first one it sees for each code so a re-run stays idempotent.
  """

  import Ecto.Query

  alias Emothe.Catalogue.Play
  alias Emothe.Import.TeiParser
  alias Emothe.Repo

  require Logger

  @default_dirs ["test/fixtures", "test/fixtures/tei_files"]

  def default_dirs, do: @default_dirs

  @doc "The FileMaker code hiding at the front of a play code or filename stem."
  def base_code(code), do: code |> String.split("_") |> List.first()

  @doc "Every .xml file under the given directories, one per code, sorted by code."
  def collect_files(dirs) do
    dirs
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.xml")))
    |> Enum.reduce(%{}, fn path, acc ->
      Map.put_new(acc, path |> Path.basename(".xml") |> base_code(), path)
    end)
    |> Enum.sort()
  end

  @doc """
  Imports each file. Codes already in the database are skipped unless `force: true`.
  """
  def import_all(files, opts \\ []) do
    force = Keyword.get(opts, :force, false)
    existing = existing_codes()

    Enum.map(files, fn {code, path} ->
      if not force and MapSet.member?(existing, code) do
        {:skipped, code}
      else
        case TeiParser.import_file(path) do
          {:ok, play} ->
            {:ok, code, play}

          {:error, reason} ->
            Logger.warning("TEI import failed for #{code}: #{inspect(reason)}")
            {:error, code, reason}
        end
      end
    end)
  end

  defp existing_codes do
    Play
    |> select([p], p.code)
    |> Repo.all()
    |> Enum.map(&base_code/1)
    |> MapSet.new()
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
mix test test/emothe/import/tei_corpus_test.exs
```

Expected: PASS, 3 tests.

- [ ] **Step 5: Write the failing test for import_all**

Append to `test/emothe/import/tei_corpus_test.exs`, inside the module:

```elixir
  describe "import_all/2" do
    @minimal_tei """
    <?xml version="1.0" encoding="UTF-8"?>
    <TEI>
      <teiHeader>
        <fileDesc>
          <titleStmt>
            <title key="archivo">EMOTHE9001_TestPlay</title>
            <title>Test Play</title>
          </titleStmt>
          <publicationStmt><idno>EMOTHE9001</idno></publicationStmt>
        </fileDesc>
      </teiHeader>
      <text><front></front><body></body></text>
    </TEI>
    """

    test "imports a file once and skips it on a second run" do
      dir = tmp_dir("import")
      File.write!(Path.join(dir, "EMOTHE9001_TestPlay.xml"), @minimal_tei)
      files = TeiCorpus.collect_files([dir])

      assert [{:ok, "EMOTHE9001", play}] = TeiCorpus.import_all(files)
      assert play.code == "EMOTHE9001_TestPlay"

      assert [{:skipped, "EMOTHE9001"}] = TeiCorpus.import_all(files)
    end
  end
```

- [ ] **Step 6: Run the test to verify it passes**

The implementation from Step 3 already covers this — it is a behaviour check on code written for
the previous test, so it should pass without new code.

```bash
mix test test/emothe/import/tei_corpus_test.exs
```

Expected: PASS, 4 tests. If the first assertion fails on `play.code`, read
`lib/emothe/import/tei_parser.ex:190` — the code comes from `<title key="archivo">`.

- [ ] **Step 7: Add the mix task**

Create `lib/mix/tasks/emothe.import.tei.ex`:

```elixir
defmodule Mix.Tasks.Emothe.Import.Tei do
  @shortdoc "Import the local TEI corpus into the database"

  @moduledoc """
  Imports every .xml file under the fixture directories, one play per code.

      mix emothe.import.tei                  # skip codes already imported
      mix emothe.import.tei --force          # re-import everything
      mix emothe.import.tei --dir some/path  # use another directory (repeatable)
  """

  use Mix.Task

  alias Emothe.Import.TeiCorpus

  @switches [force: :boolean, dir: :keep]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    Mix.Task.run("app.start")

    dirs =
      case Keyword.get_values(opts, :dir) do
        [] -> TeiCorpus.default_dirs()
        dirs -> dirs
      end

    files = TeiCorpus.collect_files(dirs)
    Mix.shell().info("#{length(files)} file(s) in #{Enum.join(dirs, ", ")}")

    results = TeiCorpus.import_all(files, force: opts[:force] || false)

    imported = Enum.count(results, &match?({:ok, _, _}, &1))
    skipped = Enum.count(results, &match?({:skipped, _}, &1))
    failed = for {:error, code, reason} <- results, do: {code, reason}

    Enum.each(failed, fn {code, reason} ->
      Mix.shell().error("  #{code}: #{inspect(reason)}")
    end)

    Mix.shell().info("imported #{imported}, skipped #{skipped}, failed #{length(failed)}")
  end
end
```

- [ ] **Step 8: Run it against the real corpus**

```bash
mix emothe.import.tei
```

Expected: `82 file(s) in test/fixtures, test/fixtures/tei_files` and a summary line. The 8 plays
already present are skipped. Any file that fails to parse is printed with its reason — record the
list in the commit message, do not fix parser bugs in this task.

- [ ] **Step 9: Commit**

```bash
mix format
git add lib/emothe/import/tei_corpus.ex lib/mix/tasks/emothe.import.tei.ex test/emothe/import/tei_corpus_test.exs
git commit -m "feat: mix task to bulk-import the local TEI corpus"
```

---

### Task 2: Read the FileMaker published index

**Files:**
- Create: `lib/emothe/import/filemaker.ex`
- Create: `test/fixtures/filemaker/index_sample.ndjson`
- Test: `test/emothe/import/filemaker_test.exs`

**Interfaces:**
- Produces: `Emothe.Import.Filemaker.load_index(path :: String.t()) :: {:ok, index} | {:error, term()}`
  where `index :: %{required(String.t()) => version}` and

  ```elixir
  version :: %{
    code: String.t(),        # "EMOTHE0052"
    lang: String.t(),        # "es" | "en" | "fr" | "it" | "pt" | ""
    title: String.t(),       # "ANTONIO Y CLEOPATRA" (upper-cased in the source)
    credit: String.t(),      # "Miguel Teruel Pozas, tra."
    role: :editor | :translator | nil,
    work: String.t(),        # "24" — the _IdIndiceCtce work id
    xml: String.t(),         # "textosXML/EMOTHE0052_AntonioYCleopatra.xml"
    family: [%{code: String.t(), role: :editor | :translator | nil}]
  }
  ```
- Produces: `Emothe.Import.Filemaker.default_path() :: String.t()`

- [ ] **Step 1: Create the test fixture**

Create `test/fixtures/filemaker/index_sample.ndjson`. Three lines, mirroring the real export's
shape (envelope line, then one record per work; every field value is a one-element array):

```
{"_meta":{"layout":"T00_indiceEM","database":"w3emothe","found_count":"2","table_count":"2","batch":200}}
{"record_id":"72","mod_id":"80","fields":{"_kp_IdIndiceEM":["72"],"_IdIndiceCtce":["24"],"bus_autor":["Shakespeare, William"],"pub_tituloOrden":["Antony and Cleopatra"],"bus_paralelo":["1"],"pub_listaObras":["<div><i>ANTONY AND CLEOPATRA</i>. William Shakespeare</div>\n<ul>\n<li><span style=\"font-size: x-small\">[EN] </span><a href=\"textosEMOTHE/EMOTHE0038_AntonyAndCleopatra.php\" target=\"_blank\"><i>ANTONY AND CLEOPATRA</i></a><span style=\"font-size: x-small;margin-left: 25px;\">Barbara Mowat and Paul Werstine, ed.</span><span style=\"font-size: x-small;margin-left: 25px;\"><a href=\"textosXML/EMOTHE0038_AntonyAndCleopatra.xml\" download=\"EMOTHE0038_AntonyAndCleopatra.xml\">[xml]</a></span></li>\n<li><span style=\"font-size: x-small\">[ES] </span><a href=\"textosEMOTHE/EMOTHE0052_AntonioYCleopatra.php\" target=\"_blank\"><i>ANTONIO Y CLEOPATRA</i></a><span style=\"font-size: x-small;margin-left: 25px;\">Miguel Teruel Pozas, tra.</span><span style=\"font-size: x-small;margin-left: 25px;\"><a href=\"textosXML/EMOTHE0052_AntonioYCleopatra.xml\" download=\"EMOTHE0052_AntonioYCleopatra.xml\">[xml]</a></span></li>\n</ul>"]}}
{"record_id":"90","mod_id":"12","fields":{"_kp_IdIndiceEM":["90"],"_IdIndiceCtce":["393"],"bus_autor":["Rojas, Fernando de"],"pub_tituloOrden":["Spanish Bawd"],"bus_paralelo":[""],"pub_listaObras":["<ul>\n<li><span style=\"font-size: x-small\">[EN] </span><a href=\"textosEMOTHE/HIE0393_TheSpanishBawd.php\" target=\"_blank\"><i>THE SPANISH BAWD</i></a><span style=\"font-size: x-small;margin-left: 25px;\">James Mabbe, tra.</span><span style=\"font-size: x-small;margin-left: 25px;\"><a href=\"textosXML/HIE0393_TheSpanishBawd.xml\" download=\"HIE0393_TheSpanishBawd.xml\">[xml]</a></span></li>\n</ul>"]}}
```

- [ ] **Step 2: Write the failing test**

Create `test/emothe/import/filemaker_test.exs`:

```elixir
defmodule Emothe.Import.FilemakerTest do
  use ExUnit.Case, async: true

  alias Emothe.Import.Filemaker

  @sample "test/fixtures/filemaker/index_sample.ndjson"

  setup do
    {:ok, index} = Filemaker.load_index(@sample)
    %{index: index}
  end

  test "indexes every published version by code", %{index: index} do
    assert Map.keys(index) |> Enum.sort() == ["EMOTHE0038", "EMOTHE0052", "HIE0393"]
  end

  test "reads the language tag", %{index: index} do
    assert index["EMOTHE0038"].lang == "en"
    assert index["EMOTHE0052"].lang == "es"
  end

  test "reads the credit and its role", %{index: index} do
    assert index["EMOTHE0038"].credit == "Barbara Mowat and Paul Werstine, ed."
    assert index["EMOTHE0038"].role == :editor
    assert index["EMOTHE0052"].credit == "Miguel Teruel Pozas, tra."
    assert index["EMOTHE0052"].role == :translator
  end

  test "strips markup from the title", %{index: index} do
    assert index["EMOTHE0052"].title == "ANTONIO Y CLEOPATRA"
  end

  test "keeps the work id and the TEI download path", %{index: index} do
    assert index["EMOTHE0052"].work == "24"
    assert index["EMOTHE0052"].xml == "textosXML/EMOTHE0052_AntonioYCleopatra.xml"
  end

  test "every version knows its whole family", %{index: index} do
    assert Enum.map(index["EMOTHE0052"].family, & &1.code) == ["EMOTHE0038", "EMOTHE0052"]
    assert Enum.map(index["EMOTHE0038"].family, & &1.role) == [:editor, :translator]
  end

  test "handles non-EMOTHE code prefixes", %{index: index} do
    assert index["HIE0393"].code == "HIE0393"
    assert index["HIE0393"].role == :translator
  end

  test "returns an error for a missing file" do
    assert {:error, :enoent} = Filemaker.load_index("test/fixtures/filemaker/nope.ndjson")
  end
end
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
mix test test/emothe/import/filemaker_test.exs
```

Expected: FAIL — `Emothe.Import.Filemaker is not available`.

- [ ] **Step 4: Write the implementation**

Create `lib/emothe/import/filemaker.ex`:

```elixir
defmodule Emothe.Import.Filemaker do
  @moduledoc """
  Reads the FileMaker NDJSON export.

  The file holds two tables, each preceded by a `_meta` envelope line and followed by
  an `_end` line. Only `T00_indiceEM` — the published index — is read here: its
  `pub_listaObras` field is the rendered HTML of every published version of a work,
  and it is the authoritative source for a play's language, its family, and whether
  it is an original (credited `ed.`) or a translation (credited `tra.`).
  """

  @default_path "doc/w3emothe_T01_tituloEM.ndjson"
  @index_layout "T00_indiceEM"

  # <li>[EN] <a href="textosEMOTHE/CODE_File.php">TITLE</a> credit… [xml] </li>
  @version ~r{<li>(?:<span[^>]*>\[([A-Z]{2})\]\s*</span>)?\s*<a href="textosEMOTHE/([A-Za-z0-9]+)_([^"]*)\.php"[^>]*>(.*?)</a>(.*?)</li>}s

  @languages %{"ES" => "es", "EN" => "en", "FR" => "fr", "IT" => "it", "PT" => "pt"}

  def default_path, do: @default_path

  @doc """
  Returns `{:ok, %{code => version}}` for every published version in the index.
  """
  def load_index(path \\ @default_path) do
    with {:ok, body} <- File.read(path) do
      index =
        body
        |> String.split("\n", trim: true)
        |> Enum.reduce({nil, %{}}, &read_line/2)
        |> elem(1)

      {:ok, index}
    end
  end

  defp read_line(line, {layout, index}) do
    case Jason.decode(line) do
      {:ok, %{"_meta" => meta}} -> {meta["layout"], index}
      {:ok, %{"fields" => fields}} when layout == @index_layout -> {layout, add_work(index, fields)}
      _ -> {layout, index}
    end
  end

  defp add_work(index, fields) do
    work = field(fields, "_IdIndiceCtce")
    versions = parse_versions(field(fields, "pub_listaObras"), work)
    family = Enum.map(versions, &Map.take(&1, [:code, :role]))

    Enum.reduce(versions, index, fn version, acc ->
      Map.put(acc, version.code, Map.put(version, :family, family))
    end)
  end

  defp parse_versions(html, work) do
    @version
    |> Regex.scan(html)
    |> Enum.map(fn [_all, lang, code, file, title, rest] ->
      credit = rest |> strip_tags() |> String.replace("[xml]", "") |> String.trim()

      %{
        code: code,
        lang: Map.get(@languages, lang, ""),
        title: strip_tags(title),
        credit: credit,
        role: role(credit),
        work: work,
        xml: "textosXML/#{code}_#{file}.xml"
      }
    end)
  end

  defp role(credit) do
    cond do
      Regex.match?(~r{,\s*ed\.}, credit) -> :editor
      Regex.match?(~r{,\s*tra\.}, credit) -> :translator
      true -> nil
    end
  end

  defp strip_tags(html) do
    html
    |> String.replace(~r{<[^>]+>}, " ")
    |> String.replace(~r{\s+}, " ")
    |> String.trim()
  end

  defp field(fields, key) do
    case Map.get(fields, key) do
      list when is_list(list) -> list |> Enum.join("\n") |> String.trim()
      value when is_binary(value) -> String.trim(value)
      _ -> ""
    end
  end
end
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
mix test test/emothe/import/filemaker_test.exs
```

Expected: PASS, 8 tests. If `family` comes back empty, the `@version` regex did not match — print
`Regex.scan(@version, html)` in IEx against the fixture and compare against the `<li>` shape in the
fixture file.

- [ ] **Step 6: Commit**

```bash
mix format
git add lib/emothe/import/filemaker.ex test/emothe/import/filemaker_test.exs test/fixtures/filemaker/index_sample.ndjson
git commit -m "feat: parse the FileMaker published index"
```

---

### Task 3: Diff the index against the database

Pure function, no writes. This is what `--dry-run` prints and what the apply step consumes.

**Files:**
- Create: `lib/emothe/import/filemaker_sync.ex`
- Test: `test/emothe/import/filemaker_sync_test.exs`

**Interfaces:**
- Consumes: the `index` map from `Emothe.Import.Filemaker.load_index/1`
- Produces: `Emothe.Import.FilemakerSync.plan(index, plays :: [%Play{}]) :: plan` where

  ```elixir
  plan :: %{
    changes: [%{play_id: binary(), code: String.t(), title: String.t(), sets: map()}],
    unchanged: [String.t()],
    missing: [String.t()]        # codes with no entry in the index (all AL#### land here)
  }
  ```
  `sets` only ever contains the keys that actually change, drawn from
  `:language`, `:relationship_type`, `:parent_play_id`.

**Rules — implement exactly these:**

| Index says | We set |
|---|---|
| language tag `[EN]` etc. | `language`, if it differs and is one of `es en fr it pt` |
| credit ends `ed.` | `relationship_type: nil` — this is the family original |
| credit ends `tra.` | `relationship_type: "traduccion"` |
| no recognisable credit | leave `relationship_type` alone |
| family has an `ed.` version, and it is this play | `parent_play_id: nil` |
| family has an `ed.` version imported in our DB | `parent_play_id` = that play's id |
| family has an `ed.` version we have not imported | leave `parent_play_id` alone |
| code not in the index at all | report under `missing`, change nothing |

- [ ] **Step 1: Write the failing test**

Create `test/emothe/import/filemaker_sync_test.exs`:

```elixir
defmodule Emothe.Import.FilemakerSyncTest do
  use Emothe.DataCase, async: true

  import Emothe.TestFixtures

  alias Emothe.Import.FilemakerSync

  # Antony and Cleopatra: EN original + ES translation, as the real index has it.
  defp index do
    family = [%{code: "EMOTHE0038", role: :editor}, %{code: "EMOTHE0052", role: :translator}]

    %{
      "EMOTHE0038" => %{
        code: "EMOTHE0038", lang: "en", title: "ANTONY AND CLEOPATRA",
        credit: "Barbara Mowat and Paul Werstine, ed.", role: :editor,
        work: "24", xml: "textosXML/EMOTHE0038_AntonyAndCleopatra.xml", family: family
      },
      "EMOTHE0052" => %{
        code: "EMOTHE0052", lang: "es", title: "ANTONIO Y CLEOPATRA",
        credit: "Miguel Teruel Pozas, tra.", role: :translator,
        work: "24", xml: "textosXML/EMOTHE0052_AntonioYCleopatra.xml", family: family
      }
    }
  end

  defp play(code, attrs \\ %{}) do
    play_fixture(Map.merge(%{"code" => code, "language" => "es"}, attrs))
  end

  test "corrects the language of an original stored as Spanish" do
    original = play("EMOTHE0038_AntonyAndCleopatra")

    plan = FilemakerSync.plan(index(), [original])

    assert [%{code: "EMOTHE0038", sets: sets}] = plan.changes
    assert sets.language == "en"
    refute Map.has_key?(sets, :parent_play_id)
  end

  test "marks a translation and links it to the original in the database" do
    original = play("EMOTHE0038_AntonyAndCleopatra", %{"language" => "en"})
    translation = play("EMOTHE0052_AntonioYCleopatra")

    plan = FilemakerSync.plan(index(), [original, translation])

    assert [%{code: "EMOTHE0052", sets: sets}] = plan.changes
    assert sets.relationship_type == "traduccion"
    assert sets.parent_play_id == original.id
    assert plan.unchanged == ["EMOTHE0038"]
  end

  test "leaves parent_play_id alone when the original is not imported" do
    translation = play("EMOTHE0052_AntonioYCleopatra")

    plan = FilemakerSync.plan(index(), [translation])

    assert [%{sets: sets}] = plan.changes
    assert sets.relationship_type == "traduccion"
    refute Map.has_key?(sets, :parent_play_id)
  end

  test "clears a wrong relationship_type on an original" do
    original =
      play("EMOTHE0038_AntonyAndCleopatra", %{"language" => "en", "relationship_type" => "adaptacion"})

    plan = FilemakerSync.plan(index(), [original])

    assert [%{sets: %{relationship_type: nil}}] = plan.changes
  end

  test "reports codes that are not in the index instead of failing" do
    artelope = play("AL0514_ElAusenteEnElLugar")

    plan = FilemakerSync.plan(index(), [artelope])

    assert plan.missing == ["AL0514"]
    assert plan.changes == []
  end

  test "a second pass over an already-synced play changes nothing" do
    original = play("EMOTHE0038_AntonyAndCleopatra", %{"language" => "en"})

    translation =
      play("EMOTHE0052_AntonioYCleopatra", %{
        "language" => "es",
        "relationship_type" => "traduccion",
        "parent_play_id" => original.id
      })

    plan = FilemakerSync.plan(index(), [original, translation])

    assert plan.changes == []
    assert Enum.sort(plan.unchanged) == ["EMOTHE0038", "EMOTHE0052"]
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
mix test test/emothe/import/filemaker_sync_test.exs
```

Expected: FAIL — `Emothe.Import.FilemakerSync is not available`.

- [ ] **Step 3: Write the implementation**

Create `lib/emothe/import/filemaker_sync.ex`:

```elixir
defmodule Emothe.Import.FilemakerSync do
  @moduledoc """
  Applies the FileMaker published index to the plays we already have.

  `plan/2` is pure: it produces the list of changes without writing anything, so the
  mix task can print it for review. `apply_plan/2` performs the writes.

  Nothing here ever creates a play. Codes with no index entry — every Artelope play,
  and anything the project never published — come back under `:missing`.
  """

  import Ecto.Query

  alias Emothe.ActivityLog
  alias Emothe.Catalogue
  alias Emothe.Catalogue.Play
  alias Emothe.Repo

  @keep :keep
  @languages ~w(es en fr it pt)

  @doc "The FileMaker code hiding at the front of a play code."
  def base_code(code), do: code |> String.split("_") |> List.first()

  @doc "Every play in the database, for `plan/2`."
  def all_plays do
    Play |> order_by([p], p.code) |> Repo.all()
  end

  @doc "Diffs the index against the given plays. Writes nothing."
  def plan(index, plays) do
    by_code = Map.new(plays, &{base_code(&1.code), &1})

    plays
    |> Enum.reduce(%{changes: [], unchanged: [], missing: []}, fn play, acc ->
      code = base_code(play.code)

      case Map.fetch(index, code) do
        :error ->
          %{acc | missing: [code | acc.missing]}

        {:ok, version} ->
          case changes_for(play, version, by_code) do
            empty when map_size(empty) == 0 ->
              %{acc | unchanged: [code | acc.unchanged]}

            sets ->
              change = %{play_id: play.id, code: code, title: play.title, sets: sets}
              %{acc | changes: [change | acc.changes]}
          end
      end
    end)
    |> Map.new(fn {key, list} -> {key, Enum.reverse(list)} end)
  end

  defp changes_for(play, version, by_code) do
    %{
      language: language_for(version),
      relationship_type: relationship_for(version),
      parent_play_id: parent_for(version, by_code)
    }
    |> Enum.reject(fn {_key, value} -> value == @keep end)
    |> Enum.reject(fn {key, value} -> Map.get(play, key) == value end)
    |> Map.new()
  end

  defp language_for(%{lang: lang}) when lang in @languages, do: lang
  defp language_for(_version), do: @keep

  defp relationship_for(%{role: :editor}), do: nil
  defp relationship_for(%{role: :translator}), do: "traduccion"
  defp relationship_for(_version), do: @keep

  defp parent_for(version, by_code) do
    head = Enum.find(version.family, &(&1.role == :editor))

    cond do
      is_nil(head) ->
        @keep

      head.code == version.code ->
        nil

      true ->
        case Map.fetch(by_code, head.code) do
          {:ok, parent} -> parent.id
          :error -> @keep
        end
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
mix test test/emothe/import/filemaker_sync_test.exs
```

Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
mix format
git add lib/emothe/import/filemaker_sync.ex test/emothe/import/filemaker_sync_test.exs
git commit -m "feat: diff the FileMaker index against imported plays"
```

---

### Task 4: Apply the plan

**Files:**
- Modify: `lib/emothe/import/filemaker_sync.ex` (add `apply_plan/2`)
- Modify: `test/emothe/import/filemaker_sync_test.exs` (add an `apply_plan/2` describe block)

**Interfaces:**
- Consumes: the `plan` map from Task 3
- Produces: `Emothe.Import.FilemakerSync.apply_plan(plan, opts :: keyword()) :: [result]`
  where `result` is `{:ok, code}` | `{:error, code, %Ecto.Changeset{}}`; option `:user_id`
  (default `nil`) is attached to each activity-log entry

- [ ] **Step 1: Write the failing test**

Append to `test/emothe/import/filemaker_sync_test.exs`, inside the module:

```elixir
  describe "apply_plan/2" do
    test "writes the changes and logs one activity entry per play" do
      original = play("EMOTHE0038_AntonyAndCleopatra")
      translation = play("EMOTHE0052_AntonioYCleopatra")

      results =
        index()
        |> FilemakerSync.plan([original, translation])
        |> FilemakerSync.apply_plan()

      assert Enum.sort(results) == [{:ok, "EMOTHE0038"}, {:ok, "EMOTHE0052"}]

      assert Emothe.Catalogue.get_play!(original.id).language == "en"

      reloaded = Emothe.Catalogue.get_play!(translation.id)
      assert reloaded.relationship_type == "traduccion"
      assert reloaded.parent_play_id == original.id

      entries = Emothe.ActivityLog.list_entries(play_id: translation.id)
      assert [entry] = entries
      assert entry.action == "update"
      assert entry.metadata["source"] == "filemaker_index"
      assert entry.changes["relationship_type"] == "traduccion"
    end

    test "applying twice is a no-op the second time" do
      original = play("EMOTHE0038_AntonyAndCleopatra")
      index = index()

      index |> FilemakerSync.plan([original]) |> FilemakerSync.apply_plan()

      second = FilemakerSync.plan(index, [Emothe.Catalogue.get_play!(original.id)])
      assert second.changes == []
    end
  end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
mix test test/emothe/import/filemaker_sync_test.exs
```

Expected: FAIL — `function Emothe.Import.FilemakerSync.apply_plan/1 is undefined or private`.

- [ ] **Step 3: Write the implementation**

Add to `lib/emothe/import/filemaker_sync.ex`:

```elixir
  @doc """
  Writes every change in the plan and logs it. Returns one result per change.
  """
  def apply_plan(plan, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)

    Enum.map(plan.changes, fn change ->
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

  defp stringify(sets) do
    Map.new(sets, fn {key, value} -> {Atom.to_string(key), value} end)
  end
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
mix test test/emothe/import/filemaker_sync_test.exs
```

Expected: PASS, 8 tests.

If the activity-log assertion fails on `entry.changes["relationship_type"]`, check that
`stringify/1` ran — `activity_logs.changes` is a jsonb column and atom keys come back as strings
either way, but the UUID in `parent_play_id` must already be a binary string, which it is.

If `Catalogue.update_play/2` rejects `relationship_type: nil`, re-read
`lib/emothe/catalogue/play.ex:82` — `validate_inclusion/3` is skipped for `nil` changes, so a nil
must pass. A failure there means the changeset gained a `validate_required` since this plan was
written; fix the changeset, not the sync.

- [ ] **Step 5: Commit**

```bash
mix format
git add lib/emothe/import/filemaker_sync.ex test/emothe/import/filemaker_sync_test.exs
git commit -m "feat: apply FileMaker index changes with an activity log entry"
```

---

### Task 5: The mix task

**Files:**
- Create: `lib/mix/tasks/emothe.import.filemaker.ex`

**Interfaces:**
- Consumes: `Emothe.Import.Filemaker.load_index/1`, `Emothe.Import.FilemakerSync.all_plays/0`,
  `plan/2`, `apply_plan/2`

- [ ] **Step 1: Write the task**

Create `lib/mix/tasks/emothe.import.filemaker.ex`:

```elixir
defmodule Mix.Tasks.Emothe.Import.Filemaker do
  @shortdoc "Sync language, relationship and work family from the FileMaker index"

  @moduledoc """
  Reads the published index out of the FileMaker NDJSON export and applies it to the
  plays already in the database. Creates nothing.

      mix emothe.import.filemaker --dry-run          # print the changes, write nothing
      mix emothe.import.filemaker                    # apply them
      mix emothe.import.filemaker --path other.ndjson

  Plays whose code is absent from the index — every Artelope play — are listed at the
  end and left untouched.
  """

  use Mix.Task

  alias Emothe.Import.Filemaker
  alias Emothe.Import.FilemakerSync

  @switches [dry_run: :boolean, path: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    Mix.Task.run("app.start")

    path = opts[:path] || Filemaker.default_path()

    case Filemaker.load_index(path) do
      {:ok, index} -> sync(index, path, opts)
      {:error, reason} -> Mix.raise("cannot read #{path}: #{inspect(reason)}")
    end
  end

  defp sync(index, path, opts) do
    plays = FilemakerSync.all_plays()
    plan = FilemakerSync.plan(index, plays)

    Mix.shell().info("#{map_size(index)} indexed versions in #{path}")
    Mix.shell().info("#{length(plays)} plays in the database\n")

    Enum.each(plan.changes, fn change ->
      Mix.shell().info("#{change.code}  #{change.title}")

      Enum.each(change.sets, fn {key, value} ->
        Mix.shell().info("    #{key} → #{inspect(value)}")
      end)
    end)

    Mix.shell().info(
      "\n#{length(plan.changes)} to change, #{length(plan.unchanged)} already correct, " <>
        "#{length(plan.missing)} not in the index"
    )

    if plan.missing != [] do
      Mix.shell().info("not in the index: #{Enum.join(plan.missing, ", ")}")
    end

    if opts[:dry_run] do
      Mix.shell().info("\ndry run, nothing written")
    else
      results = FilemakerSync.apply_plan(plan)
      failed = for {:error, code, changeset} <- results, do: {code, changeset}

      Enum.each(failed, fn {code, changeset} ->
        Mix.shell().error("  #{code}: #{inspect(changeset.errors)}")
      end)

      Mix.shell().info("\nupdated #{length(results) - length(failed)}, failed #{length(failed)}")
    end
  end
end
```

- [ ] **Step 2: Verify the task compiles and the dry run works**

```bash
mix compile --warnings-as-errors
mix emothe.import.filemaker --dry-run
```

Expected: a listing that includes these three lines (the corrections the analysis predicted), plus
the AL codes under "not in the index":

```
EMOTHE0010  The Tragedy of Hamlet, Prince of Denmark
    language → "en"
    relationship_type → nil
EMOTHE0038  Antony and Cleopatra
    language → "en"
EMOTHE0053  Hamlet
    relationship_type → "traduccion"
```

If Task 1 imported the whole corpus, many more plays appear — that is expected; what matters is
that those three are present and that no `AL####` code shows up under changes.

- [ ] **Step 3: Commit**

```bash
mix format
git add lib/mix/tasks/emothe.import.filemaker.ex
git commit -m "feat: mix emothe.import.filemaker with a dry-run report"
```

---

### Task 6: Apply for real and check it in the app

**Files:** none — this is the acceptance pass.

- [ ] **Step 1: Snapshot the current state**

```bash
PGPASSWORD=postgres psql -U postgres -h localhost -d emothe_dev -tAF'|' \
  -c "select split_part(code,'_',1), language, coalesce(relationship_type,'-'), coalesce(parent_play_id::text,'-') from plays order by code" \
  > /tmp/plays-before.txt
wc -l /tmp/plays-before.txt
```

- [ ] **Step 2: Apply**

```bash
mix emothe.import.filemaker
```

Expected: `updated N, failed 0`.

- [ ] **Step 3: Verify the three known corrections landed**

```bash
PGPASSWORD=postgres psql -U postgres -h localhost -d emothe_dev -tAF'|' -c \
  "select split_part(code,'_',1), language, coalesce(relationship_type,'-') from plays
   where code like 'EMOTHE0010%' or code like 'EMOTHE0038%' or code like 'EMOTHE0053%' order by code"
```

Expected exactly:

```
EMOTHE0010|en|-
EMOTHE0038|en|-
EMOTHE0053|es|traduccion
```

- [ ] **Step 4: Verify the family links**

```bash
PGPASSWORD=postgres psql -U postgres -h localhost -d emothe_dev -tAF'|' -c \
  "select split_part(c.code,'_',1) as child, split_part(p.code,'_',1) as parent
   from plays c join plays p on p.id = c.parent_play_id order by parent, child"
```

Expected: the Hamlet family (`EMOTHE0050`, `EMOTHE0053`, `EMOTHE0059` → `EMOTHE0010`) and the
Antony family (`EMOTHE0052`, `EMOTHE0084`, `EMOTHE0139` → `EMOTHE0038`), plus whatever other
complete families Task 1 imported.

- [ ] **Step 5: Look at the app**

```bash
mix phx.server
```

Check, without changing any UI code:
- `/plays` — translations are grouped under their original with a relationship badge
  (`lib/emothe_web/live/play_catalogue_live.ex:95`)
- `/plays/EMOTHE0053_Hamlet` — the play context bar shows the family
  (`lib/emothe_web/components/layouts.ex:149`)
- `/admin/plays/<id>/compare` — the comparison picker offers the family
  (`lib/emothe_web/live/play_comparison.ex:43`)

- [ ] **Step 6: Run the whole suite**

```bash
mix test
```

Expected: PASS. `test/emothe/roundtrip_test.exs` reads the fixture files directly and does not
touch `language` or `relationship_type`, so it should be unaffected; if it fails, read the failure
before assuming this slice caused it.

- [ ] **Step 7: Re-run the analysis page and commit**

```bash
python3 docs/build_import_analysis.py
git add docs/superpowers/plans docs/build_import_analysis.py
git commit -m "docs: FileMaker import slices and the S1 plan"
```

`doc/` is git-ignored, so the generated HTML and the export itself stay out of the repository —
only the generator and the plans are committed.

---

## Notes for whoever picks this up

- **Why the index and not the TEI:** every EMOTHE TEI file carries `xml:lang="es"` on the root
  `<TEI>` element because that marks the editorial platform's language, not the play's. The
  importer reads `profileDesc/langUsage` when present and falls back to the default `"es"`, which
  is how the English *Antony and Cleopatra* ended up Spanish. The index's `[EN]` tag is
  authoritative.
- **Why `relationship_type: nil` for originals:** the schema treats nil as "original or
  standalone" (see `lib/emothe/catalogue/play.ex:82` and
  `docs/superpowers/plans/../doc/plan-play-relationships.md`). An original wrongly marked
  `adaptacion` — which `EMOTHE0010` is today — must be cleared, not left.
- **What this slice deliberately does not do:** set `original_title` (the index titles are
  upper-cased display strings; `T01.pub_TituloObra` has proper case and comes in S2), touch
  `is_complete`, import editors, or fetch anything over the network.
- **Next slice:** S2, the version metadata panel — see
  `docs/superpowers/plans/2026-08-01-filemaker-import-slices.md`.
