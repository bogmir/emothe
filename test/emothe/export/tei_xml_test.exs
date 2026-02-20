defmodule Emothe.Export.TeiXmlTest do
  use Emothe.DataCase, async: true

  alias Emothe.Import.TeiParser
  alias Emothe.Export.TeiXml
  alias Emothe.Catalogue
  alias Emothe.PlayContent

  defp write_tei(xml) do
    path = Path.join(System.tmp_dir!(), "tei-export-#{System.unique_integer([:positive])}.xml")
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

  test "export generates valid TEI-XML with required elements" do
    body = """
    <div1 type="acto" n="1">
      <head>ACTO PRIMERO</head>
    </div1>
    """

    path = write_tei(minimal_tei(body: body, code: "EXP01", title: "Export Test"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<TEI/
    assert exported_xml =~ ~r/<teiHeader>/
    assert exported_xml =~ ~r/<text>/
    assert exported_xml =~ ~r/<body>/
    assert exported_xml =~ "EXP01"
    assert exported_xml =~ "Export Test"
  end

  test "export preserves play metadata (title, author, code)" do
    path =
      write_tei(
        minimal_tei(
          title: "La Dama Boba",
          author: "Lope de Vega",
          code: "META01"
        )
      )

    assert {:ok, play} = TeiParser.import_file(path)
    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ "La Dama Boba"
    assert exported_xml =~ "Lope de Vega"
    assert exported_xml =~ "META01"
  end

  test "export preserves characters from cast list" do
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

    path = write_tei(minimal_tei(front: front, code: "CHAR01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ "DONA"
    assert exported_xml =~ "DON"
    assert exported_xml =~ "CRIADO"
    assert exported_xml =~ "Dona Ana"
    assert exported_xml =~ "una dama"
  end

  test "export preserves acts and scenes" do
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

    path = write_tei(minimal_tei(body: body, code: "STRUCT01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ "ACTO PRIMERO"
    assert exported_xml =~ "ACTO SEGUNDO"
    assert exported_xml =~ "ESCENA I"
    assert exported_xml =~ "ESCENA II"
  end

  test "export preserves speeches with character references" do
    front = """
    <div type="elenco">
      <castList>
        <castItem><role xml:id="ANA">ANA</role></castItem>
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
      </div2>
    </div1>
    """

    path = write_tei(minimal_tei(front: front, body: body, code: "SP01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<sp\s+who="#ANA"/
    assert exported_xml =~ "<speaker>ANA</speaker>"
    assert exported_xml =~ "First verse line"
    assert exported_xml =~ "Second verse line"
  end

  test "export preserves stage directions" do
    body = """
    <div1 type="acto" n="1">
      <div2 type="escena" n="1">
        <stage>Sale el REY por la puerta</stage>
        <sp>
          <speaker>REY</speaker>
          <lg type="romance">
            <l n="1">I speak a verse</l>
          </lg>
        </sp>
        <stage>Se sienta en el trono</stage>
      </div2>
    </div1>
    """

    path = write_tei(minimal_tei(body: body, code: "STAGE01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ "Sale el REY por la puerta"
    assert exported_xml =~ "Se sienta en el trono"
  end

  test "export preserves prose elements" do
    body = """
    <div1 type="acto" n="1">
      <div2 type="escena" n="1">
        <sp>
          <speaker>NARRADOR</speaker>
          <p>A prose paragraph in the play.</p>
          <p>And a second prose paragraph.</p>
        </sp>
      </div2>
    </div1>
    """

    path = write_tei(minimal_tei(body: body, code: "PROSE01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ "A prose paragraph in the play."
    assert exported_xml =~ "And a second prose paragraph."
  end

  test "export preserves aside markers" do
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

    path = write_tei(minimal_tei(body: body, code: "ASIDE01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<seg\s+type="aside"/
    assert exported_xml =~ "An aside line"
  end

  test "exported TEI can be reimported without data loss" do
    front = """
    <div type="elenco">
      <castList>
        <castItem><role xml:id="HERO">HERO</role></castItem>
      </castList>
    </div>
    """

    body = """
    <div1 type="acto" n="1">
      <div2 type="escena" n="1">
        <sp who="#HERO">
          <speaker>HERO</speaker>
          <lg type="redondilla">
            <l n="1">Line one of the speech</l>
            <l n="2">Line two of the speech</l>
          </lg>
        </sp>
      </div2>
    </div1>
    """

    path = write_tei(minimal_tei(front: front, body: body, code: "REIMP01"))

    # First import
    assert {:ok, play1} = TeiParser.import_file(path)
    play1_full = Catalogue.get_play_with_all!(play1.id)
    exported_xml = TeiXml.generate(play1_full)

    # Reimport with different code
    reimport_xml = String.replace(exported_xml, "REIMP01", "REIMP02")
    reimport_path = write_tei(reimport_xml)
    assert {:ok, play2} = TeiParser.import_file(reimport_path)

    # Verify DB contents match
    assert length(PlayContent.list_characters(play1.id)) ==
             length(PlayContent.list_characters(play2.id))

    divs1 = PlayContent.list_top_divisions(play1.id)
    divs2 = PlayContent.list_top_divisions(play2.id)

    act1 = Enum.find(divs2, &(&1.type == "acto"))
    act2_orig = Enum.find(divs1, &(&1.type == "acto"))
    assert act1 != nil
    assert act2_orig != nil

    [scene1] = act2_orig.children
    [scene2] = act1.children

    elems1 = PlayContent.list_elements_for_division(scene1.id)
    elems2 = PlayContent.list_elements_for_division(scene2.id)
    assert length(elems1) == length(elems2)
  end

  # --- Extended metadata roundtrip ---

  defp rich_tei(opts) do
    code = Keyword.get(opts, :code, "RICH#{System.unique_integer([:positive])}")

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <TEI xmlns="http://www.tei-c.org/ns/1.0">
      <teiHeader>
        <fileDesc>
          <titleStmt>
            <title type="traduccion">El gran teatro</title>
            <title type="original">The Great Theatre</title>
            <editor role="translator"><persName>Sanderson, John D.</persName></editor>
            <author ana="fiable">William Shakespeare</author>
            <sponsor><orgName>Plan Nacional de I+D+i</orgName></sponsor>
            <funder><orgName>Ministerio de Ciencia</orgName></funder>
            <respStmt>
              <resp>Electronic edition</resp>
              <persName>Amelang, David J.</persName>
            </respStmt>
            <principal>Joan Oleza Simó</principal>
          </titleStmt>
          <publicationStmt>
            <publisher><orgName>ARTELOPE/EMOTHE</orgName></publisher>
            <authority><orgName>Universitat de València</orgName></authority>
            <idno>#{code}</idno>
            <idno type="EMOTHE">0703</idno>
            <availability>
              <p>General availability text.</p>
              <licence target="https://creativecommons.org/licenses/by-nc-nd/4.0/deed.es">CC BY-NC-ND 4.0</licence>
            </availability>
            <pubPlace>Valencia</pubPlace>
            <date>2023</date>
          </publicationStmt>
          <sourceDesc>
            <bibl>
              <title>El gran teatro del mundo</title>
              <author>Shakespeare, William</author>
              <lang>Español</lang>
              <note>Nota de fuente.</note>
            </bibl>
          </sourceDesc>
        </fileDesc>
      </teiHeader>
      <text>
        <front></front>
        <body></body>
      </text>
    </TEI>
    """
  end

  test "export includes original_title as <title type=\"original\">" do
    path = write_tei(rich_tei(code: "EXORIG01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<title[^>]*type="original"[^>]*>\s*The Great Theatre\s*<\/title>/
  end

  test "export includes translator as <editor role=\"translator\">" do
    path = write_tei(rich_tei(code: "EXTRANS01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<editor[^>]*role="translator"/
    assert exported_xml =~ "Sanderson"
  end

  test "export includes EMOTHE idno in publicationStmt" do
    path = write_tei(rich_tei(code: "EXIDNO01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<idno[^>]*type="EMOTHE"[^>]*>\s*0703\s*<\/idno>/
  end

  test "export includes licence with url and text" do
    path = write_tei(rich_tei(code: "EXLIC01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~
             ~r/<licence[^>]*target="https:\/\/creativecommons\.org\/licenses\/by-nc-nd\/4\.0\/deed\.es"/

    assert exported_xml =~ "CC BY-NC-ND 4.0"
  end

  test "export includes source language in bibl" do
    path = write_tei(rich_tei(code: "EXLANG01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<lang>\s*Español\s*<\/lang>/
  end

  test "export includes sponsor and funder in titleStmt" do
    path = write_tei(rich_tei(code: "EXSF01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<sponsor>.*Plan Nacional.*<\/sponsor>/s
    assert exported_xml =~ ~r/<funder>.*Ministerio de Ciencia.*<\/funder>/s
  end

  test "export includes authority in publicationStmt" do
    path = write_tei(rich_tei(code: "EXAUTH01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<authority>.*Universitat de Val.*<\/authority>/s
  end

  test "export includes publisher in publicationStmt" do
    path = write_tei(rich_tei(code: "EXPUB01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<publisher>.*ARTELOPE.*<\/publisher>/s
  end
end
