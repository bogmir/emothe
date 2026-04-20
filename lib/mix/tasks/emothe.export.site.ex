defmodule Mix.Tasks.Emothe.Export.Site do
  @shortdoc "Generate a static website archive of the EMOTHE catalogue"

  @moduledoc """
  Generates an Endings Project-compliant static website from the database.

  ## Usage

      mix emothe.export.site                              # all plays → _site/
      mix emothe.export.site -o /tmp/archive              # custom output dir
      mix emothe.export.site --plays AL0001,AL0002        # specific plays only
      mix emothe.export.site --base-url /emothe/ --version 2.0
      mix emothe.export.site --all                          # include incomplete plays

  ## Options

    * `-o`, `--output` - Output directory (default: `_site`)
    * `--plays` - Comma-separated play codes to export (default: all complete)
    * `--version` - Version label for the site (default: app version)
    * `--base-url` - Base URL for links (default: `/`)
    * `--all` - Include all plays, not just those marked as complete
  """

  use Mix.Task

  @switches [
    output: :string,
    plays: :string,
    version: :string,
    base_url: :string,
    all: :boolean
  ]

  @aliases [o: :output]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    Mix.Task.run("app.start")

    play_codes =
      case opts[:plays] do
        nil -> nil
        codes -> String.split(codes, ",", trim: true)
      end

    app_version =
      case :application.get_key(:emothe, :vsn) do
        {:ok, vsn} -> List.to_string(vsn)
        _ -> "1.0"
      end

    result =
      Emothe.Export.StaticSite.generate(
        output_dir: opts[:output] || "_site",
        play_codes: play_codes,
        version: opts[:version] || app_version,
        base_url: opts[:base_url] || "/",
        all: opts[:all] || false,
        on_progress: &print_progress/1
      )

    case result do
      {:ok, %{plays: count, size: size, output_dir: dir}} ->
        Mix.shell().info(
          "\n✓ Static site generated: #{count} plays → #{dir}/ (#{format_size(size)})"
        )

      {:error, reason} ->
        Mix.shell().error("Failed: #{inspect(reason)}")
    end
  end

  defp print_progress(%{step: :assets, detail: detail}), do: Mix.shell().info("  #{detail}")
  defp print_progress(%{step: :catalogue, detail: detail}), do: Mix.shell().info("  #{detail}")

  defp print_progress(%{step: :play, current: current, total: total, detail: code}) do
    Mix.shell().info("  [#{current}/#{total}] #{code}")
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"
end
