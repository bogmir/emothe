defmodule Mix.Tasks.Emothe.Import.Tei do
  @shortdoc "Import the local TEI corpus into the database"

  @moduledoc """
  Imports every .xml file under the fixture directories, one play per code.

      mix emothe.import.tei                  # skip codes already imported
      mix emothe.import.tei --force          # re-import everything
      mix emothe.import.tei --dir some/path  # use another directory (repeatable)
  """

  use Mix.Task

  alias Emothe.Import.TeiCorpus

  @switches [force: :boolean, dir: :keep]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    Mix.Task.run("app.start")

    dirs =
      case Keyword.get_values(opts, :dir) do
        [] -> TeiCorpus.default_dirs()
        dirs -> dirs
      end

    files = TeiCorpus.collect_files(dirs)
    Mix.shell().info("#{length(files)} file(s) in #{Enum.join(dirs, ", ")}")

    results = TeiCorpus.import_all(files, force: opts[:force] || false)

    imported = Enum.count(results, &match?({:ok, _, _}, &1))
    skipped = Enum.count(results, &match?({:skipped, _}, &1))
    failed = for {:error, code, reason} <- results, do: {code, reason}

    Enum.each(failed, fn {code, reason} ->
      Mix.shell().error("  #{code}: #{inspect(reason)}")
    end)

    Mix.shell().info("imported #{imported}, skipped #{skipped}, failed #{length(failed)}")
  end
end
