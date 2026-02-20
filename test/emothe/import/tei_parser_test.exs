defmodule Emothe.Import.TeiParserTest do
  use Emothe.DataCase, async: true

  alias Emothe.Import.TeiParser
  alias Emothe.Catalogue
  alias Emothe.PlayContent

  defp write_tei(xml) do
    path = Path.join(System.tmp_dir!(), "tei-import-#{System.unique_integer([:positive])}.xml")
    File.write!(path, xml)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp minimal_tei(opts) do
    title = Keyword.get(opts, :title, "Test Play")
    code = Keyword.get(opts, :code, "TEST#{System.unique_integer([:positive])}")
    author = Keyword.get(opts, :author, "")
    front = Keyword.get(opts, :front, "")
    body = Keyword.get(opts, :body, "")

    author_el = if author != "", do: "<author>#{author}</author>", else: ""

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <TEI>
      <teiHeader>
        <fileDesc>
          <titleStmt>
            <title>#{title}</title>
            #{author_el}
          </titleStmt>
          <publicationStmt>
            <idno>#{code}</idno>
          </publicationStmt>
        </fileDesc>
      </teiHeader>
      <text>
        <front>#{front}</front>
        <body>#{body}</body>
      </text>
    </TEI>
    """
  end

  # --- Metadata ---

  test "import_file/1 normalizes all-uppercase play titles" do
    path = write_tei(minimal_tei(title: "LOS RAMILLETES DE MADRID", code: "AL0606"))

    assert {:ok, play} = TeiParser.import_file(path)
    assert play.code == "AL0606"
    assert play.title == "Los Ramilletes de Madrid"
  end

  test "import_file/1 preserves mixed-case titles" do
    path = write_tei(minimal_tei(title: "La Dama Boba", code: "DAMA01"))

    assert {:ok, play} = TeiParser.import_file(path)
    assert play.title == "La Dama Boba"
  end

  test "import_file/1 extracts author name" do
    path = write_tei(minimal_tei(author: "Lope de Vega", code: "LOPE01"))

    assert {:ok, play} = TeiParser.import_file(path)
    assert play.author_name == "Lope de Vega"
  end

  test "import_file/1 returns error for non-existent file" do
    assert {:error, :enoent} = TeiParser.import_file("/nonexistent/file.xml")
  end

  test "import_file/1 returns error for invalid XML" do
    path = write_tei("<not valid xml>>>")

    assert {:error, {:xml_parse_error, _}} = TeiParser.import_file(path)
  end

  test "import_file/1 returns error when play code already exists" do
    code = "DUP01"
    path = write_tei(minimal_tei(title: "Duplicate", code: code))

    assert {:ok, play} = TeiParser.import_file(path)
    assert play.code == code

    assert {:error, {:play_already_exists, ^code}} = TeiParser.import_file(path)
  end

  # --- Cast list ---

  test "import_file/1 imports characters from cast list" do
    front = """
    <div type="elenco">
      <head>Personas</head>
      <castList>
        <castItem>
          <role xml:id="DONA">Dona Ana</role>
          <roleDesc>una dama</roleDesc>
        </castItem>
        <castItem>
          <role xml:id="DON">Don Juan</role>
          <roleDesc>un caballero</roleDesc>
        </castItem>
        <castItem ana="oculto">
          <role xml:id="CRIADO">Criado</role>
        </castItem>
      </castList>
    </div>
    """

    path = write_tei(minimal_tei(front: front))
    assert {:ok, play} = TeiParser.import_file(path)

    characters = PlayContent.list_characters(play.id)
    assert length(characters) == 3

    dona = Enum.find(characters, &(&1.xml_id == "DONA"))
    assert dona.name == "Dona Ana"
    assert dona.description == "una dama"
    assert dona.is_hidden == false

    criado = Enum.find(characters, &(&1.xml_id == "CRIADO"))
    assert criado.is_hidden == true
  end

  test "import_file/1 handles duplicate character xml_ids gracefully" do
    front = """
    <div type="elenco">
      <castList>
        <castItem>
          <role xml:id="HERO">Hero Original</role>
        </castItem>
        <castItem>
          <role xml:id="HERO">Hero Duplicate</role>
        </castItem>
        <castItem>
          <role xml:id="OTHER">Other</role>
        </castItem>
      </castList>
    </div>
    """

    path = write_tei(minimal_tei(front: front))
    assert {:ok, play} = TeiParser.import_file(path)

    characters = PlayContent.list_characters(play.id)
    assert length(characters) == 3

    hero = Enum.find(characters, &(&1.xml_id == "HERO"))
    assert hero.name == "Hero Original"

    hero_dup = Enum.find(characters, &(&1.xml_id == "HERO_2"))
    assert hero_dup.name == "Hero Duplicate"
  end

  # --- Body structure (acts, scenes, speeches, verses) ---

  test "import_file/1 imports acts and scenes" do
    body = """
    <div1 type="acto" n="1">
      <head>ACTO PRIMERO</head>
      <div2 type="escena" n="1">
        <head>ESCENA I</head>
      </div2>
      <div2 type="escena" n="2">
        <head>ESCENA II</head>
      </div2>
    </div1>
    <div1 type="acto" n="2">
      <head>ACTO SEGUNDO</head>
    </div1>
    """

    path = write_tei(minimal_tei(body: body))
    assert {:ok, play} = TeiParser.import_file(path)

    divisions = PlayContent.list_top_divisions(play.id)
    assert length(divisions) == 2

    [act1, act2] = divisions
    assert act1.type == "acto"
    assert act1.number == 1
    assert act1.title == "ACTO PRIMERO"
    assert length(act1.children) == 2

    [scene1, scene2] = act1.children
    assert scene1.type == "escena"
    assert scene1.number == 1
    assert scene2.number == 2

    assert act2.number == 2
    assert act2.children == []
  end

  test "import_file/1 imports speeches with character references" do
    front = """
    <div type="elenco">
      <castList>
        <castItem>
          <role xml:id="ANA">ANA</role>
        </castItem>
      </castList>
    </div>
    """

    body = """
    <div1 type="acto" n="1">
      <div2 type="escena" n="1">
        <sp who="#ANA">
          <speaker>ANA</speaker>
          <lg type="redondilla">
            <l n="1">First verse line</l>
            <l n="2">Second verse line</l>
          </lg>
        </sp>
        <stage>Sale ANA por la puerta</stage>
      </div2>
    </div1>
    """

    path = write_tei(minimal_tei(front: front, body: body))
    assert {:ok, play} = TeiParser.import_file(path)

    act =
      play.id
      |> PlayContent.list_top_divisions()
      |> Enum.find(&(&1.type == "acto"))

    assert act
    [scene] = act.children
    elements = PlayContent.list_elements_for_division(scene.id)

    # Should have a speech and a stage direction at top level
    speech = Enum.find(elements, &(&1.type == "speech"))
    stage_dir = Enum.find(elements, &(&1.type == "stage_direction"))

    assert speech
    assert speech.speaker_label == "ANA"
    assert speech.character_id != nil

    assert stage_dir
    assert stage_dir.content == "Sale ANA por la puerta"

    # Speech should contain a line_group with 2 verse lines
    [line_group] = speech.children
    assert line_group.type == "line_group"
    assert line_group.verse_type == "redondilla"

    verse_lines = line_group.children
    assert length(verse_lines) == 2
    [v1, v2] = verse_lines
    assert v1.type == "verse_line"
    assert v1.content == "First verse line"
    assert v1.line_number == 1
    assert v2.line_number == 2
  end

  test "import_file/1 imports prose elements" do
    body = """
    <div1 type="acto" n="1">
      <div2 type="escena" n="1">
        <sp>
          <speaker>NARRADOR</speaker>
          <p>A prose paragraph in the play.</p>
        </sp>
      </div2>
    </div1>
    """

    path = write_tei(minimal_tei(body: body))
    assert {:ok, play} = TeiParser.import_file(path)

    [act] = PlayContent.list_top_divisions(play.id)
    [scene] = act.children
    elements = PlayContent.list_elements_for_division(scene.id)

    [speech] = elements
    prose = Enum.find(speech.children, &(&1.type == "prose"))
    assert prose
    assert prose.content == "A prose paragraph in the play."
  end

  # --- Asides ---

  test "import_file/1 detects aside verse lines via stage type=delivery" do
    body = """
    <div1 type="acto" n="1">
      <div2 type="escena" n="1">
        <sp>
          <speaker>ANA</speaker>
          <lg type="redondilla">
            <l n="1">Normal verse line</l>
            <l n="2">
              <stage type="delivery">[Aparte.]</stage>
              <seg type="aside">An aside line</seg>
            </l>
          </lg>
        </sp>
      </div2>
    </div1>
    """

    path = write_tei(minimal_tei(body: body))
    assert {:ok, play} = TeiParser.import_file(path)

    [act] = PlayContent.list_top_divisions(play.id)
    [scene] = act.children
    elements = PlayContent.list_elements_for_division(scene.id)

    [speech] = Enum.filter(elements, &(&1.type == "speech"))
    [line_group] = speech.children
    verse_lines = Enum.sort_by(line_group.children, & &1.line_number)

    assert length(verse_lines) == 2
    [normal_line, aside_line] = verse_lines

    assert normal_line.is_aside == false
    assert normal_line.content == "Normal verse line"

    assert aside_line.is_aside == true
    assert aside_line.content == "An aside line"
  end

  test "import_file/1 detects aside with variant Aparte notation" do
    body = """
    <div1 type="acto" n="1">
      <div2 type="escena" n="1">
        <sp>
          <speaker>REY</speaker>
          <lg type="decima">
            <l n="1">
              <stage type="delivery">(Aparte.)</stage>
              <seg type="aside">Spoken aside</seg>
            </l>
            <l n="2">
              <stage type="delivery">Aparte</stage>
              <seg type="aside">Another aside</seg>
            </l>
          </lg>
        </sp>
      </div2>
    </div1>
    """

    path = write_tei(minimal_tei(body: body))
    assert {:ok, play} = TeiParser.import_file(path)

    [act] = PlayContent.list_top_divisions(play.id)
    [scene] = act.children
    elements = PlayContent.list_elements_for_division(scene.id)
    [speech] = elements
    [line_group] = speech.children
    verse_lines = Enum.sort_by(line_group.children, & &1.line_number)

    assert Enum.all?(verse_lines, & &1.is_aside)
    assert Enum.map(verse_lines, & &1.content) == ["Spoken aside", "Another aside"]
  end

  test "import_file/1 does not mark stage-only aparte as verse aside" do
    body = """
    <div1 type="acto" n="1">
      <div2 type="escena" n="1">
        <stage>Hablan los dos aparte.</stage>
        <sp>
          <speaker>REY</speaker>
          <lg type="redondilla">
            <l n="1">A normal line</l>
          </lg>
        </sp>
      </div2>
    </div1>
    """

    path = write_tei(minimal_tei(body: body))
    assert {:ok, play} = TeiParser.import_file(path)

    [act] = PlayContent.list_top_divisions(play.id)
    [scene] = act.children
    elements = PlayContent.list_elements_for_division(scene.id)
    [speech] = Enum.filter(elements, &(&1.type == "speech"))
    [line_group] = speech.children
    [verse_line] = line_group.children

    assert verse_line.is_aside == false
    assert verse_line.content == "A normal line"
  end

  # --- Editorial notes ---

  test "import_file/1 imports front matter editorial notes" do
    front = """
    <div type="dedicatoria">
      <head>Dedicatoria</head>
      <p>Al muy ilustre senor...</p>
      <p>Con todo respeto...</p>
    </div>
    """

    path = write_tei(minimal_tei(front: front))
    assert {:ok, play} = TeiParser.import_file(path)

    play_full = Catalogue.get_play_with_all!(play.id)
    [note] = play_full.editorial_notes
    assert note.section_type == "dedicatoria"
    assert note.heading == "Dedicatoria"
    assert note.content =~ "Al muy ilustre senor"
    assert note.content =~ "Con todo respeto"
  end

  # --- Extended metadata ---

  defp rich_tei(opts) do
    code = Keyword.get(opts, :code, "RICH#{System.unique_integer([:positive])}")
    front = Keyword.get(opts, :front, "")
    body = Keyword.get(opts, :body, "")

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <TEI xmlns="http://www.tei-c.org/ns/1.0">
      <teiHeader>
        <fileDesc>
          <titleStmt>
            <title type="traduccion">Ricardo III</title>
            <title type="original">The Tragedy of Richard III</title>
            <editor role="translator"><persName>Sanderson, John D.</persName></editor>
            <author ana="fiable">William Shakespeare</author>
            <sponsor><orgName>Plan Nacional de I+D+i</orgName></sponsor>
            <funder><orgName>Ministerio de Ciencia e Innovación</orgName></funder>
            <respStmt>
              <resp>Electronic edition</resp>
              <persName>Amelang, David J.</persName>
            </respStmt>
            <principal>Joan Oleza Simó</principal>
          </titleStmt>
          <publicationStmt>
            <publisher><orgName>ARTELOPE/EMOTHE, Universitat de València</orgName></publisher>
            <authority><orgName>Universitat de València - Estudi General</orgName></authority>
            <idno>#{code}</idno>
            <idno type="EMOTHE">0703</idno>
            <availability>
              <p>Some general availability text.</p>
              <licence target="https://creativecommons.org/licenses/by-nc-nd/4.0/deed.es">CC BY-NC-ND 4.0</licence>
            </availability>
            <pubPlace>Valencia</pubPlace>
            <date>2023</date>
          </publicationStmt>
          <sourceDesc>
            <bibl>
              <title>La tragedia del rey Ricardo III</title>
              <author>Shakespeare, William</author>
              <editor role="traductor">Sanderson, John D.</editor>
              <lang>Español</lang>
              <note>Notas de la fuente.</note>
            </bibl>
          </sourceDesc>
        </fileDesc>
      </teiHeader>
      <text>
        <front>#{front}</front>
        <body>#{body}</body>
      </text>
    </TEI>
    """
  end

  test "import_file/1 extracts original_title from <title type=\"original\">" do
    path = write_tei(rich_tei(code: "ORIG01"))
    assert {:ok, play} = TeiParser.import_file(path)
    assert play.original_title == "The Tragedy of Richard III"
  end

  test "import_file/1 imports translator role editor from titleStmt" do
    path = write_tei(rich_tei(code: "TRANS01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_full = Catalogue.get_play_with_all!(play.id)
    translator = Enum.find(play_full.editors, &(&1.role == "translator"))
    assert translator != nil
    assert translator.person_name =~ "Sanderson"
  end

  test "import_file/1 extracts emothe_id from <idno type=\"EMOTHE\">" do
    path = write_tei(rich_tei(code: "IDNO01"))
    assert {:ok, play} = TeiParser.import_file(path)
    assert play.emothe_id == "0703"
  end

  test "import_file/1 extracts licence_url from <licence target>" do
    path = write_tei(rich_tei(code: "LIC01"))
    assert {:ok, play} = TeiParser.import_file(path)
    assert play.licence_url == "https://creativecommons.org/licenses/by-nc-nd/4.0/deed.es"
  end

  test "import_file/1 extracts licence_text from <licence> text content" do
    path = write_tei(rich_tei(code: "LIC02"))
    assert {:ok, play} = TeiParser.import_file(path)
    assert play.licence_text == "CC BY-NC-ND 4.0"
  end

  test "import_file/1 extracts source language from <bibl><lang>" do
    path = write_tei(rich_tei(code: "LANG01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_full = Catalogue.get_play_with_all!(play.id)
    [source] = play_full.sources
    assert source.language == "Español"
  end

  test "import_file/1 extracts sponsor from <sponsor><orgName>" do
    path = write_tei(rich_tei(code: "SPON01"))
    assert {:ok, play} = TeiParser.import_file(path)
    assert play.sponsor == "Plan Nacional de I+D+i"
  end

  test "import_file/1 extracts funder from <funder><orgName>" do
    path = write_tei(rich_tei(code: "FUND01"))
    assert {:ok, play} = TeiParser.import_file(path)
    assert play.funder =~ "Ministerio de Ciencia"
  end

  test "import_file/1 extracts authority from <authority><orgName>" do
    path = write_tei(rich_tei(code: "AUTH01"))
    assert {:ok, play} = TeiParser.import_file(path)
    assert play.authority == "Universitat de València - Estudi General"
  end

  test "import_file/1 extracts publisher from <publisher><orgName>" do
    path = write_tei(rich_tei(code: "PUB01"))
    assert {:ok, play} = TeiParser.import_file(path)
    assert play.publisher =~ "ARTELOPE/EMOTHE"
  end

  # --- Encoding ---

  test "import_file/1 handles UTF-16 LE encoded files" do
    xml = minimal_tei(title: "UTF16 Test", code: "UTF16LE")
    # Encode as UTF-16 LE with BOM
    utf16 = <<0xFF, 0xFE>> <> :unicode.characters_to_binary(xml, :utf8, {:utf16, :little})

    path = Path.join(System.tmp_dir!(), "tei-utf16-#{System.unique_integer([:positive])}.xml")
    File.write!(path, utf16)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, play} = TeiParser.import_file(path)
    assert play.code == "UTF16LE"
    assert play.title == "UTF16 Test"
  end
end
