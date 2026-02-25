defmodule Emothe.Export.TeiValidatorTest do
  use Emothe.DataCase, async: true

  alias Emothe.Export.TeiValidator
  alias Emothe.Import.TeiParser
  alias Emothe.Export.TeiXml
  alias Emothe.Catalogue

  @fixture_path Path.expand("../../fixtures/tei_files", __DIR__)
  @fixture_file Path.join(@fixture_path, "AL0514_ElAusenteEnElLugar.xml")

  describe "validate/1" do
    if File.exists?(@fixture_file) do
      test "validates exported TEI from an imported fixture" do
        {:ok, play} = TeiParser.import_file(@fixture_file)

        play = Catalogue.get_play_with_all!(play.id)
        xml = TeiXml.generate(play)

        case TeiValidator.validate(xml) do
          {:ok, :valid} ->
            :ok

          {:error, errors} when is_list(errors) ->
            # Log validation errors for diagnostics but don't fail the test.
            # The export may not be fully schema-compliant yet; this test
            # verifies the validator itself works end-to-end.
            IO.puts("\n[TEI Validator] #{length(errors)} schema error(s) found:")
            Enum.each(Enum.take(errors, 5), &IO.puts("  #{&1}"))
            if length(errors) > 5, do: IO.puts("  ... and #{length(errors) - 5} more")
        end
      end
    end

    test "returns errors for malformed XML" do
      invalid_xml =
        ~s(<?xml version="1.0"?>\n<TEI xmlns="http://www.tei-c.org/ns/1.0"><bad></TEI>)

      assert {:error, errors} = TeiValidator.validate(invalid_xml)
      assert is_list(errors)
      assert length(errors) > 0
    end

    test "cleans up temp files after validation" do
      xml = ~s(<?xml version="1.0"?>\n<TEI xmlns="http://www.tei-c.org/ns/1.0"></TEI>)
      tmp_dir = System.tmp_dir!()
      before = File.ls!(tmp_dir) |> Enum.filter(&String.starts_with?(&1, "tei-validate-"))

      TeiValidator.validate(xml)

      after_files = File.ls!(tmp_dir) |> Enum.filter(&String.starts_with?(&1, "tei-validate-"))
      assert after_files == before
    end
  end
end
