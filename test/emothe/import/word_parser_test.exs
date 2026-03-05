defmodule Emothe.Import.WordParserTest do
  use Emothe.DataCase, async: true

  alias Emothe.Import.WordParser
  alias Emothe.PlayContent.{Character, Division, Element}
  import Ecto.Query

  @fixtures_path "test/fixtures/word_files"

  # --- Phase 1: Docx extraction ---

  describe "extract_paragraphs/1" do
    test "extracts paragraphs from ejercicio.docx fixture" do
      path = Path.join(@fixtures_path, "ejercicio.docx")
      assert {:ok, paragraphs} = WordParser.extract_paragraphs(path)
      assert is_list(paragraphs)
      assert length(paragraphs) > 0
      # All entries should be strings
      assert Enum.all?(paragraphs, &is_binary/1)
    end

    test "first paragraph of ejercicio contains the title" do
      path = Path.join(@fixtures_path, "ejercicio.docx")
      {:ok, paragraphs} = WordParser.extract_paragraphs(path)
      first_non_empty = Enum.find(paragraphs, &(String.trim(&1) != ""))
      assert first_non_empty =~ "EJERCICIO"
    end

    test "contains known tagged lines from the marked section" do
      path = Path.join(@fixtures_path, "ejercicio.docx")
      {:ok, paragraphs} = WordParser.extract_paragraphs(path)
      # The marked section should contain these tags
      assert Enum.any?(paragraphs, &(&1 =~ ~r/\{e\}/i))
      assert Enum.any?(paragraphs, &(&1 =~ ~r/\{ac\}/i))
      assert Enum.any?(paragraphs, &(&1 =~ ~r/\{p\}/i))
      assert Enum.any?(paragraphs, &(&1 =~ ~r/\{v\}/i))
      assert Enum.any?(paragraphs, &(&1 =~ ~r/\{pr\}/i))
    end

    test "returns error for non-existent file" do
      assert {:error, _} = WordParser.extract_paragraphs("/nonexistent/file.docx")
    end

    test "returns error for non-docx file" do
      # Create a plain text file and try to extract
      path = Path.join(System.tmp_dir!(), "not-a-docx-#{System.unique_integer([:positive])}.docx")
      File.write!(path, "not a zip file")
      on_exit(fn -> File.rm(path) end)
      assert {:error, _} = WordParser.extract_paragraphs(path)
    end
  end

  # --- Phase 2: Tag parsing ---

  describe "parse_line/1" do
    test "parses simple verse line" do
      assert [{:verse, "Será remedio casarte."}] =
               WordParser.parse_line("{v}Será remedio casarte.")
    end

    test "parses speaker + verse" do
      assert [{:speaker, "FEBO"}, {:verse, "Será remedio casarte."}] =
               WordParser.parse_line("{p}FEBO  {v}Será remedio casarte.")
    end

    test "parses speaker + prose" do
      assert [{:speaker, "JOHN"}, {:prose, "Hello world"}] =
               WordParser.parse_line("{p} JOHN {pr} Hello world")
    end

    test "parses stage direction" do
      assert [{:stage_direction, "Sale el Rey."}] =
               WordParser.parse_line("{ac}Sale el Rey.")
    end

    test "parses scene marker" do
      assert [{:scene, "Escena 1"}] =
               WordParser.parse_line("{e}Escena 1")
    end

    test "parses split verse parts" do
      assert [{:verse_initial, "¿Cantan?"}] = WordParser.parse_line("{ti}¿Cantan?")
      assert [{:verse_middle, "¿No lo ves?"}] = WordParser.parse_line("{tm}¿No lo ves?")
      assert [{:verse_final, "¿Pues quién"}] = WordParser.parse_line("{tf}¿Pues quién")
    end

    test "parses stanza marker" do
      assert [{:stanza, ""}] = WordParser.parse_line("{m}")
    end

    test "parses aside marker" do
      assert [{:aside, ""}, {:prose, "some text"}] =
               WordParser.parse_line("{ap} {pr} some text")
    end

    test "tags are case-insensitive" do
      assert [{:verse, "text"}] = WordParser.parse_line("{V}text")
      assert [{:prose, "text"}] = WordParser.parse_line("{PR}text")
      assert [{:speaker, "JOHN"}, {:verse, "hi"}] = WordParser.parse_line("{P}JOHN {V}hi")
      assert [{:stage_direction, "Exit."}] = WordParser.parse_line("{AC}Exit.")
    end

    test "returns untagged text as :text" do
      assert [{:text, "Some plain text"}] = WordParser.parse_line("Some plain text")
    end

    test "parses act marker" do
      assert [{:act, "JORNADA PRIMERA"}] = WordParser.parse_line("{A}JORNADA PRIMERA")
      assert [{:act, "ACTO I"}] = WordParser.parse_line("{a}ACTO I")
    end

    test "speaker + stage direction mid-line" do
      assert [{:speaker, "DUKE"}, {:stage_direction, "Aside."}, {:verse, "My lord."}] =
               WordParser.parse_line("{p}DUKE {ac}Aside. {v}My lord.")
    end
  end

  # --- Phase 3: Content structure ---

  describe "parse_content/1" do
    test "wraps all content in a default act when no act heading is found" do
      paragraphs = [
        "{e}Escena 1",
        "{p}FEBO  {v}Será remedio casarte."
      ]

      assert {:ok, %{acts: [act]}} = WordParser.parse_content(paragraphs)
      assert act.type == "acto"
      assert length(act.scenes) == 1
    end

    test "detects scene boundaries from {e} tags" do
      paragraphs = [
        "{e}Escena 1",
        "{p}FEBO  {v}Hello.",
        "{e}Escena 2",
        "{p}RICARDO  {v}Goodbye."
      ]

      assert {:ok, %{acts: [act]}} = WordParser.parse_content(paragraphs)
      assert length(act.scenes) == 2
      assert Enum.at(act.scenes, 0).head == "Escena 1"
      assert Enum.at(act.scenes, 1).head == "Escena 2"
    end

    test "creates speech elements from {p} tags with verse children" do
      paragraphs = [
        "{e}Escena 1",
        "{p}FEBO  {v}Será remedio casarte.",
        "{v}pon a esta puerta el oído."
      ]

      assert {:ok, %{acts: [act]}} = WordParser.parse_content(paragraphs)
      scene = hd(act.scenes)
      # Should have one speech with two verse lines
      assert [speech] = scene.elements
      assert speech.type == "speech"
      assert speech.speaker_label == "FEBO"
      assert length(speech.children) == 2
      assert Enum.all?(speech.children, &(&1.type == "verse_line"))
    end

    test "new {p} tag starts a new speech" do
      paragraphs = [
        "{e}Escena 1",
        "{p}FEBO  {v}Hello.",
        "{p}RICARDO  {v}Goodbye."
      ]

      assert {:ok, %{acts: [act]}} = WordParser.parse_content(paragraphs)
      scene = hd(act.scenes)
      assert length(scene.elements) == 2
      assert Enum.at(scene.elements, 0).speaker_label == "FEBO"
      assert Enum.at(scene.elements, 1).speaker_label == "RICARDO"
    end

    test "standalone stage direction outside speech" do
      paragraphs = [
        "{e}Escena 1",
        "{ac}Sale el Rey.",
        "{p}FEBO  {v}Hello."
      ]

      assert {:ok, %{acts: [act]}} = WordParser.parse_content(paragraphs)
      scene = hd(act.scenes)
      assert [stage_dir, speech] = scene.elements
      assert stage_dir.type == "stage_direction"
      assert stage_dir.content == "Sale el Rey."
      assert speech.type == "speech"
    end

    test "split verse parts are preserved" do
      paragraphs = [
        "{e}Escena 1",
        "{p}DUQUE  {ti}¿Cantan?",
        "{p}RICARDO  {tm}¿No lo ves?",
        "{p}DUQUE  {tf}¿Pues quién"
      ]

      assert {:ok, %{acts: [act]}} = WordParser.parse_content(paragraphs)
      scene = hd(act.scenes)
      speeches = scene.elements
      assert length(speeches) == 3

      parts =
        speeches
        |> Enum.flat_map(& &1.children)
        |> Enum.map(& &1.part)

      assert parts == ["I", "M", "F"]
    end

    test "prose speech" do
      paragraphs = [
        "{e}Escena 1",
        "{p}JOHN  {pr}To be or not to be."
      ]

      assert {:ok, %{acts: [act]}} = WordParser.parse_content(paragraphs)
      scene = hd(act.scenes)
      [speech] = scene.elements
      assert speech.speaker_label == "JOHN"
      assert [prose] = speech.children
      assert prose.type == "prose"
      assert prose.content == "To be or not to be."
    end

    test "act boundary detection from plain text" do
      paragraphs = [
        "ACTO PRIMERO",
        "{e}Escena 1",
        "{p}FEBO  {v}Hello.",
        "ACTO SEGUNDO",
        "{e}Escena 1",
        "{p}RICARDO  {v}Goodbye."
      ]

      assert {:ok, %{acts: acts}} = WordParser.parse_content(paragraphs)
      assert length(acts) == 2
      assert Enum.at(acts, 0).head == "ACTO PRIMERO"
      assert Enum.at(acts, 1).head == "ACTO SEGUNDO"
    end

    test "creates acts from {A} tag" do
      paragraphs = [
        "{A}ACTO PRIMERO",
        "{e}Escena 1",
        "{p}FEBO  {v}Hello.",
        "{A}ACTO SEGUNDO",
        "{e}Escena 1",
        "{p}RICARDO  {v}Goodbye."
      ]

      assert {:ok, %{acts: acts}} = WordParser.parse_content(paragraphs)
      assert length(acts) == 2
      assert Enum.at(acts, 0).head == "ACTO PRIMERO"
      assert Enum.at(acts, 0).type == "acto"
      assert Enum.at(acts, 1).head == "ACTO SEGUNDO"
    end

    test "{A} tag with JORNADA detects correct type" do
      paragraphs = [
        "{A}JORNADA PRIMERA",
        "{e}Escena 1",
        "{p}FEBO  {v}Hello."
      ]

      assert {:ok, %{acts: [act]}} = WordParser.parse_content(paragraphs)
      assert act.head == "JORNADA PRIMERA"
      assert act.type == "jornada"
    end

    test "detects prologue from {A} tag" do
      paragraphs = [
        "{A}PRÓLOGO",
        "{e}Escena 1",
        "{p}FEBO  {v}Hello.",
        "{A}ACTO PRIMERO",
        "{e}Escena 1",
        "{p}RICARDO  {v}Goodbye."
      ]

      assert {:ok, %{acts: acts}} = WordParser.parse_content(paragraphs)
      assert length(acts) == 2
      assert Enum.at(acts, 0).type == "prologo"
      assert Enum.at(acts, 0).head == "PRÓLOGO"
      assert Enum.at(acts, 1).type == "acto"
    end

    test "detects epilogue from {A} tag" do
      paragraphs = [
        "{A}ACTO PRIMERO",
        "{e}Escena 1",
        "{p}FEBO  {v}Hello.",
        "{A}EPÍLOGO",
        "{e}Escena 1",
        "{p}RICARDO  {v}Goodbye."
      ]

      assert {:ok, %{acts: acts}} = WordParser.parse_content(paragraphs)
      assert length(acts) == 2
      assert Enum.at(acts, 1).type == "epilogue"
      assert Enum.at(acts, 1).head == "EPÍLOGO"
    end

    test "auto-detects prologue from plain text" do
      paragraphs = [
        "PRÓLOGO",
        "{e}Escena 1",
        "{p}FEBO  {v}Hello."
      ]

      assert {:ok, %{acts: [act]}} = WordParser.parse_content(paragraphs)
      assert act.type == "prologo"
      assert act.head == "PRÓLOGO"
    end

    test "auto-detects epilogue from plain text" do
      paragraphs = [
        "EPILOGUE",
        "{e}Escena 1",
        "{p}FEBO  {v}Hello."
      ]

      assert {:ok, %{acts: [act]}} = WordParser.parse_content(paragraphs)
      assert act.type == "epilogue"
      assert act.head == "EPILOGUE"
    end

    test "detects JORNADA act headings with correct type" do
      paragraphs = [
        "JORNADA PRIMERA",
        "{e}Escena 1",
        "{p}FEBO  {v}Hello."
      ]

      assert {:ok, %{acts: [act]}} = WordParser.parse_content(paragraphs)
      assert act.head == "JORNADA PRIMERA"
      assert act.type == "jornada"
    end

    test "skips untagged text before first act" do
      paragraphs = [
        "EJERCICIO",
        "",
        "JORNADA I",
        "{e}Escena 1",
        "{p}FEBO  {v}Hello."
      ]

      assert {:ok, %{acts: [act]}} = WordParser.parse_content(paragraphs)
      assert act.head == "JORNADA I"
      assert act.type == "jornada"
      assert length(act.scenes) == 1
    end

    test "removes empty scenes" do
      paragraphs = [
        "ACTO PRIMERO",
        "{e}Escena 1",
        "{p}FEBO  {v}Hello."
      ]

      assert {:ok, %{acts: [act]}} = WordParser.parse_content(paragraphs)
      # Should have exactly 1 scene (no empty scene before {e})
      assert length(act.scenes) == 1
      assert hd(act.scenes).head == "Escena 1"
    end
  end

  # --- Phase 4: DB integration ---

  describe "import_content/2" do
    test "imports basic structure into an existing play" do
      play = insert_play()

      paragraphs = [
        "{e}Escena 1",
        "{p}FEBO  {v}Será remedio casarte.",
        "{v}pon a esta puerta el oído.",
        "{ac}Sale Ricardo.",
        "{p}RICARDO  {v}Si quieres desenfadarte,"
      ]

      path = write_test_docx(paragraphs)
      assert {:ok, _play} = WordParser.import_content(play.id, path)

      # Verify divisions
      divisions = list_divisions(play.id)
      assert length(divisions) >= 1
      scene = Enum.find(divisions, &(&1.type == "escena"))
      assert scene != nil
      assert scene.title == "Escena 1"

      # Verify elements
      elements = list_elements(play.id)
      speeches = Enum.filter(elements, &(&1.type == "speech"))
      verse_lines = Enum.filter(elements, &(&1.type == "verse_line"))
      stage_dirs = Enum.filter(elements, &(&1.type == "stage_direction"))

      assert length(speeches) == 2
      assert length(verse_lines) == 3
      assert length(stage_dirs) == 1
    end

    test "auto-numbers verse lines" do
      play = insert_play()

      paragraphs = [
        "{e}Escena 1",
        "{p}FEBO  {v}Line one.",
        "{v}Line two.",
        "{v}Line three."
      ]

      path = write_test_docx(paragraphs)
      assert {:ok, _play} = WordParser.import_content(play.id, path)

      elements = list_elements(play.id)

      verse_lines =
        elements |> Enum.filter(&(&1.type == "verse_line")) |> Enum.sort_by(& &1.position)

      line_numbers = Enum.map(verse_lines, & &1.line_number)
      assert line_numbers == [1, 2, 3]
    end

    test "preserves split verse parts" do
      play = insert_play()

      paragraphs = [
        "{e}Escena 1",
        "{p}DUQUE  {ti}¿Cantan?",
        "{p}RICARDO  {tf}No lo ves."
      ]

      path = write_test_docx(paragraphs)
      assert {:ok, _play} = WordParser.import_content(play.id, path)

      elements = list_elements(play.id)
      verse_lines = Enum.filter(elements, &(&1.type == "verse_line"))
      parts = Enum.map(verse_lines, & &1.part) |> Enum.sort()
      assert parts == ["F", "I"]
    end

    test "replaces existing content on re-import" do
      play = insert_play()

      paragraphs1 = ["{e}Escena 1", "{p}FEBO  {v}Hello."]
      path1 = write_test_docx(paragraphs1)
      assert {:ok, _} = WordParser.import_content(play.id, path1)

      paragraphs2 = ["{e}Escena 1", "{p}RICARDO  {v}Goodbye.", "{v}See you."]
      path2 = write_test_docx(paragraphs2)
      assert {:ok, _} = WordParser.import_content(play.id, path2)

      elements = list_elements(play.id)
      speeches = Enum.filter(elements, &(&1.type == "speech"))
      assert length(speeches) == 1
      assert hd(speeches).speaker_label == "RICARDO"

      verse_lines = Enum.filter(elements, &(&1.type == "verse_line"))
      assert length(verse_lines) == 2
    end

    test "imports ejercicio.docx fixture" do
      play = insert_play()
      path = Path.join(@fixtures_path, "ejercicio.docx")
      assert {:ok, _play} = WordParser.import_content(play.id, path)

      divisions = list_divisions(play.id)
      elements = list_elements(play.id)

      # Should have at least one scene
      scenes = Enum.filter(divisions, &(&1.type == "escena"))
      assert length(scenes) > 0

      # Should have speeches, verse lines, stage directions
      speeches = Enum.filter(elements, &(&1.type == "speech"))
      verse_lines = Enum.filter(elements, &(&1.type == "verse_line"))
      assert length(speeches) > 0
      assert length(verse_lines) > 0
    end
  end

  # --- Phase 5: Auto-create characters & auto-assign ---

  describe "import_content/2 character auto-creation" do
    test "auto-creates characters from speaker labels" do
      play = insert_play()

      paragraphs = [
        "{e}Escena 1",
        "{p}FEBO  {v}Hello.",
        "{p}RICARDO  {v}Goodbye."
      ]

      path = write_test_docx(paragraphs)
      assert {:ok, _} = WordParser.import_content(play.id, path)

      characters = list_characters(play.id)
      names = Enum.map(characters, & &1.name) |> Enum.sort()
      assert names == ["FEBO", "RICARDO"]
    end

    test "auto-assigns character_id on speeches" do
      play = insert_play()

      paragraphs = [
        "{e}Escena 1",
        "{p}FEBO  {v}Hello.",
        "{p}RICARDO  {v}Goodbye."
      ]

      path = write_test_docx(paragraphs)
      assert {:ok, _} = WordParser.import_content(play.id, path)

      speeches = list_elements(play.id) |> Enum.filter(&(&1.type == "speech"))
      assert Enum.all?(speeches, &(&1.character_id != nil))

      characters = list_characters(play.id)
      febo = Enum.find(characters, &(&1.name == "FEBO"))
      ricardo = Enum.find(characters, &(&1.name == "RICARDO"))

      febo_speech = Enum.find(speeches, &(&1.speaker_label == "FEBO"))
      ricardo_speech = Enum.find(speeches, &(&1.speaker_label == "RICARDO"))

      assert febo_speech.character_id == febo.id
      assert ricardo_speech.character_id == ricardo.id
    end

    test "child elements inherit character_id from speech" do
      play = insert_play()

      paragraphs = [
        "{e}Escena 1",
        "{p}FEBO  {v}Line one.",
        "{v}Line two."
      ]

      path = write_test_docx(paragraphs)
      assert {:ok, _} = WordParser.import_content(play.id, path)

      characters = list_characters(play.id)
      febo = Enum.find(characters, &(&1.name == "FEBO"))

      verse_lines = list_elements(play.id) |> Enum.filter(&(&1.type == "verse_line"))
      assert length(verse_lines) == 2
      assert Enum.all?(verse_lines, &(&1.character_id == febo.id))
    end

    test "re-import replaces characters" do
      play = insert_play()

      paragraphs1 = ["{e}Escena 1", "{p}FEBO  {v}Hello."]
      path1 = write_test_docx(paragraphs1)
      assert {:ok, _} = WordParser.import_content(play.id, path1)
      assert length(list_characters(play.id)) == 1

      paragraphs2 = ["{e}Escena 1", "{p}RICARDO  {v}Goodbye."]
      path2 = write_test_docx(paragraphs2)
      assert {:ok, _} = WordParser.import_content(play.id, path2)

      characters = list_characters(play.id)
      assert length(characters) == 1
      assert hd(characters).name == "RICARDO"
    end
  end

  # --- Test helpers ---

  defp list_divisions(play_id) do
    Emothe.Repo.all(from d in Division, where: d.play_id == ^play_id, order_by: d.position)
  end

  defp list_characters(play_id) do
    Emothe.Repo.all(from c in Character, where: c.play_id == ^play_id, order_by: c.position)
  end

  defp list_elements(play_id) do
    Emothe.Repo.all(from e in Element, where: e.play_id == ^play_id, order_by: e.position)
  end

  defp insert_play do
    {:ok, play} =
      Emothe.Catalogue.create_play(%{
        title: "Test Play #{System.unique_integer([:positive])}",
        author: "Test Author",
        code: "TEST#{System.unique_integer([:positive])}",
        is_verse: true
      })

    play
  end

  defp write_test_docx(paragraphs) do
    # Build a minimal valid .docx (ZIP with word/document.xml)
    xml_paragraphs =
      Enum.map(paragraphs, fn text ->
        escaped =
          text
          |> String.replace("&", "&amp;")
          |> String.replace("<", "&lt;")
          |> String.replace(">", "&gt;")

        "<w:p><w:r><w:t xml:space=\"preserve\">#{escaped}</w:t></w:r></w:p>"
      end)
      |> Enum.join("\n")

    document_xml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:body>
        #{xml_paragraphs}
      </w:body>
    </w:document>
    """

    path = Path.join(System.tmp_dir!(), "test-docx-#{System.unique_integer([:positive])}.docx")

    {:ok, {_name, zip_binary}} =
      :zip.create(
        ~c"test.docx",
        [{~c"word/document.xml", document_xml}],
        [:memory]
      )

    File.write!(path, zip_binary)
    path
  end
end
