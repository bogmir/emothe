defmodule Emothe.Import.Filemaker do
  @moduledoc """
  Reads the FileMaker NDJSON export.

  The file holds two tables, each preceded by a `_meta` envelope line and followed by
  an `_end` line. Only `T00_indiceEM` — the published index — is read here: its
  `pub_listaObras` field is the rendered HTML of every published version of a work,
  and it is the authoritative source for a play's language, its family, and whether
  it is an original (credited `ed.`) or a translation (credited `tra.`).
  """

  @default_path "doc/w3emothe_T01_tituloEM.ndjson"
  @index_layout "T00_indiceEM"

  # <li>[EN] <a href="textosEMOTHE/CODE_File.php">TITLE</a> credit… [xml] </li>
  @version ~r|<li>(?:<span[^>]*>\[([A-Z]{2})\]\s*</span>)?\s*<a href="textosEMOTHE/([A-Za-z0-9]+)_([^"]*)\.php"[^>]*>(.*?)</a>(.*?)</li>|s

  @languages %{"ES" => "es", "EN" => "en", "FR" => "fr", "IT" => "it", "PT" => "pt"}

  def default_path, do: @default_path

  @doc """
  Returns `{:ok, %{code => version}}` for every published version in the index.
  """
  def load_index(path \\ @default_path) do
    with {:ok, body} <- File.read(path) do
      index =
        body
        |> String.split("\n", trim: true)
        |> Enum.reduce({nil, %{}}, &read_line/2)
        |> elem(1)

      {:ok, index}
    end
  end

  defp read_line(line, {layout, index}) do
    case Jason.decode(line) do
      {:ok, %{"_meta" => meta}} ->
        {meta["layout"], index}

      {:ok, %{"fields" => fields}} when layout == @index_layout ->
        {layout, add_work(index, fields)}

      _ ->
        {layout, index}
    end
  end

  defp add_work(index, fields) do
    work = field(fields, "_IdIndiceCtce")
    versions = parse_versions(field(fields, "pub_listaObras"), work)
    family = Enum.map(versions, &Map.take(&1, [:code, :role]))

    Enum.reduce(versions, index, fn version, acc ->
      Map.put(acc, version.code, Map.put(version, :family, family))
    end)
  end

  defp parse_versions(html, work) do
    @version
    |> Regex.scan(html)
    |> Enum.map(fn [_all, lang, code, file, title, rest] ->
      credit = rest |> strip_tags() |> String.replace("[xml]", "") |> String.trim()

      %{
        code: code,
        lang: Map.get(@languages, lang, ""),
        title: strip_tags(title),
        credit: credit,
        role: role(credit),
        work: work,
        xml: "textosXML/#{code}_#{file}.xml"
      }
    end)
  end

  defp role(credit) do
    cond do
      Regex.match?(~r{,\s*ed\.}, credit) -> :editor
      Regex.match?(~r{,\s*tra\.}, credit) -> :translator
      true -> nil
    end
  end

  defp strip_tags(html) do
    html
    |> String.replace(~r{<[^>]+>}, " ")
    |> String.replace(~r{\s+}, " ")
    |> String.trim()
  end

  defp field(fields, key) do
    case Map.get(fields, key) do
      list when is_list(list) -> list |> Enum.join("\n") |> String.trim()
      value when is_binary(value) -> String.trim(value)
      _ -> ""
    end
  end
end
