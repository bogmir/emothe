defmodule Emothe.Import.FilemakerSync do
  @moduledoc """
  Applies the FileMaker published index to the plays we already have.

  `plan/2` is pure: it produces the list of changes without writing anything, so the
  mix task can print it for review. `apply_plan/2` performs the writes.

  Nothing here ever creates a play. Codes with no index entry — every Artelope play,
  and anything the project never published — come back under `:missing`.
  """

  import Ecto.Query

  alias Emothe.Catalogue.Play
  alias Emothe.Repo

  @keep :keep
  @languages ~w(es en fr it pt)

  @doc "The FileMaker code hiding at the front of a play code."
  def base_code(code), do: code |> String.split("_") |> List.first()

  @doc "Every play in the database, for `plan/2`."
  def all_plays do
    Play |> order_by([p], p.code) |> Repo.all()
  end

  @doc "Diffs the index against the given plays. Writes nothing."
  def plan(index, plays) do
    by_code = Map.new(plays, &{base_code(&1.code), &1})

    plays
    |> Enum.reduce(%{changes: [], unchanged: [], missing: []}, fn play, acc ->
      code = base_code(play.code)

      case Map.fetch(index, code) do
        :error ->
          %{acc | missing: [code | acc.missing]}

        {:ok, version} ->
          case changes_for(play, version, by_code) do
            empty when map_size(empty) == 0 ->
              %{acc | unchanged: [code | acc.unchanged]}

            sets ->
              change = %{play_id: play.id, code: code, title: play.title, sets: sets}
              %{acc | changes: [change | acc.changes]}
          end
      end
    end)
    |> Map.new(fn {key, list} -> {key, Enum.reverse(list)} end)
  end

  defp changes_for(play, version, by_code) do
    %{
      language: language_for(version),
      relationship_type: relationship_for(version),
      parent_play_id: parent_for(version, by_code)
    }
    |> Enum.reject(fn {_key, value} -> value == @keep end)
    |> Enum.reject(fn {key, value} -> Map.get(play, key) == value end)
    |> Map.new()
  end

  defp language_for(%{lang: lang}) when lang in @languages, do: lang
  defp language_for(_version), do: @keep

  defp relationship_for(%{role: :editor}), do: nil
  defp relationship_for(%{role: :translator}), do: "traduccion"
  defp relationship_for(_version), do: @keep

  defp parent_for(version, by_code) do
    head = Enum.find(version.family, &(&1.role == :editor))

    cond do
      is_nil(head) ->
        @keep

      head.code == version.code ->
        nil

      true ->
        case Map.fetch(by_code, head.code) do
          {:ok, parent} -> parent.id
          :error -> @keep
        end
    end
  end
end
