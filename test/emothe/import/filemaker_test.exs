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
