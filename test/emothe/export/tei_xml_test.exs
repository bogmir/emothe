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
              <editor role="traductor">Sanderson, John D.</editor>
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

  test "export preserves editor role in bibl" do
    path = write_tei(rich_tei(code: "EXEDRL01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<editor role="traductor">/
    assert exported_xml =~ "Sanderson, John D."
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

  test "export preserves split verse part markers" do
    front = """
    <div type="elenco">
      <castList>
        <castItem><role xml:id="ANA">ANA</role></castItem>
        <castItem><role xml:id="DON">DON</role></castItem>
      </castList>
    </div>
    """

    body = """
    <div1 type="acto" n="1">
      <div2 type="escena" n="1">
        <sp who="#ANA">
          <speaker>ANA</speaker>
          <lg type="redondilla">
            <l n="1" part="I">First part of split</l>
          </lg>
        </sp>
        <sp who="#DON">
          <speaker>DON</speaker>
          <lg type="redondilla">
            <l n="1" part="F">Second part of split</l>
          </lg>
        </sp>
      </div2>
    </div1>
    """

    path = write_tei(minimal_tei(front: front, body: body, code: "EXPART01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<l[^>]*part="I"[^>]*>/
    assert exported_xml =~ ~r/<l[^>]*part="F"[^>]*>/
    assert exported_xml =~ "First part of split"
    assert exported_xml =~ "Second part of split"
  end

  test "export preserves xml:id (line_id) on verse lines" do
    body = """
    <div1 type="acto" n="1">
      <div2 type="escena" n="1">
        <sp>
          <speaker>REY</speaker>
          <lg type="romance">
            <l n="1" xml:id="v001">A verse with ID</l>
            <l n="2">A verse without ID</l>
          </lg>
        </sp>
      </div2>
    </div1>
    """

    path = write_tei(minimal_tei(body: body, code: "EXLNID01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<l[^>]*xml:id="v001"[^>]*>/
    assert exported_xml =~ "A verse with ID"
  end

  test "export preserves rend attribute on verse lines" do
    body = """
    <div1 type="acto" n="1">
      <div2 type="escena" n="1">
        <sp>
          <speaker>DAMA</speaker>
          <lg type="redondilla">
            <l n="1" rend="indent">Indented line</l>
          </lg>
        </sp>
      </div2>
    </div1>
    """

    path = write_tei(minimal_tei(body: body, code: "EXREND01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<l[^>]*rend="indent"[^>]*>/
    assert exported_xml =~ "Indented line"
  end

  test "export preserves source title, author, and note in bibl" do
    path = write_tei(rich_tei(code: "EXSRC01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<title>\s*El gran teatro del mundo\s*<\/title>/
    assert exported_xml =~ ~r/<author>\s*Shakespeare, William\s*<\/author>/
    assert exported_xml =~ ~r/<note>\s*Nota de fuente\.\s*<\/note>/
  end

  test "export preserves pub_place and publication_date" do
    path = write_tei(rich_tei(code: "EXPUBPL01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<pubPlace>\s*Valencia\s*<\/pubPlace>/
    assert exported_xml =~ ~r/<date>\s*2023\s*<\/date>/
  end

  test "export preserves availability_note" do
    path = write_tei(rich_tei(code: "EXAVAIL01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ "General availability text."
  end

  # --- Language: profileDesc/langUsage/language[@ident] ---

  test "export emits <profileDesc><langUsage><language> for Italian play" do
    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <TEI>
      <teiHeader>
        <fileDesc>
          <titleStmt><title>Amleto</title></titleStmt>
          <publicationStmt><idno>EXPLANG01</idno></publicationStmt>
        </fileDesc>
        <profileDesc>
          <langUsage>
            <language ident="it-IT">Italiano</language>
          </langUsage>
        </profileDesc>
      </teiHeader>
      <text><front></front><body></body></text>
    </TEI>
    """

    path = write_tei(xml)
    assert {:ok, play} = TeiParser.import_file(path)
    assert play.language == "it"

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<language\s+ident="it-IT"/
    assert exported_xml =~ "Italiano"
    assert exported_xml =~ "<profileDesc>"
    assert exported_xml =~ "<langUsage>"
  end

  test "export emits <language ident=\"fr-FR\"> for French play" do
    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <TEI>
      <teiHeader>
        <fileDesc>
          <titleStmt><title>Le Cid</title></titleStmt>
          <publicationStmt><idno>EXPLANG02</idno></publicationStmt>
        </fileDesc>
        <profileDesc>
          <langUsage>
            <language ident="fr-FR">Français</language>
          </langUsage>
        </profileDesc>
      </teiHeader>
      <text><front></front><body></body></text>
    </TEI>
    """

    path = write_tei(xml)
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<language\s+ident="fr-FR"/
    assert exported_xml =~ "Français"
  end

  test "export defaults to <language ident=\"es-ES\"> when language is nil" do
    path = write_tei(minimal_tei(code: "EXPLANG03"))
    assert {:ok, play} = TeiParser.import_file(path)
    # no profileDesc in TEI => language stays "es" (schema default)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<language\s+ident="es-ES"/
    assert exported_xml =~ "Español"
  end

  test "export roundtrip preserves split verse content fidelity" do
    front = """
    <div type="elenco">
      <castList>
        <castItem><role xml:id="ANA">ANA</role></castItem>
        <castItem><role xml:id="DON">DON</role></castItem>
      </castList>
    </div>
    """

    body = """
    <div1 type="acto" n="1">
      <div2 type="escena" n="1">
        <sp who="#ANA">
          <speaker>ANA</speaker>
          <lg type="redondilla">
            <l n="1" part="I" xml:id="v001">First part</l>
          </lg>
        </sp>
        <sp who="#DON">
          <speaker>DON</speaker>
          <lg type="redondilla">
            <l n="1" part="F">Second part</l>
            <l n="2" rend="indent">Full line indented</l>
          </lg>
        </sp>
      </div2>
    </div1>
    """

    path = write_tei(minimal_tei(front: front, body: body, code: "RTSP01"))
    assert {:ok, play1} = TeiParser.import_file(path)

    play1_full = Catalogue.get_play_with_all!(play1.id)
    exported_xml = TeiXml.generate(play1_full)

    # Reimport with different code
    reimport_xml = String.replace(exported_xml, "RTSP01", "RTSP02")
    reimport_path = write_tei(reimport_xml)
    assert {:ok, play2} = TeiParser.import_file(reimport_path)

    # Compare content (filter to acto divisions, excluding elenco from front)
    act1 = PlayContent.list_top_divisions(play1.id) |> Enum.find(&(&1.type == "acto"))
    act2 = PlayContent.list_top_divisions(play2.id) |> Enum.find(&(&1.type == "acto"))
    [scene1] = act1.children
    [scene2] = act2.children

    elems1 = PlayContent.list_elements_for_division(scene1.id)
    elems2 = PlayContent.list_elements_for_division(scene2.id)

    # Same number of speeches
    speeches1 = Enum.filter(elems1, &(&1.type == "speech"))
    speeches2 = Enum.filter(elems2, &(&1.type == "speech"))
    assert length(speeches1) == length(speeches2)

    # Check split verse details are preserved
    all_lines1 = for sp <- speeches1, lg <- sp.children, l <- lg.children, do: l
    all_lines2 = for sp <- speeches2, lg <- sp.children, l <- lg.children, do: l

    assert length(all_lines1) == length(all_lines2)

    for {l1, l2} <-
          Enum.zip(
            Enum.sort_by(all_lines1, &{&1.line_number, &1.part}),
            Enum.sort_by(all_lines2, &{&1.line_number, &1.part})
          ) do
      assert l1.content == l2.content
      assert l1.part == l2.part
      assert l1.line_number == l2.line_number
      assert l1.rend == l2.rend
    end
  end

  # --- Medium priority: metadata, editors, content fidelity ---

  test "export includes principal in titleStmt" do
    path = write_tei(rich_tei(code: "EXPRINC01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<principal>\s*Joan Oleza Simó\s*<\/principal>/
  end

  test "export includes respStmt with role mapping in titleStmt" do
    path = write_tei(rich_tei(code: "EXRESP01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ "Amelang, David J."
    assert exported_xml =~ ~r/<respStmt>.*<resp>Electronic edition<\/resp>.*<persName>Amelang/s
  end

  test "export includes author_attribution as ana attribute" do
    path = write_tei(rich_tei(code: "EXATTR01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<author[^>]*ana="fiable"[^>]*>/
  end

  test "export includes edition_title as <title type=\"edicion\">" do
    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <TEI>
      <teiHeader>
        <fileDesc>
          <titleStmt>
            <title>Main Title</title>
            <title type="edicion">Edición crítica 2023</title>
          </titleStmt>
          <publicationStmt><idno>EXEDIT01</idno></publicationStmt>
        </fileDesc>
      </teiHeader>
      <text><front></front><body></body></text>
    </TEI>
    """

    path = write_tei(xml)
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<title[^>]*type="edicion"[^>]*>\s*Edición crítica 2023\s*<\/title>/
  end

  test "export includes hidden character with ana=oculto" do
    front = """
    <div type="elenco">
      <castList>
        <castItem><role xml:id="HERO">HERO</role></castItem>
        <castItem ana="oculto"><role xml:id="HIDDEN">HIDDEN</role></castItem>
      </castList>
    </div>
    """

    path = write_tei(minimal_tei(front: front, code: "EXHID01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<castItem[^>]*ana="oculto"[^>]*>/
    assert exported_xml =~ "HIDDEN"
  end

  test "export preserves division head titles in <head> elements" do
    body = """
    <div1 type="acto" n="1">
      <head>JORNADA PRIMERA</head>
      <div2 type="escena" n="1">
        <head>ESCENA I</head>
      </div2>
    </div1>
    """

    path = write_tei(minimal_tei(body: body, code: "EXHEAD01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<head>\s*JORNADA PRIMERA\s*<\/head>/
    assert exported_xml =~ ~r/<head>\s*ESCENA I\s*<\/head>/
  end

  test "export preserves lg part attribute" do
    body = """
    <div1 type="acto" n="1">
      <div2 type="escena" n="1">
        <sp>
          <speaker>ANA</speaker>
          <lg type="redondilla" part="I">
            <l n="1">A verse in split lg</l>
          </lg>
        </sp>
      </div2>
    </div1>
    """

    path = write_tei(minimal_tei(body: body, code: "EXLGP01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<lg[^>]*part="I"[^>]*>/
  end

  test "export preserves prose aside with seg type=aside" do
    body = """
    <div1 type="acto" n="1">
      <div2 type="escena" n="1">
        <sp>
          <speaker>REY</speaker>
          <p><seg type="aside">An aside in prose</seg></p>
          <p>Normal prose.</p>
        </sp>
      </div2>
    </div1>
    """

    path = write_tei(minimal_tei(body: body, code: "EXPA01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<p>\s*<seg type="aside">\s*An aside in prose\s*<\/seg>\s*<\/p>/
    assert exported_xml =~ "Normal prose."
  end

  test "export preserves multiple bibl sources" do
    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <TEI>
      <teiHeader>
        <fileDesc>
          <titleStmt><title>Multi Source</title></titleStmt>
          <publicationStmt><idno>EXMSRC01</idno></publicationStmt>
          <sourceDesc>
            <bibl>
              <title>First Source</title>
              <author>Author One</author>
            </bibl>
            <bibl>
              <title>Second Source</title>
              <author>Author Two</author>
            </bibl>
          </sourceDesc>
        </fileDesc>
      </teiHeader>
      <text><front></front><body></body></text>
    </TEI>
    """

    path = write_tei(xml)
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ "First Source"
    assert exported_xml =~ "Author One"
    assert exported_xml =~ "Second Source"
    assert exported_xml =~ "Author Two"
    # Should have two <bibl> elements
    assert length(Regex.scan(~r/<bibl>/, exported_xml)) == 2
  end

  test "export includes extent element when verse_count is set" do
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
            <l n="1">Line one</l>
            <l n="2">Line two</l>
          </lg>
        </sp>
      </div2>
    </div1>
    """

    path = write_tei(minimal_tei(front: front, body: body, code: "EXEXT01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    # verse_count is recomputed from actual DB data (2 verse lines)
    assert exported_xml =~ ~r/<extent[^>]*>\s*2 versos\s*<\/extent>/
  end

  test "export includes publisher in publicationStmt" do
    path = write_tei(rich_tei(code: "EXPUB01"))
    assert {:ok, play} = TeiParser.import_file(path)

    play_with_all = Catalogue.get_play_with_all!(play.id)
    exported_xml = TeiXml.generate(play_with_all)

    assert exported_xml =~ ~r/<publisher>.*ARTELOPE.*<\/publisher>/s
  end
end
