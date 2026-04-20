defmodule Emothe.Export.StaticSite do
  @moduledoc """
  Generates a complete static website from the EMOTHE database.
  Produces an Endings Project-compliant archive deployable to any web server.

  No Phoenix/LiveView dependencies — only uses Ecto contexts and export modules.
  """

  alias Emothe.Catalogue
  alias Emothe.PlayContent
  alias Emothe.Statistics
  alias Emothe.Export.TeiXml
  alias Emothe.Export.StaticSite.{Renderer, Search}

  @type progress_info :: %{
          step: :assets | :catalogue | :play,
          current: non_neg_integer(),
          total: non_neg_integer(),
          detail: String.t()
        }

  @doc """
  Generate a static site.

  ## Options
    * `:output_dir` - output directory (default: `"_site"`)
    * `:play_codes` - list of play codes to include (default: all)
    * `:version` - version label (default: `"1.0"`)
    * `:base_url` - base URL for the site (default: `"/"`)
    * `:build_date` - ISO date string (default: today)
    * `:on_progress` - `fun(progress_info) -> :ok` callback for progress reporting
  """
  @spec generate(keyword()) :: {:ok, %{plays: integer(), size: term(), output_dir: String.t()}} | {:error, String.t()}
  def generate(opts \\ []) do
    output_dir = opts[:output_dir] || "_site"
    build_date = opts[:build_date] || Date.utc_today() |> Date.to_iso8601()
    on_progress = opts[:on_progress] || fn _ -> :ok end

    opts = Keyword.put(opts, :build_date, build_date)

    # 1. Load plays (only complete plays unless :all option is set)
    plays = load_plays(opts[:play_codes], opts[:all] || false)
    total = length(plays)

    if total == 0 do
      {:error, "no plays to export (none marked as complete)"}
    else
      # 2. Prepare output directory
      File.rm_rf!(output_dir)
      File.mkdir_p!(output_dir)
      File.mkdir_p!(Path.join(output_dir, "plays"))

      # 3. Write shared assets
      on_progress.(%{step: :assets, current: 0, total: total, detail: "Writing assets..."})
      File.write!(Path.join(output_dir, "style.css"), Renderer.site_css())
      File.write!(Path.join(output_dir, "search.js"), Search.search_js())

      # 4. Write catalogue index
      on_progress.(%{step: :catalogue, current: 0, total: total, detail: "Generating catalogue..."})
      File.write!(Path.join(output_dir, "index.html"), Renderer.catalogue_page(plays, opts))

      # 5. Write search index and data
      File.write!(Path.join(output_dir, "search-index.json"), Search.build_index(plays))

      # 6. Generate each play
      plays
      |> Enum.with_index(1)
      |> Enum.each(fn {play, idx} ->
        on_progress.(%{step: :play, current: idx, total: total, detail: play.code})
        generate_play(play, output_dir, opts)
      end)

      # 7. Compute output size
      size = dir_size(output_dir)

      {:ok, %{plays: total, size: size, output_dir: output_dir}}
    end
  end

  @doc """
  Export a single play to the static site, then rebuild the catalogue index.
  """
  def generate_single_play(play_id, opts \\ []) do
    output_dir = opts[:output_dir] || "_site"
    build_date = opts[:build_date] || Date.utc_today() |> Date.to_iso8601()
    opts = Keyword.put(opts, :build_date, build_date)

    File.mkdir_p!(Path.join(output_dir, "plays"))

    play = Catalogue.get_play_with_all!(play_id)
    generate_play(play, output_dir, opts)
    rebuild_index(opts)
    :ok
  end

  @doc """
  Remove a single play from the static site, then rebuild the catalogue index.
  """
  def remove_single_play(code, opts \\ []) do
    output_dir = opts[:output_dir] || "_site"
    plays_dir = Path.join(output_dir, "plays")

    File.rm(Path.join(plays_dir, "#{code}.html"))
    File.rm(Path.join(plays_dir, "#{code}.xml"))
    rebuild_index(opts)
    :ok
  end

  @doc """
  Rebuild the catalogue index and search index based on which play files exist in _site/plays/.
  """
  def rebuild_index(opts \\ []) do
    output_dir = opts[:output_dir] || "_site"
    build_date = opts[:build_date] || Date.utc_today() |> Date.to_iso8601()
    opts = Keyword.put(opts, :build_date, build_date)

    exported_codes = list_exported_codes(output_dir)

    plays =
      Catalogue.list_plays(sort: :title_sort)
      |> Enum.filter(&(&1.code in exported_codes))

    File.mkdir_p!(output_dir)
    File.write!(Path.join(output_dir, "style.css"), Renderer.site_css())
    File.write!(Path.join(output_dir, "search.js"), Search.search_js())
    File.write!(Path.join(output_dir, "index.html"), Renderer.catalogue_page(plays, opts))
    File.write!(Path.join(output_dir, "search-index.json"), Search.build_index(plays))
  end

  @doc """
  List play codes that have been exported (have .html files in plays/ dir).
  """
  def list_exported_codes(output_dir \\ "_site") do
    plays_dir = Path.join(output_dir, "plays")

    if File.dir?(plays_dir) do
      plays_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".html"))
      |> Enum.map(&String.trim_trailing(&1, ".html"))
    else
      []
    end
  end

  defp load_plays(nil, all?) do
    Catalogue.list_plays(sort: :title_sort, complete: !all?)
  end

  defp load_plays(codes, all?) when is_list(codes) do
    Catalogue.list_plays(sort: :title_sort, complete: !all?)
    |> Enum.filter(&(&1.code in codes))
  end

  defp generate_play(play, output_dir, opts) do
    plays_dir = Path.join(output_dir, "plays")

    # Load full data
    play_full = Catalogue.get_play_with_all!(play.id)
    characters = PlayContent.list_characters(play.id)
    divisions = PlayContent.load_play_content(play.id)
    statistic = Statistics.get_statistics(play.id)

    # Write play HTML as plays/CODE.html
    html = Renderer.play_page(play_full, characters, divisions, statistic, opts)
    File.write!(Path.join(plays_dir, "#{play.code}.html"), html)

    # Write TEI-XML as plays/CODE.xml
    xml = TeiXml.generate(play_full)
    File.write!(Path.join(plays_dir, "#{play.code}.xml"), xml)
  end

  defp dir_size(path) do
    path
    |> File.ls!()
    |> Enum.reduce(0, fn entry, acc ->
      full = Path.join(path, entry)

      case File.stat(full) do
        {:ok, %{type: :regular, size: size}} -> acc + size
        {:ok, %{type: :directory}} -> acc + dir_size(full)
        _ -> acc
      end
    end)
  end
end
