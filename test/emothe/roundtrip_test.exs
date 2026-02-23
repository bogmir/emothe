defmodule Emothe.RoundtripTest do
  use Emothe.DataCase, async: false

  require Logger

  alias Emothe.Import.TeiParser
  alias Emothe.Export.TeiXml
  alias Emothe.Catalogue

  @moduledoc """
  Roundtrip tests using real-world TEI fixture files from the EMOTHE corpus.
  Verifies that import → export preserves structural integrity:
  verses, speeches, stage directions, characters, acts/scenes, etc.

  Fixture files are in test/fixtures/tei_files/ (UTF-16 encoded TEI P5 XML).
  """

  @fixtures_dir Path.expand("../fixtures/tei_files", __DIR__)
  @fields ~w(acts scenes characters speeches verses line_groups stage_dirs asides)a

  defp ms_since(t0_native) do
    System.convert_time_unit(System.monotonic_time() - t0_native, :native, :millisecond)
  end

  defp roundtrip_log(code, msg) do
    IO.puts("[roundtrip #{code}] #{msg}")
  end

  # Read a possibly UTF-16 file and return UTF-8 string
  defp read_original(path) do
    raw = File.read!(path)

    case raw do
      <<0xFF, 0xFE, rest::binary>> ->
        :unicode.characters_to_binary(rest, {:utf16, :little})

      <<0xFE, 0xFF, rest::binary>> ->
        :unicode.characters_to_binary(rest, {:utf16, :big})

      <<first, 0x00, _rest::binary>> when first != 0x00 ->
        :unicode.characters_to_binary(raw, {:utf16, :little})

      <<0xEF, 0xBB, 0xBF, rest::binary>> ->
        rest

      _ ->
        raw
    end
  end

  # Extract <body>...</body> content (avoids counting <p> in teiHeader)
  defp extract_body(xml) do
    case Regex.run(~r/<body>(.*)<\/body>/s, xml) do
      [_, body] -> body
      _ -> xml
    end
  end

  # Extract <front>...</front> content
  defp extract_front(xml) do
    case Regex.run(~r/<front>(.*)<\/front>/s, xml) do
      [_, front] -> front
      _ -> ""
    end
  end

  defp count_tag(xml, tag), do: Regex.scan(~r/<#{tag}[\s>\/]/, xml) |> length()

  # Count stage directions that the parser actually imports:
  # only <stage> elements that are direct children of div2, sp, or lg
  # (not delivery stages, not inline within <l> or <p>)
  defp count_stage_dirs(body) do
    clean = Regex.replace(~r/<\?xml[^?]*\?>/, body, "")
    {:ok, tree} = Saxy.SimpleForm.parse_string("<root>#{clean}</root>")
    count_stage_children(tree)
  end

  defp count_stage_children({_name, _attrs, children}) do
    Enum.reduce(children, 0, fn
      {"stage", attrs, _}, acc ->
        type = attr_val(attrs, "type")
        if type == "delivery", do: acc, else: acc + 1

      {tag, _, _} = el, acc when tag in ~w(root div1 div2 sp lg) ->
        acc + count_stage_children(el)

      # Don't recurse into l, p, note, etc. — their stages are inline
      _, acc ->
        acc
    end)
  end

  defp attr_val(attrs, key), do: Enum.find_value(attrs, fn {k, v} -> if k == key, do: v end)

  defp structural_counts(xml) do
    body = extract_body(xml)
    front = extract_front(xml)

    %{
      verses: count_tag(body, "l"),
      speeches: count_tag(body, "sp"),
      stage_dirs: count_stage_dirs(body),
      line_groups: count_tag(body, "lg"),
      acts: count_tag(xml, "div1"),
      scenes: count_tag(xml, "div2"),
      characters: count_tag(front, "castItem"),
      asides: count_aside_elements(body)
    }
  end

  # Count <l> and <p> elements that contain at least one <seg type="aside">
  # (matches what the importer stores: one element per <l>/<p> with is_aside=true)
  defp count_aside_elements(body) do
    clean = Regex.replace(~r/<\?xml[^?]*\?>/, body, "")
    {:ok, tree} = Saxy.SimpleForm.parse_string("<root>#{clean}</root>")
    count_aside_leaves(tree)
  end

  defp count_aside_leaves({_name, _attrs, children}) do
    Enum.reduce(children, 0, fn
      {tag, _attrs, inner}, acc when tag in ~w(l p) ->
        has_aside =
          Enum.any?(inner, fn
            {"seg", seg_attrs, _} -> attr_val(seg_attrs, "type") == "aside"
            _ -> false
          end)

        if has_aside, do: acc + 1, else: acc

      {_tag, _, _} = child, acc ->
        acc + count_aside_leaves(child)

      _, acc ->
        acc
    end)
  end

  # Files that already pass roundtrip — skip them to speed up iteration.
  # Move files back out of this list when re-verifying the full suite.
  @passing_files ~w(
    AL0514_ElAusenteEnElLugar.xml
    AL0569_LaCoronaMerecida.xml
    AL0590_LaDiscretaEnamorada.xml
    AL0606_LosRamilletesDeMadrid.xml
    AL0611_ElloDira.xml
    AL0641_LaFuerzaLastimosa.xml
    AL0644_ElGallardoCatalan.xml
    AL0711_ElLlegarEnOcasion.xml
    AL0718_LosLocosPorElCielo.xml
    AL0731_ElMasGalanPortuguesDuqueDeBerganza.xml
    AL0749_MiradAQuienAlabais.xml
    AL0750_LaMocedadDeRoldan.xml
    AL0758_LasMujeresSinHombres.xml
    AL0770_LaNinezDeSanIsidro.xml
    AL0784_LaOcasionPerdida.xml
    AL0788_LosPalaciosDeGaliana.xml
    AL0790_LaPalomaDeToledo.xml
    AL0845_LaQuintaDeFlorencia.xml
    AL2000_LaEstrellaDeSevilla.xml
    EMOTHE0008_LeCid.xml
    EMOTHE0020_LaVidaEsSueno.xml
    EMOTHE0033_Athalie.xml
    EMOTHE0254_JulesCesar.xml
  )

  for file <-
        Path.expand("../fixtures/tei_files", __DIR__)
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".xml"))
        |> Enum.reject(&(&1 in @passing_files))
        |> Enum.sort() do
    @file_name file
    @code String.replace_suffix(file, ".xml", "")

    @tag capture_log: false
    @tag timeout: 120_000
    test "roundtrip: #{@code}" do
      path = Path.join(@fixtures_dir, @file_name)
      original_xml = read_original(path)
      orig_counts = structural_counts(original_xml)

      Logger.metadata(roundtrip_code: @code, tei_file: @file_name)
      roundtrip_log(@code, "START file=#{@file_name}")

      import_t0 = System.monotonic_time()
      roundtrip_log(@code, "IMPORT start")

      assert {:ok, play} = TeiParser.import_file(path), "Failed to import #{@file_name}"

      roundtrip_log(@code, "IMPORT ok play_id=#{play.id} (#{ms_since(import_t0)}ms)")

      export_t0 = System.monotonic_time()
      roundtrip_log(@code, "EXPORT start")

      play_full = Catalogue.get_play_with_all!(play.id)
      exported_xml = TeiXml.generate(play_full)
      export_counts = structural_counts(exported_xml)

      roundtrip_log(@code, "EXPORT ok (#{ms_since(export_t0)}ms)")

      try do
        for field <- @fields do
          orig_val = Map.fetch!(orig_counts, field)
          export_val = Map.fetch!(export_counts, field)

          assert orig_val == export_val,
                 "#{@code} #{field}: original=#{orig_val} exported=#{export_val}"
        end

        roundtrip_log(@code, "OK")
      rescue
        e in ExUnit.AssertionError ->
          roundtrip_log(@code, "FAILED (see assertion). Logging count summaries...")

          Logger.error(
            "ROUNDTRIP failed original_counts=#{inspect(orig_counts)} exported_counts=#{inspect(export_counts)}"
          )

          reraise e, __STACKTRACE__
      end
    end
  end
end
