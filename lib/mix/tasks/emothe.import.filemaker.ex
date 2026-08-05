defmodule Mix.Tasks.Emothe.Import.Filemaker do
  @shortdoc "Sync language, relationship and work family from the FileMaker index"

  @moduledoc """
  Reads the published index out of the FileMaker NDJSON export and applies it to the
  plays already in the database. Creates nothing.

      mix emothe.import.filemaker --dry-run          # print the changes, write nothing
      mix emothe.import.filemaker                    # apply them
      mix emothe.import.filemaker --path other.ndjson
      mix emothe.import.filemaker --force            # also overwrite curated conflicts

  Plays whose code is absent from the index — every Artelope play — are listed at the
  end and left untouched.
  """

  use Mix.Task

  alias Emothe.Import.Filemaker
  alias Emothe.Import.FilemakerSync

  @switches [dry_run: :boolean, path: :string, force: :boolean]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    Mix.Task.run("app.start")

    path = opts[:path] || Filemaker.default_path()

    case Filemaker.load_index(path) do
      {:ok, index} ->
        # load_versions/1 cannot fail here — load_index/1 already read the same file.
        # If it ever does, crash loudly rather than sync half the data.
        {:ok, versions} = Filemaker.load_versions(path)
        sync(index, versions, path, opts)

      {:error, reason} ->
        Mix.raise("cannot read #{path}: #{inspect(reason)}")
    end
  end

  defp sync(index, versions, path, opts) do
    plays = FilemakerSync.all_plays()
    plan = FilemakerSync.plan(index, plays, versions)

    Mix.shell().info("#{map_size(index)} indexed versions in #{path}")
    Mix.shell().info("#{length(plays)} plays in the database\n")

    Enum.each(plan.changes, fn change ->
      Mix.shell().info("#{change.code}  #{change.title}")

      Enum.each(change.sets, fn {key, value} ->
        Mix.shell().info("    #{key} -> #{inspect(value)}")
      end)
    end)

    Enum.each(plan.conflicts, fn conflict ->
      Mix.shell().info(
        "#{conflict.code}  #{conflict.title}\n" <>
          "    #{conflict.field}: kept #{inspect(conflict.current)}, " <>
          "index says #{inspect(conflict.indexed)}"
      )
    end)

    Enum.each(plan.skipped, fn skipped ->
      Mix.shell().info(
        "#{skipped.code}  #{skipped.title}\n" <>
          "    dating not imported (#{skipped.reason}): #{inspect(skipped.value)}"
      )
    end)

    Mix.shell().info(
      "\n#{length(plan.changes)} to change, #{length(plan.conflicts)} conflicting, " <>
        "#{length(plan.unchanged)} already correct, #{length(plan.missing)} not in the index, " <>
        "#{length(plan.skipped)} dating(s) skipped"
    )

    if plan.conflicts != [] and !opts[:force] do
      Mix.shell().info("conflicts left alone; re-run with --force to overwrite them")
    end

    if plan.missing != [] do
      Mix.shell().info("not in the index: #{Enum.join(plan.missing, ", ")}")
    end

    if opts[:dry_run] do
      Mix.shell().info("\ndry run, nothing written")
    else
      results = FilemakerSync.apply_plan(plan, force: opts[:force] || false)
      failed = for {:error, code, changeset} <- results, do: {code, changeset}

      Enum.each(failed, fn {code, changeset} ->
        Mix.shell().error("  #{code}: #{inspect(changeset.errors)}")
      end)

      Mix.shell().info("\nupdated #{length(results) - length(failed)}, failed #{length(failed)}")
    end
  end
end
