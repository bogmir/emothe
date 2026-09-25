defmodule Playcode.Export.TeiValidatorTest do
  use Playcode.DataCase, async: true

  # Each test shells out to xmllint with the TEI RelaxNG schema: ~15s apiece,
  # 60% of the whole suite's wall clock. Excluded by default, see test_helper.exs.
  @moduletag :slow

  alias Playcode.Export.TeiValidator
  alias Playcode.Import.TeiParser
  alias Playcode.Export.TeiXml
  alias Playcode.Catalogue

  @fixture_file Path.expand(
                  "../../fixtures/EMOTHE0759_AutoDeLaBarcaDelInfierno.xml",
                  __DIR__
                )

  describe "validate/1" do
    test "an imported corpus play exports as schema-valid TEI" do
      {:ok, play} = TeiParser.import_file(@fixture_file)

      xml = play.id |> Catalogue.get_play_with_all!() |> TeiXml.generate()

      assert TeiValidator.validate(xml) == {:ok, :valid}
    end

    test "returns errors for malformed XML" do
      invalid_xml =
        ~s(<?xml version="1.0"?>\n<TEI xmlns="http://www.tei-c.org/ns/1.0"><bad></TEI>)

      assert {:error, errors} = TeiValidator.validate(invalid_xml)
      assert is_list(errors)
      assert length(errors) > 0
    end
  end
end
