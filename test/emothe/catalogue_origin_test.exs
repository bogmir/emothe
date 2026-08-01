defmodule Emothe.CatalogueOriginTest do
  use Emothe.DataCase, async: true

  import Emothe.TestFixtures

  alias Emothe.Catalogue
  alias Emothe.Import.TeiParser

  @minimal_tei """
  <?xml version="1.0" encoding="UTF-8"?>
  <TEI>
    <teiHeader>
      <fileDesc>
        <titleStmt>
          <title key="archivo">EMOTHE9201_OriginPlay</title>
          <title>Origin Play</title>
          <principal>Teresa Ferrer</principal>
        </titleStmt>
        <publicationStmt><idno>EMOTHE9201</idno></publicationStmt>
        <sourceDesc>
          <bibl><title>Primera parte</title><author>Lope de Vega</author></bibl>
        </sourceDesc>
      </fileDesc>
    </teiHeader>
    <text><front></front><body></body></text>
  </TEI>
  """

  defp tei_path do
    path = Path.join(System.tmp_dir!(), "origin-#{System.unique_integer([:positive])}.xml")
    File.write!(path, @minimal_tei)
    on_exit(fn -> File.rm(path) end)
    path
  end

  test "the importer stamps its rows" do
    assert {:ok, play} = TeiParser.import_file(tei_path())

    play = Catalogue.get_play_with_all!(play.id)

    assert Enum.any?(play.editors)
    assert Enum.all?(play.editors, &(&1.origin == "tei"))
    assert Enum.any?(play.sources)
    assert Enum.all?(play.sources, &(&1.origin == "tei"))
  end

  test "rows created anywhere else default to manual" do
    play = play_fixture()

    assert {:ok, source} = Catalogue.create_play_source(%{play_id: play.id, title: "By hand"})
    assert source.origin == "manual"

    assert {:ok, editor} =
             Catalogue.create_play_editor(%{
               play_id: play.id,
               person_name: "A Researcher",
               role: "researcher"
             })

    assert editor.origin == "manual"

    assert {:ok, note} =
             Catalogue.create_play_editorial_note(%{
               play_id: play.id,
               section_type: "nota",
               content: "Typed"
             })

    assert note.origin == "manual"
  end

  test "an unknown origin is rejected" do
    play = play_fixture()

    assert {:error, changeset} =
             Catalogue.create_play_source(%{play_id: play.id, title: "x", origin: "guesswork"})

    assert %{origin: _} = errors_on(changeset)
  end
end
