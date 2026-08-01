defmodule Mix.Tasks.Emothe.Import.Tei do
  @shortdoc "Import the local TEI corpus into the database"

  @moduledoc """
  Imports every .xml file under the fixture directories, one play per code.

      mix emothe.import.tei                  # skip codes already imported
      mix emothe.import.tei --force          # re-import everything
      mix emothe.import.tei --dry-run        # report what would happen, write nothing
      mix emothe.import.tei --dir some/path  # use another directory (repeatable)

  A re-import replaces a play's text and the records the importer created; anything
  entered by hand is kept, as are language, relationship, parent play and completeness.
  `--dry-run` prints that per file before anything is written.
  """

  use Mix.Task

  alias Emothe.Import.TeiCorpus
  alias Emothe.Import.TeiParser

  @switches [force: :boolean, dry_run: :boolean, dir: :keep]

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

    if opts[:dry_run] do
      dry_run(files, opts[:force] || false)
    else
      run_import(files, opts)
    end
  end

  defp dry_run(files, force) do
    {new, existing, unreadable} =
      Enum.reduce(files, {0, 0, 0}, fn {code, path}, {new, existing, unreadable} ->
        case TeiParser.preview_import(path) do
          {:ok, %{existing: nil}} ->
            Mix.shell().info("  #{code}  new")
            {new + 1, existing, unreadable}

          {:ok, preview} when not force ->
            Mix.shell().info("  #{code}  already imported, would be skipped")
            _ = preview
            {new, existing + 1, unreadable}

          {:ok, preview} ->
            Mix.shell().info(
              "  #{code}  replaces #{preview.replaces.divisions} division(s), " <>
                "#{preview.replaces.elements} element(s), " <>
                "#{preview.replaces.characters} character(s), " <>
                "#{preview.replaces.editors + preview.replaces.sources + preview.replaces.notes} TEI record(s)" <>
                keeps(preview)
            )

            {new, existing + 1, unreadable}

          {:error, reason} ->
            Mix.shell().error("  #{code}: #{inspect(reason)}")
            {new, existing, unreadable + 1}
        end
      end)

    Mix.shell().info(
      "\ndry run, nothing written — #{new} new, #{existing} already imported, #{unreadable} unreadable"
    )
  end

  defp keeps(preview) do
    kept = preview.preserves.editors + preview.preserves.sources + preview.preserves.notes
    restored = if preview.archived, do: ", restores it from the archive", else: ""

    case kept do
      0 -> restored
      n -> ", keeps #{n} hand-entered record(s)" <> restored
    end
  end

  defp run_import(files, opts) do
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
