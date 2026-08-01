defmodule Emothe.Import.TeiReimportTest do
  use Emothe.DataCase, async: true

  alias Emothe.Catalogue
  alias Emothe.Import.TeiParser
  alias Emothe.PlayContent

  @tei """
  <?xml version="1.0" encoding="UTF-8"?>
  <TEI>
    <teiHeader>
      <fileDesc>
        <titleStmt>
          <title key="archivo">EMOTHE9301_ReimportPlay</title>
          <title>Reimport Play</title>
        </titleStmt>
        <publicationStmt><idno>EMOTHE9301</idno></publicationStmt>
        <sourceDesc>
          <bibl><title>Primera parte</title><author>Lope de Vega</author></bibl>
        </sourceDesc>
      </fileDesc>
    </teiHeader>
    <text>
      <front>
        <div type="elenco">
          <castList><castItem><role xml:id="REY">EL REY</role></castItem></castList>
        </div>
      </front>
      <body>
        <div1 type="acto" n="1">
          <head>Acto primero</head>
          <sp who="#REY"><speaker>EL REY</speaker><l>Conde, entregad la espada.</l></sp>
        </div1>
      </body>
    </text>
  </TEI>
  """

  setup do
    path = Path.join(System.tmp_dir!(), "reimport-#{System.unique_integer([:positive])}.xml")
    File.write!(path, @tei)
    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  test "re-importing the same code updates the same row", %{path: path} do
    assert {:ok, first} = TeiParser.import_file(path)
    {:ok, _} = Catalogue.update_play(first, %{language: "en", relationship_type: "traduccion"})

    assert {:ok, second} = TeiParser.import_file(path)
    assert second.id == first.id

    reloaded = Catalogue.get_play!(first.id)
    assert reloaded.language == "en", "TEI must not clobber the FileMaker-derived language"
    assert reloaded.relationship_type == "traduccion"
  end

  test "hand-entered records survive a re-import", %{path: path} do
    {:ok, play} = TeiParser.import_file(path)
    {:ok, typed} = Catalogue.create_play_source(%{play_id: play.id, title: "Typed by hand"})

    {:ok, _} = TeiParser.import_file(path)

    sources = Catalogue.list_play_sources(play.id)
    assert typed.id in Enum.map(sources, & &1.id)
    assert Enum.count(sources, &(&1.origin == "tei")) == 1
  end

  test "re-importing an archived play restores it", %{path: path} do
    {:ok, play} = TeiParser.import_file(path)
    {:ok, _} = Catalogue.delete_play(play)

    assert {:ok, reimported} = TeiParser.import_file(path)
    assert reimported.id == play.id
    refute Catalogue.get_play!(play.id).deleted_at
  end

  test "content is replaced, not duplicated", %{path: path} do
    {:ok, play} = TeiParser.import_file(path)
    before = counts(play.id)

    {:ok, _} = TeiParser.import_file(path)

    assert counts(play.id) == before
    assert before.divisions > 0 and before.characters > 0 and before.sources > 0
  end

  defp counts(play_id) do
    %{
      divisions: length(PlayContent.list_divisions(play_id)),
      characters: length(PlayContent.list_characters(play_id)),
      sources: length(Catalogue.list_play_sources(play_id))
    }
  end
end
