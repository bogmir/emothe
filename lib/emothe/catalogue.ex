defmodule Emothe.Catalogue do
  @moduledoc """
  The Catalogue context manages plays and their metadata.
  """

  import Ecto.Query
  alias Emothe.Repo
  alias Emothe.Catalogue.{Play, PlayEditor, PlaySource, PlayEditorialNote}

  # --- Plays ---

  def list_plays(opts \\ []) do
    Play
    |> apply_search(opts[:search])
    |> apply_sort(opts[:sort] || :title_sort)
    |> Repo.all()
  end

  def get_play!(id), do: Repo.get!(Play, id)

  def get_play_by_code!(code) do
    Repo.get_by!(Play, code: code)
  end

  def get_play_with_all!(id) do
    Play
    |> Repo.get!(id)
    |> Repo.preload([:editors, :sources, :editorial_notes, :statistic])
  end

  def get_play_by_code_with_all!(code) do
    Play
    |> Repo.get_by!(code: code)
    |> Repo.preload([:editors, :sources, :editorial_notes, :statistic])
  end

  def create_play(attrs \\ %{}) do
    %Play{}
    |> Play.changeset(attrs)
    |> Repo.insert()
  end

  def update_play(%Play{} = play, attrs) do
    play
    |> Play.changeset(attrs)
    |> Repo.update()
  end

  def delete_play(%Play{} = play) do
    Repo.delete(play)
  end

  @doc "Recomputes and updates play.verse_count from the actual verse_line elements."
  def update_verse_count(play_id) do
    alias Emothe.PlayContent.Element

    # Count distinct line numbers rather than raw elements,
    # because split verses (shared lines between characters) share the same number
    count =
      Element
      |> where(play_id: ^play_id)
      |> where(type: "verse_line")
      |> where([e], not is_nil(e.line_number))
      |> select([e], count(e.line_number, :distinct))
      |> Repo.one()

    Play
    |> Repo.get!(play_id)
    |> Ecto.Changeset.change(%{verse_count: count})
    |> Repo.update()
  end

  def change_play(%Play{} = play, attrs \\ %{}) do
    Play.changeset(play, attrs)
  end

  def change_play_form(%Play{} = play, attrs \\ %{}) do
    Play.form_changeset(play, attrs)
  end

  def create_play_from_form(attrs) do
    %Play{}
    |> Play.form_changeset(attrs)
    |> Repo.insert()
  end

  def update_play_from_form(%Play{} = play, attrs) do
    play
    |> Play.form_changeset(attrs)
    |> Repo.update()
  end

  # --- Editors ---

  def create_play_editor(attrs) do
    %PlayEditor{}
    |> PlayEditor.changeset(attrs)
    |> Repo.insert()
  end

  # --- Sources ---

  def create_play_source(attrs) do
    %PlaySource{}
    |> PlaySource.changeset(attrs)
    |> Repo.insert()
  end

  # --- Editorial Notes ---

  def create_play_editorial_note(attrs) do
    %PlayEditorialNote{}
    |> PlayEditorialNote.changeset(attrs)
    |> Repo.insert()
  end

  # --- Private ---

  defp apply_search(query, nil), do: query
  defp apply_search(query, ""), do: query

  defp apply_search(query, search) do
    pattern = "%#{search}%"

    from p in query,
      where:
        ilike(p.title, ^pattern) or
          ilike(p.author_name, ^pattern) or
          ilike(p.code, ^pattern)
  end

  defp apply_sort(query, :title_sort) do
    from p in query, order_by: [asc: p.title_sort, asc: p.title]
  end

  defp apply_sort(query, :author_sort) do
    from p in query, order_by: [asc: p.author_sort, asc: p.title_sort]
  end

  defp apply_sort(query, :code) do
    from p in query, order_by: [asc: p.code]
  end

  defp apply_sort(query, _), do: query
end
