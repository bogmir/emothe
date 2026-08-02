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
end
